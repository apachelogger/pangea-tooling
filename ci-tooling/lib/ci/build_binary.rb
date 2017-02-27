# frozen_string_literal: true
#
# Copyright (C) 2015-2016 Harald Sitter <sitter@kde.org>
# Copyright (C) 2015 Rohan Garg <rohan@kde.org>
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

require_relative 'source'
require_relative '../debian/control'
require_relative '../dpkg'
require_relative '../os'
require_relative '../retry'
require_relative '../debian/dsc'

module CI
  class PackageBuilder
    BUILD_DIR  = 'build'.freeze
    RESULT_DIR = 'result'.freeze

    BIN_ONLY_WHITELIST = %w(qtbase qtxmlpatterns qtdeclarative qtwebkit
                            test-build-bin-only).freeze

    class DependencyResolver
      RESOLVER_BIN = '/usr/lib/pbuilder/pbuilder-satisfydepends'.freeze
      resolver_env = {}
      if OS.to_h.include?(:VERSION_ID) && OS::VERSION_ID == '8'
        resolver_env['APTITUDEOPT'] = '--target-release=jessie-backports'
      end
      resolver_env['DEBIAN_FRONTEND'] = 'noninteractive'
      RESOLVER_ENV = resolver_env.freeze

      def self.resolve(dir, bin_only: false)
        unless File.executable?(RESOLVER_BIN)
          raise "Can't find #{RESOLVER_BIN}!"
        end

        Retry.retry_it(times: 5) do
          opts = []
          opts << '--binary-arch' if bin_only
          opts << '--control' << "#{dir}/debian/control"
          ret = system(RESOLVER_ENV, RESOLVER_BIN, *opts)
          raise 'Failed to satisfy depends' unless ret
        end
      end
    end

    def extract
      FileUtils.rm_rf(BUILD_DIR, verbose: true)
      unless system('dpkg-source', '-x', @dsc, BUILD_DIR)
        raise 'Something went terribly wrong with extracting the source'
      end
    end

    def build_env
      deb_build_options = ENV.fetch('DEB_BUILD_OPTIONS', '').split(' ')
      {
        'DEB_BUILD_OPTIONS' => (deb_build_options + ['nocheck']).join(' '),
        'DH_BUILD_DDEBS' => '1'
      }
    end

    def build_package
      # FIXME: buildpackage probably needs to be a method on the DPKG module
      #   for logging purposes and so on and so forth
      dpkg_buildopts = [
        # Signing happens outside the container. So disable all signing.
        '-us',
        '-uc'
      ]

      dpkg_buildopts += build_flags

      Dir.chdir(BUILD_DIR) do
        raise unless system(build_env, 'dpkg-buildpackage', *dpkg_buildopts)
      end
    end

    def print_contents
      Dir.chdir(RESULT_DIR) do
        debs = Dir.glob('*.deb')
        debs.each do |deb|
          system('lesspipe', deb)
        end
      end
    end

    def copy_binaries
      Dir.mkdir(RESULT_DIR) unless Dir.exist?(RESULT_DIR)
      changes = Dir.glob("#{BUILD_DIR}/../*.changes")

      changes.select! { |e| !e.include? 'source.changes' }

      unless changes.size == 1
        warn "Not exactly one changes file WTF -> #{changes}"
        return
      end

      system('dcmd', 'cp', '-v', *changes, 'result/')
    end

    def build
      dsc_glob = Dir.glob('*.dsc')
      raise "Not exactly one dsc! Found #{dsc_glob}" unless dsc_glob.count == 1
      @dsc = dsc_glob[0]

      if arch_all_source?
        puts 'INFO: Arch all only package on wrong architecture, not building anything!'
        return
      end

      extract
      install_dependencies
      build_package
      copy_binaries
      print_contents
    end

    private

    def install_dependencies
      DependencyResolver.resolve(BUILD_DIR)
    rescue RuntimeError => e
      raise e unless bin_only_possible?
      DependencyResolver.resolve(BUILD_DIR, bin_only: true)
      @bin_only = true
    end

    # @return [Bool] whether to mangle the build for Qt
    def bin_only_possible?
      @bin_only_possible ||= begin
        control = Debian::Control.new(BUILD_DIR)
        control.parse!
        source_name = control.source.fetch('Build-Depends-Indep', '')
        false unless BIN_ONLY_WHITELIST.include?(source_name)
        control.source.key?('Build-Depends-Indep')
      end
    end

    # @return [Array<String>] of build flags (-b -j etc.)
    def build_flags
      dpkg_buildopts = []
      if arch_all?
        # Automatically decide how many concurrent build jobs we can support.
        # NOTE: special cased for trusty master servers to pass
        dpkg_buildopts << '-j1' unless pretty_old_system?
        # On arch:all only build the binaries, the source is already built.
        dpkg_buildopts << '-b'
      else
        # Automatically decide how many concurrent build jobs we can support.
        # NOTE: special cased for trusty master servers to pass
        dpkg_buildopts << '-jauto' unless pretty_old_system?
        # We only build arch:all on amd64, all other architectures must only
        # build architecture dependent packages. Otherwise we have confliciting
        # checksums when publishing arch:all packages of different architectures
        # to the repo.
        dpkg_buildopts << '-B'
      end
      dpkg_buildopts.collect! { |x| x == '-b' ? '-B' : x } if @bin_only
      dpkg_buildopts
    end

    def arch_all?
      DPKG::HOST_ARCH == 'amd64'
    end

    def arch_all_source?
      parsed_dsc = Debian::DSC.new(@dsc)
      parsed_dsc.parse!
      architectures = parsed_dsc.fields['architecture'].split
      arch_filter = ['any', DPKG::HOST_ARCH]
      arch_filter << 'all' if arch_all?
      (architectures & arch_filter).empty?
    end

    def pretty_old_system?
      OS::VERSION_ID == '14.04'
    rescue
      false
    end
  end
end
