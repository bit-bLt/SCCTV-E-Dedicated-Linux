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

. ./.env_dedi

## Kill sway / current running instances if running
pkill sway

## Get server details from user

log 0 "Begin ..."

printf "\n"
retry=1
while [ $retry -eq 1 ]; do

    instance_count=$(prompt "Number of server instances")
    server_profiles=""

    printf "\nEnter server names (no spaces!)\n\n"
    for i in $(seq 1 "$instance_count"); do
   		server_profiles="$server_profiles $(prompt "Server Profile $i Name")"
    done

    printf "\nProfile Names:\n\n"
	for profile in $server_profiles; do
       	printf "    %s\n\n" "$profile"
	done
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
    useradd "$SCCT_DEDI_STANDARD_USER" -m

    printf "(Limited Permissions User that runs everything dedicated server related)\n"
    printf "Enter password for UNIX $SCCT_DEDI_STANDARD_USER\n"

    passwd "$SCCT_DEDI_STANDARD_USER"

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

    passwd "$SCCT_DEDI_MANAGER_USER"
	chsh $SCCT_DEDI_MANAGER_USER -s "/bin/bash"
else
    log 1 "User $SCCT_DEDI_MANAGER_USER already exists (home dir found)"
fi

if [ ! -e "/home/$SCCT_DEDI_MANAGER_USER" ]; then
    log 2 "Failed to create $SCCT_DEDI_MANAGER_USER (home dir not found)"
    log 2 "Exiting ..."
    return 1
fi

## Copy manager scripts
cp "$SCCT_DEDI_STATUS" "/home/$SCCT_DEDI_MANAGER_USER/"
cp "$SCCT_DEDI_MONITOR" "/home/$SCCT_DEDI_MANAGER_USER/"

log 0 "Manager User Provisioned"

## Provision default wine prefix

log 0 "Provisioning default wine prefix for $SCCT_DEDI_STANDARD_USER ..."
if [ -e "$SCCT_DEDI_WINEPREFIX" ]; then
    log 1 "Default wine prefix for $SCCT_DEDI_STANDARD_USER already exists ..."
else
    su $SCCT_DEDI_STANDARD_USER -c "WINEPREFIX=\"$SCCT_DEDI_WINEPREFIX\" wineboot -i"
fi

if [ ! -e "$SCCT_DEDI_WINEPREFIX" ]; then
    log 2 "Failed to create default wine prefix for $SCCT_DEDI_STANDARD_USER"
    log 2 "Exiting ..."
    return 1
fi

# Band-aid bug fix; dedi auto process needs at least one profile to exist
log 0 "Creating null_prf.ini to fix automation bug ..."
scctv_profile_dir="$SCCT_DEDI_WINEPREFIX/drive_c/ProgramData/Ubisoft/Tom Clancy's Splinter Cell Chaos Theory/Saved Games/Versus"
su "$SCCT_DEDI_STANDARD_USER" -c "mkdir -p \"$scctv_profile_dir\""
su "$SCCT_DEDI_STANDARD_USER" -c "touch \"$scctv_profile_dir\"/null_prf.ini"

## Make dirs

if [ ! -e "$SCCT_GAME_BASE_DIR" ]; then
	log 0 "Creating game base directory: $SCCT_GAME_BASE_DIR"
	mkdir $SCCT_GAME_BASE_DIR

else
	log 0 "Game base directory already exists. Removing data within it."
	# Remove any game data in  game base dir
	rm -rf "$SCCT_GAME_BASE_DIR/"*
fi

## Acquire SCCT_Enhanced
log 0 "Downloading game package at: $SCCT_GAME_DOWNLOAD_URI ..."
wget "$SCCT_GAME_DOWNLOAD_URI"
log 0 "Extracting .7z package: $SCCT_GAME_PACKAGE ..."
7z x "$SCCT_GAME_PACKAGE" -y

# Move files to base dir

log 0 "Moving data from extracted folder to game base dir: $SCCT_GAME_BASE_DIR"
mv "$SCCT_GAME_FOLDER/"* "$SCCT_GAME_BASE_DIR/"

## Copy start script to working dir

log 0 "Copying dedi start script to standard user directory ..."
cp "$SCCT_DEDI_START" "$SCCT_DEDI_WORKING_DIR/$SCCT_DEDI_START"

if [ ! -e $SCCT_DEDI_WORKING_DIR/$SCCT_DEDI_START ]; then
    log 2 "Could not find start script in standard user directory!"
    log 2 "Exiting ..."
    return 1
