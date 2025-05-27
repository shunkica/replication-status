# replication-status
The script monitors MySQL/MariaDB replication status and alerts via email (or stderr if email is disabled) when issues are detected.

## Features

- Checks if the database is running
- Alerts on:
  - Slave IO not running
  - Slave SQL not running
  - Slave lag exceeds threshold ( default 300 seconds )
- Sends email via `mailx` or `msmtp`
- Logs activity to a file
