#!/bin/bash

# Kill already running duplicate process
_ps="waybar mako swaybg"
for _prs in $_ps; do
    if [ "$(pidof "${_prs}")" ]; then
         killall -9 "${_prs}"
    fi
 done

# Start our applications
swaybg --output '*' --mode center  --image $CONFIGROOT/bgs/emperor-tamarin.jpg &
mako &
waybar &
foot --server &

exec dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=wlroots
