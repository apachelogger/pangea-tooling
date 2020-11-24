#!/bin/bash
#
# Copyright (C) 2017-2018 Harald Sitter <sitter@kde.org>
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

set -ex

# Don't query us about things. We can't answer.
export DEBIAN_FRONTEND=noninteractive

# Disable bloody apt automation crap locking the database.
systemctl disable --now apt-daily.timer
systemctl disable --now apt-daily.service
systemctl mask apt-daily.service
systemctl mask apt-daily.timer
systemctl stop apt-daily.service || true

systemctl disable --now apt-daily-upgrade.timer
systemctl disable --now apt-daily-upgrade.service
systemctl mask apt-daily-upgrade.timer
systemctl mask apt-daily-upgrade.service
systemctl stop apt-daily-upgrade.service || true

# SSH comes up while cloud-init is still in progress. Wait for it to actually
# finish.
until grep '"stage"' /run/cloud-init/status.json | grep -q 'null'; do
  echo "waiting for cloud-init to finish"
  sleep 4
done

# Make sure we do not have random services claiming dpkg locks.
# Nor random background stuff we don't use (snapd, lxd)
ps aux
apt purge -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
  -y unattended-upgrades update-notifier-common snapd lxd

# DOs by default come with out of date cache.
ps aux
apt update

# Make sure the image is up to date.
apt dist-upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"

# Deploy chef 13 and chef-dk 1.3 (we have no ruby right now.)
cd /tmp
wget https://omnitruck.chef.io/install.sh
chmod +x install.sh
./install.sh -v 13
./install.sh -v 1.3 -P chefdk # so we can berks

# Use chef zero to cook localhost.
export NO_CUPBOARD=1
git clone --depth 1 https://github.com/pangea-project/pangea-kitchen.git /tmp/kitchen || true
cd /tmp/kitchen
git pull --rebase
berks install
berks vendor
chef-client --local-mode --enable-reporting

# Make sure we do not have random services claiming dpkg locks.
apt purge -y unattended-upgrades

################################################### !!!!!!!!!!!
chmod 755 /root/deploy_tooling.sh
cp -v /root/deploy_tooling.sh /tmp/
sudo -u jenkins-slave -i /tmp/deploy_tooling.sh
################################################### !!!!!!!!!!!

# Clean up cache to reduce image size.
apt --purge --yes autoremove
apt-get clean
journalctl --vacuum-time=1s
rm -rfv /var/log/journal/*
