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
require_relative '../nci/snap/identifier'

require 'mocha/test_unit'

module NCI::Snap
  class IdentifierTest < TestCase
    def test_init
      i = Identifier.new('foo')
      assert_equal('foo', i.name)
      assert_equal('latest', i.track)
      assert_equal('stable', i.risk)
      assert_nil(i.branch)
    end

    def test_extensive
      i = Identifier.new('foo/latest/edge')
      assert_equal('foo', i.name)
      assert_equal('latest', i.track)
      assert_equal('edge', i.risk)
      assert_nil(i.branch)
    end

    def test_bad_inputs
      # bad track
      assert_raises do
        Identifier.new('foo/xx/edge')
      end

      # any branch
      assert_raises do
        Identifier.new('foo/latest/edge/yy')
      end
    end
  end
end
