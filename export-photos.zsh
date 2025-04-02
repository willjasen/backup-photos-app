#!/bin/zsh

PHOTO_HOME='/Users/willjasen/Library/Mobile Documents/com~apple~CloudDocs/Photos app backup';
FROM_DATE='2025-03-01';
TO_DATE='2025-04-30';
TIMESTAMP=$(date "+%Y%m%d%H%M%S")
PHOTOS_ALBUMS=("Food" "Health")

# Define a function wrapping osxphotos export with default parameters
custom_export() {
    osxphotos export \
      --library ~/Pictures/Photos\ Library.photoslibrary \
      --download-missing \
      --use-photokit \
      --update \
      --ramdb \
      --checkpoint 100 \
      --export-by-date \
      --report "${PHOTO_HOME}/reports/export-${TIMESTAMP}.sqlite" \
      "$@"
}

mkdir -p "${PHOTO_HOME}/${PHOTO_ALBUM}"
cd "$PHOTO_HOME";

# Cycle through each album to backup
for album in "${PHOTOS_ALBUMS[@]}"; do
    mkdir -p "${PHOTO_HOME}/${album}"
    custom_export --album "${album}" "${PHOTO_HOME}/${album}"
done

#
# https://github.com/RhetTbull/osxphotos?tab=readme-ov-file#command-line-reference-export
#