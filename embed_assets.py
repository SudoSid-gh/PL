"""
embed_assets.py
Finds the first image and sound file in /assets,
base64-encodes them, and patches ShowAlert.ps1 in place.

Supported image types: .png .jpg .jpeg .bmp .gif .webp
Supported sound types: .wav .mp3 .m4a .ogg .flac .aac
"""

import base64, os, re, sys

ASSETS_DIR = "assets"
PS1_FILE   = "ShowAlert.ps1"

IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".bmp", ".gif", ".webp"}
SOUND_EXTS = {".wav", ".mp3", ".m4a", ".ogg", ".flac", ".aac"}

def find_asset(extensions):
    for fname in sorted(os.listdir(ASSETS_DIR)):
        ext = os.path.splitext(fname)[1].lower()
        if ext in extensions:
            return os.path.join(ASSETS_DIR, fname), ext
    return None, None

def encode(path):
    with open(path, "rb") as f:
        return base64.b64encode(f.read()).decode()

def patch_ps1(img_b64, img_ext, snd_b64, snd_ext):
    with open(PS1_FILE, "r", encoding="utf-8") as f:
        content = f.read()

    # Replace $IMAGE_B64 value
    content = re.sub(
        r'(\$IMAGE_B64\s*=\s*\')[^\']*\'',
        lambda m: m.group(0).split("'")[0] + "'" + img_b64 + "'",
        content
    )

    # Replace $ImageExt value
    content = re.sub(
        r'(\$ImageExt\s*=\s*")[^"]*"',
        f'\\g<1>{img_ext.lstrip(".")}"',
        content
    )

    # Replace $SOUND_B64 value
    content = re.sub(
        r'(\$SOUND_B64\s*=\s*\')[^\']*\'',
        lambda m: m.group(0).split("'")[0] + "'" + snd_b64 + "'",
        content
    )

    # Replace $SoundExt value (for non-wav formats)
    content = re.sub(
        r'(\$SoundExt\s*=\s*")[^"]*"',
        f'\\g<1>{snd_ext.lstrip(".")}"',
        content
    )

    with open(PS1_FILE, "w", encoding="utf-8") as f:
        f.write(content)

# ── Main ──────────────────────────────────────────────────────
if not os.path.isdir(ASSETS_DIR):
    print(f"ERROR: '{ASSETS_DIR}' folder not found.")
    sys.exit(1)

img_path, img_ext = find_asset(IMAGE_EXTS)
snd_path, snd_ext = find_asset(SOUND_EXTS)

if not img_path:
    print(f"ERROR: No image file found in '{ASSETS_DIR}'. Supported: {IMAGE_EXTS}")
    sys.exit(1)

if not snd_path:
    print(f"ERROR: No sound file found in '{ASSETS_DIR}'. Supported: {SOUND_EXTS}")
    sys.exit(1)

print(f"Image : {img_path} ({img_ext})")
print(f"Sound : {snd_path} ({snd_ext})")

img_b64 = encode(img_path)
snd_b64 = encode(snd_path)

print(f"Image B64 length : {len(img_b64)}")
print(f"Sound B64 length : {len(snd_b64)}")

patch_ps1(img_b64, img_ext, snd_b64, snd_ext)

print(f"✅ {PS1_FILE} updated successfully.")
