# Steam Workshop publishing kit

Everything needed for the Steam Workshop and Paradox Mods listings. Nothing here ships with the mod
itself — the mod is `descriptor.mod`, `thumbnail.png` and `gfx/` in the repository root.

| File | Where it goes |
| --- | --- |
| `description-en.txt` | Workshop item description (BBCode) |
| `description-ru.txt` | Russian version of the same description |
| `description-paradoxmods-en.txt` | same text without BBCode, for the Paradox Mods site |
| `description-paradoxmods-ru.txt` | Russian version without BBCode |
| `short-description-en.txt` | Launcher / Paradox Mods short description, 191 chars |
| `short-description-ru.txt` | Russian short description, 187 chars |
| `make_thumbnail.py` | rebuilds `thumbnail.png` from two screenshots |

The `description-paradoxmods-*.txt` files are mechanically derived from the BBCode ones
(headers uppercased, `[*]` to `-`, tags dropped, `[url]` reduced to the bare link). Edit the
BBCode version first, then regenerate, so the two never drift apart.

## Listing metadata

* **Title:** Sharp Terrain Without Advanced Shaders
* **Tags:** Fixes, Graphics, Utilities — same as `descriptor.mod`
* **Version:** 1.0.0, `supported_version="1.19.*"`
* **Visibility:** public

Short descriptions are kept under the launcher's 200 character limit; both
BBCode descriptions are well under Steam's 8000 character limit.

## Preview image on Steam

The Workshop preview is **not** set from the uploader form — the launcher picks up
`thumbnail.png` from the mod root (next to `descriptor.mod`), which is also what
`picture="thumbnail.png"` in the descriptor points at. Without that file the item
shows Steam's default placeholder, and images added to the item's gallery on the
website do not replace it.

After changing it, re-run `install.sh` and upload the mod again from the launcher —
it updates the existing Workshop item rather than creating a new one.

The uploader form's own image field applies to Paradox Mods, not to Steam.

## Rebuilding the thumbnail

`make_thumbnail.py` takes a vanilla screenshot and a modded one, crops the same
2120x1060 window out of both (chosen so that no HUD element — the pause label, the
resource bar, the portrait, the minimap, the right-hand icon column — is inside it),
stacks them, and labels them BEFORE / AFTER.

Point `OLD` and `NEW` at the two screenshots and run it. Both must be shot at the same
resolution; `CROP` is in the coordinates of a 5120x1440 screenshot, so on a different
resolution it needs adjusting.

## Image metadata

`thumbnail.png` in the repo root is 1280x1280, 922 KB, under Steam's 1 MB limit. It is
quantised to a 256 colour palette — at this size the dither is invisible, and it is what
keeps a full resolution square under the limit; a truecolour 1280x1280 comes out at 1.7 MB.

The image is rebuilt from raw pixels, so it carries no PNG text chunks, no EXIF and no
ICC profile from the source screenshots. Verify any replacement before committing it:

    python3 -c "from PIL import Image; im=Image.open('thumbnail.png'); print(len(im.getexif()), im.info)"
