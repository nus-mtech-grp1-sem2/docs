# Media

## K6 full-stack scalability demo (24 October 2026)

The presentation recording is stored as a private GitHub Release asset to keep
large binary content out of the repository history.

| Item | Value |
|---|---|
| Recording | [`K6_demo_24_Oct_1080p.mp4`](https://github.com/nus-mtech-grp1-sem2/docs/releases/download/k6-demo-2026-10-24/K6_demo_24_Oct_1080p.mp4) |
| Release | [`k6-demo-2026-10-24`](https://github.com/nus-mtech-grp1-sem2/docs/releases/tag/k6-demo-2026-10-24) |
| Access | Private; GitHub authentication and repository access are required |
| Duration | 23 minutes 3 seconds |
| Format | H.264 MP4, 1920 x 1080, 30 fps |
| Size | 48,607,260 bytes (46.4 MiB) |
| SHA-256 | `ae9aa21f1264f4aaa3e30730149112a4b037aa5fb7447f1c1cf509b139f06806` |

The recording shows the Grafana Cloud k6 run alongside live ECS desired,
pending, and running task counts, Application Auto Scaling activity,
per-service CPU metrics, and MySQL CPU and memory guardrails.

## Existing OneStage demo (split files)

The OneStage demo video, `onestage_new.mp4` (128 MB), is stored here in two parts. GitHub rejects any file over 100 MB, so the video is split into byte-for-byte pieces of 90 MB or less. The full video itself is ignored by git.

Table: Files in this folder

| File | Size | Content |
|---|---|---|
| `onestage_new.mp4.001` | 90 MB | Part 1 of the demo video |
| `onestage_new.mp4.002` | 38 MB | Part 2 of the demo video |

### Rejoining the video

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

### Replacing the video

Delete the old parts, then split the new video into 90 MB pieces from Git Bash, macOS or Linux:

```sh
split -b 90M -d --suffix-length=3 --numeric-suffixes=1 onestage_new.mp4 onestage_new.mp4.
```

On macOS, use `gsplit` from GNU coreutils, because the built-in `split` lacks these options. Update the table and the hash above, then commit the parts.
