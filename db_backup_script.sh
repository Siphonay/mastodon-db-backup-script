#!/usr/bin/env bash

# Usage function: print usage to stderr and exit with code 5
function print_usage
{
	>&2 echo -e "Usage: ${0##*/} [OPTION] FOLDER BUCKET PREFIX
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


# Error function: print error to stderr and exit with the specified code
function error_abort
{
	>&2 echo -e "ERROR: ${1}"
	exit "${2}"
}


# Defining defaults
database_user='mastodon'
database_name='mastodon_production'
unset retention_days


# Parse arguments + error out if invalid
parsed_arguments=$(getopt --name "${0##*/}" -o u:d:r: --long database-user:,database-name:,retention-days: -- "${@}") || print_usage
eval set -- "${parsed_arguments}"

while :
do
	case ${1} in
		-u | --database-user) database_user="${2}"; shift 2;;
		-d | --database-name) database_name="${2}"; shift 2;;
		-r | --retention-days) retention_days="${2}"; shift 2;;
		--) shift; break;;
		*) >&2 echo "UNEXPECTED OPTION: ${1}"; print_usage;;
	esac
done

[[ ${#@} -eq 3 ]] || print_usage


# Finding the latest backup, check disk space if it exists
latest_backup=$(find "${1}" -type f -name "${3}_*" | head -1)

if [[ -n ${latest_backup} ]]
then
	latest_backup_size=$(stat -c "%s" "${latest_backup}")
	remaining_space=$(df -B1 "${1}" | tail -1 | cut -d' ' -f 9)
	[[ ${remaining_space} -gt ${latest_backup_size} ]] || error_abort 'not enough free space on device' 2
else
	>&2 echo 'WARNING: no previous backup found, skipping free space check'
fi


# Create dump at specified location with a timestamp after the prefix
backup_name="${3}_$(date +%Y%m%d%H%M%S)"
echo "Dumping the database into ${1}/${backup_name}…"

if ! pg_dump -Z 9 -Fc -U "${database_user}" -d "${database_name}" > "${1}/${backup_name}"
then
	rm -f "${1}/${backup_name}"
	error_abort 'failed to perform backup with pg_dump' 1
fi


# Upload to B2 bucket using the same filename as on the disk
echo "Uploading backup to B2 as ${backup_name} in bucket ${2}…"
b2 upload-file --noProgress "${2}" "${1}/${backup_name}" "${backup_name}" || error_abort 'failed to upload backup to B2 bucket' 3


# If the --retention-days option is used, verbosely delete backups older than the number of days specified.
if [[ -v retention_days ]]
then
	echo "Finding and deleting backups older than ${retention_days} days…"
	find "${1}" -type f -mtime +"${retention_days}" -name "${3}_*" -print0 | xargs -r0 rm -v || error_abort "failed to delete backups older than ${retention_days}" 4
fi


# No errors, exit gracefully
echo "All done."
exit 0