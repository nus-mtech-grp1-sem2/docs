# Media

The OneStage demo video, `onestage_new.mp4` (128 MB), is stored here in two parts. GitHub rejects any file over 100 MB, so the video is split into byte-for-byte pieces of 90 MB or less. The full video itself is ignored by git.

Table: Files in this folder

| File | Size | Content |
|---|---|---|
| `onestage_new.mp4.001` | 90 MB | Part 1 of the demo video |
| `onestage_new.mp4.002` | 38 MB | Part 2 of the demo video |

## Rejoining the video

Run one of these commands in this folder. Each one writes `onestage_new.mp4`.

Windows (PowerShell or Command Prompt):

```powershell
cmd /c copy /b onestage_new.mp4.001 + onestage_new.mp4.002 onestage_new.mp4
```

macOS or Linux:

```sh
cat onestage_new.mp4.001 onestage_new.mp4.002 > onestage_new.mp4
```

Alternatively, open `onestage_new.mp4.001` in 7-Zip and extract it. 7-Zip joins the parts automatically.

To check the result, compare its SHA-256 hash with `2d9ed3db24ef98d9bfc0a73ae3942d413345a23280f9dddf6ed1b74974830c35`. Use `Get-FileHash onestage_new.mp4` on Windows or `shasum -a 256 onestage_new.mp4` on macOS and Linux.

## Replacing the video

Delete the old parts, then split the new video into 90 MB pieces from Git Bash, macOS or Linux:

```sh
split -b 90M -d --suffix-length=3 --numeric-suffixes=1 onestage_new.mp4 onestage_new.mp4.
```

On macOS, use `gsplit` from GNU coreutils, because the built-in `split` lacks these options. Update the table and the hash above, then commit the parts.
