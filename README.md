## MySQL Database Backup Script

This Bash script provides a robust and automated solution for backing up MySQL databases, designed with reliability and security in mind. It leverages `mysqldump` for database export, `tar` for archiving, and includes features for strict error handling, Telegram notifications, and old backup retention.

### Features

* **Strict Error Handling:** Uses `set -euo pipefail` for immediate exit on errors and unset variables, ensuring script reliability.
* **Telegram Notifications:** Sends real-time success/failure notifications to a specified Telegram group, keeping you informed about backup status.
* **Configurable Database Backups:** Supports backing up multiple MySQL databases, with flexible configuration for host, port, user, password, and database name.
* **Secure Credential Handling:** Emphasizes the importance of using environment variables for sensitive data (Telegram tokens, group IDs) and recommends `.my.cnf` for MySQL credentials to enhance security.
* **Temporary Directory Management:** Utilizes a secure temporary directory for dump files, with a `trap` mechanism to ensure proper cleanup even if the script fails.
* **Automated Archiving:** Compresses all database dumps into a single `tar.gz` archive with a timestamp.
* **Permission Hardening:** Sets restrictive `600` permissions on the generated archive for enhanced security.
* **Old Backup Retention:** Automatically deletes archives older than a configurable number of days, helping manage disk space.
* **Conditional Backups:** Includes an example for conditionally backing up a database based on the current hour.

### Prerequisites

* `bash` (version 4.x or higher recommended)
* `mysqldump` client utilities
* `curl` (for Telegram notifications)
* `tar`
* `find`

### Configuration

Before running the script, you need to set up the following:

1.  **Telegram Bot Token and Chat ID:**
    Set these as environment variables:
    ```bash
    export BOT_TOKEN="YOUR_TELEGRAM_BOT_TOKEN"
    export GROUP_ID="YOUR_TELEGRAM_CHAT_ID"
    ```
    You can add these to your `~/.bashrc` or `~/.profile` for persistence.

2.  **Database Configurations:**
    Edit the `DATABASES_TO_BACKUP` associative array within the script. The format is `"alias:port:user:password:database_name[:host]"`. The `host` is optional and defaults to `127.0.0.1`.

    ```bash
    declare -A DATABASES_TO_BACKUP
    DATABASES_TO_BACKUP=(
        [main_app_db]="3306:backup_user:superSecurePassword:main_database"
        [analytics_data]="3306:analyst:anotherPa$$word:analytics_db:192.168.1.100"
    )
    ```
    **Security Note:** While directly embedding passwords in the script is shown for demonstration, it's highly recommended to use a `.my.cnf` file for MySQL credentials to avoid exposing them in process lists. Refer to the comments in the script for more details.

3.  **Backup Retention:**
    Adjust the `DAYS_TO_KEEP_BACKUPS` variable to your desired retention period (default is 7 days).

### Usage

1.  **Save the script:** Save the script to a file, for example, `mysql_backup.sh`.
2.  **Make it executable:** `chmod +x mysql_backup.sh`
3.  **Run the script:** `./mysql_backup.sh`

It's recommended to schedule this script to run periodically using `cron`.
