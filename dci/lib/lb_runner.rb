# frozen_string_literal: true
require 'fileutils'

class LiveBuildRunner
  class Error < RuntimeError; end
  class ConfigError < Error; end
  class BuildFailedError < Error; end
  class FlashFailedError < Error; end

  def initialize(config_dir = Dir.pwd)
    @config_dir = config_dir
    Dir.chdir(@config_dir) do
      raise ConfigError unless File.exist?('configure') || Dir.exist?('auto')
    end
  end

  def configure!
    Dir.chdir(@config_dir) do
      system('./configure') if File.exist? 'configure'
      system('lb config') if Dir.exist? 'auto'
    end
  end

  def build!
    Dir.chdir(@config_dir) do
      begin
        raise BuildFailedError unless system('lb build')

        FileUtils.mkdir_p('result')
        @images = Dir.glob('*.{iso,tar,img}')
        FileUtils.cp(@images, 'result', verbose: true)
      ensure
        system('lb clean --purge')
      end
    end
  end
end
