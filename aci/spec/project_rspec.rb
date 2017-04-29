#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Copyright (C) 2016 Scarlett Clark <sgclark@kde.org>
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

require_relative '../libs/sources'
require_relative '../libs/packages'
require_relative '../libs/metadata'
require 'yaml'

exit_status = 'Expected 0 exit Status'

describe 'build_project' do
  it 'Retrieves sources that need to be built from source' do
    project = Metadata::PROJECT
    if File.directory?("/in/#{project}/#{project}-builddir")
      FileUtils.rm_rf(
        "/in/#{project}/#{project}-builddir"
      )
    end
    sources = Sources.new
    buildsystem = Metadata::METADATA['buildsystem']
    options = Metadata::METADATA['buildoptions']
    p "Name #{project} Buildsytem #{buildsystem} options \
    #{options}".to_s
    expect(Dir.exist?( "/in/#{project}")).to be(true), "source missing"
    expect(
      sources.run_build("#{project}", buildsystem, options)
    ).to be(0), exit_status
    p system("qmlimportscanner -rootPath  /in/#{project}")
  end
end
