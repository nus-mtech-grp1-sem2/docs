# Media

The OneStage demo video, `onestage-demo.mp4` (143 MB), is stored here in two parts. GitHub rejects any file over 100 MB, so the video is split into byte-for-byte pieces of 90 MB or less. The full video itself is ignored by git.

Table: Files in this folder

| File | Size | Content |
|---|---|---|
| `onestage-demo.mp4.001` | 90 MB | Part 1 of the demo video |
| `onestage-demo.mp4.002` | 53 MB | Part 2 of the demo video |

## Rejoining the video

Run one of these commands in this folder. Each one writes `onestage-demo.mp4`.

Windows (PowerShell or Command Prompt):

```powershell
cmd /c copy /b onestage-demo.mp4.001 + onestage-demo.mp4.002 onestage-demo.mp4
```

macOS or Linux:

```sh
cat onestage-demo.mp4.001 onestage-demo.mp4.002 > onestage-demo.mp4
```

Alternatively, open `onestage-demo.mp4.001` in 7-Zip and extract it. 7-Zip joins the parts automatically.

To check the result, compare its SHA-256 hash with `9c517900a13e797559da2b2d10ae3cf820699b7dabf3d7dd2a84aa3b4de25c76`. Use `Get-FileHash onestage-demo.mp4` on Windows or `shasum -a 256 onestage-demo.mp4` on macOS and Linux.

## Replacing the video

Delete the old parts, then split the new video into 90 MB pieces from Git Bash, macOS or Linux:

```sh
split -b 90M -d --suffix-length=3 --numeric-suffixes=1 onestage-demo.mp4 onestage-demo.mp4.
```

On macOS, use `gsplit` from GNU coreutils, because the built-in `split` lacks these options. Update the table and the hash above, then commit the parts.
