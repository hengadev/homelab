#!/bin/sh
set -eu

# Validate required environment variables
: "${BACKUP_S3_BUCKET:?BACKUP_S3_BUCKET not set}"
: "${BACKUP_PASSPHRASE:?BACKUP_PASSPHRASE not set}"
: "${AWS_ACCESS_KEY_ID:?AWS_ACCESS_KEY_ID not set}"
: "${AWS_SECRET_ACCESS_KEY:?AWS_SECRET_ACCESS_KEY not set}"
: "${AWS_DEFAULT_REGION:?AWS_DEFAULT_REGION not set}"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="vaultwarden_${TIMESTAMP}.tar.gz"
ENCRYPTED_FILE="${BACKUP_FILE}.gpg"
LOG_PREFIX="[$(date -Iseconds)]"

echo "${LOG_PREFIX} Starting Vaultwarden backup"

# Create compressed archive
echo "${LOG_PREFIX} Compressing vaultwarden data..."
tar -czf "/tmp/${BACKUP_FILE}" -C /data .

# Encrypt with symmetric GPG
echo "${LOG_PREFIX} Encrypting backup..."
echo "${BACKUP_PASSPHRASE}" | gpg --batch --yes --passphrase-fd 0 \
    --symmetric --cipher-algo AES256 \
    --output "/tmp/${ENCRYPTED_FILE}" "/tmp/${BACKUP_FILE}"

# Upload to S3
echo "${LOG_PREFIX} Uploading to S3..."
aws s3 cp "/tmp/${ENCRYPTED_FILE}" "s3://${BACKUP_S3_BUCKET}/${ENCRYPTED_FILE}" \
    --storage-class STANDARD_IA

# Clean up local files
rm -f "/tmp/${BACKUP_FILE}" "/tmp/${ENCRYPTED_FILE}"

# Prune old backups (keep last 30 days)
echo "${LOG_PREFIX} Pruning old backups..."
CUTOFF_DATE=$(date -d "30 days ago" +%Y%m%d)
aws s3 ls "s3://${BACKUP_S3_BUCKET}/" | while read -r line; do
    FILE_NAME=$(echo "$line" | awk '{print $4}')
    FILE_DATE=$(echo "${FILE_NAME}" | sed -n 's/vaultwarden_\([0-9]\{8\}\).*/\1/p')
    if [ -n "$FILE_DATE" ] && [ "$FILE_DATE" -lt "$CUTOFF_DATE" ]; then
        echo "${LOG_PREFIX} Deleting old backup: ${FILE_NAME}"
        aws s3 rm "s3://${BACKUP_S3_BUCKET}/${FILE_NAME}"
    fi
done

echo "${LOG_PREFIX} Backup completed successfully"
