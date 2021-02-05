#!/usr/bin/env ruby
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

require 'aptly'
require 'terminal-table'
require_relative 'lib/repo_diff'

dist = NCI.current_series

parser = OptionParser.new do |opts|
  opts.banner =
    "Usage: #{opts.program_name} REPO1 REPO2"

  opts.on('-d DIST', '--dist DIST', 'Distribution label to look for') do |v|
    dist = v
  end
end
parser.parse!

Aptly.configure do |config|
  config.uri = URI::HTTPS.build(host: 'archive-api.neon.kde.org')
  # This is read-only.
end

puts "Checking dist: #{dist}"

differ = RepoDiff.new
rows = differ.diff_repo(ARGV[0], ARGV[1], dist)
puts Terminal::Table.new(rows: rows)
