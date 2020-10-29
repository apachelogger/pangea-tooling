# frozen_string_literal: true
#
# Copyright (C) 2014-2017 Harald Sitter <sitter@kde.org>
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

require 'concurrent'
require 'logger'
require 'logger/colors'
require 'rexml/document'

require_relative '../ci-tooling/lib/retry'
require_relative '../lib/jenkins/job'
require_relative 'template'

# Base class for Jenkins jobs.
class JenkinsJob < Template
  # FIXME: redundant should be name
  attr_reader :job_name

  def initialize(job_name, template_name, **kwords)
    @job_name = job_name
    super(template_name, **kwords)
  end

  # Legit class variable. This is for all JenkinsJobs.
  # rubocop:disable Style/ClassVars
  def remote_jobs
    @@remote_jobs ||= Jenkins.job.list_all
  end

  def safety_update_jobs
    @@safety_update_jobs ||= Concurrent::Array.new
  end

  def self.reset
    @@remote_jobs = nil
  end
  # rubocop:enable Style/ClassVars

  def self.include_pattern
    @include_pattern ||= begin
      include_pattern = ENV.fetch('UPDATE_INCLUDE', '')
      if include_pattern.start_with?('/')
        # TODO: this check would be handy somewhere else. at update we
        #   have done half the work already, so aborting here is meh.
        unless include_pattern.end_with?('/')
          raise 'Include pattern malformed. starts with /, must end with /'
        end

        # eval the regex literal returns a Regexp if valid, raises otherwise
        include_pattern = eval(include_pattern)
      end
      include_pattern
    end
  end

  def include_pattern
    # not going through class, this isn't mutable for different instances of Job
    JenkinsJob.include_pattern
  end

  def include?
    return include_pattern.match?(job_name) if include_pattern.is_a?(Regexp)

    job_name.include?(ENV.fetch('UPDATE_INCLUDE', ''))
  end

  # Creates or updates the Jenkins job.
  # @return the job_name
  def update(log: Logger.new(STDOUT))
    # FIXME: this should use retry_it
    return unless include?

    xml = render_template
    Retry.retry_it(times: 4, sleep: 1) do
      xml_debug(xml) if @debug
      jenkins_job = if ENV['PANGEA_LOCAL_JENKINS']
                      LocalJenkinsJobAdaptor.new(job_name)
                    else
                      Jenkins::Job.new(job_name)
                    end
      log.info job_name

      if remote_jobs.include?(job_name) # Already exists.
        original_xml = jenkins_job.get_config
        if xml_equal(original_xml, xml)
          log.info "♻ #{job_name} already up to date"
          return
        end
        log.info "#{job_name} updating..."
        jenkins_job.update(xml)
      elsif safety_update_jobs.include?(job_name)
        log.info "#{job_name} carefully updating..."
        jenkins_job.update(xml)
      else
        log.info "#{job_name} creating..."
        begin
          jenkins_job.create(xml)
        rescue JenkinsApi::Exceptions::JobAlreadyExists
          # Jenkins is a shitpile and doesn't always delete jobs from disk.
          # Cause: unknown
          # When this happens it will however throw itself in our face about
          # the thing existing, it is however not in the job list, because, well
          # it doesn't exist... except on disk. To get jenkins to fuck off
          # we'll simply issue an update as though the thing existed, except it
          # doesn't... except on disk.
          # The longer we use Jenkins the more I come to hate it. With a passion
          log.warn "#{job_name} already existed apparently, updating instead..."
          safety_update_jobs << job_name
        end
      end
    end
  end

  private

  def xml_debug(data)
    xml_pretty(data, $stdout)
  end

  def xml_equal(data1, data2)
    xml_pretty_string(data1) == xml_pretty_string(data2)
  end

  def xml_pretty_string(data)
    io = StringIO.new
    xml_pretty(data, io)
    io.rewind
    io.read
  end

  def xml_pretty(data, io)
    doc = REXML::Document.new(data)
    REXML::Formatters::Pretty.new.write(doc, io)
  end

  alias to_s job_name
  alias to_str to_s
end
