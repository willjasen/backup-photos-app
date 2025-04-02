#!/bin/zsh

#
# This script will backup photo albums from the Photos app to a specified directory.
# It uses the `osxphotos` command-line tool to export photos from the Photos app.
#
# Though the word "photos" is used here, it also backs up videos.
#
# If the photos/videos are in iCloud, it will download them first.
#
# To increase its speed, it uses the `--ramdb` option to store the database in RAM, but
# saves to disk every 100 checkpoints/exports.
#
# https://github.com/RhetTbull/osxphotos?tab=readme-ov-file#command-line-reference-export
#

PHOTO_BACKUP_DIR='/Users/willjasen/Library/Mobile Documents/com~apple~CloudDocs/Photos app backup';
PHOTOS_LIBRARY_DIR="/Users/willjasen/Pictures/Photos Library.photoslibrary";
FROM_DATE='2025-03-01';
TO_DATE='2025-04-30';
REPORTS_DIR_NAME="-reports-";
CHECKPOINTS=100;
PHOTOS_ALBUMS=("Food");

# Define a function wrapping osxphotos export with default parameters to export an album
export_album() {
  local album="$1"
  echo "Processing album: $album"  # Added echo for album
  mkdir -p "${PHOTO_BACKUP_DIR}/${album}/${REPORTS_DIR_NAME}"   # Ensure reports directory exists
  osxphotos export \
    --library ${PHOTOS_LIBRARY_DIR} \
    --download-missing \
    --use-photokit \
    --update \
    --ramdb \
    --checkpoint $CHECKPOINTS \
    --export-by-date \
    --report "${PHOTO_BACKUP_DIR}/${album}/${REPORTS_DIR_NAME}/export-${TIMESTAMP}.sqlite" \
    \
    --album "${album}" \
    "${PHOTO_BACKUP_DIR}/${album}" \
    ;
}

# Define a function wrapping osxphotos export with default parameters to all photos/videos between two dates
export_by_date() {
    local by_date_dir_name="-by-date-";
    echo "Processing all photos between $FROM_DATE and $TO_DATE";
    mkdir -p "${PHOTO_BACKUP_DIR}/${by_date_dir_name}/${REPORTS_DIR_NAME}";
    osxphotos export \
    --library ${PHOTOS_LIBRARY_DIR} \
    --download-missing \
    --use-photokit \
    --update \
    --ramdb \
    --checkpoint $CHECKPOINTS \
    --export-by-date \
    --report "${PHOTO_BACKUP_DIR}/${by_date_dir_name}/${REPORTS_DIR_NAME}/export-${TIMESTAMP}.sqlite" \
    \
    --from-date "$FROM_DATE" \
    --to-date "$TO_DATE" \
    "${PHOTO_BACKUP_DIR}/${by_date_dir_name}" \
    ;
}

# Cycle through each album to backup
for album in "${PHOTOS_ALBUMS[@]}"; do
    TIMESTAMP=$(date "+%Y%m%d%H%M%S")
    mkdir -p "${PHOTO_BACKUP_DIR}/${album}"
    export_album $album
done

# Export all photos between dates
TIMESTAMP=$(date "+%Y%m%d%H%M%S")
export_by_date


## --post-command exported "echo {shell_quote,{filepath}{comma}{,+keyword,}} >> {shell_quote,{export_dir}/exported.txt}" 