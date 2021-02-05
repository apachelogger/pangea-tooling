# frozen_string_literal: true
#
# Copyright (C) 2018 Harald Sitter <sitter@kde.org>
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
require_relative '../nci/snap/manifest_extender'

require 'mocha/test_unit'

module NCI::Snap
  class ManifestExtendertest < TestCase
    def setup
      ManifestExtender.manifest_path = "#{Dir.pwd}/man"
      ENV['APPNAME'] = 'kolourpaint'
      ENV['DIST'] = 'bionic'

      stub_request(:get, Extender::Core18::STAGED_CONTENT_PATH)
        .to_return(status: 200, body: JSON.generate(['meep']))
      stub_request(:get, Extender::Core18::STAGED_DEV_PATH)
        .to_return(status: 200, body: JSON.generate(['meep-dev']))
    end

    def test_run
      File.write(ManifestExtender.manifest_path, '')
      FileUtils.cp(data, 'snapcraft.yaml')
      ManifestExtender.new('snapcraft.yaml').run do
      end
      assert_path_exist('man')
      assert_path_exist('man.bak')
      assert_path_exist('man.ext')
      assert_equal('', File.read('man'))
      assert_includes(File.read('man.ext'), 'meep')
    end

    # The build snap collapser removes records of the build snap, so our
    # detection logic for extending the manifest needs to have other
    # (post-collapsion) ways to determine if a snap is using the build snap.
    def test_run_using_sdk
      File.write(ManifestExtender.manifest_path, '')
      FileUtils.cp(data, 'snapcraft.yaml')
      ManifestExtender.new('snapcraft.yaml').run do
      end
      assert_path_exist('man')
      assert_path_exist('man.bak')
      assert_path_exist('man.ext')
      assert_equal('', File.read('man'))
      assert_includes(File.read('man.ext'), 'meep')
    end

    def test_no_run_without_base_snap
      File.write(ManifestExtender.manifest_path, '')
      FileUtils.cp(data, 'snapcraft.yaml')
      ManifestExtender.new('snapcraft.yaml').run do
      end
      assert_path_exist('man')
      assert_path_exist('man.bak')
      assert_path_exist('man.ext')
      assert_equal('', File.read('man'))
      assert_equal(File.read('man.ext'), '') # MUST BE EMPTY! this is no kf5 snap
    end
  end
end
