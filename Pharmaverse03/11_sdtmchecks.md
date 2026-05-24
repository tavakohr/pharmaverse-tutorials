# Lesson 11 — `{sdtmchecks}`: Analysis-Focused SDTM Quality Checks

**Module**: 2 — Raw data and SDTM
**Estimated length**: ~20 min spoken
**Prerequisites**: Lessons 07–10

---

## Learning objectives

By the end of this lesson, you will be able to:

1. Position `{sdtmchecks}` relative to Pinnacle 21 — what it covers, what it doesn't
2. Install the package and explore the catalog of checks
3. Run a single check on an SDTM dataset and interpret the output
4. Use `run_all_checks()` to run the full check suite at once
5. Build an Excel report of failed checks for a study team
6. Recognize check priorities and the High/Medium/Low triage convention
7. Contribute new checks or modify existing ones (the package's "crowdsourced" model)

---

## 1. Why a special checks package?

When clinical programmers think "SDTM checks," they usually think Pinnacle 21 (P21). P21 is excellent and necessary — but it's focused on **CDISC conformance**: does your dataset conform to the SDTMIG schema? Are variable lengths right? Are codelists correct? Is the dataset structure valid?

P21 doesn't typically catch things like:

- A subject has 12 records for the same lab test on the same date
- An AE has a start date before the subject's first dose
- A subject has DM data but no exposure records
- VS records exist for a subject after their disposition date of "Death"

These are **analysis-impacting issues**. The dataset might be perfectly P21-clean and still break your downstream analysis. `{sdtmchecks}` is built specifically to find these.

The package has been developed internally at Roche since 2014 — that's a decade of accumulated "we've seen this break studies before, let's automate the check" wisdom. Roche open-sourced it under pharmaverse, and it's now community-extended.

## 2. Installation

```r
install.packages("sdtmchecks")
```

The latest dev version (with new checks not yet on CRAN) is on GitHub:

```r
remotes::install_github("pharmaverse/sdtmchecks")
```

## 3. The check function naming convention

Every check is an R function whose name starts with `check_`. The naming follows a domain-and-issue pattern:

- `check_ae_dup()` — adverse event duplicates
- `check_ae_aestdt_dm_dthdt()` — AE start date after death date
- `check_lb_lbornrlo_lbornrhi()` — lab values where reference ranges are misordered
- `check_dm_usubjid_dup()` — duplicate USUBJID in DM
- `check_ex_dup()` — duplicate exposure records

You can find the full catalog at the [Reference page](https://pharmaverse.github.io/sdtmchecks/reference/index.html) or by listing:

```r
library(sdtmchecks)
ls("package:sdtmchecks")[grep("^check_", ls("package:sdtmchecks"))]
```

As of recent versions, there are 100+ checks across all domains.

## 4. A check's input/output contract

Every check function follows the same pattern:

- **Input**: one or more SDTM datasets (as data frames) named for the domain
- **Output**: a data frame of *offending rows* — if empty, the check passed; if non-empty, those are the issues

Example:

```r
library(sdtmchecks)
library(pharmaversesdtm)
data("ae")

# Run a single check
issues <- check_ae_dup(ae)

# An empty data frame means the check passed
nrow(issues)
issues
```

The returned data frame contains the offending rows with enough context to investigate — typically USUBJID, AESEQ, AETERM, AESTDTC, and similar identifiers.

Some checks need multiple domains:

```r
data("ae")
data("dm")
data("ex")

# Check: AE records with start date before first exposure
issues <- check_ae_aestdtc_after_dm_death(ae = ae, dm = dm)
```

Each check's help page documents its required arguments and the check's intent. Use `?check_ae_dup` to read.

## 5. Running all checks at once

For a full QC pass, use `run_all_checks()`:

```r
all_results <- run_all_checks(
  metads = sdtmchecksmeta,        # the package's check metadata
  priority = c("High", "Medium")  # optional priority filter
)
```

`run_all_checks()` expects your SDTM datasets to be loaded as objects in your global environment with their standard names (`ae`, `dm`, `ex`, `lb`, etc.). This function assumes you have all of your sdtm datasets as objects in your global environment, e.g. ae, dm, ex, etc. It loops through every applicable check function, runs it against the relevant datasets, and returns a structured summary of which checks failed and what they found.

The return value is a list with results per check, suitable for downstream reporting.

## 6. The check metadata: `sdtmchecksmeta`

The package ships a metadata data frame describing every check:

```r
data(sdtmchecksmeta, package = "sdtmchecks")
glimpse(sdtmchecksmeta)
```

Columns include (depending on version):

- `check`: the function name
- `category`: the SDTM domain or area (AE, LB, DM, etc.)
- `priority`: High / Medium / Low
- `description`: what the check looks for
- `xls_title`: how it appears in the Excel report
- `datasets`: which SDTM datasets it needs

This metadata drives `run_all_checks()` and lets you filter, search, or customize which checks run.

## 7. Priority triage

Each check has a priority:

- **High**: issue strongly suggests a data error that would corrupt analysis. Must investigate before analysis.
- **Medium**: issue may or may not be problematic; usually worth investigating but might be expected for the study design.
- **Low**: informational; usually expected variations, but flagging them helps you confirm.

A reasonable workflow:

1. First pass through a clean SDTM batch: run only **High** priority checks
2. Resolve all High issues with the data managers / clinical team
3. Run **Medium** checks; investigate ones not explained by study design
4. Periodically run **Low** as a sanity check

The priority for each check is editable in the metadata, so you can re-classify based on your study's specifics.

## 8. Generating an Excel report

For sharing with non-R-using stakeholders (data managers, clinical operations, biostatistics leadership), `report_to_xlsx()` produces a multi-tab Excel file:

```r
all_results <- run_all_checks(metads = sdtmchecksmeta)

report_to_xlsx(
  res = all_results,
  outfile = "sdtm_qc_report.xlsx"
)
```

The output contains:

- A summary tab listing every check, its priority, and a pass/fail status
- One tab per failed check, with the offending rows

This is the operational reality of using `sdtmchecks`: you produce the Excel report, share it with the study team, and they remediate the issues either in the EDC, in the SDTM derivation, or by adding annotations.

## 9. Writing your own check

Adding a new check is straightforward. The function signature convention:

```r
check_lb_high_count_per_visit <- function(LB) {
  LB |>
    dplyr::group_by(USUBJID, LBTESTCD, VISIT) |>
    dplyr::filter(dplyr::n() > 1) |>
    dplyr::ungroup() |>
    dplyr::arrange(USUBJID, LBTESTCD, VISIT, LBDTC)
}
```

If the check finds issues, it returns rows. If not, it returns an empty data frame. The package's helper conventions handle wrapping it into the broader framework.

To contribute the check upstream:

1. Fork `pharmaverse/sdtmchecks` on GitHub
2. Add the function in `R/`, with roxygen documentation explaining the issue and the expected output
3. Add an entry to `data-raw/sdtmchecksmeta.R` describing the check
4. Open a pull request

The package has been developed internally at Roche since 2014 with a crowdsourced contribution model — Roche actively welcomes external check contributions, and many recent additions come from non-Roche contributors.

## 10. Examples of common high-priority checks

Here are illustrative names to give you a sense of what's covered:

| Check (representative) | What it catches |
|---|---|
| `check_dm_usubjid_dup` | Same USUBJID appearing twice in DM |
| `check_ae_dup` | Duplicate adverse event records (same subject/term/date) |
| `check_ex_dup` | Duplicate exposure records on the same date |
| `check_ae_aestdtc_after_dm_death` | AE start date after the death date (impossible) |
| `check_lb_dup` | Duplicate lab records per subject/test/visit/date |
| `check_dm_armcd_consistency` | ARM and ARMCD inconsistent |
| `check_ae_aedecod` | AEDECOD missing or unmapped |
| `check_lb_lbornrlo_lbornrhi` | Lab reference range low > high |
| `check_vs_dup` | Duplicate vital signs records |

Each is a clear, named, narrow check. You can run any single one in isolation, which makes debugging easy.

## 11. Roche-specific implementation choices

A practical caveat from the package documentation: There may be areas where the checks expect Roche-specific SDTM implementation choices. Proposed additions or modifications should attempt to maintain generalizability for slightly different data standards across companies.

In practice, some checks may flag issues that are intentional for non-Roche studies (e.g., a particular study uses RACEN differently than Roche convention). You'll occasionally need to:

- Read the check's help page to understand its assumption
- Disable a specific check that doesn't apply to your study
- Suggest a generalization to the maintainers via a pull request

Don't blindly accept every flagged issue as a real problem. Read the check, understand what it's looking for, then decide if it's relevant.

## 12. Where `{sdtmchecks}` fits in the QC story

In a full submission-quality QC story:

1. **`{sdtmchecks}`** — analysis-focused checks, while building SDTM (first pass, then iteratively)
2. **Pinnacle 21 Community/Enterprise** — CDISC conformance checks, after SDTM is feature-complete
3. **Study-specific custom checks** — sponsor- or therapeutic-area-specific issues not covered by the above
4. **Final manual review** — eyes on the data, especially for derivation logic

`sdtmchecks` is best in step 1; it gets you to clean data fastest. P21 is mandatory before submission; it covers the conformance angle. They're complementary, not substitutes.

A common question from FAQs: P21 validation checks are for CDISC conformance and quite comprehensive for eSubmission, whereas the sdtmchecks package aims to cover variables impacting analysis. There may be some overlap in checks from these two tools.

**You need both.** Use sdtmchecks during development; use P21 before submission.

## 13. Integration with the workflow

A typical workflow integrating `{sdtmchecks}`:

```r
# After building SDTM (via sdtm.oak or otherwise)
library(sdtmchecks)

# Run all High-priority checks
high_results <- run_all_checks(
  metads = subset(sdtmchecksmeta, priority == "High")
)

# Generate report
report_to_xlsx(high_results, "qc/high_priority.xlsx")

# Iterate: fix issues in SDTM derivation, re-run, until clean
```

Once High passes, expand to Medium. Once Medium is mostly explained, expand to Low. Throughout, the Excel report is what study teams discuss in their data review meetings.

In some companies, `{sdtmchecks}` is run as part of a Shiny app — Roche uses it that way internally — so non-R-using study managers can trigger checks through a UI. The talk Assuring SDTM data quality with the sdtmchecks package mentions current use within Roche/Genentech within a Shiny app.

## 14. Beyond `{sdtmchecks}`: complementary checks packages

A few sibling packages worth knowing:

- **`{datacutr}`** — supports applying a data cut (typically by date) to SDTM, preserving the structure. Useful for interim analyses where you need a clean cut by a snapshot date.
- **`{sasvalidate}` / various sponsor-internal tools** — proprietary equivalents many companies still use

`sdtmchecks` is the canonical open-source choice in pharmaverse today.

## 15. A note on assertion-style checking

Sometimes you want a check to **error** if it fails, not just return a data frame. For example, in a production pipeline, you want the script to stop if SDTM has duplicate AEs — not silently continue.

`{sdtmchecks}` returns data frames; it doesn't error. To convert to assertion style:

```r
issues <- check_ae_dup(ae)
if (nrow(issues) > 0) {
  stop("AE duplicates detected. See:\n",
       paste(capture.output(print(issues)), collapse = "\n"))
}
```

Or wrap in a helper:

```r
stop_if_issues <- function(check_fn, ..., msg = NULL) {
  issues <- check_fn(...)
  if (nrow(issues) > 0) {
    stop(msg %||% sprintf("Check %s failed", deparse(substitute(check_fn))),
         "\n", paste(capture.output(print(head(issues, 20))), collapse = "\n"))
  }
  invisible(issues)
}

stop_if_issues(check_ae_dup, ae = ae)
```

This is a personal-style choice. The package gives you the data; you decide how to react.

## 16. Key takeaways

- `{sdtmchecks}` is for **analysis-impacting issues**; Pinnacle 21 is for **CDISC conformance**
- Use both; they're complementary
- Each check is a function returning a data frame of offending rows (empty = passed)
- `run_all_checks()` runs the full suite; `report_to_xlsx()` makes shareable Excel reports
- Checks have priorities (High/Medium/Low); start with High and work down
- Roche-originated, crowdsourced model; you can extend it for your sponsor or study
- Some checks encode Roche-specific assumptions — read the help page, customize if needed

## 17. What's next

Module 2 is complete. Module 3 covers **metadata-driven programming** with `{metacore}` (the spec object) and `{metatools}` (using the spec to build and validate datasets). These two packages are smaller than admiral or sdtm.oak but they're load-bearing for any project that wants traceability from the spec spreadsheet to the final dataset.

After Module 3, we enter Module 4 — the heart of pharmaverse — with the **admiral** package for ADaM construction. That's where most of the daily work of a clinical R programmer happens.

---

## Self-check questions

1. What's the difference between `{sdtmchecks}` and Pinnacle 21?
2. What does a check function return when the check "passes"?
3. How do you run all checks at once, and what does the function need?
4. What are the three priority levels and how do you choose which to run?
5. How would you contribute a new check to the package?
6. Why might a check flag an issue that's not actually a problem for your study?

## Glossary

- **Conformance check** — A check that verifies adherence to a published standard (SDTMIG, define.xml)
- **Analysis-impacting issue** — A data problem that, while perhaps conformant, would corrupt downstream analysis
- **`run_all_checks()`** — Run every check function in the package against named SDTM datasets
- **`sdtmchecksmeta`** — Package data frame describing each check (function name, priority, datasets needed, description)
- **Priority (High/Medium/Low)** — Each check's severity rating; drives triage order
- **`report_to_xlsx()`** — Generate a multi-tab Excel file from check results, for study-team review
- **P21 / Pinnacle 21** — Industry-standard CDISC conformance checker; complementary to sdtmchecks
- **`{datacutr}`** — Pharmaverse package for applying a data cut to SDTM; sibling of `{sdtmchecks}`
