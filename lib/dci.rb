# frozen_string_literal: true
require_relative 'xci'

# Debian CI specific data.
module DCI
  extend XCI

  module_function

  def previous_series
    data['previous_series']
  end
  
  def all_image_data
    file = File.expand_path("../data/dci/dci.image.yaml", __dir__)
    raise "Data file not found (#{file})" unless File.exist?(file)

    @all_image_data = YAML.load(File.read(file))
    @all_image_data.each_value(&:freeze) # May be worth looking into a deep freeze gem.
  end

  def image_data_by_release_type(type)
    all_image_data[type]
  end

  def arm_boards
    data['arm_boards']
  end

  def aptly_prefix(type)
    type == 'zynthbox' ? 'zynthbox' : 'netrunner'
  end
  
  def arm?(rel)
    rel.end_with?('c1', 'rock64', 'rpi4')
  end

  def arm_board_by_release(release_data)
    release_data['arm_board']
  end

  def arch_by_release(release_data)
    release_data['arch']
  end

  def components_by_release(release_data)
    release_data['components'].split
  end

  def release_types
    data['release_types'].keys
  end

  def releases_for_type(type)
    data['release_types'].fetch(type)['releases'].keys
  end

  def release_data_for_type(type)
    data['release_types'].fetch(type)['releases']
  end

  def get_release_data(type, release)
    release_data_for_type(type)[release].to_h
  end
end
