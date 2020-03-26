#!/usr/bin/env ruby
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

require 'fileutils'

require_relative 'lib/lint/qml'
require_relative 'lib/setup_repo'
require_relative '../../lib/aptly-ext/remote'

NCI.add_repo_key!
NCI.setup_proxy!
NCI.maybe_setup_apt_preference

def without_recommends
  path = '/etc/apt/apt.conf.d/neon-no-recommends'
  File.write(path, <<-CONF)
    APT::Get::Install-Recommends "false";
  CONF
  yield
ensure
  FileUtils.rm_f(path)
end

Aptly::Ext::Remote.neon_read_only do
  without_recommends do
    Lint::QML.new(ENV.fetch('TYPE'), ENV.fetch('DIST')).lint
  end
end
