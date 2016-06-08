#!/usr/bin/env bash
#


set -e

base_dir=$(readlink -nf $(dirname $0)/../..)
source $base_dir/lib/prelude_apply.bash



#download xenserver distrib to extract toos

#url="http://archive.ubuntu.com/ubuntu/pool/main/d/debootstrap/debootstrap_1.0.59_all.deb"
#wget $url -qO $downloaded_file

rm -rf ${work}/xenserver
mkdir ${work}/xenserver
wget http://downloadns.citrix.com.edgesuite.net/9286/XenServer-6.2.0-SP1-XS62ESP1003-xs-tools-6.2.0-5.iso?_ga=1.263249609.455660746.1421837492 -O ${work}/xenserver/XenServer-6.2.0-SP1-XS62ESP1003-xs-tools-6.2.0-5.iso


#mount iso
iso_mount_path=`mktemp -d`
echo "Mounting xenserver iso from at $iso_mount_path"
mount -o loop -t iso9660 ${work}/xenserver/XenServer-6.2.0-SP1-XS62ESP1003-xs-tools-6.2.0-5.iso $iso_mount_path
add_on_exit "umount $iso_mount_path"

#mirror="file://$iso_mount_path"


#extract and copy tools
cp $iso_mount_path/Linux/xe-guest-utilities_6.2.0-1137_amd64.deb $chroot/tmp

#install tools in chroot
run_in_chroot $chroot "sudo dpkg -i /tmp/xe-guest-utilities_6.2.0-1137_amd64.deb"



