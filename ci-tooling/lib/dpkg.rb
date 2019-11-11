# frozen_string_literal: true
#
# Copyright (C) 2014-2015 Harald Sitter <sitter@kde.org>
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

require 'tty/command'

# Wrapper around dpkg commandline tool.
module DPKG
  def self.run(cmd, args)
    proc = TTY::Command.new(uuid: false, printer: :null)
    result = proc.run(cmd, *args)
    result.out.strip.split($/).compact
  rescue TTY::Command::ExitError
    # TODO: port away from internal resuce, let the caller deal with errors
    #   needs making sure that we don't break anything by not rescuing though
    []
  end

  def self.dpkg(args)
    run('dpkg', args)
  end

  def self.architecture(var)
    run('dpkg-architecture', [] << "-q#{var}")[0]
  end

  def self.const_missing(name)
    architecture("DEB_#{name}")
  end

  # optionized wrapper around dpkg-architecture
  class Architecture
    attr_reader :host_arch

    def initialize(host_arch: nil)
      # Make sure empty string also becomes nil. Otherwise simply set it.
      @host_arch = host_arch&.empty? ? nil : host_arch
    end

    def args
      args = []
      args << '--host-arch' << host_arch if host_arch
      args
    end

    def is(wildcard)
      system('dpkg-architecture', *args, '--is', wildcard)
    end
  end

  module_function

  def list(package)
    DPKG.dpkg([] << '-L' << package)
  end
end
