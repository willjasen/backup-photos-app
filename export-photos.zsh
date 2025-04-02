#!/bin/zsh

#
# This script will backup photos/videos from the Photos app to a specified directory.
# It uses the `osxphotos` command-line tool to export photos from the Photos app.
#
# If the photos/videos are in iCloud, it will download them first.
#
# To increase its speed, it uses the `--ramdb` option to store the database in RAM, but
# saves to disk after a supplied amount of checkpoints/exports.
#
# https://github.com/RhetTbull/osxphotos?tab=readme-ov-file#command-line-reference-export
#

PHOTO_BACKUP_DIR='/Users/willjasen/Library/Mobile Documents/com~apple~CloudDocs/Photos app backup';
PHOTOS_LIBRARY_DIR="/Users/willjasen/Pictures/Photos Library.photoslibrary";
REPORTS_DIR_NAME="-reports-";
CHECKPOINTS=100;

FROM_DATE='2025-03-01';
TO_DATE='2025-04-30';

PHOTOS_ALBUMS=();
PEOPLE=();

# Define a function wrapping osxphotos export with default parameters to export an album
export_album() {
    TIMESTAMP=$(date "+%Y%m%d%H%M%S")
    local album="$1"
    echo "\033[0;32mProcessing album: $album\033[0m"  # Changed echo to green output
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
    TIMESTAMP=$(date "+%Y%m%d%H%M%S")
    local by_date_dir_name="-by-date-";
    echo "\033[0;32mProcessing all photos between $FROM_DATE and $TO_DATE\033[0m";  # Changed echo to green output
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

export_by_person() {
    TIMESTAMP=$(date "+%Y%m%d%H%M%S")
    local person=$1
    local by_person_dir_name="-by-person-";
    echo "\033[0;32mProcessing all photos by person $1\033[0m";  # Changed echo to green output
    mkdir -p "${PHOTO_BACKUP_DIR}/${by_person_dir_name}/${person}/${REPORTS_DIR_NAME}";
    osxphotos export \
    --library ${PHOTOS_LIBRARY_DIR} \
    --download-missing \
    --use-photokit \
    --update \
    --ramdb \
    --checkpoint $CHECKPOINTS \
    --export-by-date \
    --report "${PHOTO_BACKUP_DIR}/${by_person_dir_name}/${person}/${REPORTS_DIR_NAME}/export-${TIMESTAMP}.sqlite" \
    \
    --person $person \
    "${PHOTO_BACKUP_DIR}/${by_person_dir_name}/${person}" \
    ;
}

# Cycle through each album to backup
for album in "${PHOTOS_ALBUMS[@]}"; do
    TIMESTAMP=$(date "+%Y%m%d%H%M%S")
    export_album $album
done

# Export all photos/videos by person
for person in "${PEOPLE[@]}"; do
    export_by_person $person
done

# Export all photos between dates
# export_by_date


## --post-command exported "echo {shell_quote,{filepath}{comma}{,+keyword,}} >> {shell_quote,{export_dir}/exported.txt}"