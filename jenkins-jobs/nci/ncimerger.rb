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

require_relative '../job'
require_relative '../../lib/nci'

# Mergers merge a set of branches
class NCIMergerJob < JenkinsJob
  attr_reader :packaging_scm
  attr_reader :merge_branches
  attr_reader :dependees

  def initialize(project, dependees:, branches:)
    if project.component == 'kf6'
      name = "kf6_#{project.name}"
    else
      name = project.name
    end
    super("merger_#{name}", 'merger.xml.erb')
    @packaging_scm = project.packaging_scm
    @merge_branches = branches
    @dependees = dependees
  end
end
