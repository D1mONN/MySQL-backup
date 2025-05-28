#!/bin/bash

# --- Strict Mode ---
# -e: Exit immediately if a command exits with a non-zero status.
# -u: Treat unset variables as an error when substituting.
# -o pipefail: Return the exit status of the last command in the pipe that failed.
set -euo pipefail

# --- Configuration ---
# Secrets (tokens, group IDs) should be environment variables or loaded from a secure file.
# For example, they can be set in your .bashrc or .profile:
# export BOT_TOKEN="your_bot_token"
# export GROUP_ID="your_group_or_chat_id"

# Check for required environment variables
if [[ -z "${BOT_TOKEN:-}" ]]; then
  echo "Error: BOT_TOKEN environment variable is not set." >&2
  exit 1
fi
if [[ -z "${GROUP_ID:-}" ]]; then
  echo "Error: GROUP_ID environment variable is not set." >&2
  exit 1
fi

# Base directory for backups
readonly BACKUP_BASE_DIR="${HOME}/db_backups"
# Number of days to keep backups
readonly DAYS_TO_KEEP_BACKUPS=7
# Default MySQL host
readonly MYSQL_HOST_DEFAULT="127.0.0.1"
# Hostname for Telegram notifications
readonly HOSTNAME_INFO=$(hostname -s)

# --- Database Configurations ---
# Format: "alias:port:user:password:database_name[:host]"
# Host is optional and defaults to MYSQL_HOST_DEFAULT.
# IMPORTANT: Avoid spaces in passwords or other fields if using this simple string format.
# For passwords with special characters (including colon ':'), consider using .my.cnf or more robust parsing.
declare -A DATABASES_TO_BACKUP
DATABASES_TO_BACKUP=(
    # Examples:
    # [main_db]="3306:your_user:your_password:your_database"
    # [service_db]="3306:another_user:another_pass:another_db:${MYSQL_HOST_DEFAULT}"
    # [remote_db]="3306:remote_user:remote_pass:remote_database_name:your_remote_host_ip"
)

# # Conditional backup (e.g., for a specific database that only needs to be backed up under certain conditions)
#readonly CURRENT_HOUR=$(date +%H)
#if [[ "$CURRENT_HOUR" -lt "4" ]]; then # If the hour is less than 04:00
#    DATABASES_TO_BACKUP[db_alias]="db4_port:db4_user:db4_password:db4_database"
#fi


# --- Functions ---

# Function to send a message to Telegram and exit on error
notify_telegram() {
    local message_type="$1" # "ERROR", "INFO", "WARNING"
    local message="$2"
    local full_message="${HOSTNAME_INFO} - ${message_type}: ${message}"

    echo "$(date +"%Y-%m-%d %H:%M:%S") - $full_message" # Log to stdout/stderr

    # Attempt to send message to Telegram
    # Added timeout and retry attempts for curl
    if ! curl --connect-timeout 10 --retry 3 --retry-delay 5 -s \
             --data-urlencode "text=${full_message}" \
             --data-urlencode "chat_id=${GROUP_ID}" \
             "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" > /dev/null; then
        echo "$(date +"%Y-%m-%d %H:%M:%S") - WARNING: Failed to send Telegram message: ${message}" >&2
    fi
}

# Error handler that calls notify_telegram and exits the script
handle_error() {
    local error_message="$1"
    local line_number="${BASH_LINENO[0]}" # Approximate line number where the error occurred
    notify_telegram "ERROR" "Line $line_number: $error_message"
    # Cleanup of temporary directory is not needed here, as trap EXIT will handle it
    exit 1
}


# --- Main Script ---

# Create a temporary directory for backups
# `mktemp` creates a unique temporary directory and is more secure
TEMP_BACKUP_DIR="" # Initialize for trap
TEMP_BACKUP_DIR=$(mktemp -d "${BACKUP_BASE_DIR}/backup_temp_XXXXXX")

# Trap to ensure guaranteed cleanup of the temporary directory on exit (success or failure)
# shellcheck disable=SC2154 # TEMP_BACKUP_DIR is set after trap definition but before execution
trap 'if [[ -n "$TEMP_BACKUP_DIR" && -d "$TEMP_BACKUP_DIR" ]]; then rm -rf -- "$TEMP_BACKUP_DIR"; echo "Temporary directory $TEMP_BACKUP_DIR removed."; fi' EXIT SIGINT SIGTERM

