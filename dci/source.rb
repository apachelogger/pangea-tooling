require 'logger'
require 'json'
require_relative '../ci-tooling/lib/debian/changelog'
require_relative '../ci-tooling/lib/logger'

logger = DCILogger.instance

logger.info('Starting source only build')

Dir.chdir('packaging') do
    $changelog = Changelog.new
end

REPOS_FILE = 'debian/meta/extra_repos.json'

repos = ['default']
Dir.chdir("#{ENV['WORKSPACE']}/packaging") do
    if File.exist? REPOS_FILE
        repos += JSON::parse(File.read(REPOS_FILE))['repos']
    end
end

repos = repos.join(',')

SOURCE_NAME = $changelog.name

RELEASE = ENV['JOB_NAME'].split('_')[-1]

system("schroot -u root -c #{RELEASE}-amd64 -d #{ENV['WORKSPACE']} \
        -o jenkins.workspace=#{ENV['WORKSPACE']} \
        -- ruby ./tooling/ci-tooling/dci.rb source \
        -r #{repos} \
        -w #{ENV['WORKSPACE']}/tooling/data \
        -R #{RELEASE} \
         #{ENV['WORKSPACE']}")

Dir.mkdir('build') unless Dir.exist? 'build'

raise 'Cant move files!' unless system("dcmd mv /var/lib/sbuild/build/#{SOURCE_NAME}*.changes build/")

logger.close
