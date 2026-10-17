# OneStage design documents

Design documentation for OneStage, the SWE5001 (Architecting Scalable Systems, NUS-ISS) team project: a cloud-native ticketing platform on AWS. The `architecture/` folder describes the system **as built**. It is written to drop into chapter 3 of the project report (`project_report_template.docx`) with as little editing as possible.

## What is here

| Path | Report section | Content |
|---|---|---|
| `architecture/00-overview.md` | 3 Solution Overview (introduction) | System context, the solution at a glance, original design versus as built |
| `architecture/01-logical-architecture.md` | 3.1, 3.1.1–3.1.3 | AD-01 to AD-11, logical detail deployment diagram, tiers and layers, nodes and subsystems |
| `architecture/02-platform-design.md` | 3.1.4 Platform Design | Seed, producers, consumers; bounded contexts; context map; aggregates; domain events |
| `architecture/03-physical-architecture.md` | 3.2, 3.2.1–3.2.2 | AD-12 to AD-22, physical detail deployment diagram, technology and services |
| `architecture/04-persistence-design.md` | 3.2.3 Persistence Design | Schemas, ERDs, cross-schema access, concurrency, retention, data groups |
| `architecture/05-detailed-design.md` | 3.2.4 Detailed Design | Buyer journey for both tiers; seated purchase under contention; asynchronous payment and issuance; door check-in |
| `architecture/06-other-decisions.md` | 3.3 Other Architectural Decisions | AD-23 to AD-30 |
| `architecture/07-architectural-limitations.md` | 3.4 Architectural Limitation | AISS-01 to AISS-17 |
| `architecture/08-api-catalogue.md` | Appendix | Every HTTP endpoint and message contract |
| `performance-testing/k6/2026-10-11-grafana-cloud-results.md` | 4 Quality Attributes | Deployed read-only Grafana Cloud k6 evidence |
| `performance-testing/buyer-workflow/2026-10-13-buyer-workflow-capacity-results.md` | 4 Quality Attributes | Stage-by-stage (B), end-to-end (A) and browser-overlay (D) evidence |
| `diagrams/src/*.mmd` | | Mermaid sources, one per figure; the file number is the figure number |
| `diagrams/rendered/*.png` | | Rendered figures, used by both the markdown and the docx |
| `scripts/render-diagrams.sh` | | Re-renders the figures (Docker) |
| `scripts/export-docx.sh` | | Builds `build/OneStage-Architecture.docx` with the report template's styles (Docker, python3) |
| `onestage-user-stories.md` | 1.4 Project Scope | The 27 user stories and use-case diagrams (requirements baseline) |
| `archive/` | | The original August 2026 system design and BCE diagrams, kept as a historical record |
| `media/` | | The demo video, split into parts under GitHub's 100 MB limit; `media/README.md` explains how to rejoin them |

The project proposal (`SWE5001_project_proposal.docx`) is the record of the initial plan and is not updated.

## Status and sources

The architecture chapter reflects the code and infrastructure on 17 October 2026:

- `backend-repo` at `e62ba78`
- `core-frontend` at `a1e77e1`
- ADRs 0001–0003 in `onestage-ai-engineering`

Statements about behaviour come from reading the code, the database migrations, `kong.yml` and Terraform, not from the original design. When the system changes, update the affected section and the original-versus-as-built table in `00-overview.md`.

Not integrated into the generated report yet: chapter 4 (Quality Attributes) and chapter 5 (DevOps and Development Lifecycle). The captured performance evidence is available under `performance-testing/`.

## Writing conventions (keep these so the docx export stays clean)

- **One top-level `#` heading per file**, with no section numbers. Word numbers headings from the template's styles (levels 1–3, for example 3.1.1; deeper levels are unnumbered). The export script nests each file at the right level.
- **Tables are plain pipe tables**, with no HTML, no merged cells and no lists inside cells. Put a caption line `Table: ...` directly above the table, on its own line, with a blank line before it.
- **Figures are PNG images on a line of their own** with alt text `Figure N. Caption`. Pandoc turns the alt text into the figure caption. Never put Mermaid code blocks in the chapters: they do not survive export.
- **IDs are stable.** ADs are numbered continuously across 3.1, 3.2 and 3.3 (AD-01 to AD-30); limitations are AISS-01 onwards. Add new decisions at the end of the relevant range and renumber only before submission.
- **Cross-reference by section name or ID** ("see Persistence Design", "AISS-03"), not by file name.
- **Cite evidence as `repo: path`**, for example `backend-repo: services/order/src/index.ts`.
- **British English** (organiser, behaviour), and plain sentences.

## Updating a diagram

1. Edit `diagrams/src/NN-name.mmd`. Prefer top-to-bottom layouts: wide left-to-right diagrams shrink to unreadable sizes on an A4 page.
2. Run `scripts/render-diagrams.sh NN-name` (or no argument for all).
3. Check the PNG, then commit the source and the PNG together.

Mermaid ignores a subgraph's `direction` when arrows from outside point at nodes inside it, so keep cross-subgraph arrows pointing at the subgraph or restructure the diagram.

## Exporting to Word

```sh
scripts/export-docx.sh                     # writes build/OneStage-Architecture.docx
scripts/export-docx.sh ~/report-ch3.docx   # or choose the output path
```

The script:

1. Joins the chapter files in report order, shifting their headings.
2. Copies `../project_report_template.docx` and adds bordered table and caption styles that the template lacks (`scripts/make-reference-docx.py`).
3. Runs pandoc with that copy as the reference document and `scripts/fit-figures.lua`, which sizes each figure to fit an A4 page.

To use the result, paste its content into the report under chapter 3 (Keep Source Formatting), or use Word's Insert > Object > Text from File. The tallest figures (physical deployment, context map, check-in sequence) may read better on a landscape page in the final report.
