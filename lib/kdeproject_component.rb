# frozen_string_literal: true
#
# Copyright (C) 2018 Harald Sitter <sitter@kde.org>
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

# downloads and makes available as arrays lists of jobs which 
# are part of Plasma, Applications and Frameworks

require 'httparty'

class KDEProjectsComponent
  @projects_to_jobs = {'kirigami'=> 'kirigami2', 'discover'=> 'plasma-discover'}
  class << self
      
    def frameworks
      @frameworks ||= to_names(projects('frameworks'))
    end

    def applications
      @applications ||= begin
        apps = projects('kde').reject {|x| x.start_with?('kde/workspace') }
        to_names(apps)
      end
    end

    def plasma
      @plasma ||= to_names(projects('kde/workspace'))
    end

    private

    def to_names(project_list)
      project_list.collect! { |project| project.split('/')[-1] }
      @projects_to_jobs.each do |project_name, job_name|
        index = project_list.find_index(project_name)
        project_list[index] = job_name unless index.nil?
      end
      project_list
    end

    def projects(filter)
      url = "https://projects.kde.org/api/v1/projects/#{filter}"
      response = HTTParty.get(url)
      response.parsed_response
    end
  end
end
