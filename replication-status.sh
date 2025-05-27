#!/bin/bash
### Based on https://handyman.dulare.com/mysql-replication-status-alerts-with-bash-script/

####################
### INSTALLATION ###
####################

### Create replication status user in the database:
# CREATE USER 'replstatus'@'localhost' IDENTIFIED BY 'your_password';
# GRANT SHOW DATABASES, REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'replstatus'@'localhost';
# FLUSH PRIVILEGES;

### Create a cron job to run the script every 5 minutes
# */5 * * * * DB_PASSWORD=YourPassword /bin/bash /usr/local/sbin/replication-status.sh

#############
### SETUP ###
#############

# Set the maximum number of seconds behind master that will be ignored.
# If the slave is be more than maximumSecondsBehind, an email will be sent.
MAX_SECONDS_BEHIND=300

# Database
DB_TYPE=mariadb
DB_USER=replstatus
#DB_PASSWORD=your_password

# Email
DISABLE_EMAIL_REPORTS=0 # 1 to disable reports
MAIL_TO=user1@example.com
MAIL_FROM=user2@example.com
SMTP_SERVER=localhost
MAILX_CMD=/usr/bin/mailx
MSMTP_CMD=/usr/bin/msmtp
MAIL_TYPE=mailx # can be 'mailx' or 'msmtp'

# Logs
LOG_FILE=/var/log/replication-status.log
ERR_FILE=/var/log/replication-status.err

#################
### END SETUP ###
#################

# Send email with log in attachment
function send_email() {
    if [[ "$DISABLE_EMAIL_REPORTS" -eq 1 ]]; then
        return
    fi

    echo "Sending email to ${MAIL_TO}"

    SUBJECT="Database replication error on $HOSTNAME"
    BODY=$(printf "An error occurred during database replication on %s:\n\n%s" "${HOSTNAME}" "$(cat $ERR_FILE)")

    if [[ "$MAIL_TYPE" == "mailx" ]]; then
        echo "$BODY" | $MAILX_CMD -s "$SUBJECT" -r "$MAIL_FROM" -S smtp="$SMTP_SERVER" -a "$ERR_FILE" "$MAIL_TO"
    elif [[ "$MAIL_TYPE" == "msmtp" ]]; then
        {
            echo "Subject: $SUBJECT"
            echo "From: $MAIL_FROM"
            echo "To: $MAIL_TO"
            echo
            echo "$BODY"
        } | $MSMTP_CMD --from="$MAIL_FROM" -t
    else
        echo "Unsupported MAIL_TYPE: $MAIL_TYPE" >&2
    fi
}


{
    echo "$(date +%Y%m%d_%H%M%S): Replication check started."

    # Check if the database is running
    if systemctl is-active ${DB_TYPE} > /dev/null; then
        # Get the replication status...
        ${DB_TYPE} -u ${DB_USER} -p${DB_PASSWORD} -e 'SHOW SLAVE STATUS \G' | grep 'Running:\|Master:\|Error:' >$ERR_FILE

        # Getting parameters
        slaveRunning="$(grep -c "Slave_IO_Running: Yes" $ERR_FILE)"
        slaveSQLRunning="$(grep -c "Slave_SQL_Running: Yes" $ERR_FILE)"
        secondsBehind="$(grep "Seconds_Behind_Master" $ERR_FILE | tr -dc '0-9')"
        dbNotRunning=0
    else
        # The database is not running
        printf "%s\n\n%s" "Error: ${DB_TYPE} is not running." "$(systemctl status ${DB_TYPE})" >$ERR_FILE
        dbNotRunning=1
    fi

    # Check for problems and send email if needed
    if [[ $dbNotRunning == 1 || $slaveRunning != 1 || $slaveSQLRunning != 1 || $secondsBehind -gt $MAX_SECONDS_BEHIND ]]; then
        cat $ERR_FILE
        echo "$(date +%Y%m%d_%H%M%S): Replication check finished. Problems detected."
        send_email
        retval=1
    else
        echo "$(date +%Y%m%d_%H%M%S): Replication check finished OK."
        retval=0
    fi

    sync
    exit $retval
} 2>&1 | tee -a ${LOG_FILE}
