# frozen_string_literal: true
#
# Copyright (C) 2017 Harald Sitter <sitter@kde.org>
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

require_relative 'lib/testcase'
require_relative '../nci/snap/extender'

require 'mocha/test_unit'

module NCI::Snap
  class Extendertest < TestCase
    def setup
      ENV['APPNAME'] = 'kolourpaint'
      ENV['DIST'] = 'xenial'
    end

    def test_extend
      FileUtils.cp_r(data('source'), '.')
      FileUtils.mv('source/git', 'source/.git')

      stub_request(:get, Extender::Core16::STAGED_CONTENT_PATH)
        .to_return(status: 200, body: JSON.generate(['bar']))
      stub_request(:get, Extender::Core16::STAGED_DEV_PATH)
        .to_return(status: 200, body: JSON.generate(['bar-dev']))

      assert_path_not_exist('snapcraft.yaml')
      Extender.extend(data('snapcraft.yaml'))
      assert_path_exist('snapcraft.yaml')
      data = YAML.load_file('snapcraft.yaml')
      ref = YAML.load_file(data('output.yaml'))
      assert_equal(ref, data)

      assert_path_exist('snap/plugins/x-stage-debs.py')
    end

    def test_release_with_git
      ENV['TYPE'] = 'release'
      assert_raises RuntimeError do
        Extender.extend(data('snapcraft.yaml'))
      end
    end

    # When building a release type we don't want the git mangling to happen.
    def test_release_no_gitification
      ENV['TYPE'] = 'release'

      stub_request(:get, Extender::Core16::STAGED_CONTENT_PATH)
        .to_return(status: 200, body: JSON.generate(['bar']))
      stub_request(:get, Extender::Core16::STAGED_DEV_PATH)
        .to_return(status: 200, body: JSON.generate(['bar-dev']))

      assert_path_not_exist('snapcraft.yaml')
      Extender.extend(data('snapcraft.yaml'))
      assert_path_exist('snapcraft.yaml')
      data = YAML.load_file('snapcraft.yaml')
      ref = YAML.load_file(data('output.yaml'))
      assert_equal(ref, data)
    end

    def test_extend_core18
      ENV['DIST'] = 'bionic'

      # source is a symlink, dereference it
      FileUtils.mkpath('source')
      FileUtils.cp_r(data('source/.'), 'source/', verbose: true)

      FileUtils.mv('source/git', 'source/.git')

      stub_request(:get, Extender::Core18::STAGED_CONTENT_PATH)
        .to_return(status: 200, body: JSON.generate(['bar']))
      stub_request(:get, Extender::Core18::STAGED_DEV_PATH)
        .to_return(status: 200, body: JSON.generate(['bar-dev']))

      assert_path_not_exist('snapcraft.yaml')
      Extender.extend(data('snapcraft.yaml'))
      assert_path_exist('snapcraft.yaml')
      data = YAML.load_file('snapcraft.yaml')
      ref = YAML.load_file(data('output.yaml'))
      assert_equal(ref, data)

      assert_path_exist('snap/plugins/x-stage-debs.py')
    end
  end
end
