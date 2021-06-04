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

require_relative 'lib/testcase'

require 'mocha/test_unit'
require 'rugged'

require_relative '../nci/debian-merge/tagdetective'

module NCI
  module DebianMerge
    class NCITagDetectiveTest < TestCase
      def setup; end

      def test_last_tag_base
        stub_request(:get, "https://projects.kde.org/api/v1/projects/frameworks").
          with(
            headers: {
                'Accept'=>'*/*',
                'Accept-Encoding'=>'gzip;q=1.0,deflate;q=0.6,identity;q=0.3',
                'User-Agent'=>'Ruby'
            }).
          to_return(status: 200, body: '["frameworks/extra-cmake-modules"]', headers: { 'Content-Type' => 'text/json' })
        remote_dir = File.join(Dir.pwd, 'frameworks/extra-cmake-modules')
        FileUtils.mkpath(remote_dir)
        Dir.chdir(remote_dir) do
          `git init --bare .`
        end
        Dir.mktmpdir do |tmpdir|
          Dir.chdir(tmpdir) do
            `git clone #{remote_dir} clone`
            Dir.chdir('clone') do
              File.write('c1', '')
              `git add c1`
              `git commit --all -m 'commit'`
              `git tag debian/1-0`

              File.write('c2', '')
              `git add c2`
              `git commit --all -m 'commit'`
              `git tag debian/2-0`

              `git push --all`
              `git push --tags`
            end
          end
        end
        ProjectsFactory::Neon.stubs(:ls).returns(%w[frameworks/extra-cmake-modules])
        ProjectsFactory::Neon.stubs(:url_base).returns(Dir.pwd)

        assert_equal('debian/2', TagDetective.new.last_tag_base)
      end

      def test_investigate
        stub_request(:get, "https://projects.kde.org/api/v1/projects/frameworks").
          with(
            headers: {
                'Accept'=>'*/*',
                'Accept-Encoding'=>'gzip;q=1.0,deflate;q=0.6,identity;q=0.3',
                'User-Agent'=>'Ruby'
            }).
          to_return(status: 200, body: '["frameworks/meow"]', headers: { 'Content-Type' => 'text/json' })
        remote_dir = File.join(Dir.pwd, 'kde/meow')
        FileUtils.mkpath(remote_dir)
        Dir.chdir(remote_dir) do
          `git init --bare .`
        end
        Dir.mktmpdir do |tmpdir|
          Dir.chdir(tmpdir) do
            `git clone #{remote_dir} clone`
            Dir.chdir('clone') do
              File.write('c2', '')
              `git add c2`
              `git commit --all -m 'commit'`
              `git tag debian/2-0`

              `git push --all`
              `git push --tags`
            end
          end
        end

        ProjectsFactory::Neon.stubs(:ls).returns(%w[kde/meow])
        ProjectsFactory::Neon.stubs(:url_base).returns(Dir.pwd)

        TagDetective.any_instance.stubs(:last_tag_base).returns('debian/2')

        TagDetective.new.investigate
        assert_path_exist('data.json')
        assert_equal({ 'tag_base' => 'debian/2', 'repos' => [remote_dir] },
                    JSON.parse(File.read('data.json')))
      end

      def test_unreleased
        stub_request(:get, "https://projects.kde.org/api/v1/projects/frameworks").
          with(
            headers: {
                'Accept'=>'*/*',
                'Accept-Encoding'=>'gzip;q=1.0,deflate;q=0.6,identity;q=0.3',
                'User-Agent'=>'Ruby'
            }).
          to_return(status: 200, body: '["frameworks/meow"]', headers: { 'Content-Type' => 'text/json' })

        remote_dir = File.join(Dir.pwd, 'kde/meow')
        FileUtils.mkpath(remote_dir)
        Dir.chdir(remote_dir) do
          `git init --bare .`
        end
        Dir.mktmpdir do |tmpdir|
          Dir.chdir(tmpdir) do
            `git clone #{remote_dir} clone`
            Dir.chdir('clone') do
              File.write('c2', '')
              `git add c2`
              `git commit --all -m 'commit'`

              `git push --all`
              `git push --tags`
            end
          end
        end

        ProjectsFactory::Neon.stubs(:ls).returns(%w[kde/meow])
        ProjectsFactory::Neon.stubs(:url_base).returns(Dir.pwd)

        TagDetective.any_instance.stubs(:last_tag_base).returns('debian/2')

        TagDetective.new.investigate
        assert_path_exist('data.json')
        assert_equal({ 'tag_base' => 'debian/2', 'repos' => [] },
                     JSON.parse(File.read('data.json')))
      end

      def test_released_invalid
        stub_request(:get, "https://projects.kde.org/api/v1/projects/frameworks").
          with(
            headers: {
                'Accept'=>'*/*',
                'Accept-Encoding'=>'gzip;q=1.0,deflate;q=0.6,identity;q=0.3',
                'User-Agent'=>'Ruby'
            }).
          to_return(status: 200, body: '["frameworks/released-invalid"]', headers: { 'Content-Type' => 'text/json' })

        remote_dir = File.join(Dir.pwd, 'kde/released-invalid')
        FileUtils.mkpath(remote_dir)
        Dir.chdir(remote_dir) do
          `git init --bare .`
        end
        Dir.mktmpdir do |tmpdir|
          Dir.chdir(tmpdir) do
            `git clone #{remote_dir} clone`
            Dir.chdir('clone') do
              File.write('c2', '')
              `git add c2`
              `git commit --all -m 'commit'`
              `git tag debian/2-0`

              `git checkout -b Neon/release`

              `git push --all`
              `git push --tags`
            end
          end
        end

        ProjectsFactory::Neon.stubs(:ls).returns(%w[kde/released-invalid])
        ProjectsFactory::Neon.stubs(:url_base).returns(Dir.pwd)

        TagDetective.any_instance.stubs(:last_tag_base).returns('debian/3')

        # the repo has no debian/3 tag, but a Neon/release branch, so it is
        # released but not tagged, which means the invistigation ought to
        # abort with an error.
        assert_raises RuntimeError do
          TagDetective.new.investigate
        end
      end

      def test_pre_existing
        remote_dir = File.join(Dir.pwd, 'frameworks/meow')
        FileUtils.mkpath(remote_dir)
        Dir.chdir(remote_dir) do
          `git init --bare .`
        end
        Dir.mktmpdir do |tmpdir|
          Dir.chdir(tmpdir) do
            `git clone #{remote_dir} clone`
            Dir.chdir('clone') do
              File.write('c2', '')
              `git add c2`
              `git commit --all -m 'commit'`
              `git tag debian/2-0`

              `git push --all`
              `git push --tags`
            end
          end
        end

        # use bogus repos to make sure this works as expected.
        # bogus name should still be present in the end because the detective
        # would simply use the existing file.
        File.write('data.json', JSON.generate({ 'tag_base' => 'debian/2', 'repos' => ['woop'] }))

        ProjectsFactory::Neon.stubs(:ls).returns(%w[frameworks/meow])
        ProjectsFactory::Neon.stubs(:url_base).returns(Dir.pwd)
        TagDetective.any_instance.stubs(:last_tag_base).returns('debian/2')

        TagDetective.new.run
        assert_path_exist('data.json')
        assert_equal({ 'tag_base' => 'debian/2', 'repos' => ['woop'] },
                     JSON.parse(File.read('data.json')))
      end
    end
  end
end
