# backup-photos-app
script that i use to backup my macos photos app

This script will backup photo albums from the Photos app to a specified directory.
It uses the `osxphotos` command-line tool to export photos from the Photos app.

If you are running macOS 26.x, use `osxphotos >= 0.74.0`. Older versions fail against the newer Photos database schema.

Though the word "photos" is used here, it also backs up videos.

If the photos/videos are in iCloud, it will download them first.

To increase its speed, it uses the `--ramdb` option to store the database in RAM, but
saves to disk every 100 checkpoints/exports.

https://github.com/RhetTbull/osxphotos?tab=readme-ov-file#command-line-reference-export

---

Example commands:

To export albums:
`./export-photos --albums`