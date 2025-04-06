
# Purpose

This script is currently made in the context of a fresh VPS provisioned with a only root account.

Run SCCT_Versus_Dedicated_Setup.sh and it will configure things from there.

# Configuration

Look to env vars in .env_dedi

# Install

as root:

```./SCCT_Versus_Dedicated_Setup.sh```

- Choose number of server instances,
- Choose name of each (whitespace not currently supported)
- Reboot

# What the script does

TLDR; the dedicated server instance(s) runs underneath headless Sway and Xwayland.

- Updates server
- Creates standard user (see .env_dedi)
- Creates management / sudo user (see .env_dedi)
- Installs required dependancies (see .env_dedi)
- Disables Root ssh login
- Changes default ssh port (see .env_dedi)
- Downloads the game files (see .env_dedi)
- Creates systemd services to start server instances on boot
- Configures 1x1 virtual display in Sway (this seems to work, and lowers memory footprint)
- Provides status script to output the window title of the dedicated server cmd window (holds fps and player count stat)
- Provides monitor script to "watch" the status script
- Enables UFW and contextual ports for number of inputs (see .env_dedi for base ports)

# Support

Currently only supports Ubuntu Server 24.04

# Todo
- [ ] Logging in SCCT_Versus_Dedicated_Start.sh
- [ ] Run scheduled updates only when no players in lobby
- [ ] Add better logging checks in SCCT_Versus_Dedicated_Setup.sh
- [ ] Decompose SCCT_Versus_Dedicated_Setup.sh into functional parts rather than giant main body :)
