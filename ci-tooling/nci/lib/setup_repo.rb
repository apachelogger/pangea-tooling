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

require 'net/http'
require 'open-uri'

require_relative '../../lib/apt'
require_relative '../../lib/os'
require_relative '../../lib/retry'
require_relative '../../lib/nci'

# Neon CI specific helpers.
module NCI
  # NOTE: we talk to squid directly to reduce forwarding overhead, if we routed
  #   through apache we'd be spending between 10 and 25% of CPU on the forward.
  PROXY_URI = URI::HTTP.build(host: 'apt.cache.pangea.pub', port: 8000)

  module_function

  def setup_repo_codename
    @setup_repo_codename ||= OS::VERSION_CODENAME
  end

  def setup_repo_codename=(codename)
    @setup_repo_codename = codename
  end

  def default_sources_file=(file)
    @default_sources_file = file
  end

  def default_sources_file
    @default_sources_file ||= '/etc/apt/sources.list'
  end

  def reset_setup_repo
    @repo_added = nil
    @default_sources_file = nil
    @setup_repo_codename = nil
  end

  def add_repo_key!
    @repo_added ||= begin
      Retry.retry_it(times: 3, sleep: 8) do
        raise 'Failed to import key' unless Apt::Key.add(NCI.archive_key)
      end
      true
    end
  end

  def setup_repo!(with_source: false, with_proxy: true)
    setup_proxy! if with_proxy
    add_repo!
    add_source_repo! if with_source
    setup_experimental! if ENV.fetch('TYPE').include?('experimental')
    Retry.retry_it(times: 5, sleep: 4) { raise unless Apt.update }
    # Make sure we have the latest pkg-kde-tools, not whatever is in the image.
    raise 'failed to install deps' unless Apt.install(%w[pkg-kde-tools])

    # Qt6 Hack
    return unless %w[_qt6_bin_ _qt6_src].any? do |x|
      ENV.fetch('JOB_NAME', '').include?(x)
    end

    cmake_key = '6D90 3995 424A 83A4 8D42  D53D A8E5 EF3A 0260 0268'
    cmake_line = 'deb https://apt.kitware.com/ubuntu/ focal main'
    raise 'Failed to import cmake key' unless Apt::Key.add(cmake_key)
    raise 'Failed to add cmake repo' unless Apt::Repository.add(cmake_line)
    Retry.retry_it(times: 5, sleep: 4) { raise unless Apt.update }
    # may be installed in base image
    raise unless Apt.install('cmake')
  end

  def setup_proxy!
    puts "Set proxy to #{PROXY_URI}"
    File.write('/etc/apt/apt.conf.d/proxy',
               "Acquire::http::Proxy \"#{PROXY_URI}\";")
  end

  def maybe_setup_apt_preference
    # If the dist at hand is the future series establish a preference.
    # Due to teh moving nature of the future series it may fall behind ubuntu
    # and build against the incorrect packages. The preference is meant to
    # prevent this by forcing our versions to be the gold standard.
    return unless ENV.fetch('DIST', NCI.current_series) == NCI.future_series
    puts 'Setting up apt preference.'
    @preference = Apt::Preference.new('pangea-neon', content: <<-PREFERENCE)
Package: *
Pin: release o=neon
Pin-Priority: 1001
    PREFERENCE
    @preference.write
  end

  def maybe_teardown_apt_preference
    return unless @preference
    puts 'Discarding apt preference.'
    @preference.delete
    @preference = nil
  end

  def maybe_teardown_experimental_apt_preference
    return unless @experimental_preference
    puts 'Discarding testing apt preference.'
    @experimental_preference.delete
    @experimental_preference = nil
  end

  class << self
    private

    def setup_experimental!
      puts 'Setting up apt preference for experimental repository.'
      @experimental_preference = Apt::Preference.new('pangea-neon-experimental',
                                                content: <<-PREFERENCE)
Package: *
Pin: release l=KDE neon - Experimental Edition
Pin-Priority: 1001
      PREFERENCE
      @experimental_preference.write
      ENV['TYPE'] = 'release'
      add_repo!
    end

    # Sets the default release. We'll add the deb-src of all enabled series
    # if enabled. To prevent us from using an incorret series simply force the
    # series we are running under to be the default (outscores others).
    # This effectively increases the apt score of the current series to 990!
    def set_default_release!
      File.write('/etc/apt/apt.conf.d/99-default', <<-CONFIG)
APT::Default-Release "#{setup_repo_codename}";
      CONFIG
    end

    # Sets up source repo(s). This method is special in that it sets up
    # deb-src for all enabled series, not just the current one. This allows
    # finding the "newest" tarball in any series. Which we need to detect
    # and avoid uscan repack divergence between series.
    def add_source_repo!
      set_default_release!
      add_repo_key!
      NCI.series.each_key do |dist|
        # This doesn't use Apt::Repository because it uses apt-add-repository
        # which smartly says
        #   Error: 'deb-src http://archive.neon.kde.org/unstable xenial main'
        #   invalid
        # obviously.
        lines = [debsrcline(dist: dist)]
        # Also add deb entry -.-
        # https://bugs.debian.org/892174
        lines << debline(dist: dist) if dist != setup_repo_codename
        File.write("/etc/apt/sources.list.d/neon_src_#{dist}.list",
                   lines.join("\n"))
        puts "lines: #{lines.join('\n')}"
      end
      disable_all_src
    end

    def disable_all_src
      data = File.read(default_sources_file)
      lines = data.split("\n")
      lines.collect! do |line|
        next line unless line.strip.start_with?('deb-src')
        "# #{line}"
      end
      File.write(default_sources_file, lines.join("\n"))
    end

    def debline(type: ENV.fetch('TYPE'), dist: setup_repo_codename)
      # rename editions but not (yet) renamed the job type
      type = 'testing' if type == 'stable'
      type = type.tr('-', '/')
      format('deb http://archive.neon.kde.org/%<type>s %<dist>s main',
             type: type, dist: dist)
    end

    def debsrcline(type: ENV.fetch('TYPE'), dist: setup_repo_codename)
      # rename editions but not (yet) renamed the job type
      type = 'testing' if type == 'stable'
      type = type.tr('-', '/')
      format('deb-src http://archive.neon.kde.org/%<type>s %<dist>s main',
             type: type, dist: dist)
    end

    def add_repo!
      add_repo_key!
      Retry.retry_it(times: 5, sleep: 4) do
        raise 'adding repo failed' unless Apt::Repository.add(debline)
      end
      puts "added #{debline}"
    end
  end
end
