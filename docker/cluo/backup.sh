#!/bin/sh
set -eu

: "${BACKUP_S3_BUCKET:?BACKUP_S3_BUCKET not set}"
: "${BACKUP_PASSPHRASE:?BACKUP_PASSPHRASE not set}"
: "${AWS_ACCESS_KEY_ID:?AWS_ACCESS_KEY_ID not set}"
: "${AWS_SECRET_ACCESS_KEY:?AWS_SECRET_ACCESS_KEY not set}"
: "${AWS_DEFAULT_REGION:?AWS_DEFAULT_REGION not set}"

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

echo "${LOG_PREFIX} Starting cluo backup"

backup_service "minio" "/minio-data"

# Prune old backups (keep last 30 days)
echo "${LOG_PREFIX} Pruning old backups..."
CUTOFF_DATE=$(date -d @$(( $(date +%s) - 30*86400 )) +%Y%m%d)
aws s3 ls "s3://${BACKUP_S3_BUCKET}/" | while read -r line; do
    FILE_NAME=$(echo "$line" | awk '{print $4}')
    FILE_DATE=$(echo "${FILE_NAME}" | sed -n 's/minio_\([0-9]\{8\}\)_.*/\1/p')
    if [ -n "$FILE_DATE" ] && [ "$FILE_DATE" -lt "$CUTOFF_DATE" ]; then
        echo "${LOG_PREFIX} Deleting old backup: ${FILE_NAME}"
        aws s3 rm "s3://${BACKUP_S3_BUCKET}/${FILE_NAME}"
    fi
done

echo "${LOG_PREFIX} Cluo backup completed successfully"
