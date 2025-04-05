#!/bin/sh
su scct_dedi -c "xwininfo -display :0 -root -tree | grep -oP '\"\K[^\"]* FPS'"

