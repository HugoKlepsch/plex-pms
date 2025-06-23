#!/bin/bash

# Plex Data Backup Script
# This script creates compressed backups of Plex configuration directories

# Configuration
SOURCE_DIR="$HOME/plex/local_data_mnt/plex"
BACKUP_DIR="$HOME/plex/plex_data_mnt/plex2/backups"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="plex_backup_${DATE}"
LOG_FILE="$BACKUP_DIR/backup.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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
	esac
}

# Check if source directory exists
if [ ! -d "$SOURCE_DIR" ]; then
	print_status "Source directory $SOURCE_DIR does not exist!" "ERROR"
	log_message "ERROR: Source directory $SOURCE_DIR does not exist!"
	exit 1
fi

# Create backup directory if it doesn't exist
if [ ! -d "$BACKUP_DIR" ]; then
	print_status "Creating backup directory: $BACKUP_DIR" "INFO"
	mkdir -p "$BACKUP_DIR"
	if [ $? -ne 0 ]; then
		print_status "Failed to create backup directory!" "ERROR"
		exit 1
	fi
fi

# Start backup process
print_status "Starting backup process..." "INFO"
log_message "Starting backup: $BACKUP_NAME"

# Create the backup using tar with compression
BACKUP_FILE="$BACKUP_DIR/${BACKUP_NAME}.tar.gz"
print_status "Creating compressed backup: $BACKUP_FILE" "INFO"

# Change to the parent directory of the source to maintain relative paths
cd "$(dirname "$SOURCE_DIR")" || exit 1

# Create tar backup with progress indication and exclude cache/temp files
sudo -u plex -g plexapp tar --exclude='*/Cache/*' \
	--exclude='*/cache/*' \
	--exclude='*/Logs/*' \
	--exclude='*/logs/*' \
	--exclude='*/tmp/*' \
	--exclude='*/temp/*' \
	--exclude='*/qbt_config/.bash_history' \
	--exclude='*/qbt_config/qBittorrent/ipc-socket' \
	-czf "$BACKUP_FILE" \
	"$(basename "$SOURCE_DIR")" 2>&1

if [ $? -eq 0 ]; then
	# Get backup file size
	BACKUP_SIZE=$(du -sh "$BACKUP_FILE" | cut -f1)
	print_status "Backup completed successfully!" "SUCCESS"
	print_status "Backup file: $BACKUP_FILE" "INFO"
	print_status "Backup size: $BACKUP_SIZE" "INFO"
	print_status "Free space: $(df -h ${BACKUP_DIR})" "INFO"
	log_message "SUCCESS: Backup completed - Size: $BACKUP_SIZE"

# Create a symlink to the latest backup
LATEST_LINK="$BACKUP_DIR/latest_backup.tar.gz"
ln -sf "$BACKUP_FILE" "$LATEST_LINK"
print_status "Latest backup symlink updated: $LATEST_LINK" "INFO"
else
	print_status "Backup failed!" "ERROR"
	log_message "ERROR: Backup failed"
	exit 1
fi

# Clean up old backups (keep last 30 days)
print_status "Cleaning up old backups (keeping last 30 days)..." "INFO"
find "$BACKUP_DIR" -name "plex_backup_*.tar.gz" -type f -mtime +30 -delete
log_message "Cleanup completed"

print_status "Backup process completed!" "SUCCESS"
