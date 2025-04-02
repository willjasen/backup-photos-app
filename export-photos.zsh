#!/bin/zsh

#
# This script will backup photo albums from the Photos app to a specified directory.
# It uses the `osxphotos` command-line tool to export photos from the Photos app.
#
# If the photos/videos are in iCloud, it will download them first.
#
# To increase its speed, it uses the `--ramdb` option to store the database in RAM, but
# saves to disk every 100 checkpoints/exports.
#
# https://github.com/RhetTbull/osxphotos?tab=readme-ov-file#command-line-reference-export
#

PHOTO_BACKUP_DIR='/Users/willjasen/Library/Mobile Documents/com~apple~CloudDocs/Photos app backup';
FROM_DATE='2025-03-01';
TO_DATE='2025-04-30';
REPORTS_DIR_NAME="-reports-"
PHOTOS_ALBUMS=("Food" "Health")

# Define a function wrapping osxphotos export with default parameters
custom_export() {
  local album="$1"
  echo "Processing album: $album"  # Added echo for album
  mkdir -p "${PHOTO_BACKUP_DIR}/${album}/${REPORTS_DIR_NAME}"   # Ensure reports directory exists
  osxphotos export \
    --library ~/Pictures/Photos\ Library.photoslibrary \
    --download-missing \
    --use-photokit \
    --update \
    --ramdb \
    --checkpoint 100 \
    --export-by-date \
    --report "${PHOTO_BACKUP_DIR}/${album}/${REPORTS_DIR_NAME}/export-${TIMESTAMP}.sqlite" \
    --album "${album}" \
    "${PHOTO_BACKUP_DIR}/${album}" \
    ;
}

# Cycle through each album to backup
for album in "${PHOTOS_ALBUMS[@]}"; do
    TIMESTAMP=$(date "+%Y%m%d%H%M%S")
    mkdir -p "${PHOTO_BACKUP_DIR}/${album}"
    custom_export $album
done

# osxphotos export \
#     --library ~/Pictures/Photos\ Library.photoslibrary \
#     --export-by-date \
#     --from-date "$FROM_DATE" \
#     --to-date "$TO_DATE" \
#     --update \
#     --checkpoint 1000 \
#     --download-missing --use-photokit \
#     --ramdb \
#     --report "${PHOTO_HOME}/reports/export-${TIMESTAMP}.sqlite" \
#     ;
