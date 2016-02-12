require 'logger'
require 'json'
require_relative '../ci-tooling/lib/debian/changelog'
require_relative '../ci-tooling/lib/logger'

logger = DCILogger.instance

logger.info('Starting source only build')

if File.exist? 'source/debian/source/format'
  PACKAGING_DIR = 'source'.freeze
else
  PACKAGING_DIR = 'packaging'.freeze
end

Dir.chdir(PACKAGING_DIR) do
  $changelog = Changelog.new
end

REPOS_FILE = 'debian/meta/extra_repos.json'.freeze

repos = ['default']
Dir.chdir("#{ENV['WORKSPACE']}/#{PACKAGING_DIR}") do
  repos << JSON.parse(File.read(REPOS_FILE))['repos'] if File.exist? REPOS_FILE
end

repos = repos.join(',')

SOURCE_NAME = $changelog.name

RELEASE = ENV['JOB_NAME'].split('_')[-1]

if RbConfig::CONFIG['host_cpu'] == 'arm'
  ARCH = 'armhf'.freeze
else
  ARCH = 'amd64'.freeze
end

system("schroot -u root -c #{RELEASE}-#{ARCH} -d #{ENV['WORKSPACE']} \
        -o jenkins.workspace=#{ENV['WORKSPACE']} \
        -- ruby ./tooling/ci-tooling/dci.rb source \
        -r #{repos} \
        -w #{ENV['WORKSPACE']}/tooling/data \
        -R #{RELEASE} \
         #{ENV['WORKSPACE']}")

Dir.mkdir('build') unless Dir.exist? 'build'

raise 'Cant move files!' unless system("dcmd mv /var/lib/sbuild/build/#{SOURCE_NAME}*.changes build/")

logger.close
