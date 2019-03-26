#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Copyright (C) 2015-2018 Harald Sitter <sitter@kde.org>
# Copyright (C) 2016 Jonathan Riddell <jr@jriddell.org>
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
require 'net/sftp'
require 'net/ssh'
require 'tty-command'
require_relative 'imager_img_push_support'

DIST = ENV.fetch('DIST')
TYPE = ENV.fetch('TYPE')
ARCH = ENV.fetch('ARCH')
IMAGENAME = ENV.fetch('IMAGENAME')

# copy to master.kde.org using same directory without -proposed for now, later we want
# this to only be published if passing some QA test
DATE = File.read('date_stamp').strip
IMGNAME="#{IMAGENAME}-pinebook-remix-#{TYPE}-#{DATE}-#{ARCH}"
REMOTE_DIR = "neon/images/pinebook-remix-nonfree/"
REMOTE_PUB_DIR = "#{REMOTE_DIR}/#{TYPE}/#{DATE}"

puts "GPG signing disk image file"
unless system('gpg', '--no-use-agent', '--armor', '--detach-sign', '-o',
              "#{IMGNAME}.img.gz.sig",
              "#{IMGNAME}.img")
  raise 'Failed to sign'
end

# SFTPSessionOverlay
# Todo, move it to seperate file
module SFTPSessionOverlay
  def __cmd
    @__cmd ||= TTY::Command.new
  end

  def cli_uploads
    @use_cli_sftp ||= false
  end

  def cli_uploads=(enable)
    @use_cli_sftp = enable
  end

  def __cli_upload(from, to)
    remote = format('%<user>s@%<host>s',
                    user: session.options[:user],
                    host: session.host)
    key_file = ENV.fetch('SSH_KEY_FILE', nil)
    identity = key_file ? ['-i', key_file] : []
    __cmd.run('sftp', *identity, '-b', '-', remote,
              stdin: <<~STDIN)
                put #{from} #{to}
                quit
              STDIN
  end

  def upload!(from, to, **kwords)
    return super unless @use_cli_sftp
    raise 'CLI upload of dirs not implemented' if File.directory?(from)
    # cli wants dirs for remote location
    __cli_upload(from, File.dirname(to))
  end
end
class Net::SFTP::Session
  prepend SFTPSessionOverlay
end

key_file = ENV.fetch('SSH_KEY_FILE', nil)
ssh_args = key_file ? [{ keys: [key_file] }] : []

# Publish ISO and associated content.
Net::SFTP.start('master.kde.org', 'neon', *ssh_args) do |sftp|
  puts "mkdir #{REMOTE_PUB_DIR}"
  sftp.cli_uploads = true
  sftp.mkdir!(REMOTE_PUB_DIR)
  types = %w[img.gz img.gz.sig contents zsync sha256sum]
  types.each do |type|
    Dir.glob("*#{type}").each do |file|
      name = File.basename(file)
      STDERR.puts "Uploading #{file}..."
      sftp.upload!(file, "#{REMOTE_PUB_DIR}/#{name}")
    end
  end
  sftp.cli_uploads = false

  # Need a second SSH session here, since the SFTP one is busy looping.
  Net::SSH.start('master.kde.org', 'neon', *ssh_args) do |ssh|
    ssh.exec!("cd #{REMOTE_DIR}/#{TYPE}; rm -f current; ln -s #{DATE} current")
  end

  # delete old directories
  img_directories = sftp.dir.glob("#{REMOTE_DIR}/#{TYPE}", '*').collect(&:name)
  img_directories = old_directories_to_remove(img_directories)
  img_directories.each do |name|
    path = "#{REMOTE_DIR}/#{TYPE}/#{name}"
    STDERR.puts "rm #{path}"
    sftp.dir.glob(path, '*') { |e| sftp.remove!("#{path}/#{e.name}") }
    sftp.rmdir!(path)
  end
end 
