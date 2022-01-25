# frozen_string_literal: true
#
# Copyright (C) 2015-2016 Harald Sitter <sitter@kde.org>
# Copyright (C) 2016 Rohan Garg <rohan@garg.io>
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

require 'vcr'

require_relative '../lib/ci/containment'
require_relative 'lib/testcase'

require 'mocha/test_unit'

Docker.options[:read_timeout] = 4 * 60 * 60 # 4 hours.

class DCIDeployInContainerTest < TestCase
  self.file = __FILE__

  # :nocov:
  def cleanup_container
    # Make sure the default container name isn't used, it can screw up
    # the vcr data.
    c = Docker::Container.get(@job_name)
    c.stop
    c.kill!
    c.remove
  rescue Docker::Error::NotFoundError, Excon::Errors::SocketError
  end

  def cleanup_image
    return unless Docker::Image.exist?(@image)

    puts "Cleaning up image #{@image}"
    image = Docker::Image.get(@image)
    image.delete(force: true, noprune: true)
  rescue Docker::Error::NotFoundError, Excon::Errors::SocketError
  end

  def create_container
    puts "Creating new base image #{@image}"
    Docker::Image.create(fromImage: 'debian:22').tag(repo: @repo,
                                                        tag: 'latest')
  end
  # :nocov:

  def setup
    # Disable attaching as on failure attaching can happen too late or not
    # at all as it depends on thread execution order.
    # This can cause falky tests and is not relevant to the test outcome for
    # any test.
    CI::Containment.no_attach = true

    VCR.configure do |config|
      config.cassette_library_dir = datadir
      config.hook_into :excon
      config.default_cassette_options = {
        match_requests_on: %i[method uri body]
      }
      # ERB PWD
      config.filter_sensitive_data('<%= Dir.pwd %>') { Dir.pwd }
    end

    @repo = self.class.to_s.downcase
    @image = "#{@repo}:latest"

    @job_name = @repo.tr(':', '_')
    @tooling_path = File.expand_path("#{__dir__}/../")
    @binds = ["#{Dir.pwd}:/tooling-pending"]
    # Instead of using the live upgrader script, use a stub to avoid failure
    # from actual problems in the upgrader script and/or the system.
    FileUtils.cp_r("#{datadir}/deploy_in_container.sh", Dir.pwd)

    # Fake info call for consistency
    Docker.stubs(:info).returns('DockerRootDir' => '/var/lib/docker')
    Docker.stubs(:version).returns('ApiVersion' => '1.24', 'Version' => '1.12.3')
  end

  def teardown
    VCR.turned_off do
      cleanup_container
    end
    CI::EphemeralContainer.safety_sleep = 5
  end

  def vcr_it(meth, **kwords)
    defaults = {
      erb: true
    }
    VCR.use_cassette(meth, defaults.merge(kwords)) do |cassette|
      if cassette.recording?
        VCR.eject_cassette
        VCR.turned_off do
          cleanup_container
          cleanup_image
          create_container
        end
        VCR.insert_cassette(cassette.name)
      else
        CI::EphemeralContainer.safety_sleep = 0
      end
      yield cassette
    end
  end

  def test_success
    vcr_it(__method__) do
      c = CI::Containment.new(@job_name, image: @image, binds: @binds)
      cmd = ['sh', '/tooling-pending/deploy_in_container.sh',
             'debian', '22']
      ret = c.run(Cmd: cmd)
      assert_equal(0, ret)
      # The script has testing capability built in since we have no proper
      # provisioning to inspect containments post-run in any sort of reasonable
      # way to make assertations. This is a bit of a tricky thing to get right
      # so for the time being inside-testing will have to do.
    end
  end
end
