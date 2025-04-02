#!/bin/zsh

PHOTO_BACKUP_DIR='/Users/willjasen/Library/Mobile Documents/com~apple~CloudDocs/Photos app backup';
FROM_DATE='2025-03-01';
TO_DATE='2025-04-30';
TIMESTAMP=$(date "+%Y%m%d%H%M%S")
PHOTOS_ALBUMS=("Food" "Health")
REPORTS_DIR_NAME="-reports-"

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
    mkdir -p "${PHOTO_BACKUP_DIR}/${album}"
    custom_export $album
done

#
# https://github.com/RhetTbull/osxphotos?tab=readme-ov-file#command-line-reference-export
#