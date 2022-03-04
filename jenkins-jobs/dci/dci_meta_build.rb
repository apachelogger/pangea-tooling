# frozen_string_literal: true
require_relative '../job'

# Meta builder depending on all builds and being able to trigger them.
class MetaBuildJob < JenkinsJob
  attr_reader :downstream_triggers

  def initialize(type:, distribution:, downstream_jobs:)
    super("mgmt_meta_build__#{type}_#{distribution}", 'dci_meta_build.xml.erb')
    @downstream_triggers = downstream_jobs.collect(&:job_name)
  end
end
