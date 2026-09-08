#!/bin/sh
set -eu

# Validate required environment variables
: "${BACKUP_S3_BUCKET:?BACKUP_S3_BUCKET not set}"
: "${BACKUP_PASSPHRASE:?BACKUP_PASSPHRASE not set}"
: "${AWS_ACCESS_KEY_ID:?AWS_ACCESS_KEY_ID not set}"
: "${AWS_SECRET_ACCESS_KEY:?AWS_SECRET_ACCESS_KEY not set}"
: "${AWS_DEFAULT_REGION:?AWS_DEFAULT_REGION not set}"
: "${INFISICAL_DB_PASSWORD:?INFISICAL_DB_PASSWORD not set}"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_PREFIX="[$(date -Iseconds)]"

backup_service() {
    NAME="$1"
    SRC_DIR="$2"
    ARCHIVE="/tmp/${NAME}_${TIMESTAMP}.tar.gz"
    ENCRYPTED="${ARCHIVE}.gpg"

    echo "${LOG_PREFIX} Compressing ${NAME} data..."
    tar -czf "${ARCHIVE}" -C "${SRC_DIR}" .

    echo "${LOG_PREFIX} Encrypting ${NAME} backup..."
    echo "${BACKUP_PASSPHRASE}" | gpg --batch --yes --passphrase-fd 0 \
        --symmetric --cipher-algo AES256 \
        --output "${ENCRYPTED}" "${ARCHIVE}"

    echo "${LOG_PREFIX} Uploading ${NAME} backup to S3..."
    aws s3 cp "${ENCRYPTED}" "s3://${BACKUP_S3_BUCKET}/$(basename "${ENCRYPTED}")" \
        --storage-class STANDARD_IA

    rm -f "${ARCHIVE}" "${ENCRYPTED}"
}

backup_postgres() {
    NAME="$1"
    HOST="$2"
    DB="$3"
    USER="$4"
    PASSWORD="$5"
    DUMP="/tmp/${NAME}_${TIMESTAMP}.sql.gz"
    ENCRYPTED="${DUMP}.gpg"

    echo "${LOG_PREFIX} Dumping ${NAME} Postgres database..."
    PGPASSWORD="${PASSWORD}" pg_dump -h "${HOST}" -U "${USER}" "${DB}" | gzip > "${DUMP}"

    echo "${LOG_PREFIX} Encrypting ${NAME} backup..."
    echo "${BACKUP_PASSPHRASE}" | gpg --batch --yes --passphrase-fd 0 \
        --symmetric --cipher-algo AES256 \
        --output "${ENCRYPTED}" "${DUMP}"

    echo "${LOG_PREFIX} Uploading ${NAME} backup to S3..."
    aws s3 cp "${ENCRYPTED}" "s3://${BACKUP_S3_BUCKET}/$(basename "${ENCRYPTED}")" \
        --storage-class STANDARD_IA

    rm -f "${DUMP}" "${ENCRYPTED}"
}

echo "${LOG_PREFIX} Starting backup"

backup_service "vaultwarden" "/data"
backup_service "anki" "/anki-data"
backup_service "woodpecker" "/woodpecker-data"
backup_postgres "infisical" "infisical-db" "infisical" "infisical" "${INFISICAL_DB_PASSWORD}"

# Prune old backups (keep last 30 days)
echo "${LOG_PREFIX} Pruning old backups..."
CUTOFF_DATE=$(date -d @$(( $(date +%s) - 30*86400 )) +%Y%m%d)
aws s3 ls "s3://${BACKUP_S3_BUCKET}/" | while read -r line; do
    FILE_NAME=$(echo "$line" | awk '{print $4}')
    FILE_DATE=$(echo "${FILE_NAME}" | sed -n 's/\(vaultwarden\|anki\|woodpecker\|infisical\)_\([0-9]\{8\}\)_.*/\2/p')
    if [ -n "$FILE_DATE" ] && [ "$FILE_DATE" -lt "$CUTOFF_DATE" ]; then
        echo "${LOG_PREFIX} Deleting old backup: ${FILE_NAME}"
        aws s3 rm "s3://${BACKUP_S3_BUCKET}/${FILE_NAME}"
    fi
done

echo "${LOG_PREFIX} Backup completed successfully"
