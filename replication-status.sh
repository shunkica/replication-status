#!/bin/bash
### Based on https://handyman.dulare.com/mysql-replication-status-alerts-with-bash-script/

####################
### INSTALLATION ###
####################

### Create replication status user in mysql:
# CREATE USER 'replstatus'@'localhost' IDENTIFIED BY 'your_password';
# GRANT SHOW DATABASES, REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'replstatus'@'localhost';
# FLUSH PRIVILEGES;

### Add to cron to run every 5 minutes
# */5 * * * * MYSQL_PASSWORD=YourPassword /bin/bash /usr/local/sbin/replication-status.sh

#############
### SETUP ###
#############

# Set the maximum number of seconds behind master that will be ignored.
# If the slave is be more than maximumSecondsBehind, an email will be sent.
MAX_SECONDS_BEHIND=300

# MySQL login
MYSQL_USER=replstatus
#MYSQL_PASSWORD=your_password

# Email
MAILTO=user1@example.com
MAILFROM=user2@example.com
SMTPSERVER=localhost
MAILXCMD=/bin/mailx

# Logs
LOGFILE=/var/log/replication-status.log
ERRFILE=/var/log/replication-status.err

#################
### END SETUP ###
#################

# Send email with log in attachment
function send_email() {
  echo "Sending email to ${MAILTO}"
  printf "An error occured during MariaDB replication on %s:\n\n%s" "${HOSTNAME}" "$(cat $ERRFILE)" \
      | $MAILXCMD -s "MariaDB replication error on $HOSTNAME" -r ${MAILFROM} -S ${SMTPSERVER} -a $ERRFILE ${MAILTO}
}

{
  echo "$(date +%Y%m%d_%H%M%S): Replication check started."

  # Check if MySQL is running
  if systemctl is-active mysql >/dev/null; then
    # Get MySQL replication status...
    mysql -u ${MYSQL_USER} -p"${MYSQL_PASSWORD}" -e 'SHOW SLAVE STATUS \G' | grep 'Running:\|Master:\|Error:' >$ERRFILE

    # Getting parameters
    slaveRunning="$(grep -c "Slave_IO_Running: Yes" $ERRFILE)"
    slaveSQLRunning="$(grep -c "Slave_SQL_Running: Yes" $ERRFILE)"
    secondsBehind="$(grep "Seconds_Behind_Master" $ERRFILE | tr -dc '0-9')"
  else
    # mysql is down
    printf "%s\n\n%s" "Error: MySQL seems to be down." "$(systemctl status mysql)" >$ERRFILE
    mysql_down=1
  fi

  # Check for problems and send email if needed
  if [[ $mysql_down == 1 || $slaveRunning != 1 || $slaveSQLRunning != 1 || $secondsBehind -gt $MAX_SECONDS_BEHIND ]]; then
    cat $ERRFILE
    echo "$(date +%Y%m%d_%H%M%S): Replication check finished. Problems detected."
    send_email
    RETVAL=1
  else
    echo "$(date +%Y%m%d_%H%M%S): Replication check finished OK."
    RETVAL=0
  fi

  sync
  exit $RETVAL
} 2>&1 | tee -a ${LOGFILE}
