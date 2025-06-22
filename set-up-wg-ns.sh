#!/bin/bash

set -e

. .env

# Function to bring up the WireGuard namespace
bring_up() {
	echo "Setting up WireGuard namespace..."

	# Check if namespace already exists
	if sudo ip netns list | grep -q "^$NAMESPACE"; then
		echo "Warning: Namespace '$NAMESPACE' already exists. Cleaning up first..."
		bring_down
	fi

	# Create namespace
	echo "Creating namespace: $NAMESPACE"
	sudo ip netns add $NAMESPACE
	sudo ip netns exec $NAMESPACE ip link set lo up

	# Create and configure WireGuard interface
	echo "Creating WireGuard interface: $WG_INTERFACE"
	sudo ip link add $WG_INTERFACE type wireguard
	# systemd-resolved DNS configuration doesn't work in network namespace. 
	# Use 1.1.1.1 directly as a hack workaround.
	sudo resolvectl dns $WG_INTERFACE 1.1.1.1
	sudo ip link set $WG_INTERFACE netns $NAMESPACE
	sudo ip netns exec $NAMESPACE ip addr add $WG_IP dev $WG_INTERFACE
	sudo ip netns exec $NAMESPACE ip link set $WG_INTERFACE up

	# Configure WireGuard
	echo "Configuring WireGuard..."
	sudo ip netns exec $NAMESPACE wg set $WG_INTERFACE \
		private-key $PRIVATE_KEY_PATH \
		peer $PEER_PUBLIC_KEY \
		preshared-key $PEER_PRESHARED_KEY_PATH \
		allowed-ips 0.0.0.0/0,::/0 \
		endpoint $PEER_ENDPOINT \
		persistent-keepalive 25

	# Set up routing
	echo "Setting up routing..."
	sudo ip netns exec $NAMESPACE ip route add default dev $WG_INTERFACE

	echo "WireGuard namespace setup complete!"
	echo "Test with: sudo ip netns exec $NAMESPACE curl ifconfig.me"
}

# Function to clean up the WireGuard namespace
bring_down() {
	echo "Cleaning up WireGuard namespace..."

	# Check if namespace exists
	if ! sudo ip netns list | grep -q "^$NAMESPACE"; then
		echo "Namespace '$NAMESPACE' does not exist. Nothing to clean up."
		return 0
	fi

	# Remove WireGuard interface (this also removes it from the namespace)
	echo "Removing WireGuard interface: $WG_INTERFACE"
	if sudo ip netns exec $NAMESPACE ip link show $WG_INTERFACE &>/dev/null; then
		sudo ip netns exec $NAMESPACE ip link del $WG_INTERFACE 2>/dev/null || true
	fi

	# Delete namespace
	echo "Deleting namespace: $NAMESPACE"
	sudo ip netns del $NAMESPACE

	echo "WireGuard namespace cleanup complete!"
}

# Function to show usage
show_usage() {
	echo "Usage: $0 [up|down]"
	echo "  up   - Create and configure WireGuard namespace"
	echo "  down - Clean up WireGuard namespace"
	echo ""
}

# Parse command line arguments
case "${1:-}" in
	"up")
		bring_up
		;;
	"down")
		bring_down
		;;
	"")
		echo "Error: No command specified."
		show_usage
		exit 1
		;;
	*)
		echo "Error: Unknown command '$1'"
		show_usage
		exit 1
		;;
esac
