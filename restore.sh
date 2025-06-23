#!/bin/bash

# Plex Data Restore Script
# This script restores Plex configuration directories from backup

# Configuration
RESTORE_TARGET="$HOME/plex/local_data_mnt"
BACKUP_DIR="$HOME/plex/plex_data_mnt/plex2/backups"
LOG_FILE="$BACKUP_DIR/restore.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to log messages
log_message() {
	echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Function to print colored output
print_status() {
	case $2 in
		"ERROR")
			echo -e "${RED}[ERROR]${NC} $1"
			;;
		"SUCCESS")
			echo -e "${GREEN}[SUCCESS]${NC} $1"
			;;
		"INFO")
			echo -e "${YELLOW}[INFO]${NC} $1"
			;;
		"PROMPT")
			echo -e "${BLUE}[PROMPT]${NC} $1"
			;;
	esac
}

# Function to list available backups
list_backups() {
	print_status "Available backups:" "INFO"
	echo "------------------------"
	if [ -f "$BACKUP_DIR/latest_backup.tar.gz" ]; then
		echo "0) Latest backup ($(readlink "$BACKUP_DIR/latest_backup.tar.gz" | xargs basename))"
	fi

	local counter=1
	for backup in $(find "$BACKUP_DIR" -name "plex_backup_*.tar.gz" -type f | sort -r); do
		local filename=$(basename "$backup")
		local size=$(du -sh "$backup" | cut -f1)
		local date_part=$(echo "$filename" | sed 's/plex_backup_\(.*\)\.tar\.gz/\1/')
		local formatted_date=$(echo "$date_part" | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)_\([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3 \4:\5:\6/')
		echo "$counter) $filename ($size) - $formatted_date"
		((counter++))
	done
	echo "------------------------"
}

# Function to select backup
select_backup() {
	list_backups

	print_status "Enter the number of the backup to restore (or 'q' to quit): " "PROMPT"
	read -r choice

	if [ "$choice" = "q" ] || [ "$choice" = "Q" ]; then
		print_status "Restore cancelled by user." "INFO"
		exit 0
	fi

	if [ "$choice" = "0" ]; then
		if [ -f "$BACKUP_DIR/latest_backup.tar.gz" ]; then
			SELECTED_BACKUP="$BACKUP_DIR/latest_backup.tar.gz"
		else
			print_status "Latest backup not found!" "ERROR"
			exit 1
		fi
	else
		local counter=1
		for backup in $(find "$BACKUP_DIR" -name "plex_backup_*.tar.gz" -type f | sort -r); do
			if [ "$counter" -eq "$choice" ]; then
				SELECTED_BACKUP="$backup"
				break
			fi
			((counter++))
		done
	fi

	if [ -z "$SELECTED_BACKUP" ]; then
		print_status "Invalid selection!" "ERROR"
		exit 1
	fi

	print_status "Selected backup: $(basename "$SELECTED_BACKUP")" "INFO"
}

# Check if backup directory exists
if [ ! -d "$BACKUP_DIR" ]; then
	print_status "Backup directory $BACKUP_DIR does not exist!" "ERROR"
	exit 1
fi

# Check if there are any backups
if [ -z "$(find "$BACKUP_DIR" -name "plex_backup_*.tar.gz" -type f)" ]; then
	print_status "No backup files found in $BACKUP_DIR" "ERROR"
	exit 1
fi

# Handle command line argument for backup file
if [ $# -eq 1 ]; then
	if [ -f "$1" ]; then
		SELECTED_BACKUP="$1"
		print_status "Using specified backup file: $(basename "$SELECTED_BACKUP")" "INFO"
	elif [ -f "$BACKUP_DIR/$1" ]; then
		SELECTED_BACKUP="$BACKUP_DIR/$1"
		print_status "Using backup file: $(basename "$SELECTED_BACKUP")" "INFO"
	else
		print_status "Specified backup file not found: $1" "ERROR"
		exit 1
	fi
else
	select_backup
fi

# Confirm restore operation
print_status "WARNING: This will overwrite existing Plex configuration data!" "ERROR"
print_status "Current data will be backed up to: $RESTORE_TARGET/plex_backup_before_restore_$(date +%Y%m%d_%H%M%S)" "INFO"
print_status "Are you sure you want to continue? (yes/no): " "PROMPT"
read -r confirmation

if [ "$confirmation" != "yes" ]; then
	print_status "Restore cancelled." "INFO"
	exit 0
fi

# Create restore target directory if it doesn't exist
mkdir -p "$RESTORE_TARGET"

# Backup existing data before restore
if [ -d "$RESTORE_TARGET/plex" ]; then
	SAFETY_BACKUP="$RESTORE_TARGET/plex_backup_before_restore_$(date +%Y%m%d_%H%M%S)"
	print_status "Creating safety backup of existing data..." "INFO"
	sudo -u plex -g plexapp mv "$RESTORE_TARGET/plex" "$SAFETY_BACKUP"
	log_message "Safety backup created: $SAFETY_BACKUP"
fi

# Start restore process
print_status "Starting restore process..." "INFO"
log_message "Starting restore from: $(basename "$SELECTED_BACKUP")"

# Change to restore target directory
cd "$RESTORE_TARGET" || exit 1

# Extract the backup
print_status "Extracting backup..." "INFO"
sudo -u plex -g plexapp tar -xzf "$SELECTED_BACKUP" 2>&1

if [ $? -eq 0 ]; then
	print_status "Restore completed successfully!" "SUCCESS"
	print_status "Data restored to: $RESTORE_TARGET/plex" "INFO"
	log_message "SUCCESS: Restore completed from $(basename "$SELECTED_BACKUP")"

	# Display restored directories
	print_status "Restored directories:" "INFO"
	du -sh "$RESTORE_TARGET/plex"/* 2>/dev/null || true
else
	print_status "Restore failed!" "ERROR"
	log_message "ERROR: Restore failed from $(basename "$SELECTED_BACKUP")"

	# Restore safety backup if restore failed
	if [ -d "$SAFETY_BACKUP" ]; then
		print_status "Restoring original data due to restore failure..." "INFO"
		mv "$SAFETY_BACKUP" "$RESTORE_TARGET/plex"
	fi
	exit 1
fi

print_status "Restore process completed!" "SUCCESS"
print_status "Remember to restart your Plex services if they were running." "INFO"
