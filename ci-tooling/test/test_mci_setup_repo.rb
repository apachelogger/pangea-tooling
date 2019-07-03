# frozen_string_literal: true
#
# Copyright (C) 2016 Harald Sitter <sitter@kde.org>
# Copyright (C) 2016 Bhushan Shah <bshah@kde.org>
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) version 3, or any
# later version accepted by the membership of KDE e.V. (or its
# successor approved by the membership of KDE e.V.), which shall
# act as a proxy defined in Section 6 of version 3 of the license.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library.  If not, see <http://www.gnu.org/licenses/>.

require_relative '../mci/lib/setup_repo'
require_relative 'lib/testcase'

require 'mocha/test_unit'
require 'webmock/test_unit'

class MCISetupRepoTest < TestCase
  def setup
    LSB.instance_variable_set(:@hash, DISTRIB_CODENAME: 'vivid')

    # Reset caching.
    Apt::Repository.send(:reset)
    # Disable bionic compat check (always assume true)
    Apt::Repository.send(:instance_variable_set, :@disable_auto_update, true)
    # Disable automatic update
    Apt::Abstrapt.send(:instance_variable_set, :@last_update, Time.now)
    # Make sure $? is fine before we start!
    reset_child_status!
    # Disable all system invocation.
    Object.any_instance.expects(:`).never
    Object.any_instance.expects(:system).never
    # Disable all web (used for key).
    WebMock.disable_net_connect!
    ENV['TYPE'] = 'unstable'
    ENV['VARIANT'] = 'caf'
  end

  def teardown
    Apt::Repository.send(:reset)

    WebMock.allow_net_connect!
    LSB.reset
    ENV['TYPE'] = nil
    ENV['VARIANT'] = nil
  end

  def test_setup_repo
    system_calls = [
      ['apt-get', *Apt::Abstrapt.default_args, 'install', 'software-properties-common'],
      ['add-apt-repository', '--no-update', '-y', 'deb http://repo.plasma-mobile.org vivid main'],
      ['add-apt-repository', '--no-update', '-y', 'deb http://repo.plasma-mobile.org/caf vivid main'],
      ['add-apt-repository', '--no-update', '-y', 'deb http://archive.neon.kde.org/unstable vivid main'],
      ['add-apt-repository', '--no-update', '-y', 'deb http://repo.halium.org vivid main'],
      ['add-apt-repository', '--no-update', '-y', 'deb http://repo.halium.org/caf vivid main'],
      ['apt-get', *Apt::Abstrapt.default_args, 'update'],
      ['apt-get', *Apt::Abstrapt.default_args, 'install', 'pkg-kde-tools']
    ]

    system_sequence = sequence('system-calls')
    system_calls.each do |cmd|
      Object.any_instance.expects(:system)
            .with(*cmd)
            .returns(true)
            .in_sequence(system_sequence)
    end

    Object.any_instance.stubs(:`)
          .with('dpkg-architecture -qDEB_BUILD_ARCH')
          .returns('amd64')

    key_catcher = StringIO.new
    IO.expects(:popen)
      .with(['apt-key', 'add', '-'], 'w')
      .yields(key_catcher)
      .returns(true)

    key_catcher_neon = StringIO.new
    IO.expects(:popen)
      .with(['apt-key', 'add', '-'], 'w')
      .yields(key_catcher_neon)
      .returns(true)

    stub_request(:get, 'http://repo.plasma-mobile.org/Pangea%20CI.gpg.key')
      .to_return(status: 200, body: 'abc')

    stub_request(:get, 'http://archive.neon.kde.org/public.key')
      .to_return(status: 200, body: 'abc')

    MCI.setup_repo!

    assert_equal("abc\n", key_catcher.string)
    assert_equal("abc\n", key_catcher_neon.string)
  end
end
