# mastodon-db-backup-script
Script that makes a dump of a mastodon database, uploads it to a BackBlaze B2 container, and optionally deletes older backups. Originally made for [donphan.social](https://donphan.social), re-written to be used on any server without needing to edit the script.

## Requirements
- `bash` >= 4.2
- GNU `getopt` (from package `util-linux`)
- GNU `find`
- GNU `xargs`
- `b2` CLI set up with write access to a bucket for the user running the script

## Usage
```
Usage: db_backup_script.sh [OPTION] FOLDER BUCKET PREFIX
FOLDER is the folder where potentially existing backups will be looked for and the new backup will be created
BUCKET is the name of the BackBlaze B2 bucket to which the new backup will be uploaded
PREFIX is the filename prefix of the potentially existing backups and the new backup

Additional options, all with mandatory arguments:
  -u, --database-user=USER      username for the PostgreSQL to perform a backup on
                                default value if option not used: mastodon

  -d, --database-name=NAME      name of the PostgreSQL database to perform a backup on
                                default value if option not used: mastodon_production

  -r, --retention-days=NUM      existing backups older than the number of days specified will be deleted
```

## Automation
This script is meant to be scheduled to run daily, for example with `cron`, here’s an example entry for a cron job, with e-mail alert sent with `ssmtp` in case of an error:
```
0 12 * * * /bin/bash -c '"${HOME}/mastodon-db-backup-script/db_backup_script.sh" --retention-days=14 "${HOME}/backup" mastodon_db_backups db_dump >>"${HOME}/db_backup_script.log" 2>"${HOME}/db_backup_script.err.log" || echo -e "Subject: DAILY DB BACKUP FAILED\n\n$(cat "${HOME}/db_backup_script.err.log")" | ssmtp your@email.here'
```
Of course, you have to replace the paths to where you store the scripts and where you want to store the logs, set the script’s options and arguments to your liking as well as configure your SMTP client and replace the example e-mail address with your desired one.

You might also want to change the job’s time. [crontab.guru](https://crontab.guru) is helpful.