# Photos Export

This project backs up photos and videos from the Photos app on macOS to a specified directory.
It uses the `osxphotos` command-line tool to export photos from the Photos app.

If you are running macOS 26.x, use `osxphotos >= 0.74.0`. Older versions fail against the newer Photos database schema.

Though the word "photos" is used here, it also backs up videos.

If the photos/videos are in iCloud, it will download them first.

To increase its speed, it uses the `--ramdb` option to store the database in RAM, but
saves to disk every 100 checkpoints/exports.

https://github.com/RhetTbull/osxphotos?tab=readme-ov-file#command-line-reference-export

## Set up

1. Copy `config.example.json` to `config.json` and update the paths.
2. Create `albums.txt` and `people.txt` inside the configured `photo_backup_dir`, or create them from the website.
3. Put one album or person on each line. Blank lines and lines beginning with `#` are ignored.

Album names cannot contain commas.

## Use the website

Double-click `start-website.command`, or run:

```sh
python3 app.py --open
```

The local site opens at <http://127.0.0.1:8765>. It can start and stop exports, show live output, and edit both list files. Leave the terminal window open while using the site. Press Control-C there to stop the website.

The site listens only on this Mac by default and has no third-party web dependencies.

The exporter uses `osxphotos` from the project's `.venv` directory when available. If it is missing, the script creates that local environment and installs `osxphotos` there; it does not modify Homebrew's system-managed Python.

## Use the script directly

Export everything:

```sh
./export-photos.zsh --all
```

Export by albums:

```sh
./export-photos.zsh --albums
```

Export by people:

```sh
./export-photos.zsh --people
```

Export a configured date range:

```sh
./export-photos.zsh --date
```

## Tests

```sh
python3 -m unittest discover -s tests
```
