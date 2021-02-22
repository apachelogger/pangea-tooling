# frozen_string_literal: true
#
# Copyright (C) 2014-2016 Harald Sitter <sitter@kde.org>
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

require 'fileutils'
require 'git'
require 'logger'
require 'logger/colors'
require 'tmpdir'

require_relative 'merger/branch_sequence'

# Stdlib Logger. Monkey patch with factory methods.
class Logger
  def self.merger_formatter
    proc do |severity, _datetime, progname, msg|
      max_line = 80
      white_space_count = 2
      spacers = (max_line - msg.size - white_space_count) / 2
      spacers = ' ' * spacers
      next "\n\e[1m#{spacers} #{msg} #{spacers}\e[0m\n" if severity == 'ANY'

      "[#{severity[0]}] #{progname}: #{msg}\n"
    end
  end

  def self.new_for_merger
    l = Logger.new(STDOUT)
    l.progname = 'merger'
    l.level = Logger::INFO
    l.formatter = merger_formatter
    l
  end

  def self.new_for_git
    l = Logger.new(STDOUT)
    l.progname = 'git'
    l.level = Logger::WARN
    l
  end
end

# A Merger base class. Sets up a repo instance with a working directory
# in a tmpdir that is cleaned upon instance finalization.
# i.e. this keeps the actual clone clean.
class Merger
  class << self
    # Workign directory used by merger.
    attr_reader :workdir
    # Logger instance used by the Merger.
    attr_reader :log

    def cleanup(workdir)
      proc { FileUtils.remove_entry_secure(workdir) }
    end

    def static_init(instance)
      @workdir = Dir.mktmpdir(to_s).freeze
      # Workaround for Git::Base not correctly creating .git for index.lock.
      FileUtils.mkpath("#{@workdir}/.git")
      ObjectSpace.define_finalizer(instance, cleanup(@workdir))
    end
  end

  # Creates a new Merger. Creates a logger, sets up dpkg-mergechangelogs and
  # opens Dir.pwd as a Git::Base.
  def initialize(repo_path = Dir.pwd)
    self.class.static_init(self)

    @log = Logger.new_for_merger

    # SSH key loading is mutually exclusive with semaphore as the
    # semaphore would run git out-of-process, thus bypassing the environment
    # variable making the key not get used.
    setup_semaphore! || setup_ssh_key!

    @repo = open_repo(repo_path)
    configure_repo!
    cleanup_repo!
  end

  def sequence(starting_point)
    BranchSequence.new(starting_point, git: @repo)
  end

  private

  def setup_semaphore!
    return false unless File.exist?('/var/lib/jenkins/git-semaphore/git')

    @log.info 'Setting up git semaphore as git binary'
    Git.configure { |c| c.binary_path = '/var/lib/jenkins/git-semaphore/git' }
    true
  end

  def setup_ssh_key!
    return false unless ENV.include?('SSH_KEY_FILE')

    @log.info 'Setting up GIT_SSH to load the key file defined in SSH_KEY_FILE'
    ENV['GIT_SSH'] = "#{File.expand_path(__dir__)}/libexec/ssh_key_file.sh"
    true
  end

  def open_repo(repo_path)
    repo = Git.open(self.class.workdir,
                    repository: repo_path,
                    log: Logger.new_for_git)
    repo.branches # Trigger an execution to possibly raise an error.
    repo
  rescue Git::GitExecuteError => e
    raise e if repo_path.end_with?('.git', '.git/')

    repo_path = "#{repo_path}/.git"
    retry
  end

  def configure_repo!
    @repo.config('merge.dpkg-mergechangelogs.name',
                 'debian/changelog merge driver')
    @repo.config('merge.dpkg-mergechangelogs.driver',
                 'dpkg-mergechangelogs -m %O %A %B %A')
    repo_path = @repo.repo.path
    FileUtils.mkpath("#{repo_path}/info")
    File.write("#{repo_path}/info/attributes",
               "debian/changelog merge=dpkg-mergechangelogs\n")
  end

  # Hard resets the repository. This deletes ALL local branches in preparation
  # for merging. Deleting all branches makes sure that we do not run into
  # outdated local branches or god forbid local branches that failed to push
  # and now can't be updated properly.
  def cleanup_repo!
    @repo.reset(nil, hard: true)
    @repo.clean(force: true, d: true)
    randomly_detatch
    @repo.branches.local.each { |b| b.current ? next : b.delete }
    @repo.gc
    @repo.config('remote.origin.prune', true)
  end

  def randomly_detatch
    index ||= 0
    remote = @repo.branches.remote.fetch(index)
    remote.checkout
  rescue Git::GitExecuteError
    @log.warn "failed to detatch remote #{remote.full}"
    index += 1
    retry
  rescue IndexError => e
    @log.fatal 'Could not find a remote to detatch from'
    raise e
  end

  def noci_merge?(source)
    log = @git.log.between('', source.full)
    return false unless log.size >= 1

    log.each do |commit|
      return false unless commit.message.include?('NOCI')
    end
    true
  end
end
