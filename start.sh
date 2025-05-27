#!/bin/bash
#
# Script for copying MySQL databases.
#


# User environment variables are set in ~/.bashrc
# For each variable you want to make permanent, add a line to the end of the file using the following syntax:
# export [VARIABLE_NAME]=[VARIABLE_VALUE]
# To apply the changes during the current session, you need to run the command:
# source ~/.bashrc

# BOT_TOKEN - token is currently in environment variables
# GROUP_ID - id is currently in environment variables
# How to create this read more https://core.telegram.org/bots/tutorial

# Function for sending an error message to Telegram
error_exit()
{
    echo "Error: $1"
    curl -s --data "text=$1" --data "chat_id=$GROUP_ID" 'https://api.telegram.org/bot'$BOT_TOKEN'/sendMessage' > /dev/null
}

# Fill in the array: port, login, password, database name 
# To avoid confusion and somehow make the script more civilized
dbONE="port user password database"
dbTWO="port2 user2 password2 database2"
dbTHREE="port3 user3 password3 database3"
# ..................................
# dbN="portN userN passwordN databaseN"

# Example
# MYDB="3306 notroot password testdb"

# Form a dictionary
declare -A DB=(
[one]=$dbONE
[two]=$dbTWO
# ..................................
# [n]=$dbN
)

DATE=$(date +"%Y-%m-%d_%H-%M-%S")
HOUR=$(date +%H)
BACKUP_DIR=~/db_backups
TEMP_DIR=~/db_backups/$DATE
ERROR_TEXT="ERROR. Backup creation error"
mkdir $TEMP_DIR

# If we need to dump a database at a different frequency or under a certain condition, 
# we can add an exception. https://www.w3schools.com/bash/bash_operators.php
if  [ "$HOUR" -lt "4" ]; then
        DB[three]=$dbTHREE
fi

for key in "${!DB[@]}"
        do
                for item in ${DB[$key]}
                        do
                                tmp_arr+=($item)
                        done
                mysqldump -h 127.0.0.1 -P ${tmp_arr[0]} -u ${tmp_arr[1]} --password=${tmp_arr[2]} ${tmp_arr[3]} > $TEMP_DIR/$key.sql || error_exit "$ERROR_TEXT $key.sql"
                tmp_arr=()
done

# Archive the folder
tar -zcvf $BACKUP_DIR/$DATE-local.tar.gz $TEMP_DIR || error_exit "$ERROR_TEXT, namely creating the archive"
rm $TEMP_DIR -R
chmod 600 $BACKUP_DIR/$DATE-local.tar.gz
# Find and delete old archives
find $BACKUP_DIR -type f -name "*.gz" -mtime +7 -delete || error_exit "$ERROR_TEXT, namely deleting old archives"
