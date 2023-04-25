#!/bin/bash

echo "Uninstalling ..."

# Unmount and disable folder2ram
folder2ram -syncall
folder2ram -umountall
folder2ram -disablesystemd

# Remove cron job
crontab -l | sed '/trunc_ram_log/d' | crontab -

# Remove trunc_ram_log
rm -f /sbin/trunc_ram_log

echo "Done."
