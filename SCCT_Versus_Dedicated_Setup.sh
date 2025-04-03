#!/bin/sh

### Helpers

log() {
    tag="[null]"
    if [ $1 = 0 ]; then
        tag="[INFO]"
    fi
    if [ $1 = 1 ]; then
        tag="[WARN]"
    fi
    if [ $1 = 2 ]; then
        tag="[ERROR]"
    fi

    echo "$tag $2" >&2
 
    if [ $SCCT_DEDI_LOG_FILE_ENABLE -eq 1 ]; then
        echo "$tag $2" >> "SCCT_Dedicated_Setup.log"
    fi

    return 0
}

prompt() {
  read -p "$1 > " response
  echo "$response"
}

### MAIN

## Get env vars 

source .env_dedi

## Get server details from user

printf "\n"
retry=1
while [ $retry -eq 1 ]; do

        instance_count=$(prompt "Number of server instances")
        server_profiles=()

        printf "\nEnter server names (no spaces!)\n\n"
        for i in $(seq 1 "$instance_count"); do
                server_profiles+=($(prompt "Server Profile $i Name"))
        done

        printf "\nProfile Names:\n\n"
        printf "    %s\n" ${server_profiles[@]}
        printf "\n"

        result=$(prompt "Look good? (y/n)")

        if [ $result = "y" ]; then
                retry=0
        fi
done

## Add i386 repositories

log 0 "Adding i386 repositories via dpkg ..."
dpkg --add-architecture i386

## Update

log 0 "Updating Server ..."
apt update
apt upgrade -y

log 0 "Updating Server Finished"

## Install Deps

log 0 "Installing deps: $SCCT_DEDI_DEPS ..."

apt install -y $SCCT_DEDI_DEPS

log 0 "Installing deps Finished"

## Create Standard User

log 0 "Adding user: $SCCT_DEDI_STANDARD_USER ..."

if [ ! -e "/home/$SCCT_DEDI_STANDARD_USER" ]; then
        useradd $SCCT_DEDI_STANDARD_USER -m

        log 0 "(Limited Permissions User that runs everything dedicated server related)"
        log 0 "Enter password for UNIX $SCCT_DEDI_STANDARD_USER"

        passwd $SCCT_DEDI_STANDARD_USER

else
        log 1 "User $SCCT_DEDI_STANDARD_USER already exists (home dir found)"
fi

if [ ! -e "/home/$SCCT_DEDI_STANDARD_USER" ]; then
        log 2 "Failed to create $SCCT_DEDI_STANDARD_USER (home dir not found)"
        log 2 "Exiting ..."
        return 1
fi

log 0 "Standard User Provisioned"

## Create manager / sudo user

log 0 "Adding user: $SCCT_DEDI_MANAGER_USER ..."
if [ ! -e "/home/$SCCT_DEDI_MANAGER_USER" ]; then
        useradd -m -G $SCCT_DEDI_MANAGER_USER_GROUPS $SCCT_DEDI_MANAGER_USER

        printf "(This is the user you should sign in with to manage the server, not root)\n"
        printf "Enter password for UNIX user: $SCCT_DEDI_MANAGER_USER\n"

        passwd $SCCT_DEDI_MANAGER_USER
else
        log 1 "User $SCCT_DEDI_MANAGER_USER already exists (home dir found)"
fi

if [ ! -e "/home/$SCCT_DEDI_MANAGER_USER" ]; then
        log 2 "Failed to create $SCCT_DEDI_MANAGER_USER (home dir not found)"
        log 2 "Exiting ..."
        return 1
fi

log 0 "Manager User Provisioned"

## Provision default wine prefix

log 0 "Provisioning default wine prefix for $SCCT_DEDI_STANDARD_USER ..."
if [ -e "$SCCT_DEDI_WINEPREFIX" ]; then
        log 1 "Default wine prefix for $SCCT_DEDI_STANDARD_USER already exists ..."
else
        su $SCCT_DEDI_STANDARD_USER -c 'WINEPREFIX='$SCCT_DEDI_WINEPREFIX' wineboot -i'
fi

if [ ! -e "$SCCT_DEDI_WINEPREFIX" ]; then
        log 2 "Failed to create default wine prefix for $SCCT_DEDI_STANDARD__USER"
        log 2 "Exiting ..."
        return 1
fi

# Band-aid bug fix; dedi auto process needs at least one profile to exist
touch "$SCCT_DEDI_WINEPREFIX/drive_c/ProgramData/Ubisoft/Tom Clancy's Splinter Cell Chaos Theory/Saved Games/Versus/null_prf.ini"

## Make dirs

mkdir -p $SCCT_DEDI_WORKING_DIR

## Acquire SCCT_Enhanced

wget $SCCT_GAME_DOWNLOAD_URI
7z x $SCCT_GAME_PACKAGE $SCCT_DEDI_BASE_DIR

## Copy start script to working dir

log 0 "Copying dedi start script to standard user directory ..."

cp "$SCCT_DEDI_START" "$SCCT_DEDI_WORKING_DIR/$SCCT_DEDI_START"

if [ ! -e $SCCT_DEDI_WORKING_DIR/$SCCT_DEDI_START ]; then
        log 2 "Could not find start script in standard user directory!"
        log 2 "Exiting ..."
        return 1
fi

# If provided dedicated functionality URI, download and install it
if [ ! -z $SCCT_DEDI_CORE_URI ]; then
	wget $SCCT_DEDI_CORE_URI
	cp "Reloaded.Core.dll" $SCCT_DEDI_WORKING_DIR
do

## Ensure proper permissions for standard user in base dir

chown -R $SCCT_DEDI_STANDARD_USER:$SCCT_DEDI_STANDARD_USER $SCCT_DEDI_BASE_DIR

## Systemd service creation
# Launches $SCCT_DEDI_START script

service_content="
[Unit]
Description=SCCT Versus Dedicated: @%I
BindsTo=default.target
Wants=default.target
After=default.target

[Service]
Type=simple
User=$SCCT_DEDI_STANDARD_USER
WorkingDirectory=$SCCT_DEDI_WORKING_DIR
ExecStart=sh $SCCT_DEDI_START @%I
PAMName=Login
Environment=WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 WAYLAND_DISPLAY=wayland-1 WLR_RENDERER=pixman WLR_RENDERER_ALLOW_SOFTWARE=1 DISPLAY=:0
Restart=on-failure
RestartSec=1
TimeoutStopSec=10

[Install]
WantedBy=default.target
"

log 0 "Creating agnostic Systemd service ..."
echo "$service_content" > "/etc/systemd/system/${SCCT_DEDI_SERVICE_BASE_NAME}@.service"
systemctl daemon-reload

# Enable systemd services based on provided profiles (for launch on startup)

log 0 "Creation symlinks to server profiles for Systemd service to run on startup ..."

count=0
delay_mult=10 # Seconds; Really only needed in current hacky port adjustment with a single file. If framelimit allows -port args, we might be able to nix this
for profile in "${server_profiles[@]}"; do
        echo $profile

        systemctl enable --now "$SCCT_DEDI_SERVICE_BASE_NAME@$profile:$((SCCT_DEDI_SERVICE_BASE_PORT_QUERY+count)):$((SCCT_DEDI_SERVICE_BASE_PORT_HOST+count)):$((delay_mult*count))"
        log 0 "Allowing contextual ports with UFW ..."
        ufw allow $((SCCT_DEDI_SERVICE_BASE_PORT_QUERY+count))
        ufw allow $((SCCT_DEDI_SERVICE_BASE_PORT_HOST+count))

        count=$((count + 1))
done

log 0 "Created agnostic Systemd service and profiles"

