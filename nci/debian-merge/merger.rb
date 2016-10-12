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

require 'concurrent'
require 'json'
require 'tmpdir'

require_relative 'data'
require_relative 'repository'

module NCI
  module DebianMerge
    # TODO: make generic or port from future to promises
    # A future observer
    class FutureObserver
      attr_reader :observations

      def initialize
        @futures = []
        @observations = Concurrent::Array.new
      end

      def update(time, value, reason)
        p [time, value.nil?, reason]
        @observations << value
      end

      def observe(future)
        @futures << future
        future.add_observer(self)
      end

      def wait_for_all
        @futures.each(&:execute)
        sleep 1 until @futures.all?(&:complete?)
        # raise unless @futures.any?(&:rejected?)
        @futures.find_all(&:rejected?).each do |r|
          raise r.reason
        end
        @observations
      end
    end

    # Conducts a mere into Neon/pending-merge
    class Merger
      def initialize
        @data = Data.from_file
      end

      def run
        Dir.mktmpdir do |tmpdir|
          futures = merge_repos(tmpdir)
          push_futures(futures)
        end
      end

      # kind of private bits

      def merge_future(url, tmpdir)
        repo = Repository.clone_into(url, tmpdir)
        repo.tag_base = @data.tag_base
        repo.merge
        Concurrent::Future.new { repo.push }
      end

      def merge_repos(tmpdir)
        merge_observer = FutureObserver.new
        @data.repos.each do |url|
          f = Concurrent::Future.new do
            merge_future(url, tmpdir)
          end
          merge_observer.observe(f)
        end
        merge_observer.wait_for_all
      end

      def push_futures(futures)
        push_observer = FutureObserver.new
        futures.each { |f| push_observer.observe(f) }
        push_observer.wait_for_all
      end
    end
  end
end

# :nocov:
Merger.new.run if __FILE__ == $PROGRAM_NAME
# :nocov:
