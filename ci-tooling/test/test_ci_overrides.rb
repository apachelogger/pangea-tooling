# frozen_string_literal: true
#
# Copyright (C) 2016 Harald Sitter <sitter@kde.org>
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

require_relative '../lib/ci/overrides'
require_relative '../lib/ci/scm'
require_relative 'lib/testcase'

# Test ci/overrides
module CI
  class OverridesTest < TestCase
    def setup
      CI::Overrides.default_files = [] # Disable overrides by default.
    end

    def teardown
      CI::Overrides.default_files = nil # Reset
    end

    def test_pattern_match
      # FIXME: this uses live data
      o = Overrides.new([data('o1.yaml')])
      scm = SCM.new('git', 'git://packaging.neon.kde.org.uk/plasma/kitten', 'kubuntu_stable')
      overrides = o.rules_for_scm(scm)
      refute_nil overrides
      assert_equal({"upstream_scm"=>{"branch"=>"Plasma/5.5"}}, overrides)
    end

    def test_definitive_match
    end

    def test_cascading
      o = Overrides.new([data('o1.yaml'), data('o2.yaml')])
      scm = SCM.new('git', 'git://packaging.neon.kde.org.uk/plasma/kitten', 'kubuntu_stable')

      overrides = o.rules_for_scm(scm)

      refute_nil overrides
      assert_equal({"packaging_scm"=>{"branch"=>"yolo"}, "upstream_scm"=>{"branch"=>"kitten"}},
                   overrides)
    end

    def test_cascading_reverse
      o = Overrides.new([data('o2.yaml'), data('o1.yaml')])
      scm = SCM.new('git', 'git://packaging.neon.kde.org.uk/plasma/kitten', 'kubuntu_stable')

      overrides = o.rules_for_scm(scm)

      refute_nil overrides
      assert_equal({"packaging_scm"=>{"branch"=>"kitten"}, "upstream_scm"=>{"branch"=>"kitten"}},
                   overrides)
    end

    def test_specific_overrides_generic
      o = Overrides.new([data('o1.yaml')])
      scm = SCM.new('git', 'git://packaging.neon.kde.org.uk/qt/qt5webkit', 'kubuntu_vivid_mobile')

      overrides = o.rules_for_scm(scm)

      refute_nil overrides
      expected = {
        'upstream_scm' => {
          'branch' => nil,
          'type' => 'tarball',
          'url' => 'http://http.debian.net/qtwebkit.tar.xz'
        }
      }
      assert_equal(expected, overrides)
    end

    def test_branchless_scm
      o = Overrides.new([data('o1.yaml')])
      scm = SCM.new('bzr', 'lp:fishy', nil)

      overrides = o.rules_for_scm(scm)

      refute_nil overrides
      expected = {
        'upstream_scm' => {
          'url' => 'http://meow.git'
        }
      }
      assert_equal(expected, overrides)
    end

    def test_nil_upstream_scm
      # standalone deep_merge would overwrite properties set to nil explicitly, but
      # we want them preserved!
      o = Overrides.new([data('o1.yaml')])
      scm = SCM.new('git', 'git://packaging.neon.kde.org.uk/qt/qt5webkit', 'test_nil_upstream_scm')

      overrides = o.rules_for_scm(scm)

      refute_nil overrides
      expected = {
        'upstream_scm' => nil
      }
      assert_equal(expected, overrides)
    end
  end
end