# Create the base backup directory if it doesn't exist
mkdir -p "$BACKUP_BASE_DIR" || handle_error "Failed to create base backup directory: $BACKUP_BASE_DIR"

# Check if there are databases to backup
if [[ ${#DATABASES_TO_BACKUP[@]} -eq 0 ]]; then
    notify_telegram "INFO" "No databases configured for backup. Exiting."
    exit 0 # Not an error, just nothing to do.
fi

#notify_telegram "INFO" "Starting MySQL backup process."
echo "Temporary backup directory: $TEMP_BACKUP_DIR"

for db_alias in "${!DATABASES_TO_BACKUP[@]}"; do
    config_string="${DATABASES_TO_BACKUP[$db_alias]}"
    
    # Parse the configuration string
    # Important: password is the third field. If it contains ':', this parsing might be inaccurate.
    IFS=':' read -r db_port db_user db_pass db_name db_host <<< "$config_string"

    # Set default host if not provided
    db_host="${db_host:-$MYSQL_HOST_DEFAULT}"
    local_filename="${db_alias}.sql"
    local_filepath="${TEMP_BACKUP_DIR}/${local_filename}"

    echo "Backing up database '$db_name' (alias: '$db_alias') from $db_host:$db_port..."

    # SECURITY RECOMMENDATION:
    # For secure storage of MySQL credentials, it's better to use a .my.cnf file.
    # Example content for ~/.my.cnf:
    # [client]
    # user=your_backup_user
    # password="your_actual_password"
    # host=your_db_host_if_always_the_same
    # port=your_db_port_if_always_the_same
    #
    # If .my.cnf is properly configured for the user running the script,
    # you can remove --user, --password, --host, --port from the mysqldump command,
    # if they match the configuration in .my.cnf.
    # For different credentials for different databases, you can use --defaults-group-suffix.
    # WARNING: The current method of passing the password via --password makes it visible in process lists.

    # Using MYSQL_PWD is another option, but also has security drawbacks.
    # export MYSQL_PWD="$db_pass" # Makes password available as an environment variable to child processes
    
    # mysqldump command
    if mysqldump --host="$db_host" \
                 --port="$db_port" \
                 --user="$db_user" \
                 --password="$db_pass" \
                 --databases "$db_name" \
                 --single-transaction \
                 --quick \
                 --routines \
                 --triggers \
                 --events \
                 --skip-lock-tables > "$local_filepath"; then # Added --skip-lock-tables for InnoDB
        echo "Successfully backed up '$db_name' to '$local_filepath'"
    else
        # Remove partially created dump file on error
        rm -f "$local_filepath"
        handle_error "Failed to backup database '$db_name' (alias: '$db_alias'). mysqldump error."
        # Script will exit here due to handle_error -> exit 1
    fi
    # unset MYSQL_PWD # If using MYSQL_PWD
done

# Archive the temporary directory
readonly TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
ARCHIVE_NAME="${TIMESTAMP}-backup.tar.gz"
ARCHIVE_PATH="${BACKUP_BASE_DIR}/${ARCHIVE_NAME}"

echo "Archiving backups to $ARCHIVE_PATH..."
# Archive the contents of TEMP_BACKUP_DIR, not the directory itself
if tar -zcvf "$ARCHIVE_PATH" -C "$TEMP_BACKUP_DIR" .; then
    echo "Successfully created archive: $ARCHIVE_PATH"
else
    handle_error "Failed to create archive $ARCHIVE_PATH."
fi

# Set permissions for the archive (only owner can read/write)
if chmod 600 "$ARCHIVE_PATH"; then
    echo "Permissions for $ARCHIVE_PATH set to 600."
else
    # This is not a critical error, so just a warning
    notify_telegram "WARNING" "Failed to set permissions 600 for archive $ARCHIVE_PATH."
fi

# Cleanup: Temporary directory is removed by the trap EXIT function.

# Find and delete old archives
echo "Deleting old backups (older than $DAYS_TO_KEEP_BACKUPS days)..."
# -print will show which files are being deleted
if find "$BACKUP_BASE_DIR" -maxdepth 1 -type f -name "*.tar.gz" -mtime "+$DAYS_TO_KEEP_BACKUPS" -print -delete; then
    echo "Old backups successfully deleted."
else
    # An error during deletion is not critical for the current backup, but requires attention
    notify_telegram "WARNING" "An error occurred while deleting old archives. Some old archives might remain."
fi

#notify_telegram "INFO" "MySQL backup process completed successfully. Archive: $ARCHIVE_PATH"
exit 0 # Explicit exit with successful status
