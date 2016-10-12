#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Copyright (C) 2016 Harald Sitter <sitter@kde.org>
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

require 'rugged'
require 'tmpdir'

require_relative 'data'

module NCI
  module DebianMerge
    # Finalizes a merge by fast forwarding the pending branch into the
    # target branch.
    class Finalizer
      # Helper class to manage a repo
      class Repo
        attr_reader :rug
        attr_reader :pending
        attr_reader :target

        def initialize(rug)
          @rug = rug
          resolve_branches!
          @rug.checkout(target)
          return if pending.target == target.target
          return if @rug.merge_analysis(pending.target).include?(:fastforward)
          raise "cannot fast forward #{@rug.workdir}, must be out of date :O"
        end

        def resolve_branches!
          resolve_pending!
          resolve_target!
        end

        def resolve_pending!
          @pending = @rug.branches.find do |b|
            b.name == 'origin/Neon/pending-merge'
          end
          raise "#{@rug.workdir} has no pending branch!" unless pending
        end

        def resolve_target!
          @target = @rug.branches.find { |b| b.name == 'origin/Neon/unstable' }
          raise "#{@rug.workdir} has no target branch!" unless target
        end

        def push
          remote = @rug.remotes['origin']
          remote.push(["#{pending.canonical_name}:refs/heads/Neon/unstable"],
                      update_tips: ->(*args) { puts "tip:: #{args}" })
          remote.push([':refs/heads/Neon/pending-merge'],
                      update_tips: ->(*args) { puts "tip:: #{args}" })
        end
      end

      def initialize
        @data = Data.from_file
      end

      def run
        Dir.mktmpdir do |tmpdir|
          # This clones first so we have everything local and asserted a
          # couple of requirements to do with branches
          clone_repos(tmpdir).each(&:push)
        end
      end

      def clone_repos(tmpdir)
        @data.repos.collect do |url|
          rug = Rugged::Repository.clone_at(url,
                                            "#{tmpdir}/#{File.basename(url)}")
          Repo.new(rug)
        end
      end
    end
  end
end

# :nocov:
Finalizer.new.run if __FILE__ == $PROGRAM_NAME
# :nocov:
