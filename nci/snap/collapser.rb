# frozen_string_literal: true
#
# Copyright (C) 2018-2019 Harald Sitter <sitter@kde.org>
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

require 'yaml'

require_relative 'snapcraft_config'
require_relative 'unpacker'

module NCI
  module Snap
    # Takes a Part instance and collappses its build-snaps by unpacking them.
    class BuildSnapPartCollapser
      attr_reader :part
      attr_reader :root_paths

      def initialize(part)
        @part = part
        @root_paths = []
      end

      def run
        # Drop ids and fill root_paths
        ids_to_root_paths!
        # Return if no paths were found. Do note that the above method
        # asserts that only cmake plugins may have build-snaps, so the following
        # calls would only happen iff build-snaps are set AND the plugin type
        # is in fact supported.
        return if @root_paths.empty?

        extend_xdg_data_dirs!
        extend_configflags!
      end

      private

      def extend_configflags!
        part.cmake_parameters ||= []
        part.cmake_parameters.reject! do |flag|
          name, value = flag.split('=', 2)
          next false unless name == '-DCMAKE_FIND_ROOT_PATH'

          root_paths << value
        end
        part.cmake_parameters << "-DCMAKE_FIND_ROOT_PATH=#{root_paths.join(';')}"
      end

      def extend_xdg_data_dirs!
        # KDoctools is rubbish and lets meinproc resolve asset paths through
        #  QStandardPaths *AT BUILD TIME*. So, we need to set up
        #  paths correctly.
        # FIXME: this actually moved into the SDK wrapper and can be dropped
        #   in 2019 or so.
        ENV['XDG_DATA_DIRS'] ||= '/usr/local/share:/usr/share'
        data_paths = root_paths.map { |x| File.join(x, '/usr/share') }
        ENV['XDG_DATA_DIRS'] = "#{data_paths.join(':')}:#{ENV['XDG_DATA_DIRS']}"
      end

      def ids_to_root_paths!
        # Reject to drop the build-snap entry
        part.build_snaps&.reject! do |build_snap|
          unless part.plugin == 'cmake'
            # build-snaps are currently only supported for cmake.
            # We *may* need to pull additional magic tricks depending on the
            # type, e.g. with cmake snapcraft is presumably injecting the
            # root_path, so by taking build-snap control away from snapcraft
            # we'll need to deal with it here.
            raise "Part contains #{build_snap} but is not using cmake."
          end

          @root_paths << Unpacker.new(build_snap).unpack
          # When build-snaps are classic they rpath the core, so make sure we
          # have the core available for use!
          # Don't add to root_paths. Presently I cannot imagine what useful
          # stuff cmake might find there that is not also in the host system.
          Unpacker.new('core18').unpack
          true
        end
      end
    end

    # Takes a snapcraft.yaml, iters all parts and unpacks the build-snaps so
    # they can be used without snapd.
    class BuildSnapCollapser
      attr_reader :data
      attr_reader :orig_path

      def initialize(snapcraft_yaml)
        @orig_path = File.absolute_path(snapcraft_yaml)
        @data = YAML.load_file(snapcraft_yaml)
        data['parts'].each do |k, v|
          data['parts'][k] = SnapcraftConfig::Part.new(v)
        end
        @cmd = TTY::Command.new(uuid: false)
      end

      # Temporariy collapses the snapcraft.yaml, must get a block. The file
      # is un-collapsed once the method returns!
      def run
        bak_path = "#{@orig_path}.bak"
        FileUtils.cp(@orig_path, bak_path, verbose: true)
        data['parts'].each_value do |part|
          BuildSnapPartCollapser.new(part).run
        end
        File.write(@orig_path, YAML.dump(data))
        yield
      ensure
        FileUtils.mv(bak_path, @orig_path, verbose: true)
      end
    end
  end
end
