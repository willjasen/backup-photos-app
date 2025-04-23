#!/bin/zsh

# Track the script start time
START_TIME=$(date +%s)

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

PHOTO_BACKUP_DIR='/Volumes/tote/Photos/export-photos';
PHOTOS_LIBRARY_DIR="/Volumes/tote/Photos/Photos Library.photoslibrary";
REPORTS_DIR_NAME="-reports-";
CHECKPOINTS=100;

FROM_DATE='2025-03-01';
TO_DATE='2025-04-30';

# Parse command-line parameters
RUN_ALBUMS=false
RUN_PEOPLE=false
RUN_DATE=false

# Process command line arguments
for arg in "$@"; do
  case $arg in
    --albums)
      RUN_ALBUMS=true
      ;;
    --people)
      RUN_PEOPLE=true
      ;;
    --date)
      RUN_DATE=true
      ;;
  esac
done

# If no specific export type is specified, exit with a message
if [[ "$RUN_ALBUMS" == "false" && "$RUN_PEOPLE" == "false" && "$RUN_DATE" == "false" ]]; then
    echo "No parameters specified. Please provide --albums, --people, or --date."
    exit 1
fi

# Replace empty PHOTO_ALBUMS array with file input, skipping lines that start with a # sign or are blank.
ALBUMS_FILE="${PHOTO_BACKUP_DIR}/albums.txt"
if [[ -f "$ALBUMS_FILE" ]]; then
    PHOTO_ALBUMS=("${(f)$(grep -v '^\s*#' "$ALBUMS_FILE" | grep -v '^\s*$')}")
else
    echo "Albums file not found: $ALBUMS_FILE"
    PHOTO_ALBUMS=();
fi

# Replace empty PEOPLE array with file input, skipping lines that start with a # sign or are blank.
PEOPLE_FILE="${PHOTO_BACKUP_DIR}/people.txt"
if [[ -f "$PEOPLE_FILE" ]]; then
    PEOPLE=("${(f)$(grep -v '^\s*#' "$PEOPLE_FILE" | grep -v '^\s*$')}")
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
# --verbose \

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
# --verbose \

#####
#####  --MAIN SCRIPT--
#####

# Export photos by album if --albums parameter is specified
if [[ "$RUN_ALBUMS" == "true" ]]; then
    echo "\033[0;36mRunning album exports\033[0m"
    max_jobs=3;
    for album in "${PHOTO_ALBUMS[@]}"; do
        ((i=i%max_jobs)); ((i++==0)) && wait
        export_album "$album" &
    done
    wait
    echo "\033[0;32mFinished processing all albums\033[0m"
fi

# Export photos by person if --people parameter is specified
if [[ "$RUN_PEOPLE" == "true" ]]; then
    echo "\033[0;36mRunning people exports\033[0m"
    max_jobs=3;
    total_people=${#PEOPLE[@]};
    processed_people=0;

    for person in "${PEOPLE[@]}"; do
        ((i=i%max_jobs)); ((i++==0)) && wait
        ((processed_people++))
        percentage=$((processed_people * 100 / total_people))
        echo "\033[0;34mProgress: $percentage% ($processed_people/$total_people)\033[0m"
        export_by_person "$person" &
    done
    wait
    echo "\033[0;32mFinished processing all people\033[0m"
fi

# Export photos by date if --date parameter is specified
if [[ "$RUN_DATE" == "true" ]]; then
    echo "\033[0;36mRunning date-range export\033[0m"
    export_by_date
fi

echo "All exports have completed."

# Calculate and display the execution time
END_TIME=$(date +%s)
ELAPSED_TIME=$((END_TIME - START_TIME))
HOURS=$((ELAPSED_TIME / 3600))
MINUTES=$(( (ELAPSED_TIME % 3600) / 60 ))
SECONDS=$((ELAPSED_TIME % 60))

echo "\033[0;36mTotal execution time: ${HOURS}h ${MINUTES}m ${SECONDS}s\033[0m"

## --post-command exported "echo {shell_quote,{filepath}{comma}{,+keyword,}} >> {shell_quote,{export_dir}/exported.txt}"