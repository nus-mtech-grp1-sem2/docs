#!/usr/bin/env bash
# Build a .docx of the architecture chapter (report chapter 3, plus the API
# appendix) using the project report template's styles.
#
# Each file is written as a standalone page (its own "#" heading). This script
# shifts each file's headings so they nest as in the report template:
#
#   Solution Overview (H1)                       00-overview.md            +0
#     Logical Architecture & Design (H2)         01-logical-architecture   +1
#       Platform Design (H3, 3.1.4)              02-platform-design        +2
#     Physical Architecture & Design (H2)        03-physical-architecture  +1
#       Persistence Design (H3, 3.2.3)           04-persistence-design     +2
#       Detailed Design (H3, 3.2.4)              05-detailed-design        +2
#     Other Architectural Decisions (H2)         06-other-decisions        +1
#     Architectural Limitation (H2)              07-architectural-limits   +1
#   Appendix: API Catalogue (H1)                 08-api-catalogue          +0
#
# Pandoc turns "Table: ..." lines into table captions and a lone image with
# alt text into a captioned figure. Word numbers the headings from the
# template's styles, so the markdown headings carry no numbers. fit-figures.lua
# sizes diagrams to the A4 page; make-reference-docx.py adds table and caption
# styles the template lacks.
#
# Usage: scripts/export-docx.sh [output.docx]
#        (default build/OneStage-Architecture.docx; build/ is git-ignored)
# Needs: Docker (image pandoc/core, pulled on first run) and python3.
# Reference doc: ../project_report_template.docx, or set REFERENCE_DOCX.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
out="${1:-$root/build/OneStage-Architecture.docx}"
image="${PANDOC_IMAGE:-pandoc/core:latest}"
reference="${REFERENCE_DOCX:-$root/../project_report_template.docx}"
mkdir -p "$(dirname "$out")" "$root/build"

combined="$root/build/architecture-combined.md"
: > "$combined"

add() { # add <file> <heading shift>
  awk -v shift="$2" '
    /^#+ / { prefix = ""; for (i = 0; i < shift; i++) prefix = prefix "#"; print prefix $0; next }
    { print }
  ' "$root/architecture/$1" >> "$combined"
  printf '\n\n' >> "$combined"
}

add 00-overview.md 0
add 01-logical-architecture.md 1
add 02-platform-design.md 2
add 03-physical-architecture.md 1
add 04-persistence-design.md 2
add 05-detailed-design.md 2
add 06-other-decisions.md 1
add 07-architectural-limitations.md 1
add 08-api-catalogue.md 0

ref_args=()
if [ -f "$reference" ]; then
  python3 "$root/scripts/make-reference-docx.py" "$reference" "$root/build/reference.docx"
  ref_args=(--reference-doc=/data/build/reference.docx)
else
  echo "warning: $reference not found; using pandoc's default styles" >&2
fi

docker run --rm -u "$(id -u):$(id -g)" -v "$root:/data" -w /data "$image" \
  build/architecture-combined.md \
  --from=markdown --to=docx \
  --resource-path=/data/architecture \
  --lua-filter=/data/scripts/fit-figures.lua \
  "${ref_args[@]}" \
  --output="/data/build/$(basename "$out")"

if [ "$(cd "$(dirname "$out")" && pwd)/$(basename "$out")" != "$root/build/$(basename "$out")" ]; then
  mv "$root/build/$(basename "$out")" "$out"
fi
echo "wrote $out"
