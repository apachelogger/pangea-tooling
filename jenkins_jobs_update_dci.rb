#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Copyright (C) 2015-2016 Harald Sitter <sitter@kde.org>
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

require_relative 'lib/dci'
require_relative 'lib/projects/factory'
require_relative 'lib/jenkins/project_updater'
require_relative 'lib/kdeproject_component'

require 'sigdump/setup'

Dir.glob(File.expand_path('jenkins-jobs/*.rb', __dir__)).sort.each do |file|
  require file
end

Dir.glob(File.expand_path('jenkins-jobs/dci/*.rb', __dir__)).sort.each do |file|
  require file
end

# Updates Jenkins Projects
class ProjectUpdater < Jenkins::ProjectUpdater
  def initialize
    @blacklisted_plugins = [
      'ircbot', # spammy drain on performance
      'instant-messaging' # dep of ircbot and otherwise useless
    ]
    @data_dir = File.expand_path('data', __dir__)
    @projects_dir = File.expand_path('projects/dci', @data_dir)
    upload_map_file = File.expand_path('dci.upload.yaml', @data_dir)
    JenkinsJob.flavor_dir = File.expand_path('jenkins-jobs/dci', __dir__)
    return unless File.exist?(upload_map_file)

    @upload_map = YAML.load_file(upload_map_file)
    super
  end

  private

  def populate_queue
    CI::Overrides.default_files
    all_meta_builds = []
    all_builds = []
    jobs = []
    @series = ''
    @dci_release = ''
    @release_type = ''
    @data_file_name = ''
    @series = ''

    DCI.release_types.each do |release_type|
      @release_type = release_type
      DCI.releases_for_type(@release_type).each do |dci_release|
        @dci_release = dci_release
        @release_data = DCI.get_release_data(@release_type, @dci_release)
        @arm = DCI.arm_board_by_release(@dci_release)
        @data_file_name = DCI.arm?(@dci_release) ? "#{@release_type}-#{@arm}.yaml" : "#{@release_type}.yaml"
        DCI.series.each_key do |series|
          @series = series
          DCI.all_architectures.each do |arch|
            release_arch = DCI.arch_by_release(@dci_release)
            data_dir = File.expand_path(@series, @projects_dir)
            puts "Working on series: #{series} @dci_release: #{@dci_release}"
            raise unless @data_file_name

            file = File.expand_path(@data_file_name,  data_dir)
            projects = ProjectsFactory.from_file(file, branch: "Netrunner/#{@series}")
            raise unless projects

            projects.each do |project|
              next unless release_arch == arch

              jobs = DCIProjectMultiJob.job(
                project,
                release: @dci_release,
                series: @series,
                architecture: arch,
                upload_map: @upload_map
              )
              jobs.each { |j| enqueue(j) }
              all_builds += jobs
            end
           #  # Remove everything but source as they are the anchor points for
           #  # other jobs that might want to reference them.
           #  all_builds.select! { |j| j.job_name.end_with?('_src') }
           #  # This could actually returned into a collect if placed below
           #  meta_build = MetaBuildJob.new(
           #  type: @series,
           #  distribution: release,
           #  downstream_jobs: all_builds
           # )
           # all_meta_builds << enqueue(meta_build)
           # image Jobs
            image_data = DCI.image_data_by_release_type(@release_type)
            @stamp = DateTime.now.strftime("%Y%m%d.%H%M")
            enqueue(
              DCIImageJob.new(
                release: @dci_release,
                series: @series,
                architecture: release_arch,
                repo: image_data[:repo],
                branch: image_data.fetch(@dci_release)[:releases].fetch(@series)
              )
            )
            enqueue(
              DCISnapShotJob.new(
                snapshot: "#{@series}-#{@stamp}",
                series: @series,
                release: @dci_release,
                architecture: release_arch
              )
            )
          end
        end
      end
    end
    docker = enqueue(MGMTDockerJob.new(dependees: all_meta_builds))
    tooling_deploy = enqueue(MGMTToolingDeployJob.new(downstreams: [docker]))
    tooling_progenitor = enqueue(MGMTToolingProgenitorJob.new(downstreams: [tooling_deploy]))
    enqueue(MGMTToolingJob.new(downstreams: [tooling_progenitor], dependees: []))
    enqueue(MGMTPauseIntegrationJob.new(downstreams: all_meta_builds))
    enqueue(MGMTRepoCleanupJob.new)
    enqueue(MGMTDCIReleaseBranchingJob.new)
  end
end

if $PROGRAM_NAME == __FILE__
  updater = ProjectUpdater.new
  updater.install_plugins
  updater.update
end