# frozen_string_literal: true
require 'docker'
require 'fileutils'
require 'json'
require 'ostruct'
require 'ruby-progressbar'
require 'vcr'

require_relative '../lib/dci'
require_relative '../lib/dpkg'
require_relative 'lib/testcase'
require_relative '../lib/ci/pangeaimage'
require_relative '../lib/ci/container/ephemeral'
require_relative '../lib/mgmt/deployer'

class DeployTest < TestCase
  def setup
    VCR.configure do |config|
      config.cassette_library_dir = datadir
      config.hook_into :excon
      config.default_cassette_options = {
        match_requests_on: %i[method uri body],
        tag: :erb_pwd
      }

      # The PWD is used as home and as such it appears in the interactions.
      # Filter it into a ERB expression we can play back.
      config.filter_sensitive_data('<%= Dir.pwd %>', :erb_pwd) { Dir.pwd }

      # VCR records the binary tar image over the socket, so instead of actually
      # writing out the binary tar, replace it with nil since on replay docker
      # actually always sends out a empty body
      config.before_record do |interaction|
        interaction.response.body = nil if interaction.request.uri.end_with?('export')
      end
    end

    @oldnamespace = CI::PangeaImage.namespace
    @namespace = 'pangea-testing'
    CI::PangeaImage.namespace = @namespace
    @oldhome = ENV.fetch('HOME')
    @oldlabels = ENV['NODE_LABELS']
    ENV['NODE_LABELS'] = 'master'

    # Hardcode ubuntu as the actual live values change and that would mean
    # a) regenerating the test data for no good reason
    # b) a new series might entail an upgrade which gets focused testing
    #    so having it appear in broad testing doesn't make much sense.
    # NB: order matters here, first is newest, last is oldest
    @ubuntu_series = %w[wily vivid]
    # Except for debian, where Rohan couldn't be bothered to read the
    # comment above and it was recorded in reverse.
    @debian_series = %w[1706 1710 backports]
  end

  def teardown
    VCR.configuration.default_cassette_options.delete(:tag)
    CI::PangeaImage.namespace = @oldnamespace
    ENV['HOME'] = @oldhome
    ENV['NODE_LABELS'] = @oldlabels
  end

  def vcr_it(meth, **kwords)
    VCR.use_cassette(meth, kwords) do |cassette|
      CI::EphemeralContainer.safety_sleep = 0 unless cassette.recording?
      yield cassette
    end
  end

  def copy_data
    FileUtils.cp_r(Dir.glob("#{data}/*"), Dir.pwd)
  end

  def load_relative(path)
    load(File.join(__dir__, path.to_str))
  end

  # create base
  def create_base(flavor, tag)
    b = CI::PangeaImage.new(flavor, tag)
    return if Docker::Image.exist?(b.to_s)

    deployer = MGMT::Deployer.new(flavor, tag)
    deployer.create_base
  end

  def remove_base(flavor, tag)
    b = CI::PangeaImage.new(flavor, tag)
    return unless Docker::Image.exist?(b.to_s)

    image = Docker::Image.get(b.to_s)
    # Do not prune to keep the history. Otherwise we have to download the
    # entire image in the _new test.
    image.delete(force: true, noprune: true)
  end

  def deploy_all
    @ubuntu_series.each do |k|
      d = MGMT::Deployer.new('ubuntu', k)
      d.run!
    end

    @debian_series.each do |k|
      d = MGMT::Deployer.new('debian', k)
      d.run!
    end
  end

  def test_deploy_new
    copy_data

    ENV['HOME'] = Dir.pwd
    ENV['JENKINS_HOME'] = Dir.pwd

    vcr_it(__method__, erb: true) do |cassette|
      if cassette.recording?
        VCR.eject_cassette
        VCR.turned_off do
          @ubuntu_series.each do |k|
            remove_base('ubuntu', k)
          end

          @debian_series.each do |k|
            remove_base('debian', k)
          end
        end
        VCR.insert_cassette(cassette.name)
      end

      assert_nothing_raised do
        deploy_all
      end
    end
  end

  def test_deploy_exists
    copy_data

    ENV['HOME'] = Dir.pwd
    ENV['JENKINS_HOME'] = Dir.pwd

    vcr_it(__method__, erb: true) do |cassette|
      if cassette.recording?
        VCR.eject_cassette
        VCR.turned_off do
          @ubuntu_series.each do |k|
            create_base('ubuntu', k)
          end

          @debian_series.each do |k|
            create_base('debian', k)
          end
        end
        VCR.insert_cassette(cassette.name)
      end

      assert_nothing_raised do
        deploy_all
      end
    end
  end

  def test_upgrade
    # When trying to provision an image for an ubuntu series that doesn't exist
    # in dockerhub we can upgrade from an earlier series. To do this we'd pass
    # the version to upgrade from and then expect create_base to actually
    # indicate an upgrade.
    copy_data
    ENV['HOME'] = Dir.pwd

    vcr_recording = nil
    vcr_it(__method__, erb: true) do |cassette|
      vcr_recording = cassette.recording?
      if vcr_recording
        VCR.eject_cassette
        VCR.turned_off do
          remove_base(:ubuntu, 'wily')
          remove_base(:ubuntu, __method__)
        end
        VCR.insert_cassette(cassette.name)
      end

      # Wily should exist so the fallback upgrade shouldn't be used.
      d = MGMT::Deployer.new(:ubuntu, 'wily', %w[vivid])
      upgrade = d.create_base
      assert_nil(upgrade)
      # Fake series name shouldn't exist and trigger an upgrade.
      d = MGMT::Deployer.new(:ubuntu, __method__.to_s, %w[wily])
      upgrade = d.create_base
      assert_not_nil(upgrade)
      assert_equal('wily', upgrade.from)
      assert_equal(__method__.to_s, upgrade.to)
    end
  ensure
    VCR.turned_off do
      remove_base(:ubuntu, __method__) if vcr_recording
    end
  end

  def test_openqa
    # When the hostname contains openqa we want to have autoinst provisioning
    # enabled automatically.
    Socket.expects(:gethostname).returns('foo')
    MGMT::Deployer.new(:ubuntu, 'wily', %w[vivid])
    refute ENV.include?('PANGEA_PROVISION_AUTOINST')

    Socket.expects(:gethostname).returns('foo-openqa-bar')
    MGMT::Deployer.new(:ubuntu, 'wily', %w[vivid])
    assert ENV.include?('PANGEA_PROVISION_AUTOINST')
  ensure
    ENV.delete('PANGEA_PROVISION_AUTOINST')
  end

  def test_target_arch
    # Arch is determined from the node labels, labels.size can be 0-N so make
    # sure we pick the right arch. Otherwise our image can become the wrong
    # arch and set everything on fire!

    # Burried in other labels
    ENV['NODE_LABELS'] = 'persistent abc armhf fooobar'
    assert_equal('armhf', MGMT::Deployer.target_arch)

    # Multiple arch labels aren't supported. This technically could mean
    # 'make two images' but in reality that should need handling on the CI
    # level not the tooling level
    ENV['NODE_LABELS'] = 'arm64 armhf'
    assert_raises { MGMT::Deployer.target_arch }

    # It also checks for multiple dpkg arches coming out of the query. It's
    # untested because I think that cannot actually happen, but the return
    # type is an array, so we need to make sure it's not malformed.
  end
end
