# frozen_string_literal: true
#
# Copyright (C) 2015-2018 Harald Sitter <sitter@kde.org>
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

require_relative '../../ci-tooling/lib/nci'
require_relative '../sourcer'
require_relative '../binarier'
require_relative 'lintcmakejob'
require_relative 'lintqmljob'
require_relative 'publisher'
require_relative '../multijob_phase'

# Magic builder to create an array of build steps
class ProjectJob < JenkinsJob
  def self.job(project, distribution:, architectures:, type:)
    return [] unless project.debian?

    architectures = architectures.dup
    architectures << 'i386' if project.name.include?('util-linux')

    basename = basename(distribution, type, project.component, project.name)

    dependees = project.dependees.collect do |d|
      basename(distribution, type, d.component, d.name)
    end
    # FIXME: frameworks is special, very special ...
    # Base builds have no stable thingy but their unstable version is equal
    # to their not unstable version.
    # NB: '' is for pkg-kde-tools which lives in /
    if (%w[qt] << '').include?(project.component) ||
       %w[pyqt5].include?(project.name) || project.kdecomponent == 'frameworks'
      dependees += project.dependees.collect do |d|
        # Stable is a dependee
        basename(distribution, 'stable', d.component, d.name)
        # Release is as well, but only iff component is not one we release.
        next if project.component == 'frameworks'

        basename(distribution, 'release', d.component, d.name)
      end
    end
    dependees = dependees.compact.uniq.sort

    publisher_dependees = project.dependees.collect do |d|
      "#{basename(distribution, type, d.component, d.name)}_src"
    end.compact
    sourcer = SourcerJob.new(basename,
                             type: type,
                             distribution: distribution,
                             project: project)
    publisher = NeonPublisherJob.new(basename,
                                     type: type,
                                     distribution: distribution,
                                     dependees: publisher_dependees,
                                     component: project.component,
                                     upload_map: nil,
                                     architectures: architectures,
                                     kdecomponent: project.kdecomponent,
                                     project: project)
    binariers = architectures.collect do |architecture|
      BinarierJob.new(basename, type: type, distribution: distribution,
                                architecture: architecture)
    end
    jobs = [sourcer, binariers, publisher]
    basename1 = jobs[0].job_name.rpartition('_')[0]
    unless basename == basename1
      raise "unexpected basename diff #{basename} v #{basename1}"
    end

    unless NCI.experimental_skip_qa.any? { |x| jobs[0].job_name.include?(x) }
      # After _pub
      lintqml = LintQMLJob.new(basename, distribution: distribution, type: type)
      lintcmake = LintCMakeJob.new(basename, distribution: distribution,
                                             type: type)
      jobs << [lintqml, lintcmake]
    end

    jobs << new(basename, distribution: distribution, project: project,
                          jobs: jobs, type: type, dependees: dependees)
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

  # @! attribute [r] distribution
  #   @return [String] codename of distribution
  attr_reader :distribution

  # @! attribute [r] type
  #   @return [String] type name of the build (e.g. unstable or something)
  attr_reader :type

  def self.basename(dist, type, component, name)
    "#{dist}_#{type}_#{component}_#{name}"
  end

  private

  def initialize(basename, distribution:, project:, jobs:, type:, dependees: [])
    super(basename, 'project.xml.erb')

    # We use nested jobs for phases with multiple jobs, we need to aggregate
    # them appropriately.
    job_names = jobs.collect do |job|
      next job.collect(&:job_name) if job.is_a?(Array)

      job.job_name
    end

    @distribution = distribution.freeze
    @nested_jobs = job_names.freeze
    @jobs = job_names.flatten.freeze
    @dependees = dependees.freeze
    @project = project.freeze
    @type = type.freeze
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
    scm = @project.packaging_scm_for(series: @distribution)
    PackagingSCMTemplate.new(scm: scm).render_template
  end

  def render_commit_hook_disabled
    # disable triggers for legacy series during transition-period
    return 'true' if NCI.old_series == distribution

    'false'
  end

  def render_upstream_scm
    @upstream_scm = @project.upstream_scm # FIXME: compat assignment
    return '' unless @upstream_scm # native packages have no upstream_scm

    case @upstream_scm.type
    when 'git', 'svn'
      render("upstream-scms/#{@upstream_scm.type}.xml.erb")
    when 'tarball', 'bzr', 'uscan'
      ''
    else
      raise "Unknown upstream_scm type encountered '#{@upstream_scm.type}'"
    end
  end
end
