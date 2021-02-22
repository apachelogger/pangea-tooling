# frozen_string_literal: true
# SPDX-License-Identifier: LGPL-2.1-only OR LGPL-3.0-only OR LicenseRef-KDE-Accepted-LGPL
# SPDX-FileCopyrightText: 2016-2017 Rohan Garg <rohan@garg.io>
# SPDX-FileCopyrightText: 2017-2021 Harald Sitter <sitter@kde.org>

require 'vcr'

require_relative '../lib/ci/container'
require_relative '../lib/ci/container/ephemeral'
require_relative 'lib/testcase'

require 'mocha/test_unit'

# The majority of functionality is covered through containment.
# Only test what remains here.
class ContainerTest < TestCase
  # :nocov:
  def cleanup_container
    # Make sure the default container name isn't used, it can screw up
    # the vcr data.
    c = Docker::Container.get(@job_name)
    c.stop
    c.kill! if c.json.fetch('State').fetch('Running')
    c.remove
  rescue Docker::Error::NotFoundError, Excon::Errors::SocketError
  end
  # :nocov:

  def setup
    VCR.configure do |config|
      config.cassette_library_dir = datadir
      config.hook_into :excon
      config.default_cassette_options = {
        match_requests_on: %i[method uri body],
        tag: :erb_pwd
      }
      config.filter_sensitive_data('<%= Dir.pwd %>', :erb_pwd) { Dir.pwd }
    end

    @job_name = self.class.to_s
    @image = 'ubuntu:15.04'
    VCR.turned_off { cleanup_container }
  end

  def teardown
    VCR.turned_off { cleanup_container }
  end

  def vcr_it(meth, **kwords)
    VCR.use_cassette(meth, kwords) do |cassette|
      if cassette.recording?
        VCR.eject_cassette
        VCR.turned_off do
          Docker::Image.create(fromImage: @image)
        end
        VCR.insert_cassette(cassette.name)
      else
        CI::EphemeralContainer.safety_sleep = 0
      end
      yield cassette
    end
  end

  def test_exist
    vcr_it(__method__, erb: true) do
      assert(!CI::Container.exist?(@job_name))
      CI::Container.create(Image: @image, name: @job_name)
      assert(CI::Container.exist?(@job_name))
    end
  end

  ### Compatibility tests! DirectBindingArray used to live in Container.

  def test_to_volumes
    v = CI::Container::DirectBindingArray.to_volumes(['/', '/tmp'])
    assert_equal({ '/' => {}, '/tmp' => {} }, v)
  end

  def test_to_bindings
    b = CI::Container::DirectBindingArray.to_bindings(['/', '/tmp'])
    assert_equal(%w[/:/ /tmp:/tmp], b)
  end

  def test_to_volumes_mixed_format
    v = CI::Container::DirectBindingArray.to_volumes(['/', '/tmp:/tmp'])
    assert_equal({ '/' => {}, '/tmp' => {} }, v)
  end

  def test_to_bindings_mixed_fromat
    b = CI::Container::DirectBindingArray.to_bindings(['/', '/tmp:/tmp'])
    assert_equal(%w[/:/ /tmp:/tmp], b)
  end

  def test_to_bindings_colons
    # This is a string containing colon but isn't a binding map
    path = '/tmp/CI::ContainmentTest20150929-32520-12hjrdo'
    assert_raise do
      CI::Container::DirectBindingArray.to_bindings([path])
    end

    # This is a string containing colons but is already a binding map because
    # it is symetric.
    path = '/tmp:/tmp:/tmp:/tmp'
    assert_raise do
      CI::Container::DirectBindingArray.to_bindings([path.to_s])
    end

    # Not symetric but the part after the first colon is an absolute path.
    path = '/tmp:/tmp:/tmp'
    assert_raise do
      CI::Container::DirectBindingArray.to_bindings([path.to_s])
    end
  end

  def test_env_whitelist
    # No problems with empty
    ENV['DOCKER_ENV_WHITELIST'] = nil
    CI::Container.default_create_options
    ENV['DOCKER_ENV_WHITELIST'] = ''
    CI::Container.default_create_options

    # Whitelist
    ENV['XX_YY_ZZ'] = 'meow'
    ENV['ZZ_YY_XX'] = 'bark'
    # Single
    ENV['DOCKER_ENV_WHITELIST'] = 'XX_YY_ZZ'
    assert_include CI::Container.default_create_options[:Env], 'XX_YY_ZZ=meow'
    # Multiple
    ENV['DOCKER_ENV_WHITELIST'] = 'XX_YY_ZZ:ZZ_YY_XX'
    assert_include CI::Container.default_create_options[:Env], 'XX_YY_ZZ=meow'
    assert_include CI::Container.default_create_options[:Env], 'ZZ_YY_XX=bark'
    # Hardcoded core variables (should not require explicit whitelisting)
    ENV['DIST'] = 'flippytwitty'
    assert_include CI::Container.default_create_options[:Env], 'DIST=flippytwitty'
  ensure
    ENV.delete('DOCKER_ENV_WHITELIST')
  end
end
