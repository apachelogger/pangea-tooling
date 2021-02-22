# frozen_string_literal: true
# SPDX-License-Identifier: LGPL-2.1-only OR LGPL-3.0-only OR LicenseRef-KDE-Accepted-LGPL
# SPDX-FileCopyrightText: 2016-2021 Harald Sitter <sitter@kde.org>

require_relative '../lib/debian/control'
require_relative 'lib/testcase'

# Test debian/control
module Debian
  class ControlTest < TestCase
    def setup
      FileUtils.cp_r("#{datadir}/.", Dir.pwd)
    end

    def test_old_names
      assert(Kernel.const_defined?(:DebianControl))
    end

    def test_parse
      assert_nothing_raised do
        c = Control.new
        c.parse!
      end
    end

    def test_key
      c = Control.new
      c.parse!
      assert_not_nil(c.source.key?('build-depends'))
    end

    def test_value
      c = Control.new
      c.parse!
      assert_equal(1, c.source['build-depends'].size)
      assert_nil(c.source.fetch('magic', nil))
    end

    def test_multiline_newlines
      c = Control.new
      c.parse!
      # We want accurate newlines preserved for multilines
      assert_equal("meow\nkitten\n.\na", c.binaries[0].fetch('Description'))
    end

    def test_no_final_newline
      c = Control.new(__method__)
      c.parse!
      assert_equal('woof', c.binaries[-1].fetch('Homepage'))
    end

    # Also tests !pwd opening
    def test_no_build_deps
      c = Control.new(__method__)
      c.parse!
      assert_equal(nil, c.source.fetch('build-depends', nil),
                   "Found a build dep #{c.source.fetch('build-depends', nil)}")
    end

    def test_write_nochange
      c = Control.new(__method__)
      c.parse!
      build_deps = c.source.fetch('build-depends', nil)
      assert_not_equal(nil, build_deps)
      assert_equal(File.read("#{__method__}/debian/control").split($/),
                   c.dump.split($/))
    end

    def test_alt_build_deps
      c = Control.new(__method__)
      c.parse!
      build_deps = c.source.fetch('build-depends', nil)
      assert_not_equal(nil, build_deps)
      assert_equal(1, build_deps.count)
      assert_equal(2, build_deps.first.count)
      assert_equal(File.read("#{__method__}/debian/control").split($/),
                   c.dump.split($/))
    end

    def test_ordered_alt_build_deps
      c = Control.new(__method__)
      c.parse!
      build_deps = c.source.fetch('build-depends', nil)
      assert_not_equal(nil, build_deps)
      assert_equal(File.read("#{__method__}/debian/control").split($/),
                   c.dump.split($/))
    end

    description 'changing build-deps works and can be written and read'
    def test_write
      c = Control.new(__method__)
      c.parse!
      build_deps = c.source.fetch('build-depends', nil)
      gwenview_arr = build_deps.find { |x| x.find { |e| e if e.name == 'gwenview' } }
      gwenview = gwenview_arr.find { |x| x.name == 'gwenview' }
      gwenview.operator = '='
      gwenview.version = '1.0'

      File.write("#{__method__}/debian/control", c.dump)
      # Make sure this is actually equal to our golden ref before even trying
      # to parse it again.
      assert_equal(File.read("#{__method__}.ref").split($/), c.dump.split($/))
    end

    def test_write_consistency
      # Make sure adding values to a paragraph preserves order as per golden
      # reference file.

      c = Control.new(__method__)
      c.parse!
      assert_nil(c.source['Vcs-Git'])
      c.source['Vcs-Git'] = 'abc'

      assert_equal(File.read("#{__method__}.ref").split($/), c.dump.split($/))
    end

    def test_write_wrap_and_sort
      # Has super long foldable and relationship fields, we expect them to
      # be properly broken as wrap-and-sort would.

      c = Control.new(__method__)
      c.parse!
      assert_equal(File.read("#{__method__}.ref").split($/), c.dump.split($/))
    end

    def test_single_foldable
      # Uploaders is too long line and foldable. It should be split properly.

      c = Control.new(__method__)
      c.parse!
      assert_equal(c.source['uploaders'],
                   ['Sune Vuorela <debian@pusling.com>',
                    'Modestas Vainius <modax@debian.org>',
                    'Fathi Boudra <fabo@debian.org>',
                    'Maximiliano Curia <maxy@debian.org>'])
    end

    def test_folded_uploaders_write
      c = Control.new(__method__)
      c.parse!
      # Assert that our output is consistent with the input. If we assembled
      # Uploaders incorrectly it wouldn't be.
      assert_equal(File.read("#{__method__}/debian/control").split($/),
                   c.dump.split($/))
    end

    def test_description_not_at_end_dump
      c = Control.new(__method__)
      c.parse!
      # Assert that output is consistent. The input has a non-standard order
      # of fields. Notably Description of binaries is inside the paragraph
      # rather than its end. This resulted in a format screwup due to how we
      # processed multiline trailing whitespace characters (e.g. \n)
      assert_equal(File.read("#{__method__}/debian/control"),
                   c.dump)
    end

    def test_trailing_newline_dump
      c = Control.new(__method__)
      c.parse!
      # The input does not end in a terminal newline (i.e. \nEOF). This
      # shouldn't trip up the parser.
      # Assert that stripping the terminal newline from the dump is consistent
      # with the input data.
      ref = File.read("#{__method__}/debian/control")
      assert(ref)
      assert(ref[-1] != "\n") # make sure the fixture is correct!
      assert_equal("#{ref}\n",
                   c.dump)
    end

    def test_preserve_description_left_space
      c = Control.new(__method__)
      c.parse!
      # Make sure we preserve leading whitespaces in descriptions.
      # Do however rstrip so terminal newlines doesn't mess with the assertion,
      # for the purposes of this assertion we do not care about newline
      # consistency.
      assert_equal(File.read("#{__method__}.description.ref").rstrip,
                   c.binaries[0]['Description'].rstrip)
    end

    def test_excess_newlines
      c = Control.new(__method__)
      c.parse!
      # Assert that the output doens't have extra newlines. When the last
      # field is Description it would end in \n\n (possibly)
      assert_equal(File.read("#{__method__}/debian/control"),
                   c.dump)
      assert(c.dump[-2] != "\n")
    end
  end
end
