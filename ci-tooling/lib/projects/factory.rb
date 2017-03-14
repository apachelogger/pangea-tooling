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

# We trust our configs entirely.
# rubocop:disable Security/YAMLLoad

require 'yaml'

require_relative '../projects'
Dir["#{__dir__}/factory/*.rb"].each { |f| require f }

# Constructs projects based on a yaml configuration file.
class ProjectsFactory
  class << self
    def factories
      constants.collect do |const|
        klass = const_get(const)
        next nil unless klass.is_a?(Class)
        klass
      end.compact
    end

    def factory_for(type)
      selection = nil
      factories.each do |factory|
        next unless (selection = factory.from_type(type))
        break
      end
      selection
    end

    def from_file(file, **kwords)
      data = YAML.load(File.read(file))
      raise unless data.is_a?(Hash)
      # Special config setting origin control where to draw default upstream_scm
      # data from.
      kwords[:origin] = data.delete('origin').to_sym if data.key?('origin')
      projects = factorize_data(data, **kwords)
      resolve_dependencies(projects)
    end

    # FIXME: I have the feeling some of this should be in project or a
    # different class altogether
    private

    def factorize_data(data, **kwords)
      data.collect do |type, list|
        raise unless type.is_a?(String)
        raise unless list.is_a?(Array)
        factory = factory_for(type)
        raise unless factory
        factory.default_params = factory.default_params.merge(kwords)
        factory.factorize(list)
      end.flatten.compact
    end

    def provided_by(projects)
      provided_by = {}
      projects.each do |project|
        project.provided_binaries.each do |binary|
          provided_by[binary] = project
        end
      end
      provided_by
    end

    # FIXME: this actually isn't test covered as the factory tests have no
    #   actual dependency chains
    def resolved_dependency(project, dependency, provided_by, projects)
      # NOTE: if this was an instance we could cache provided_by!
      return nil unless provided_by.include?(dependency)
      dependency = provided_by[dependency]
      # Reverse insert us into the list of dependees of our dependency
      projects.collect! do |dep_project|
        next dep_project if dep_project.name != dependency.name
        dep_project.dependees << project
        dep_project.dependees.compact!
        break dep_project
      end
      dependency
    end

    def resolve_dependencies(projects)
      provided_by = provided_by(projects)
      projects.collect do |project|
        project.dependencies.collect! do |dependency|
          next resolved_dependency(project, dependency, provided_by, projects)
        end
        # Ditch nil and duplicates
        project.dependencies.compact!
        project
      end
    end
  end
end
