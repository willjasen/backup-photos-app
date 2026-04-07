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

## export PATH="$HOME/.local/bin:$PATH"

MIN_OSXPHOTOS_VERSION="0.74.0"
autoload -Uz is-at-least

version_lt() {
    local left="$1"
    local right="$2"
    if is-at-least "$right" "$left"; then
        echo 0
    else
        echo 1
    fi
}

upgrade_osxphotos() {
    if [[ -n "$VIRTUAL_ENV" && -x "$VIRTUAL_ENV/bin/python" ]]; then
        echo "Upgrading osxphotos in active virtual environment..."
        "$VIRTUAL_ENV/bin/python" -m pip install --upgrade "osxphotos>=${MIN_OSXPHOTOS_VERSION}" || return 1
        hash -r
        return 0
    fi

    if command -v pipx &>/dev/null; then
        echo "Upgrading osxphotos via pipx..."
        pipx upgrade osxphotos || return 1
        hash -r
        return 0
    fi

    return 1
}

ensure_osxphotos_version() {
    local current_version
    current_version=$(osxphotos --version 2>/dev/null | grep -Eo '[0-9]+(\.[0-9]+)+' | head -1)

    if [[ -z "$current_version" ]]; then
        echo "Unable to determine installed osxphotos version."
        return 1
    fi

    if [[ "$(version_lt "$current_version" "$MIN_OSXPHOTOS_VERSION")" == "1" ]]; then
        echo "Detected osxphotos ${current_version}, but macOS 26 Photos libraries require osxphotos ${MIN_OSXPHOTOS_VERSION} or newer."
        if ! upgrade_osxphotos; then
            echo "Failed to upgrade osxphotos automatically. Activate your export environment and run: python -m pip install --upgrade 'osxphotos>=${MIN_OSXPHOTOS_VERSION}'"
            return 1
        fi

        current_version=$(osxphotos --version 2>/dev/null | grep -Eo '[0-9]+(\.[0-9]+)+' | head -1)
        if [[ -z "$current_version" || "$(version_lt "$current_version" "$MIN_OSXPHOTOS_VERSION")" == "1" ]]; then
            echo "osxphotos upgrade did not reach the required version ${MIN_OSXPHOTOS_VERSION}."
            return 1
        fi
    fi
}

# Ensure osxphotos is installed
if ! command -v osxphotos &>/dev/null; then
    if ! command -v pipx &>/dev/null; then
        echo "pipx not found, installing via pip3..."
        pip3 install --user pipx
        python3 -m pipx ensurepath
    fi
    echo "osxphotos not found, installing via pipx..."
    pipx install osxphotos
fi

if ! ensure_osxphotos_version; then
    exit 1
fi

# Ensure exiftool is installed
if ! command -v exiftool &>/dev/null; then
    if ! command -v brew &>/dev/null; then
        echo "exiftool not found and Homebrew is not available. Please install exiftool from https://exiftool.org/"
        exit 1
    fi
    echo "exiftool not found, installing via Homebrew..."
    brew install exiftool
fi

CONFIG_FILE="$(dirname "$0")/config.json"
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Config file not found: $CONFIG_FILE (copy config.example.json to config.json and update values)"
    exit 1
fi

PHOTO_BACKUP_DIR=$(jq -r '.photo_backup_dir' "$CONFIG_FILE")
PHOTOS_LIBRARY_DIR=$(jq -r '.photos_library_dir' "$CONFIG_FILE")
REPORTS_DIR_NAME=$(jq -r '.reports_dir_name' "$CONFIG_FILE")
CHECKPOINTS=$(jq -r '.checkpoints' "$CONFIG_FILE")
FROM_DATE=$(jq -r '.from_date' "$CONFIG_FILE")
TO_DATE=$(jq -r '.to_date' "$CONFIG_FILE")

# Parse command-line parameters
RUN_ALBUMS=false
RUN_PEOPLE=false
RUN_DATE=false
RUN_ALL=false

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
    --all)
      RUN_ALL=true
      ;;
  esac
done

# If no specific export type is specified, exit with a message
if [[ "$RUN_ALBUMS" == "false" && "$RUN_PEOPLE" == "false" && "$RUN_DATE" == "false" && "$RUN_ALL" == "false" ]]; then
    echo "No parameters specified. Please provide --albums, --people, --date, or --all."
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

# Graceful shutdown on Ctrl+C or SIGTERM
cleanup() {
    trap - INT TERM
    echo "\n\033[0;33mInterrupt received, stopping exports...\033[0m"
    kill 0
    exit 130
}
trap cleanup INT TERM

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

export_all() {
    TIMESTAMP=$(date "+%Y%m%d%H%M%S")
    local all_dir_name="--all--";
    echo "\033[0;32mProcessing all photos\033[0m";
    mkdir -p "${PHOTO_BACKUP_DIR}/${all_dir_name}/${REPORTS_DIR_NAME}";
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
        --report "${PHOTO_BACKUP_DIR}/${all_dir_name}/${REPORTS_DIR_NAME}/${TIMESTAMP}.sqlite" \
        --export-by-date \
        "${PHOTO_BACKUP_DIR}/${all_dir_name}" \
        ;
    echo "\033[0;32mFinished processing all photos\033[0m";
}

#####
#####  --MAIN SCRIPT--
#####

# Export photos by album if --albums parameter is specified
if [[ "$RUN_ALBUMS" == "true" ]]; then
    echo "\033[0;36mRunning album exports\033[0m"
    max_jobs=1;
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
    max_jobs=1;
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

# Export all photos if --all parameter is specified
if [[ "$RUN_ALL" == "true" ]]; then
    echo "\033[0;36mRunning all-photos export\033[0m"
    export_all
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