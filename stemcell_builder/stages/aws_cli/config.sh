#!/usr/bin/env bash

set -e

base_dir=$(readlink -nf $(dirname $0)/../..)
source $base_dir/lib/prelude_config.bash

# Download CLI source or release from github into assets directory
cd $assets_dir
rm -rf s3cli
mkdir s3cli
current_version=0.0.20
curl -L -o s3cli/s3cli https://s3.amazonaws.com/s3cli-artifacts/s3cli-${current_version}-linux-amd64
echo "b168931ed916e1c86563986d3ec06ac6fd613fa0 s3cli/s3cli" | sha1sum -c -
