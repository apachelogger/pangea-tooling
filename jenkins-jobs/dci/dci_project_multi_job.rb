# frozen_string_literal: true
#
# Copyright (C) 2017 Bhushan Shah <bshah@kde.org>
# Copyright (C) 2015-2017 Harald Sitter <sitter@kde.org>
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

require_relative 'sourcer'
require_relative 'binarier'
require_relative 'publisher'
require_relative 'dci_builder'
require_relative '../job'
require_relative 'multijob_phase'
require_relative '../../lib/dci'
# Magic builder to create an array of build steps
class DCIProjectMultiJob < JenkinsJob
  def self.job(project, type:, series:, release_type:, release:, upload_map:, architecture:)
    return [] unless project.debian?

    architecture = architecture.dup
    type = type.dup
    release = release.dup
    release_type = release_type.dup
    series = series.dup
    upload_map = upload_map.dup
    release_distribution = DCI.release_distribution(release, series)
    basename = DCIBuilderJobBuilder.basename(release_distribution, project.component, project.name, architecture)

    dependees = project.dependees.collect do |d|
      DCIBuilderJobBuilder.basename(release_distribution, d.component, d.name, architecture)
    end
    dependees = dependees.compact.uniq.sort

    publisher_dependees = project.dependees.collect do |d|
      "#{basename}_src"
    end.compact

    sourcer = DCISourcerJob.new(
      basename,
      release: release,
      release_type: release_type,
      series: series,
      type: type,
      architecture: architecture,
      project: project
    )
    publisher = DCIPublisherJob.new(
      basename,
      release: release,
      release_type: release_type,
      series: series,
      architecture: architecture,
      dependees: publisher_dependees,
      component: project.component,
      upload_map: upload_map
    )
    binarier = DCIBinarierJob.new(
      basename,
      release: release,
      release_type: release_type,
      series: series,
      architecture: architecture
    )
    jobs = [sourcer, binarier, publisher]
    basename1 = jobs[0].job_name.rpartition('_')[0]
    raise "unexpected basename diff #{basename} v #{basename1}" unless basename == basename1

    jobs << new(basename, project: project, jobs: jobs, dependees: dependees)
    # The actual jobs array cannot be nested, so flatten it out.
    jobs.flatten
  end

  # @! attribute [r] jobs
  #   @return [Array<String>] jobs invoked as part of the multi-phases
  attr_reader :jobs

  # @! attribute [r] dependees
  #   @return [Array<String>] name of jobs depending on this job
  attr_reader :dependees

  # @! attribute [r] project
  #   @return [Project] project instance of this job
  attr_reader :project

  # @! attribute [r] upstream_scm
  #   @return [CI::UpstreamSCM] upstream scm instance of this job_name
  # FIXME: this is a compat thingy for sourcer (see render method)
  attr_reader :upstream_scm

  private

  def initialize(basename, project:, jobs:, dependees: [])
    super(basename, 'project.xml.erb')

    # We use nested jobs for phases with multiple jobs, we need to aggregate
    # them appropriately.
    job_names = jobs.collect do |job|
      next job.collect(&:job_name) if job.is_a?(Array)

      job.job_name
    end

    @nested_jobs = job_names.freeze
    @jobs = job_names.flatten.freeze
    @dependees = dependees.freeze
    @project = project.freeze
  end

  def render_phases
    ret = ''
    @nested_jobs.each_with_index do |job, i|
      ret += MultiJobPhase.new(phase_name: "Phase#{i}",
                               phased_jobs: [job].flatten).render_template
    end
    ret
  end

  def render_packaging_scm
    PackagingSCMTemplate.new(scm: @project.packaging_scm).render_template
  end

  def render_upstream_scm
  @upstream_scm = @project.upstream_scm # FIXME: compat assignment
    return '' unless @upstream_scm
    case @upstream_scm.type
  when 'git'
      render('upstream-scms/git.xml.erb')
    when 'svn'
      render('upstream-scms/svn.xml.erb')
    when 'tarball'
      ''
    when 'bzr'
      ''
    when 'uscan'
      ''
    else
      raise "Unknown upstream_scm type encountered '#{@upstream_scm.type}'"
    end
  end
end
