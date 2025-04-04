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

PHOTO_BACKUP_DIR='/Users/willjasen/Application Data/Syncthing/Photos app';
PHOTOS_LIBRARY_DIR="/Users/willjasen/Pictures/Photos Library.photoslibrary";
REPORTS_DIR_NAME="-reports-";
CHECKPOINTS=100;

FROM_DATE='2025-03-01';
TO_DATE='2025-04-30';

# Replace empty PHOTO_ALBUMS array with file input.
ALBUMS_FILE="${PHOTO_BACKUP_DIR}/albums.txt"
if [[ -f "$ALBUMS_FILE" ]]; then
    PHOTO_ALBUMS=("${(f)$(<"$ALBUMS_FILE")}")
else
    echo "People file not found: $ALBUMS_FILE"
    PHOTO_ALBUMS=();
fi

# Replace empty PEOPLE array with file input.
PEOPLE_FILE="${PHOTO_BACKUP_DIR}/people.txt"
if [[ -f "$PEOPLE_FILE" ]]; then
    PEOPLE=("${(f)$(<"$PEOPLE_FILE")}")
else
    echo "People file not found: $PEOPLE_FILE"
    PEOPLE=();
fi

# Define a function wrapping osxphotos export with default parameters to export an album
export_album() {
    TIMESTAMP=$(date "+%Y%m%d%H%M%S")
    local album="$1"
    local by_album_dir_name="--by-album--";
    echo "\033[0;32mProcessing album: $album\033[0m"  # Changed echo to green output
    mkdir -p "${PHOTO_BACKUP_DIR}/${by_album_dir_name}/${album}/${REPORTS_DIR_NAME}"   # Ensure reports directory exists
    osxphotos export \
        --library ${PHOTOS_LIBRARY_DIR} \
        --verbose \
        --download-missing \
        --use-photokit \
        --exiftool \
        --touch-file \
        --sidecar XMP \
        --update \
        --ramdb \
        --checkpoint $CHECKPOINTS \
        --report "${PHOTO_BACKUP_DIR}/${by_album_dir_name}/${album}/${REPORTS_DIR_NAME}/${TIMESTAMP}.sqlite" \
        \
        --album "${album}" \
        "${PHOTO_BACKUP_DIR}/${by_album_dir_name}/${album}" \
        ;
        echo "\033[0;32mFinished processing album: $album\033[0m"  # Changed echo to green output
}

# Define a function wrapping osxphotos export with default parameters to all photos/videos between two dates
export_by_date() {
    TIMESTAMP=$(date "+%Y%m%d%H%M%S")
    local by_date_dir_name="--by-date--";
    echo "\033[0;32mProcessing all photos between $FROM_DATE and $TO_DATE\033[0m";  # Changed echo to green output
    mkdir -p "${PHOTO_BACKUP_DIR}/${by_date_dir_name}/${REPORTS_DIR_NAME}";
    osxphotos export \
    --library ${PHOTOS_LIBRARY_DIR} \
    --verbose \
    --download-missing \
    --use-photokit \
    --exiftool \
    --touch-file \
    --sidecar XMP \
    --update \
    --ramdb \
    --checkpoint $CHECKPOINTS \
    
    --report "${PHOTO_BACKUP_DIR}/${by_date_dir_name}/${REPORTS_DIR_NAME}/${TIMESTAMP}.sqlite" \
    \
    --from-date "$FROM_DATE" \
    --to-date "$TO_DATE" \
    --export-by-date \
    "${PHOTO_BACKUP_DIR}/${by_date_dir_name}" \
    ;
    echo "\033[0;32mFinished processing all photos between $FROM_DATE and $TO_DATE\033[0m";  # Changed echo to green output
}

export_by_person() {
    TIMESTAMP=$(date "+%Y%m%d%H%M%S")
    local person=$1
    local by_person_dir_name="--by-person--";
    echo "\033[0;32mProcessing all photos by person $1\033[0m";  # Changed echo to green output
    mkdir -p "${PHOTO_BACKUP_DIR}/${by_person_dir_name}/${person}/${REPORTS_DIR_NAME}";
    osxphotos export \
        --library ${PHOTOS_LIBRARY_DIR} \
        --verbose \
        --download-missing \
        --use-photokit \
        --exiftool \
        --touch-file \
        --sidecar XMP \
        --update \
        --ramdb \
        --checkpoint $CHECKPOINTS \
        --report "${PHOTO_BACKUP_DIR}/${by_person_dir_name}/${person}/${REPORTS_DIR_NAME}/${TIMESTAMP}.sqlite" \
        \
        --person $person \
        --export-by-date \
    "${PHOTO_BACKUP_DIR}/${by_person_dir_name}/${person}" \
    ;
    echo "\033[0;32mFinished processing all photos by person $1\033[0m";  # Changed echo to green output
}

# Cycle through each album to backup
#for album in "${PHOTO_ALBUMS[@]}"; do
#    TIMESTAMP=$(date "+%Y%m%d%H%M%S")
#    export_album $album
#done


#for album in "${PHOTO_ALBUMS[@]}"; do
#    ( export_album "$album" ) &
#done
#wait
#echo "\033[0;32mFinished processing all albums\033[0m"  # Changed echo to green output

# Export all photos/videos by person
for person in "${PEOPLE[@]}"; do
    ( export_by_person $person ) &
done
wait
echo "\033[0;32mFinished processing all people\033[0m"  # Changed echo to green output

# Export all photos between dates
# export_by_date

# wait
echo "All album and person exports have completed."

## --post-command exported "echo {shell_quote,{filepath}{comma}{,+keyword,}} >> {shell_quote,{export_dir}/exported.txt}"