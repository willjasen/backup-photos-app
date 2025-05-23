# query function to be used with osxphotos query --query-function to find photos with identified face circles that are unnamed.
# See: https://www.reddit.com/r/osxphotos/comments/16o3wbs/finding_unnamed_faces_more_than_apple_photos_shows/
# Run with `osxphotos query --query-function find_unnamed_faces.py::unnamed_faces --add-to-album "Unnamed Faces" --quiet`

from __future__ import annotations
from osxphotos import PhotoInfo


def unnamed_faces(photos: list[PhotoInfo]) -> list[PhotoInfo]:
    # your query function should take a list of PhotoInfo objects and return a list of PhotoInfo objects (or empty list)"""

    face_quality = -1.0

    # filter out photos with no face info
    photos = [p for p in photos if p.face_info]
    if not photos:
        return []

    # filter out screenshots
    photos = [p for p in photos if "screenshot" not in p.filename.lower()]
    if not photos:
        return []

    # filter out .png images
    # photos = [p for p in photos if not p.filename.lower().endswith(".png")]
    # if not photos:
    #     return []
    
    # filter out photos with "ignore-faces" keyword
    photos = [p for p in photos if "ignore-faces" not in p.keywords]
    if not photos:
        return []

    # find identified face circles with no name
    face_photos = []
    for photo in photos:
        for face in photo.face_info:
            if face.quality > face_quality and (face.name is None or face.name.strip() == ""):
                face_photos.append(photo)
                break
    return face_photos
