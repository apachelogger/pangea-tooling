#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Copyright (C) 2016-2017 Harald Sitter <sitter@kde.org>
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

# Enable the apt resolver by default (instead of pbuilder); should be faster!
# NB: This needs to be set before requires, it's evaluated at global scope.
# TODO: make default everywhere. only needs some soft testing in production
ENV['PANGEA_APT_RESOLVER'] = '1'

require_relative 'lib/setup_repo'
require_relative '../lib/ci/build_binary'
require_relative '../lib/nci'
require_relative '../lib/retry'

NCI.setup_repo!

if File.exist?('/ccache')
  require 'mkmf' # for find_exectuable

  Retry.retry_it(times: 4) { Apt.install('ccache') || raise }
  system('ccache', '-z') # reset stats, ignore return value
  ENV['PATH'] = "/usr/lib/ccache:#{ENV.fetch('PATH')}"
  # Debhelper's cmake.pm doesn't resolve from PATH. Bloody crap.
  ENV['CC'] = find_executable('cc')
  ENV['CXX'] = find_executable('c++')
  ENV['CCACHE_DIR'] = '/ccache'
end

no_adt = NCI.only_adt.none? { |x| ENV['JOB_NAME']&.include?(x) }
# Hacky: p-f's tests/testengine is only built and installed when
#   BUILD_TESTING is set, fairly weird but I don't know if it is
#   intentional
# - kimap installs kimaptest fakeserver/mockjob
#   https://bugs.kde.org/show_bug.cgi?id=419481
needs_testing = %w[
  plasma-framework
  kimap
]
is_excluded = needs_testing.any? { |x| ENV['JOB_NAME']&.include?(x) }
if no_adt && !is_excluded
  File.write('adt_disabled', '') # marker file to tell our cmake overlay to disable test building
end

builder = CI::PackageBuilder.new
builder.build

if File.exist?('/ccache')
  system('ccache', '-s') # print stats, ignore return value
end

if File.exist?('build_url')
  url = File.read('build_url').strip
  if NCI.experimental_skip_qa.any? { |x| url.include?(x) }
    puts "Not linting, #{url} is in exclusion list."
    exit
  end
  # skip the linting if build dir doesn't exist
  # happens in case of Architecture: all packages on armhf for example
  require_relative 'lint_bin' if Dir.exist?('build')
end

# For the version check we'll need to unmanagle the preference pin as we rely
# on apt show to give us 'available version' info.
NCI.maybe_teardown_apt_preference
NCI.maybe_teardown_experimental_apt_preference

# Check that our versions are good enough.
unless system('/tooling/nci/lint_versions.rb', '-v')
  warn 'bad versions?'
  warn File.expand_path('../../nci/lint_versions.rb')
  # raise 'Bad version(s)'
end
