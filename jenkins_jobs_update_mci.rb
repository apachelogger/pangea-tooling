#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Copyright (C) 2017 Bhushan Shah <bshah@kde.org>
#
# This code is based on code in jenkins_jobs_update_nci.rb
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

require_relative 'ci-tooling/lib/mobilekci'
require_relative 'ci-tooling/lib/projects/factory'
require_relative 'lib/jenkins/project_updater'

Dir.glob(File.expand_path('jenkins-jobs/*.rb', __dir__)).each do |file|
  require file
end

Dir.glob(File.expand_path('jenkins-jobs/mci/*.rb', __dir__)).each do |file|
  require file
end

# Updates Jenkins Projects
class ProjectUpdater < Jenkins::ProjectUpdater
  def initialize
    @job_queue = Queue.new
    @flavor = 'mci'
    @projects_dir = "#{__dir__}/ci-tooling/data/projects"
    JenkinsJob.flavor_dir = "#{__dir__}/jenkins-jobs/#{@flavor}"
    super
  end

  private

  def all_template_files
    files = super
    files + Dir.glob("#{JenkinsJob.flavor_dir}/templates/**.xml.erb")
  end

  def populate_queue
    all_builds = []
    all_meta_builds = []
    all_mergers = []
    type_projects = {}

    MCI.types.each do |type|
      projects_file = "#{@projects_dir}/mci/#{type}.yaml"
      projects = ProjectsFactory.from_file(projects_file,
                                           branch: "Neon/#{type}")
      type_projects[type] = projects
    end

    MCI.series.each_key do |distribution|
      MCI.types.each do |type|
        type_projects[type].each do |project|
          jobs = ProjectJob.job(project,
                                distribution: distribution,
                                type: type,
                                architectures: MCI.architectures)
          jobs.each { |j| enqueue(j) }
          all_builds += jobs
        end

        # Meta builds
        all_builds.select! { |j| j.is_a?(ProjectJob) }
        meta_args = {
          downstream_jobs: all_builds
        }
        meta_builder = MetaMergeJob.new(meta_args)
        all_meta_builds << enqueue(meta_builder)
      end
    end

    progenitor = enqueue(
      MgmtProgenitorJob.new(downstream_jobs: all_meta_builds)
    )
    enqueue(MGMTPauseIntegrationJob.new(downstreams: [progenitor]))
    #enqueue(MGMTAptlyJob.new(dependees: [progenitor]))
    #enqueue(MGMTWorkspaceCleanerJob.new)
    docker = enqueue(MGMTDockerJob.new(dependees: all_meta_builds))
    #enqueue(MGMTGerminateJob.new)
    #enqueue(MGMTJenkinsPruneArchivesJob.new)
    #enqueue(MGMTJenkinsPruneLogsJob.new)
    #enqueue(MGMTJenkinsPruneParameterListJob.new)
    #enqueue(MGMTJenkinsArchive.new)
    enqueue(MGMTGitSemaphoreJob.new)
    enqueue(MGMTGitJewellerJob.new)
    tooling_deploy = enqueue(MGMTToolingDeployJob.new(downstreams: [docker]))
    tooling_test =
      enqueue(MGMTToolingTestJob.new(downstreams: [tooling_deploy]))
    enqueue(MGMTToolingProgenitorJob.new(downstreams: [tooling_test]))
  end
end

if $PROGRAM_NAME == __FILE__
  updater = ProjectUpdater.new
  updater.update
  updater.install_plugins
end
