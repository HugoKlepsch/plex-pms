#!/bin/bash -e
# Create a systemd service that autostarts & manages a docker-compose instance in the current directory
# by Uli Köhler - https://techoverflow.net
# Licensed as CC0 1.0 Universal
# Modified by Hugo Klepsch

set -euo pipefail

SERVICENAME=$(basename $(pwd))

# Load variables
ENV_FILE=".env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Error: $ENV_FILE file not found." >&2
  exit 1
fi

# Use 'set -a' to export all sourced variables to the environment
set -a
if ! source "$ENV_FILE"; then
  echo "Error: Failed to source $ENV_FILE." >&2
  exit 1
fi
set +a
echo "$ENV_FILE loaded successfully."

# Generate the systemd mount unit name
path="$(pwd)/${mount_dir}"

# Strip leading slash, replace slashes with dashes and append ".mount"
mount_unit_name="${path#/}"
mount_unit_name="${mount_unit_name//\//-}.mount"

echo "Creating systemd samba mount... ${mount_unit_name}"
# Create systemd mount file
cat >"${mount_unit_name}" <<EOF
[Unit]
Description=Plex SMB Share
After=network-online.target
Wants=network-online.target

[Mount]
What=//${smb_host}/${smb_drive}
Where=${path}
Type=cifs
Options=credentials=/etc/samba/creds_plex_data,uid=${mount_user},gid=${mount_group},file_mode=0775,dir_mode=0775,iocharset=utf8,nofail
TimeoutSec=30

[Install]
WantedBy=multi-user.target
EOF

seedbox_ns_unit_name="seedbox-ns.service"

echo "Creating set up network namespace service... ${seedbox_ns_unit_name}"
# Create systemd service file
cat >"${seedbox_ns_unit_name}" <<EOF
[Unit]
Description=Set up the seedbox network namespace
After=network.target
Requires=network.target

[Service]
Restart=no
User=root
WorkingDirectory=$(pwd)
# Start container when unit is started
ExecStart=/bin/bash -c "./set-up-wg-ns.sh up"
# Stop container when unit is stopped
ExecStop=/bin/bash -c "./set-up-wg-ns.sh down"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

echo "Creating systemd service... ${SERVICENAME}.service"
# Create systemd service file
cat >"${SERVICENAME}.service" <<EOF
[Unit]
Description=$SERVICENAME
After=${mount_unit_name} docker.service ${seedbox_ns_unit_name}
Requires=${mount_unit_name} docker.service ${seedbox_ns_unit_name}

[Service]
RestartSec=10
Restart=always
User=root
Group=docker
WorkingDirectory=$(pwd)
# Shutdown container (if running) when unit is started
ExecStartPre=/bin/bash -c ". .env; $(which docker-compose) down"
# Start container when unit is started
ExecStart=/bin/bash -c ". .env; $(which docker-compose) up"
# Stop container when unit is stopped
ExecStop=/bin/bash -c ". .env; $(which docker-compose) down"

[Install]
WantedBy=multi-user.target
EOF

if [[ "${INSTALL:-false}" == "true" ]]; then
	echo "Installing systemd samba mount... /etc/systemd/system/${mount_unit_name}"
	sudo cp "${mount_unit_name}" "/etc/systemd/system/${mount_unit_name}"

	echo "Installing seedbox ns service... /etc/systemd/system/${seedbox_ns_unit_name}"
	sudo cp "${seedbox_ns_unit_name}" "/etc/systemd/system/${seedbox_ns_unit_name}"

	echo "Installing systemd service... /etc/systemd/system/$SERVICENAME.service"
	sudo cp "${SERVICENAME}.service" "/etc/systemd/system/$SERVICENAME.service"

	sudo systemctl daemon-reload

	echo "Enabling & starting ${mount_unit_name} and $SERVICENAME"
	# Start systemd units on startup (and right now)
	sudo systemctl enable --now "${mount_unit_name}"
	sudo systemctl enable --now "seedbox-ns.service"
	sudo systemctl enable --now "${SERVICENAME}.service"
	exit 0
else
	echo "Run with INSTALL=true ./create... to install"
	exit 0
fi

exit 0
