# frozen_string_literal: true
require 'fileutils'

require_relative 'debian/changelog'
require_relative 'os'

class KDEIfy
  PATCHES = %w[../suse/firefox-kde.patch ../suse/mozilla-kde.patch].freeze
  class << self
    def init_env
      ENV['QUILT_PATCHES'] = 'debian/patches'
    end

    def apply_patches
      # Need to remove unity menubar from patches first since it interferes with
      # the KDE patches
      system('quilt delete unity-menubar.patch')
      PATCHES.each do |patch|
        system("quilt import #{patch}")
      end
    end

    def install_kde_js
      if Dir.exist?('debian/extra-stuff')
        @substvar = '@browser@'
        FileUtils.cp('../suse/MozillaFirefox/kde.js', 'debian/extra-stuff/')
        File.open('debian/extra-stuff/moz.build', 'a') do |f|
          f.write("\nJS_PREFERENCE_FILES += ['kde.js']\n")
        end
        return
      end

      @substvar = '@MOZ_PKG_NAME@' if File.exist?('debian/control.in')

      FileUtils.cp('../suse/MozillaFirefox/kde.js', 'debian/')
      rules = File.read('debian/rules')
      rules.gsub!(/pre-build.*$/) do |m|
        m += "\n\tmkdir -p $(MOZ_DISTDIR)/bin/defaults/pref/\n\tcp $(CURDIR)/debian/kde.js $(MOZ_DISTDIR)/bin/defaults/pref/kde.js"
      end
      File.write('debian/rules', rules)
    end

    def add_plasma_package(package)
      # Add dummy package
      if File.exist?('debian/control.in')
        control = File.read('debian/control.in')
      else
        control = File.read('debian/control')
      end

      control += "\nPackage: #{@substvar}-plasma
Architecture: any
Depends: #{@substvar} (= ${binary:Version}), mozilla-kde-support
Description: #{package} package for integration with KDE
 Install this package if you'd like #{package} with Plasma integration
"
      if File.exist?('debian/control.in')
        File.write('debian/control.in', control)
        system('debian/rules debian/control')
      else
        File.write('debian/control', control)
      end
    end

    def add_changelog_entry
      changelog = Changelog.new
      version =
        "#{changelog.version(Changelog::EPOCH).to_i + 1}:" +
        "#{changelog.version(Changelog::BASE | Changelog::BASESUFFIX | Changelog::REVISION)}" +
        "+#{OS::VERSION_ID}+#{ENV.fetch('DIST')}"
      dchs = []
      dchs << [
        'dch',
        '--force-bad-version',
        '--newversion', version,
        'Automatic CI Build'
      ]
      dchs << ['dch', '--release', '']

      dchs.each do |dch|
        raise 'Failed to create changelog entry' unless system(*dch)
      end
    end

    def filterdiff
      PATCHES.each do |patch|
        filterdiff = `filterdiff --addprefix=a/mozilla/ --strip 1 #{patch}`
        # Newly created files are represented as /dev/null in the old prefix
        # This leads to issues when we add the new prefix via filterdiff
        # gsub'ing the path's back to /dev/null allows for the patches to
        # apply properly
        filterdiff.gsub!(%r{a\/mozilla\/\/dev\/null}, '/dev/null')
        File.write(patch, filterdiff)
      end
    end

    def firefox!
      init_env
      @substvar = 'firefox'
      Dir.chdir('packaging') do
        apply_patches
        install_kde_js
        add_plasma_package('firefox')
        add_changelog_entry
      end
    end

    def thunderbird!
      init_env
      @substvar = 'thunderbird'
      Dir.chdir('packaging') do
        filterdiff
        apply_patches
        install_kde_js
        add_plasma_package('thunderbird')
        add_changelog_entry
      end
    end
  end
end
