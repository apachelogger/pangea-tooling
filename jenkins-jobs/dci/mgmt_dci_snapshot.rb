# frozen_string_literal: true
require_relative '../job'

# Generate a job to run snapshots of aptly repos.
class DCISnapShotJob < JenkinsJob
  attr_reader :architecture
  attr_reader :release
  attr_reader :snapshot
  attr_reader :series
  attr_reader :arm_board

  def initialize(snapshot:, series:, release:, architecture:, arm_board: nil)
    @release_type = release_type
    @architecture = architecture
    @snapshot = snapshot
    @series = series
    @arm_board = arm_board
    if @arm_board
      super("snapshot_#{series}_#{release}_#{snapshot}_#{architecture}_#{arm_board}", 'mgmt_dci_snapshot.xml.erb')
    else
      super("snapshot_#{series}_#{release}_#{snapshot}_#{architecture}", 'mgmt_dci_snapshot.xml.erb')
    end
  end
end
