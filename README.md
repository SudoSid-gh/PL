# ShowAlert

A self-contained PowerShell prank/alert script with auto-embedding via GitHub Actions.

## How it works

1. You drop an image and sound file into the `assets/` folder and push to GitHub
2. The GitHub Action automatically encodes them and bakes them into `ShowAlert.ps1`
3. Download the updated `ShowAlert.ps1` — no other files needed

---

## Usage

### 1. Add your files to `assets/`

| Type  | Supported formats                          |
|-------|--------------------------------------------|
| Image | `.png` `.jpg` `.jpeg` `.bmp` `.gif` `.webp` |
| Sound | `.wav` `.mp3` `.m4a` `.ogg` `.flac` `.aac`  |

Only **one image** and **one sound** file at a time. If there are multiple, it picks the first one alphabetically.

### 2. Push to GitHub

```bash
git add assets/
git commit -m "Update assets"
git push
```

The Action runs automatically and commits an updated `ShowAlert.ps1` within ~30 seconds.

### 3. Download and run

```powershell
powershell -ExecutionPolicy Bypass -File ShowAlert.ps1
```

---

## Repo structure

```
/
├── .github/
│   └── workflows/
│       └── build.yml       ← GitHub Action
├── assets/
│   ├── image.png           ← your image goes here
│   └── sound.m4a           ← your sound goes here
├── embed_assets.py         ← encoding script (run by the Action)
├── ShowAlert.ps1           ← the final self-contained script
└── README.md
```

---

## Settings (in ShowAlert.ps1)

| Variable          | Default | Description                        |
|-------------------|---------|------------------------------------|
| `$DelaySeconds`   | `30`    | How long to wait before showing    |
| `$DisplaySeconds` | `5`     | How long to show the alert         |

These are at the top of the script and can be edited manually after downloading.
