#!/usr/bin/env bash
# Render every Mermaid source in diagrams/src to a PNG in diagrams/rendered.
#
# The PNGs are committed: the markdown chapters and the docx export both use
# them, so readers never need Mermaid support. Re-run this after editing any
# .mmd file and commit the source and the PNG together.
#
# Usage: scripts/render-diagrams.sh [name ...]   (no args = all diagrams)
# Needs: Docker. Image: minlag/mermaid-cli (pulled on first run).
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
src="$root/diagrams/src"
out="$root/diagrams/rendered"
image="${MERMAID_CLI_IMAGE:-minlag/mermaid-cli:latest}"
mkdir -p "$out"

if [ "$#" -gt 0 ]; then
  files=()
  for name in "$@"; do files+=("${name%.mmd}.mmd"); done
else
  files=()
  for path in "$src"/*.mmd; do files+=("$(basename "$path")"); done
fi

for file in "${files[@]}"; do
  base="${file%.mmd}"
  echo "rendering $base"
  docker run --rm -u "$(id -u):$(id -g)" -v "$root/diagrams:/data" "$image" \
    -i "/data/src/$file" -o "/data/rendered/$base.png" \
    -c /data/mermaid-config.json -b white -s 2 -q
done
