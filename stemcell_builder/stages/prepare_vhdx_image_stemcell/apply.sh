#!/usr/bin/env bash
#


set -e

base_dir=$(readlink -nf $(dirname $0)/../..)
source $base_dir/lib/prelude_apply.bash

rm -f $work/root.vhd
rm -f $work/0.vhd 

# targeting xenserver vhd acceptable format
#qemu-img convert -O vpc -o subformat=dynamic $work/${stemcell_image_name} $work/root.vhd


#add faketime
sudo apt-get install -y faketime


#vhd-utils does only raw => fixed, or fixed => dynamic. chaining 2 conversions
faketime '2010-01-01' vhd-util convert -i $work/${stemcell_image_name} -s 0 -t 1  -o $work/0.vhd 
faketime '2010-01-01' vhd-util convert -i $work/0.vhd -s 1 -t 2  -o $work/root.vhd 

#Verification: 
vhd-util check -n $work/root.vhd 

pushd $work
tar zcf stemcell/image root.vhd
popd
