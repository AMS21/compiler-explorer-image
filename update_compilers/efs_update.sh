#!/bin/bash

set -ex

mkdir -p /opt
mount -t nfs $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone).fs-db4c8192.efs.us-east-1.amazonaws.com:/ /opt

./install_binaries.sh
./install_compilers.sh nightly
./install_nonfree_compilers.sh
./install_libraries.sh

umount /opt
