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

require 'fileutils'

module Jenkins
  # A Jenkins job directory handler. That is a directory in jobs/ and its
  # metadata.
  class JobDir
    STATE_SYMLINKS = %w[
      lastFailedBuild
      lastStableBuild
      lastSuccessfulBuild
      lastUnstableBuild
      lastUnsuccessfulBuild
      legacyIds
    ].freeze

    def self.age(file)
      ((Time.now - File.mtime(file)) / 60 / 60 / 24).to_i
    end

    def self.recursive?(file)
      return false unless File.symlink?(file)

      abs_file = File.absolute_path(file)
      abs_file_dir = File.dirname(abs_file)
      link = File.readlink(abs_file)
      abs_link = File.absolute_path(link, abs_file_dir)
      abs_link == abs_file
    end

    # @return [Array<String>] of build dirs inside a jenkins builds/ tree
    #   that are valid paths, not a stateful symlink (lastSuccessfulBuild etc.),
    #   and not otherwise unsuitable for processing.
    def self.build_dirs(buildsdir)
      content = Dir.glob("#{buildsdir}/*")

      # Paths that may not be processed in any form or fashion.
      locked = []

      # Add stateful symlinks and their targets to the locked list.
      # This is done separately from removal for ease of reading.
      content.each do |d|
        # Is it a stateful symlink?
        next unless STATE_SYMLINKS.include?(File.basename(d))

        # Lock it!
        locked << d

        # Does the target of the link exist?
        next unless File.exist?(d)

        # Lock that too!
        locked << File.realpath(d)
      end

      # Remove locked paths from the content list. They are entirely excluded
      # from processing.
      content = content.reject do |d|
        next true if locked.include?(d)

        # Deal with broken symlinks before calling realpath...
        # Broken would be a symlink that doesn't exist at all or points to
        # itself. We've already skipped stateful symlinks here as per the
        # above condition, so whatever remains would be build numbers.
        if File.symlink?(d) && (!File.exist?(d) || recursive?(d))
          FileUtils.rm(d)
          next true
        end

        next true if locked.include?(File.realpath(d))

        false
      end

      content.sort_by { |c| File.basename(c).to_i }
    end

    # WARNING: I am almost certain min_count is off-by-one, so, be mindful when
    #   you want to keep 1 build! ~sitter, Nov 2018
    # @param min_count [Integer] the minimum amount of builds to keep
    # @param max_age [Integer,nil] the maximum age in days or nil if there is
    #   none. builds older than this are listed *unless* they are in the
    #   min_count. i.e. the min_count newest builds are never listed, even when
    #   they exceed the max_age. out of the remaining jobs all older than
    #   max_age are listed. if no max_age is set all builds that are not in
    #   the min_count are listed.
    def self.each_ancient_build(dir, min_count:, max_age:, &_blk)
      buildsdir = "#{dir}/builds"
      return unless File.exist?(buildsdir)
      dirs = build_dirs(buildsdir)

      dirs[0..-min_count].each do |d| # Always keep the last N builds.
        yield d if max_age.nil? || (File.exist?(d) && age(d) > max_age)
      end
    end

    def self.prune(dir, min_count: 6, max_age: 14, paths: %w[log archive])
      each_ancient_build(dir, min_count: min_count,
                              max_age: nil) do |ancient_build|
        paths.each do |path|
          path = "#{ancient_build}/#{path}"
          if File.exist?(path) && (age(path) > max_age)
            FileUtils.rm_r(File.realpath(path), verbose: true)
          end
        end
      end
    end
  end
end
