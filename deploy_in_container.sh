#!/bin/bash

set -ex

SCRIPTDIR=$(readlink -f $(dirname -- "$0"))

export DEBIAN_FRONTEND=noninteractive
export LANG=en_US.UTF-8

env_tag="LANG=$LANG"
(! grep -q $env_tag /etc/profile) && echo $env_tag >> /etc/profile
(! grep -q $env_tag /etc/environment) && echo $env_tag >> /etc/environment

# Ubuntu's armhf and aarch64 containers are a bit fscked right now
# manually fix their source entries
(grep -q ports.ubuntu.com /etc/apt/sources.list) && cat > /etc/apt/sources.list << EOF
deb http://ports.ubuntu.com/ubuntu-ports/ $DIST main universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports/ $DIST-updates main universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports/ $DIST-security main universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports/ $DIST-backports main universe multiverse
EOF

echo 'Acquire::Languages "none";' > /etc/apt/apt.conf.d/00aptitude
echo 'APT::Color "1";' > /etc/apt/apt.conf.d/99color

i="5"
while [ $i -gt 0 ]; do
  apt-get update && break
  i=$((i-1))
  sleep 60 # sleep a bit to give problem a chance to resolve
done

if [ "$DIST" = "bionic" ]; then
  # Workaround to make sure early bionic builds don't break.
  apt-mark hold makedev # do not update makedev it won't work on unpriv'd
fi

ESSENTIAL_PACKAGES="rake ruby ruby-dev build-essential zlib1g-dev git-core libffi-dev cmake pkg-config wget dirmngr ca-certificates debhelper"
i="5"
while [ $i -gt 0 ]; do
  apt-get -y -o APT::Get::force-yes=true -o Debug::pkgProblemResolver=true \
    install ${ESSENTIAL_PACKAGES} && break
  i=$((i-1))
done

cd $SCRIPTDIR
# Ensure rake is installed
ruby -e "Gem.install('rake')"
# And tty-command (used by apt, which we'll load in the rake tasks)
ruby -e "Gem.install('tty-command') unless Gem::Specification.map(&:name).include?('tty-command')"

exec rake -f deploy_in_container.rake deploy_in_container
