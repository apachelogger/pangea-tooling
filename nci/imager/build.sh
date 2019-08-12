#!/bin/sh

set -ex

cleanup() {
    if [ ! -d build ]; then
        mkdir build
    fi
    if [ ! -d result ]; then
        mkdir result
    fi
    rm -rf $WD/result/*
    rm -rf $WD/build/livecd.ubuntu.*
    rm -rf $WD/build/source.debian*
}

export WD=$1
export DIST=$2
export ARCH=$3
export TYPE=$4
export METAPACKAGE=$5
export IMAGENAME=$6
export NEONARCHIVE=$7

if [ -z $WD ] || [ -z $DIST ] || [ -z $ARCH ] || [ -z $TYPE ] || [ -z $METAPACKAGE ] || [ -z $IMAGENAME ] || [ -z $NEONARCHIVE ]; then
    echo "!!! Not all arguments provided! ABORT !!!"
    env
    exit 1
fi

cat /proc/self/cgroup

# FIXME: let nci/lib/setup_repo.rb handle the repo setup as well this is just
# duplicate code here...
ls -lah /tooling/nci
ls -lah /tooling/ci-tooling
ls -lah /tooling/ci-tooling/lib
/tooling/nci/setup_apt_repo.rb --no-repo
sudo apt-add-repository http://archive.neon.kde.org/${NEONARCHIVE}
sudo apt update
sudo apt dist-upgrade -y
sudo apt install -y --no-install-recommends \
    git ubuntu-defaults-builder wget ca-certificates zsync distro-info \
    syslinux-utils livecd-rootfs xorriso pxz base-files lsb-release

cd $WD
ls -lah
cleanup
ls -lah

cd $WD/build

sed -i \
    's%SEEDMIRROR=http://embra.edinburghlinux.co.uk/~jr/neon-seeds/seeds/%SEEDMIRROR=https://metadata.neon.kde.org/germinate/seeds%g' \
    /usr/share/livecd-rootfs/live-build/auto/config

_DATE=$(date +%Y%m%d)
_TIME=$(date +%H%M)
DATETIME="${_DATE}-${_TIME}"
DATE="${_DATE}${_TIME}"

# Random nonesense sponsored by Rohan.
# Somewhere in utopic things fell to shit, so lb doesn't pack all files necessary
# for isolinux on the ISO. Why it happens or how or what is unknown. However linking
# the required files into place seems to solve the problem. LOL.
sudo apt install -y --no-install-recommends  syslinux-themes-ubuntu syslinux-themes-neon
# sudo ln -s /usr/lib/syslinux/modules/bios/ldlinux.c32 /usr/share/syslinux/themes/ubuntu-$DIST/isolinux-live/ldlinux.c32
# sudo ln -s /usr/lib/syslinux/modules/bios/libutil.c32 /usr/share/syslinux/themes/ubuntu-$DIST/isolinux-live/libutil.c32
# sudo ln -s /usr/lib/syslinux/modules/bios/libcom32.c32 /usr/share/syslinux/themes/ubuntu-$DIST/isolinux-live/libcom32.c32

# # Compress with XZ, because it is awesome!
# JOB_COUNT=2
# export MKSQUASHFS_OPTIONS="-comp xz -processors $JOB_COUNT"

# Since we can not define live-build options directly, let's cheat our way
# around defaults-image by exporting the vars lb uses :O

## Super internal var used in lb_binary_disk to figure out the version of LB_DISTRIBUTION
# used in e.g. renaming the ubiquity .desktop file on Desktop by casper which gets it from /cdrom/.disk/info from live-build lb_binary_disk
EDITION=$TYPE
export RELEASE_${DIST}=${EDITION}
## Bring down the overall size a bit by using a more sophisticated albeit expensive algorithm.
export LB_COMPRESSION=none
## Create a zsync file allowing over-http delta-downloads.
export LB_ZSYNC=true # This is overridden by silly old defaults-image...
## Use our cache as proxy.
# FIXME: get out of nci/lib/setup_repo.rb
export LB_APT_HTTP_PROXY="http://apt.cache.pangea.pub:8000"
## Also set the proxy on apt options. This is used internally to expand on a lot
## of apt-get calls. For us primarily of interest because it is used for
## lb_source, which would otherwise bypass the proxy entirely.
export APT_OPTIONS="--yes -o Acquire::http::Proxy='$LB_APT_HTTP_PROXY'"

[ -z "$CONFIG_SETTINGS" ] && CONFIG_SETTINGS="$(dirname "$0")/config-settings-${IMAGENAME}.sh"
[ -z "$CONFIG_HOOKS" ] && CONFIG_HOOKS="$(dirname "$0")/config-hooks-${IMAGENAME}"
[ -z "$BUILD_HOOKS" ] && BUILD_HOOKS="$(dirname "$0")/build-hooks-${IMAGENAME}"

# jriddell 03-2019 special case where developer and ko ISOs get their build hooks to allow for simpler ISO names
if [ $TYPE = 'developer' ] || [ $TYPE = 'ko' ]; then
    CONFIG_SETTINGS="$(dirname "$0")/config-settings-${IMAGENAME}-${TYPE}.sh"
    CONFIG_HOOKS="$(dirname "$0")/config-hooks-${IMAGENAME}-${TYPE}"
    BUILD_HOOKS="$(dirname "$0")/build-hooks-${IMAGENAME}-${TYPE}"
fi

export CONFIG_SETTINGS CONFIG_HOOKS BUILD_HOOKS

# Preserve envrionment -E plz.
sudo -E $(dirname "$0")/ubuntu-defaults-image \
    --package $METAPACKAGE \
    --arch $ARCH \
    --release $DIST \
    --flavor neon \
    --components main,restricted,universe,multiverse

cat config/common

ls -lah

if [ ! -e livecd.neon.iso ]; then
    echo "ISO Build Failed."
    ls -la
    cleanup
    exit 1
fi

mv livecd.neon.* ../result/
mv source.debian.tar ../result/ || true
cd ../result/

for f in live*; do
    new_name=$(echo $f | sed "s/livecd\.neon/${IMAGENAME}-${TYPE}-${DATETIME}/")
    mv $f $new_name
done

mv source.debian.tar ${IMAGENAME}-${TYPE}-${DATETIME}-source.tar || true
ln -s ${IMAGENAME}-${TYPE}-${DATETIME}.iso ${IMAGENAME}-${TYPE}-current.iso
zsyncmake ${IMAGENAME}-${TYPE}-current.iso
sha256sum ${IMAGENAME}-${TYPE}-${DATETIME}.iso > ${IMAGENAME}-${TYPE}-${DATETIME}.sha256sum
cat > .message << END
KDE neon

${IMAGENAME}-${TYPE}-${DATETIME}.iso Live and Installable ISO
${IMAGENAME}-${TYPE}-${DATETIME}.iso.sig PGP Digital Signature
${IMAGENAME}-${TYPE}-${DATETIME}.manifest ISO contents
${IMAGENAME}-${TYPE}-${DATETIME}.sha256sum Checksum
${IMAGENAME}-${TYPE}-${DATETIME}.torrent Web Seed torrent (you client needs to support web seeds or it may not work)
"current" files are the same files for those wanting a URL which does not change daily.
END
echo $DATETIME > date_stamp

pwd
chown -Rv jenkins:jenkins .

exit 0
