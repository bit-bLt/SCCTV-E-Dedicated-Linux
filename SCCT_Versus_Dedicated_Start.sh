#!/bin/sh

## Start

# Wayland
export WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 WAYLAND_DISPLAY=wayland-1 WLR_RENDERER=pixman WLR_RENDERER_ALLOW_SOFTWARE=1

# Display for X11 / XWayland processes
export DISPLAY=:0

# Start Sway

sway_started=$(pgrep -x sway > /dev/null 2>&1 && echo "true" || echo "false")
if [ $sway_started = "false" ] ; then
    sway &
fi

# Alias for access to sway socket
alias sway-runner='swaymsg -s $XDG_RUNTIME_DIR/sway-ipc.* exec'

# Set display mode. Less res = less memory. Somehow, 1x1 doesn't break things :)
sway-runner swaymsg output HEADLESS-1 mode 1x1

# Get colon delimited args (to be passed by systemd service... or you if you want)
profile=$(echo "$1" | awk -F':' '{print $1}')

# Systemd args leaves behind @; this checks for leading @ and removes it
first_char=$(printf %.1s "$profile")
if [ $first_char = "@" ]; then
        profile=${profile#?}
fi


query_port=$(echo "$1" | awk -F':' '{print $2}')
game_port=$(echo "$1" | awk -F':' '{print $3}')

# Hack work around for port change
sed -i "s/\"host_port_query\": [0-9]*,/\"host_port_query\": $game_port,/" SCCT_Versus.config
sed -i "s/\"host_port_game\": [0-9]*,/\"host_port_game\": $query_port,/" SCCT_Versus.config

wine SCCT_Versus.exe -dedicated -hide3d -profile $profile

