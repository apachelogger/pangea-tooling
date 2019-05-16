#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Copyright (C) 2018 Harald Sitter <sitter@kde.org>
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

require_relative 'jenkins_jobs_update_nci'

SNAPS = %w[
  blinken
  bomber
  bovo
  falkon
  granatier
  katomic
  kblackbox
  kbruch
  kblocks
  kcalc
  kgeography
  kmplot
  kollision
  konversation
  kruler
  ksquares
  kteatime
  ktuberling
  ktouch
  okular
  picmi
].freeze

# Updates Jenkins Projects
class OpenQAProjectUpdater < ProjectUpdater
  private

  def populate_queue
    NCI.series.each_key do |series|
      # TODO: maybe we should have an editions list?
      NCI.types.each do |type|
        next if type == NCI.qt_stage_type

        # Standard install
        enqueue(OpenQAInstallJob.new(series: series, type: type))

        # LTS is useless work to maintain. Only support core installs.
        # We don't officially offer or support LTS much anyway.
        next if type == 'release-lts'

        # Advanced install scenarios
        enqueue(OpenQAInstallOfflineJob.new(series: series, type: type))
        enqueue(OpenQAInstallSecurebootJob.new(series: series, type: type))
        enqueue(OpenQAInstallBIOSJob.new(series: series, type: type))

        # Skip this for xenial. It's about to die in favor of bionic anyway.
        if series != 'xenial'
          enqueue(OpenQAInstallPartitioningJob.new(series: series, type: type))
        end

        if type == 'release'
          # TODO: l10n with cala should work nowadays, but needs needles created
          enqueue(OpenQAInstallNonEnglishJob.new(series: series, type: type))
          enqueue(OpenQAInstallOEMJob.new(series: series, type: type))
        end

        if %w[unstable release].include?(type)
          enqueue(OpenQATestJob.new('plasma',
                                    series: series, type: type,
                                    extra_env: %w[PLASMA_DESKTOP=5]))
          enqueue(
            OpenQATestJob.new(
              'plasma-wayland',
              series: series, type: type,
              extra_env: %w[TESTS_TO_RUN=tests/plasma/plasma_wayland.pm]
            )
          )
        end
      end
    end

    SNAPS.each do |snap|
      enqueue(OpenQASnapJob.new(snap, channel: 'candidate'))
    end
  end

  # Don't do a template check. It doesn't support only listing openqa_*
  # FIXME: fix this method to support our use case
  def check_jobs_exist; end
end

if $PROGRAM_NAME == __FILE__
  updater = OpenQAProjectUpdater.new
  updater.update
  updater.install_plugins
end
