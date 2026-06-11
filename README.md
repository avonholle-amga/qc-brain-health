# Brain Health QI — QC Data Report Shiny App

A Shiny app that takes an HCO Excel data template, runs the existing
two-step Rmd pipeline, displays the HTML report in the browser, and
offers the report as an HTML or Word download.

## Files

| File | Role |
|---|---|
| `app.R` | The Shiny app (upload, options, render, view, download) |
| `data-handling.Rmd` | Step 1: reads the Excel template, builds `df` / `df.wide.tot`, saves `dat.RData` |
| `analysis.Rmd` | Step 2: figures and validation tables; rendered to HTML (viewer) and .docx (download) |
| `template2.docx` | *(optional)* Word reference template used by the .docx download if present |

All files go in one folder. Run locally with `shiny::runApp()` from that
folder, or publish the folder to Posit Connect (include all files in the
publish bundle).

## How it works

1. User uploads a template (`.xlsx`, `.xls`, or `.xlsm` — org B `.xlsm`
   files are copied to `.xlsx` automatically, no manual renaming).
2. The "Check upload" tab lists the sheet names so the user can confirm
   the right template, and shows the merged-cells reminder for option 1.
3. "Generate report" renders `data-handling.Rmd` then `analysis.Rmd` in
   **one shared R environment** (replicating the original interactive
   workflow — required because, for type 2, `analysis.Rmd`'s validation
   step 4 uses `all.dat2.`, which is created by `data-handling.Rmd` but
   never saved to `dat.RData`).
4. The HTML report displays in the "Report" tab (self-contained HTML in
   an iframe, served via `addResourcePath`). Each run gets a fresh
   working directory and a timestamped filename (prevents stale
   `dat.RData` and browser caching).
5. The download button offers the on-screen report as HTML (direct copy)
   or Word (re-renders `analysis.Rmd` only, with the stored environment,
   using the Rmd's `word_document` format; falls back to default Word
   styling if `template2.docx` is absent).

## App inputs → Rmd params

| App input | Param | Used in |
|---|---|---|
| Uploaded file | `xlsx_path` | `data-handling.Rmd` (placed at both `fnames` indices since `read_opt1` uses index 1, `read_opt2` index 2) |
| Template type radio (1 = quarterly, 2 = monthly) | `type` | both Rmds |
| *(derived, no prompt)* org name | `hco_name` | internal logic only — see Anonymity |

## Anonymity

There is no HCO prompt and reports carry **no organization label**: figure
titles have no org suffix, and the org column shown in facet strips and
validation tables is the neutral constant "HCO". Filenames contain only a
timestamp. Internally the scripts still need a real org name for their
logic, derived from the template type: type 2 = "org B"; type 1 uses
"A" as a stand-in for any quarterly org, which is safe because the
only real-name-dependent rule (the preferred-language fill in
`data-handling.Rmd`) checks membership in the quarterly-org set and so
behaves identically for xx. Verified
by rendering both report types and scanning the HTML: no org names appear
in the output.

## Modifications made to the original Rmds

Every change is marked with a `# MODIFIED for Shiny app` comment.

**data-handling.Rmd**
- `fnames`, `type`, and the hardcoded `hco` values (`"test"`,
  `"org B"`) now come from params.
- **Automatic data ranges (option 1, quarterly template).** Sheets are
  read from the fixed header position (row 6, columns A:L), open-ended
  downward, then **truncated at the first fully blank row**. The
  template's data block is contiguous and a blank row separates it from
  the validation tables below — which reuse the same strata labels and
  "Total", so position (not labels) is the only reliable boundary.
  Verified against the real template: reproduces the original
  `A6:L39` / `A6:L103` ranges exactly. Columns are read as **text** so
  the three sheets always `bind_rows()` with consistent types (the
  pipeline already converts values with `as.numeric()`).
- **Automatic data ranges (option 2, org B monthly template).** Same
  first-blank-row truncation, anchored at header row 2, columns A:G
  (age & sex) / A:F (race, ethnicity). These sheets are clean rectangles
  with nothing below the data, so the truncation is future-proofing.
  Column types are left to readxl's guessing here because the option-2
  pipeline does arithmetic on denom/num directly.
- The final `save()` is guarded (`df.wide.tot <- NULL` when absent),
  since type 2 never creates `df.wide.tot`.

**analysis.Rmd**
- `type` and `hco.name` come from params (previously hardcoded).
- `hco_labels` lookup falls back to the raw HCO name via
  `dplyr::coalesce()`.
- Displayed org labels are neutralized after loading the data (`hco`
  column set to "HCO"; figure titles drop the org suffix) — see Anonymity.

**Both Rmds** have a commented "INTERACTIVE USE" block where the old
hardcoded values lived — uncomment one line to run chunks in the RStudio
console outside the app (params otherwise take the YAML defaults:
type 1, A, test.xlsx).

## Assumptions / known limitations

- **Option 1 template:** header row stays at row 6, layout A:L, no blank
  rows *inside* the data block (the template's own "Counts exist for all
  cells" check enforces completeness). If a future template version
  moves the header row, edit `opt1_range` (one line).
- **Option 1, language section:** the merged-cells requirement in the
  'Data Entry race, ethn, & lang' sheet (rows 8–31, Measure 1) still
  applies before upload — the app shows a reminder.
- **Behavioral note:** with real HCO names flowing into `hco` (instead
  of the old `"test"`), the rule filling `type = "preferred language"`
  for Measure 1 language rows in `all.dat` now activates for
  HCOs (it could never fire before).
  Spot-check Measure 1 language figures against a previous manual run.
- **B template** has a "Data Entry preferred language" sheet (all
  zeros at time of writing) that the pipeline does not read, consistent
  with the note that org B has no language data. Small change to add
  if it becomes populated.
- The validation step 4 table for type 2 sets 21 fixed header labels;
  if a submission's surviving year/month combinations differ, this is a
  spot to revisit.

## Packages

shiny, rmarkdown, readxl (with cellranger), plus the Rmds' libraries:
here, gt, gtsummary, tidyverse, kableExtra, flextable, legendry,
patchwork. Pandoc is required for rendering (bundled with RStudio and
with Posit Connect). Note `legendry` is fairly new and needs a recent
ggplot2 — the most likely first-deploy hiccup on Connect if the server's
package repository is frozen to an older snapshot.

## Deployment (Posit Connect)

1. Get a publisher account; add the server under RStudio → Tools →
   Global Options → Publishing.
2. Open `app.R` → Publish button → make sure **all** files are checked
   (`app.R`, both Rmds, `template2.docx` if used).
3. On the Connect dashboard: restrict Access to specific users/groups,
   set a vanity URL, and raise "Max connection time" if renders are slow.
4. **After replacing any file, restart/republish the app** — a running
   session can hold stale copies (this caused one "still doesn't work"
   during development).

## Troubleshooting

- Render errors appear as a red notification in the app **and** print
  the full error (including knitr's `Quitting from lines X-Y [chunk]`
  line identifying the failing chunk) to the R console / Connect logs.
- `complete.cases(): invalid 'type'` style errors with strange strata
  values (e.g., checklist text) mean non-data rows leaked into the read
  — check that the data block in the uploaded file is contiguous and
  separated from anything below it by a blank row.
- If a sheet name in a submission differs from the template, the read
  fails with a "Sheet not found" style error — compare the "Check
  upload" tab's sheet list against the expected names.
