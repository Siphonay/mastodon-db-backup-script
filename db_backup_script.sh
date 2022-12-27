#!/bin/bash

function print_usage
{
	>&2 echo -e "Usage: $(basename "${0}") [OPTION] FOLDER BUCKET PREFIX
FOLDER is the folder where potentially existing backups will be looked for and the new backup will be created
BUCKET is the name of the BackBlaze B2 bucket to which the new backup will be uploaded
PREFIX is the filename prefix of the potentially existing backups and the new backup\n
Additional options, all with mandatory arguments:
  -u, --database-user=USER\tusername for the PostgreSQL to perform a backup on
\t\t\t\tdefault value if option not used: mastodon\n
  -d, --database-name=NAME\tname of the PostgreSQL database to perform a backup on
\t\t\t\tdefault value if option not used: mastodon_production\n
  -r, --retention-days=NUM\texisting backups older than the number of days specified will be deleted"
	exit 5
}

# Defining defaults
database_user="mastodon"
database_name="mastodon_production"
unset retention_days

# Parse arguments + error out if invalid
parsed_arguments="$(getopt -n "$(basename "${0}")" -o u:d:r: --long database-user:,database-name:,retention-days: -- "${@}")" || print_usage

eval set -- "${parsed_arguments}"
while :
do
	case "${1}" in
		-u | --database-user) database_user="${2}"; shift 2;;
		-d | --database-name) database_name="${2}"; shift 2;;
		-r | --retention-days) retention_days="${2}"; shift 2;;
		--) shift; break;;
		*) >&2 echo "UNEXPECTED OPTION: ${1}"; print_usage;;
	esac
done

if [ "${#@}" -ne 3 ]
then
	print_usage
fi

# Finding the latest backup
latest_backup=$(find "${1}" -type f -name "${3}_*" | head -1)

# If latest backup exists, check if enough space
if [ -n "${latest_backup}" ]
then
	latest_backup_size=$(stat -c "%s" "${latest_backup}")
	remaining_space=$(df -B1 "${1}" | tail -1 | cut -d' ' -f 9)

	if [ "${remaining_space}" -lt "${latest_backup_size}" ]
	then
		>&2 echo "ERROR: NOT ENOUGH FREE SPACE ON DEVICE!!!"
		exit 2
	fi
else
	>&2 echo "WARNING: no previous backup found"
fi

backup_name="${3}_$(date +%Y%m%d%H%M%S)"
echo "Backing up the database…"
if ! pg_dump -Z 9 -Fc -U "${database_user}" -d "${database_name}" > "${1}/${backup_name}"
then
	>&2 echo "ERROR PERFORMING BACKUP!!!"
	rm -f "${1}/${backup_name}"
	exit 1
fi
echo "Created backup ${1}/${backup_name}"

echo "Uploading backup to BackBlaze…"
if ! b2 upload-file --noProgress "${2}" "${1}/${backup_name}" "${backup_name}"
then
	>&2 echo "ERROR UPLOADING BACKUP TO BACKBLAZE!!!"
	exit 3
fi
echo "Uploaded to BackBlaze as ${backup_name} in bucket ${2}"

if [ -v retention_days ]
then
	echo "Finding and deleting backups older than ${retention_days} days…"
	if ! find "${1}" -type f -mtime +"${retention_days}" -name "${3}_*" -print0 | xargs -r0 rm -v
	then
		>&2 echo "ERROR DELETING BACKUPS OLDER THAN ${retention_days} DAYS!!!"
		exit 4
	fi
fi

echo "All done."
exit 0