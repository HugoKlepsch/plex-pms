#!/bin/bash

# qBittorrent Listen Port Watchdog
# When gluetun restarts the VPN it deletes and recreates tun0, which destroys
# qBittorrent's listening sockets on the VPN address. qBittorrent does not
# reliably re-open them, leaving the forwarded port closed until it is
# restarted. This script restarts a qBittorrent container that has no TCP
# listener on the tun0 address.
#
# Run from the repo root (it sources .env.bash for the torrent ports).
# Set DRY_RUN=true to log what would be restarted without restarting.

set -euo pipefail

ENV_FILE=".env.bash"
GLUETUN_CONTAINER="gluetun"
DRY_RUN="${DRY_RUN:-false}"

if [[ ! -f "$ENV_FILE" ]]; then
	echo "Error: $ENV_FILE file not found." >&2
	exit 1
fi
source "$ENV_FILE"

# Do nothing unless the tunnel is up and stable. Restarting qBittorrent while
# gluetun is still cycling the VPN would only get broken again.
health=$(docker inspect -f '{{.State.Health.Status}}' "$GLUETUN_CONTAINER" 2>/dev/null || true)
if [[ "$health" != "healthy" ]]; then
	echo "${GLUETUN_CONTAINER} is not healthy (status: ${health:-not found}), skipping"
	exit 0
fi

tun_ip=$(docker exec "$GLUETUN_CONTAINER" ip -4 -o addr show tun0 2>/dev/null | awk '{print $4}' | cut -d/ -f1)
if [[ -z "$tun_ip" ]]; then
	echo "tun0 has no IPv4 address, skipping"
	exit 0
fi

# qBittorrent shares gluetun's network namespace, so its sockets show up here
listeners=$(docker exec "$GLUETUN_CONTAINER" netstat -tln)

check_container() {
	local container="$1"
	local port="$2"

	# Leave containers alone if they were stopped on purpose
	if [[ "$(docker inspect -f '{{.State.Running}}' "$container" 2>/dev/null || true)" != "true" ]]; then
		echo "${container} is not running, skipping"
		return 0
	fi

	if grep -qE "^tcp +[0-9]+ +[0-9]+ +${tun_ip//./\\.}:${port} " <<<"$listeners"; then
		return 0
	fi

	if [[ "$DRY_RUN" == "true" ]]; then
		echo "${container} is not listening on ${tun_ip}:${port}, would restart (dry run)"
		return 0
	fi

	echo "${container} is not listening on ${tun_ip}:${port}, restarting"
	docker restart "$container" >/dev/null
}

check_container "qbittorrent" "$QBT_TORRENT_PORT"
check_container "qbittorrent2" "$QBT2_TORRENT_PORT"