fi

# Ensure sound disabled (game likely to crash when system isn't sound capable)
sed -i "s/UseSound=True/UseSound=False/" "$SCCT_DEDI_WORKING_DIR/Default.ini"

# If provided dedicated package URI, download and install it
if [ ! -z "$SCCT_DEDI_PACKAGE_URI" ]; then
    wget "$SCCT_DEDI_PACKAGE_URI"
    7z x "$SCCT_DEDI_PACKAGE" -o"$SCCT_DEDI_WORKING_DIR" -y
fi

## Ensure proper permissions for standard user in base dir

chown -R $SCCT_DEDI_STANDARD_USER:$SCCT_DEDI_STANDARD_USER $SCCT_GAME_BASE_DIR

## Systemd service creation
# Launches $SCCT_DEDI_START script

service_content="
[Unit]
Description=SCCT Versus Dedicated: %i
BindsTo=default.target
Wants=default.target
After=default.target

[Service]
Type=simple
User=$SCCT_DEDI_STANDARD_USER
WorkingDirectory=$SCCT_DEDI_WORKING_DIR
ExecStart=sh $SCCT_DEDI_START %i
PAMName=Login
Restart=on-failure
RestartSec=1
TimeoutStopSec=10

[Install]
WantedBy=default.target
"

# Remove existing services if found
if [ -e "/etc/systemd/system/$SCCT_DEDI_SERVICE_BASE_NAME@.service" ]; then
	log 0 "Removing old existing services ..."
	systemctl disable "$SCCT_DEDI_SERVICE_BASE_NAME@"
	rm "/etc/systemd/system/$SCCT_DEDI_SERVICE_BASE_NAME@.service"
fi

log 0 "Creating agnostic Systemd service ..."
echo "$service_content" > "/etc/systemd/system/${SCCT_DEDI_SERVICE_BASE_NAME}@.service"
log 0 "Reloading systemd service daemon ..."
systemctl daemon-reload

# Enable systemd services based on provided profiles (for launch on startup)

log 0 "Creating symlinks to server profiles for Systemd service to run on startup ..."

count=0
delay_mult=20 # Seconds; Delay each server instance by delay_mult*count
for profile in $server_profiles; do
    echo $profile

    systemctl enable "$SCCT_DEDI_SERVICE_BASE_NAME@$profile:$((SCCT_DEDI_SERVICE_BASE_PORT_QUERY+count)):$((SCCT_DEDI_SERVICE_BASE_PORT_HOST+count)):$((delay_mult*count))"
    log 0 "Allowing contextual ports with UFW ..."
    ufw allow $((SCCT_DEDI_SERVICE_BASE_PORT_QUERY+count))
    ufw allow $((SCCT_DEDI_SERVICE_BASE_PORT_HOST+count))

    count=$((count + 1))
done

log 0 "Created agnostic Systemd service and profiles"

## SSH

# Disable root over ssh
log 0 "Disabling root ssh access ..."
sed -i "s/PermitRootLogin yes/PermitRootLogin no/" "/etc/ssh/sshd_config"

# Change default port
log 0 "Changing default ssh port to: $SCCT_DEDI_SSH_PORT ..."
sed -i "s/^#*Port 22/Port $SCCT_DEDI_SSH_PORT/" "/etc/ssh/sshd_config"

## Disable unattended upgrades

log 0 "Removing unattended-upgrades"
apt remove unattended-upgrades -y


## Cleanup

log 0 "Cleaning up ..."

if [ -e "$SCCT_DEDI_PACKAGE" ]; then
	rm "$SCCT_DEDI_PACKAGE"
fi

rm "$SCCT_GAME_PACKAGE"
rm "$SCCT_GAME_FOLDER" -r

## Reboot (updates and whatnot)
echo "A reboot is recommended ..."
result=$(prompt "Reboot now? (y/n)")

echo ""
echo "IMPORTANT!"
echo "The new ssh port is: $SCCT_DEDI_SSH_PORT"
echo "Log in as: $SCCT_DEDI_MANAGER_USER"
echo "All game related services run under: $SCCT_DEDI_STANDARD_USER"
echo ""	

log 0 "Finished!"

cp "SCCT_Dedicated_Setup.log" "/home/$SCCT_DEDI_MANAGER_USER/"

if [ $result = "y" ]; then
	echo "Rebooting in 15 seconds."
	sleep 15
	reboot
fi

