# frozen_string_literal: true
#
# Copyright (C) 2016-2018 Harald Sitter <sitter@kde.org>
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

require 'tmpdir'
require 'tty/command'

module CI
  # A tarball handling class.
  class Tarball
    # FIXME: copied from debian::version's upstream regex
    ORIG_EXP = /(.+)_(?<version>[A-Za-z0-9.+:~-]+?)\.orig\.tar(.*)/

    attr_reader :path

    def initialize(path)
      @path = File.absolute_path(path)
    end

    def basename
      File.basename(@path)
    end

    def version
      raise "Not an orig tarball #{path}" unless orig?
      match = basename.match(ORIG_EXP)
      match[:version]
    end

    def to_s
      @path
    end
    alias to_str to_s

    def orig?
      self.class.orig?(@path)
    end

    # Change tarball path to Debian orig format.
    # @return New Tarball with orig path or existing Tarball if it was orig.
    #         This method copies the existing tarball to retain
    #         working paths if the path is being changed.
    def origify
      return self if orig?
      clone.origify!
    end

    # Like {origify} but in-place.
    # @return [Tarball, nil] self if the tarball is now orig, nil if it was orig
    def origify!
      return nil if orig?
      dir = File.dirname(@path)
      match = basename.match(/(?<name>.+)-(?<version>(([\d.]+)(\+)?(~)?(.+)?))\.(?<ext>tar(.*))/)
      raise "Could not parse tarball #{basename}" unless match
      old_path = @path
      @path = "#{dir}/#{match[:name]}_#{match[:version]}.orig.#{match[:ext]}"
      FileUtils.cp(old_path, @path) if File.exist?(old_path)
      self
    end

    # @param dest path to extract to. This must be the actual target
    #             for the directory content. If the tarball contains
    #             a single top-level directory it will be renamed to
    #             the basename of to_dir. If it contains more than one
    #             top-level directory or no directory all content is
    #             moved *into* dest.
    def extract(dest)
      Dir.mktmpdir do |tmpdir|
        system('tar', '-xf', path, '-C', tmpdir)
        content = list_content(tmpdir)
        if content.size > 1 || !File.directory?(content[0])
          FileUtils.mkpath(dest) unless Dir.exist?(dest)
          FileUtils.cp_r(content, dest)
        else
          FileUtils.cp_r(content[0], dest)
        end
      end
    end

    def self.orig?(path)
      !File.basename(path).match(ORIG_EXP).nil?
    end

    private

    # Helper to include hidden dirs but strip self and parent refernces.
    def list_content(path)
      content = Dir.glob("#{path}/*", File::FNM_DOTMATCH)
      content.reject { |c| %w[. ..].include?(File.basename(c)) }
    end
  end

  # Special variant of tarball which has an associated dsc already, extracing
  # will go through the dpkg-source intead of manually extracting the tar.
  class DSCTarball < Tarball
    def initialize(tar, dsc:)
      super(tar)
      @dsc = dsc
    end

    def extract(dest)
      TTY::Command.new.run('dpkg-source', '-x', @dsc, dest)
    end
  end
end
