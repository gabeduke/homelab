#!/bin/bash

CGROUPS_ENABLED=$(grep cgroup_memory /boot/firmware/cmdline.txt)

sudo apt-get install linux-modules-extra-raspi -y

if [ -z "$CGROUPS_ENABLED" ]; then
    echo "Enabling cgroups"
    sudo sed -i '1 s/$/ cgroup_memory=1 cgroup_enable=memory systemd.unified_cgroup_hierarchy=1/' /boot/firmware/cmdline.txt
fi
