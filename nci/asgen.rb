#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Copyright (C) 2016-2021 Harald Sitter <sitter@kde.org>
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
require 'tty-command'

require_relative 'lib/setup_repo'
require_relative '../lib/apt'
require_relative '../lib/asgen'
require_relative '../lib/nci'

# WARNING: this program is run from a minimal debian container without
#  the tooling properly provisioned. Great care must be taken about
#  brining in too many or complex dependencies!

STDOUT.sync = true # lest TTY output from meson gets merged randomly

TYPE = ENV.fetch('TYPE')
DIST = ENV.fetch('DIST')
APTLY_REPOSITORY = ENV.fetch('APTLY_REPOSITORY')
LAST_BUILD_STAMP = File.absolute_path('last_build')

# Runtime Deps - install before repo setup so we get these from debian and
# not run into comapt issues between neon's repo and debian!
Apt::Get.install('libglibd-2.0-dev')
Apt::Get.install('appstream-generator') # Make sure runtime deps are in.

cmd = TTY::Command.new

run_dir = File.absolute_path('run')

suites = [DIST]
config = ASGEN::Conf.new("neon/#{TYPE}")
# NB: use origin here. dlang's curl wrapper doesn't know how HTTP works and
# parses HTTP/2 status lines incorrectly. Fixed in git and landing with LDC 1.13
# https://github.com/dlang/phobos/commit/1d4cfe3d8875c3e6a57c7e90fb736f09b18ddf2d
config.ArchiveRoot = "https://origin.archive.neon.kde.org/#{APTLY_REPOSITORY}"
config.MediaBaseUrl =
  "https://metadata.neon.kde.org/appstream/#{TYPE}_#{DIST}/media"
config.HtmlBaseUrl =
  "https://metadata.neon.kde.org/appstream/#{TYPE}_#{DIST}/html"
config.Backend = 'debian'
config.ExtraMetainfoDir = "#{Dir.pwd}/extra-metainfo"
config.Features['validateMetainfo'] = true
# FIXME: we should merge the dist jobs and make one job generate all supported
#   series. this also requires adjustments to asgen_push to "detect" which dists
#   it needs to publish instead of hardcoding DIST.
suites.each do |suite|
  config.Suites << ASGEN::Suite.new(suite).tap do |s|
    s.sections = %w[main]
    s.architectures = %w[amd64]
    s.dataPriority = 200 # definitely >> ubuntu (currently caps at 40)
    s.useIconTheme = 'breeze'
  end
end

# Since we are on debian the actual repo codename needs some help to get
# correctly set up. Manually force the right codename.
# Note that we do this here because we only need this to install the
# correct icon themes.
# Also disable proxy since we don't want debian shebang cached (for now)
NCI.setup_repo_codename = DIST
NCI.setup_repo!(with_proxy: false, with_install: false)

# FIXME: http_proxy and friends are possibly not the smartest idea.
#   this will also route image fetching through the proxy I think, and the proxy
#   gets grumpy when it has to talk to unknown servers (which the image hosting
#   will ofc be)
# Generate
# Install theme to hopefully override icons with breeze version.
Apt.install('breeze-icon-theme', 'hicolor-icon-theme')
FileUtils.mkpath(run_dir) unless Dir.exist?(run_dir)
config.write("#{run_dir}/asgen-config.json")
suites.each do |suite|
  cmd.run('appstream-generator', 'process', '--verbose', suite, chdir: run_dir)
end

# TODO
# [15:03] <ximion> sitter: the version number changing isn't an issue -
# it does nothing with one architecture, and it's an optimization if you have
# at least one other architecture.
# [15:03] <ximion> sitter: you should run ascli cleanup every once in a while
# though, to collect garbage
# https://github.com/ximion/appstream-generator/issues/97

## Manual export dir cleanup since asgen's cleanup isn't hot enough
id_paths = Dir.glob('run/export/media/**/{icons,screenshots}/').collect do |dir|
  File.dirname(dir) # this is the instance id `org.foo.bar/ID/`
end.uniq

component_to_idpaths = id_paths.group_by { |path| File.dirname(path) }.to_h
component_to_idpaths.each do |component, paths|
  # sort by ctime, newer will be farther back in the array
  paths = paths.sort_by { |path| File.ctime(path).to_i }
  paths_to_drop = paths[0..-11] # (-1 is the end so this is offset by 1)
  puts component
  paths_to_drop.each do |path|
    puts "  Dropping #{path}"
    FileUtils.rm_r(path)
  end
end
