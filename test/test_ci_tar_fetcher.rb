# frozen_string_literal: true
#
# Copyright (C) 2015-2018 Harald Sitter <sitter@kde.org>
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

require 'vcr'
require 'webmock/test_unit'

require_relative 'lib/serve'
require_relative 'lib/testcase'

require_relative '../lib/ci/tar_fetcher'

module CI
  class TarFetcherTest < TestCase
    SERVER_PORT = '9475'

    def setup
      VCR.configure do |config|
        config.cassette_library_dir = datadir
        config.hook_into :webmock
        config.default_cassette_options = {
          match_requests_on: %i[method uri body]
        }
      end

      OS.instance_variable_set(:@hash,
                                UBUNTU_CODENAME: NCI.current_series,
                                ID: 'ubuntu')
    end

    def teardown
      OS.reset
    end

    def test_fetch
      VCR.use_cassette(__method__) do
        f = URLTarFetcher.new('http://people.ubuntu.com/~apachelogger/.static/testu-1.0.tar.xz')
        t = f.fetch(Dir.pwd)
        assert(t.is_a?(Tarball))
        assert_path_exist('testu-1.0.tar.xz')
        assert_false(t.orig?)
        assert_equal('testu_1.0.orig.tar.xz', File.basename(t.origify.path))
      end
    end

    def test_fetch_orig
      VCR.use_cassette(__method__) do
        f = URLTarFetcher.new('http://people.ubuntu.com/~apachelogger/.static/testu_1.0.orig.tar.xz')
        t = f.fetch(Dir.pwd)
        assert(t.orig?)
      end
    end

    def test_fetch_escaped_orig
      VCR.use_cassette(__method__) do
        f = URLTarFetcher.new('http://http.debian.net/debian/pool/main/libd/libdbusmenu-qt/libdbusmenu-qt_0.9.3%2B15.10.20150604.orig.tar.gz')
        t = f.fetch(Dir.pwd)
        file = File.basename(t.origify.path)
        assert_equal('libdbusmenu-qt_0.9.3+15.10.20150604.orig.tar.gz', file)
      end
    end

    # TODO: maybe split
    def test_watch_fetch
      require_binaries(%w[uscan])

      assert_raise RuntimeError do
        WatchTarFetcher.new('/a/b/c')
        # Not a watch
      end
      assert_raise RuntimeError do
        WatchTarFetcher.new('/a/b/watch')
        # Not a debian dir
      end

      Test.http_serve(data('http'), port: SERVER_PORT) do
        f = WatchTarFetcher.new(data('debian/watch'))
        t = f.fetch(Dir.pwd)

        # assert_path_exist('dragon_15.08.1.orig.tar.xz')
        assert_equal(Tarball, t.class)
        assert_path_exist('dragon_15.08.1.orig.tar.xz')
        assert(t.orig?) # uscan mangles by default, we expect it like that
        assert_equal('dragon_15.08.1.orig.tar.xz',
                     File.basename(t.origify.path))
      end
    end

    # test code to mange the watch file to look at alternative server
    # currently only works on stable/
    def test_watch_mangle
      FileUtils.cp_r(data, 'debian/')
      f = WatchTarFetcher.new('debian/watch', mangle_download: true)

      ref_line = 'http://download.kde.internal.neon.kde.org/stable/applications/([\d.]+)/kgamma5-([\d.]+).tar.xz'

      # Mangles are transient, so we need to assert at the time of uscan
      # invocation.
      TTY::Command.any_instance.expects(:run).never
      Object.any_instance.expects(:system).never
      Object.any_instance.expects(:`).never
      TTY::Command.any_instance.expects(:run).once.with do |*args|
        next false unless args[0] == 'uscan'
        data = File.read('debian/watch')
        assert_include(data.chomp!, ref_line)
        true
      end.returns(true)

      f.fetch(Dir.pwd)

      # Since mangles are transient, we should not fine the line afterwards.
      data = File.read('debian/watch')
      assert_not_include(data, ref_line)
    end

    description 'when destdir does not exist uscan shits its pants'
    def test_watch_create_destdir
      require_binaries(%w[uscan])

      # Create an old file. The fetcher is meant to remove this.
      File.write('dragon_15.08.1.orig.tar.xz', '')

      Test.http_serve(data('http'), port: SERVER_PORT) do
        f = WatchTarFetcher.new(data('debian/watch'))
        f.fetch('source')

        assert_path_exist('source/dragon_15.08.1.orig.tar.xz')
      end
    end

    def test_watch_multiple_tars
      FileUtils.cp_r(data, 'debian/')
      # We fully fake this at runtime to not have to provide dummy files...

      files = %w[
        yolo_1.3.2.orig.tar.gz
        yolo_1.2.3.orig.tar.gz
      ]

      TTY::Command
        .any_instance
        .expects(:run)
        .once
        .with do |*args|
          next false unless args[0] == 'uscan'
          files.each { |f| File.write(f, '') }
          true
        end
        .returns(true)
      Object.any_instance.stubs(:system)
            .with('dpkg', '--compare-versions', '1.3.2', 'gt', '1.2.3')
            .returns(true)
      Object.any_instance.stubs(:system)
            .with('dpkg', '--compare-versions', '1.2.3', 'gt', '1.3.2')
            .returns(false)
      Object.any_instance.stubs(:system)
            .with('dpkg', '--compare-versions', '1.2.3', 'lt', '1.3.2')
            .returns(true)

      f = WatchTarFetcher.new('debian/watch')
      tar = f.fetch(Dir.pwd)
      assert_not_nil(tar)

      assert_path_exist(files[0])
      assert_path_not_exist(files[1])
    end

    def test_watch_multiple_entries
      require_binaries(%w[uscan])

      Test.http_serve(data('http'), port: SERVER_PORT) do
        f = WatchTarFetcher.new(data('debian/watch'))
        f.fetch('source')

        # On 20.04 uscan only fetches one of the multiple matching downlods.
        # Seems to be consistently the first one.
        # This test was only concerned with fetching works at all when multiple
        # entries are present - preveiously it did not, so even if we only
        # get one of the entries back that still passes our expectation.
        # NB: double check if you want to add another assertion on the
        #   other entry (orig-contrib.tar.gz)
        assert_path_exist('source/opencv_3.2.0.orig.tar.gz')
      end
    end

    def test_watch_with_series
      require_binaries(%w[uscan])

      TTY::Command
        .any_instance
        .expects(:run!)
        .with('apt-get', 'source', '--only-source', '--download-only', '-t', 'vivid', 'dragon',
              chdir: 'source') do |*args|
                Dir.chdir('source') do
                  File.write('dragon_15.08.1.orig.tar.xz', '')
                  File.write('dragon_15.08.1-4:15.08.1-0ubuntu1.dsc', '')
                  File.write('dragon_15.08.1-4:15.08.1-0ubuntu1.debian.tar.xz', '')
                end

                args == ['apt-get', 'source', '--only-source', '--download-only', '-t', 'vivid',
                         'dragon', chdir: 'source']
              end
        .returns(nil)

      Test.http_serve(data('http'), port: SERVER_PORT) do
        f = WatchTarFetcher.new(data('debian/watch'), series: ['vivid'])
        f.fetch('source')

        assert_path_exist('source/dragon_15.08.1.orig.tar.xz')
        assert_path_not_exist('source/dragon_15.08.1-4:15.08.1-0ubuntu1.dsc')
        assert_path_not_exist('source/dragon_15.08.1-4:15.08.1-0ubuntu1.debian.tar.xz')
      end
    end

    def test_watch_tar_finder_with_lingering_tar_of_higher_version
      require_binaries(%w[uscan])

      # In a see of incorrect tarballs we always want to find the right one!
      # Previously we used a fairly daft approach for this which often located
      # the wrong file.

      FileUtils.mkdir('source')
      FileUtils.touch('source/dragon_16.08.1+dfsg.orig.tar.xz')
      FileUtils.touch('source/dragon_17.orig.tar.xz')
      FileUtils.touch('source/dragon_17.tar.xz')
      FileUtils.touch('source/meow_17.tar.xz')

      TTY::Command
        .any_instance
        .expects(:run!)
        .with('apt-get', 'source', '--only-source', '--download-only', '-t', 'vivid', 'dragon',
              chdir: 'source') do |*args|
                Dir.chdir('source') do
                  File.write('dragon_15.08.1.orig.tar.xz', '')
                  File.write('dragon_15.08.1-4:15.08.1-0ubuntu1.dsc', '')
                  File.write('dragon_15.08.1-4:15.08.1-0ubuntu1.debian.tar.xz', '')
                end

                args == ['apt-get', 'source', '--only-source', '--download-only', '-t', 'vivid',
                         'dragon', chdir: 'source']
              end
        .returns(nil)

      Test.http_serve(data('http'), port: SERVER_PORT) do
        f = WatchTarFetcher.new(data('debian/watch'), series: ['vivid'])
        tarball = f.fetch('source')

        assert_equal("#{Dir.pwd}/source/dragon_15.08.1.orig.tar.xz", tarball.path)
      end
    end

    def test_watch_fetch_repack
      require_binaries(%w[uscan])

      OS.instance_variable_set(:@hash,
                                UBUNTU_CODENAME: NCI.current_series + '1',
                                ID: 'ubuntu')

      # Not passing any series in and expecting a failure as we'd repack
      # on a series that isn't NCI.current_series
      assert_raises CI::WatchTarFetcher::RepackOnNotCurrentSeries do
        WatchTarFetcher.new(data('debian/watch')).fetch('source')
      end
    end

    def test_watch_hyphen_in_orig
      require_binaries(%w[uscan])

      Test.http_serve(data('http'), port: SERVER_PORT) do
        f = WatchTarFetcher.new(data('debian/watch'))
        f.fetch('source')

        assert_path_exist('source/qtchooser_64-ga1b6736.orig.tar.gz')
      end
    end

    def test_watch_native
      # native packages need not run uscan. It makes no sense as they generate
      # their own source. Make sure this doesn't happen anywhere.
      require_binaries(%w[uscan])

      assert_raises CI::WatchTarFetcher::NativePackaging do
        WatchTarFetcher.new(data('debian/watch'))
      end
    end

    def test_url_fetch_twice
      VCR.turned_off do
        stub_request(:get, 'http://troll/dragon-15.08.1.tar.xz')
          .to_return(body: File.read(data('http/dragon-15.08.1.tar.xz')))

        f = URLTarFetcher.new('http://troll/dragon-15.08.1.tar.xz')
        t = f.fetch(Dir.pwd)
        assert_false(t.orig?, "File orig but was not meant to #{t.inspect}")

        # And again this actually should not do a request.
        f = URLTarFetcher.new('http://troll/dragon-15.08.1.tar.xz')
        t = f.fetch(Dir.pwd)
        assert_false(t.orig?, "File orig but was not meant to #{t.inspect}")

        assert_requested(:get, 'http://troll/dragon-15.08.1.tar.xz', times: 1)
      end
    end

    def test_deb_scm_fetch
      assert_raises do
        # No content
        DebSCMFetcher.new.fetch('source')
      end

      FileUtils.mkpath('debscm')
      File.write('debscm/foo_1.orig.tar.xz', '')
      File.write('debscm/foo_1-1.debian.tar.xz', '')
      File.write('debscm/foo_1-1.dsc', '')

      DebSCMFetcher.new.fetch('source')
    end
  end
end
