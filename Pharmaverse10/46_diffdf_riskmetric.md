# Lesson 46 — `{diffdf}` and `{riskmetric}`: Dual Programming and Package Risk

**Module**: 10 — Traceability, validation, and tooling
**Estimated length**: ~20 min spoken
**Prerequisites**: Lesson 45 (logrx); Lessons 14-19 (admiral)

---

## Learning objectives

By the end of this lesson, you will be able to:

1. Explain dual programming and why pharma uses it for QC
2. Use `diffdf::diffdf()` to compare two data frames and identify discrepancies
3. Interpret diffdf output: missing variables, extra variables, value differences, attribute differences
4. Use `riskmetric` to assess R packages for regulated use
5. Generate package risk assessment reports with documented scoring criteria
6. Combine diffdf + logrx + riskmetric for a complete QC/validation toolkit

---

## 1. Dual programming — the pharma QC standard

Pharma's standard quality control approach for clinical programming is **dual programming**:

1. **Primary programmer** writes the analysis code, produces the output (ADaM dataset, TLG table)
2. **QC programmer** writes independent code targeting the same output, blind to the primary's code
3. **Comparison step**: the two outputs are compared; any discrepancies investigated and resolved

The rationale: if two programmers independently produce the same result, the probability of both making the same mistake is low. Discrepancies surface real issues — bugs in either implementation, ambiguities in the spec, or genuine analytical decisions worth debating.

For SAS programs, comparison has historically used `PROC COMPARE` — a built-in procedure that produces a structured comparison report. For R, the equivalent is `{diffdf}`.

## 2. `{diffdf}` — dataset comparison for R

`{diffdf}` is a pharmaverse package (originally GSK, broader contributors now) that compares two data frames and produces a structured discrepancy report.

```r
install.packages("diffdf")
library(diffdf)
```

Simple usage:

```r
df_a <- haven::read_xpt("primary/adsl.xpt")
df_b <- haven::read_xpt("qc/adsl.xpt")

result <- diffdf(df_a, df_b, keys = c("STUDYID", "USUBJID"))
print(result)
```

The output is a structured comparison: missing variables, extra variables, row-level value differences, type/length attribute differences. If `result` is empty, the two datasets match exactly.

For typical use, the comparison succeeds (datasets match), giving QC clean sign-off in seconds. For mismatches, the output guides investigation.

## 3. The diffdf comparison categories

A `diffdf` report has structured sections:

| Section | What it shows |
|---|---|
| **Variables not in BASE** | Variables in `df_b` (QC) but not `df_a` (primary) |
| **Variables not in COMPARE** | Variables in `df_a` (primary) but not `df_b` (QC) |
| **Class differences** | Same variable name, different R types between datasets |
| **Attribute differences** | Same variable, different attributes (labels, lengths, formats) |
| **Differences in row data** | Same variable, different values per (row × column) |
| **Rows in BASE not in COMPARE** | Subjects/keys in `df_a` but not `df_b` |
| **Rows in COMPARE not in BASE** | Subjects/keys in `df_b` but not `df_a` |

Each section is generated only if it has content; a clean comparison has all sections empty.

For each "Differences in row data" entry, diffdf shows:

- The variable name
- The keys (subject identifier) of the affected row
- The base value (primary) and compare value (QC)

This pinpoints the exact subjects/variables where discrepancies exist. Investigation becomes targeted: read the spec, check upstream data, identify the cause.

## 4. The complete diffdf API

```r
diffdf(
  base,                              # primary dataset
  compare,                           # QC dataset
  keys = NULL,                       # join keys (vector of column names)
  suppress_warnings = FALSE,         # suppress warnings about issues
  strict_numeric = TRUE,             # exact numeric comparison vs. tolerance
  strict_factor = TRUE,              # factor levels must match exactly
  tolerance = sqrt(.Machine$double.eps),  # numeric tolerance
  scale = NULL,                      # absolute vs relative tolerance
  file = NULL                        # write report to file
)
```

Key arguments:

- **`keys`**: critical — without keys, diffdf can't align rows for comparison. For ADSL it's `USUBJID`; for BDS datasets it's typically `USUBJID + PARAMCD + AVISITN`.
- **`tolerance`**: for numeric comparisons. Default is machine precision; relaxed for floating-point comparisons that shouldn't fail on rounding (e.g., comparing 75.2000000001 to 75.2).
- **`file`**: writes a human-readable report file. Useful for archiving QC sign-off.

Returns a `diffdf` object. Print it for summary; access components programmatically for automated QC checks.

## 5. Numeric tolerance: when exact comparison hurts

R's floating-point arithmetic isn't always reproducible across operations. The same computation done two different ways may produce 75.20000000 and 75.19999999 — exactly equal mathematically but not bit-identical.

For QC, you typically want tolerance:

```r
diffdf(
  primary, qc,
  keys = "USUBJID",
  strict_numeric = FALSE,
  tolerance = 1e-6                   # accept differences below 1 millionth
)
```

A `tolerance = 1e-6` allows tiny floating-point variations to not flag as differences. For most clinical analyses, this is appropriate — the spec doesn't specify 12-digit precision; small numerical artifacts shouldn't fail QC.

For variables where exactness matters (e.g., dates encoded as integers), keep `strict_numeric = TRUE`.

## 6. Beyond exact comparison: `compare()` family

For more flexible comparison, `compare()` from base R or `dplyr::all_equal()` are alternatives. But diffdf is **pharma-specific**:

- Captures CDISC variable attributes (labels, lengths, formats) — not just values
- Handles factor variables with full level comparison
- Output format is designed for QC sign-off documents

For pharma use, diffdf is the right tool. base R's `compare()` is too thin; `all_equal` is too narrow.

## 7. A realistic dual programming workflow

```r
# Primary programmer's output
library(admiral)
adsl_primary <- pharmaverseadam::adsl |>
  filter(SAFFL == "Y")

# QC programmer's independent output
adsl_qc <- haven::read_xpt("data/dm.xpt") |>
  # ... QC programmer's own derivations ...
  derive_var_treatment_start() |>
  filter(!is.na(TRTSDT))

# Compare
result <- diffdf(
  adsl_primary,
  adsl_qc,
  keys = c("STUDYID", "USUBJID"),
  strict_numeric = FALSE,
  tolerance = 1e-6
)

# Save QC sign-off
diffdf(adsl_primary, adsl_qc, ..., file = "qc/adsl_diff.txt")

# Programmatic check for CI
stopifnot(length(result$VarsInBaseOnly) == 0)
stopifnot(length(result$ValDiffs) == 0)
```

For an entire ADaM set, loop:

```r
for (name in c("ADSL", "ADAE", "ADLB", "ADTTE")) {
  primary <- haven::read_xpt(paste0("primary/", tolower(name), ".xpt"))
  qc <- haven::read_xpt(paste0("qc/", tolower(name), ".xpt"))
  
  result <- diffdf(
    primary, qc,
    keys = if (name == "ADSL") "USUBJID" else c("USUBJID", "PARAMCD", "AVISITN"),
    tolerance = 1e-6,
    file = paste0("qc/", tolower(name), "_diff.txt")
  )
  
  if (length(result$ValDiffs) > 0) {
    message("Discrepancies found in ", name)
  } else {
    message(name, ": match")
  }
}
```

This produces one diff report per ADaM. Programs with no discrepancies get sign-off; programs with diffs get investigation.

## 8. Common diffdf findings and resolutions

### "Attribute differences" on labels
Two programmers used different labels for the same variable.
**Resolution**: align with spec (metacore source of truth).

### "Class differences" — character vs factor
One produced factor, the other character.
**Resolution**: both should follow spec; typically character is preferred unless the spec specifically requires factor.

### "Differences in row data" on a single variable
Genuine analytical difference.
**Resolution**: investigate the derivation; typically uncovers a bug in one implementation or a spec ambiguity worth clarifying.

### "Rows in BASE not in COMPARE"
Subject filtering differs.
**Resolution**: check population filters (SAFFL vs ITTFL vs custom flags).

### Many tiny floating-point differences
Calculation order matters.
**Resolution**: increase tolerance; document the tolerance threshold used.

In practice, ~80% of diffs are spec ambiguities resolved by aligning the two programs. ~15% are genuine bugs caught by the QC process. ~5% are floating-point noise resolved by tolerance.

## 9. `{riskmetric}` — assessing R package risk

Now switching topics: when adopting R for regulated use, your QA/Compliance team asks "is this package safe to use?" `{riskmetric}` answers that question programmatically.

Origin: developed by the **R Validation Hub** — a cross-pharma effort to systematize R package validation. Maintained by the R Consortium. Released to CRAN ~2020; current version 0.x as of mid-2026.

```r
install.packages("riskmetric")
library(riskmetric)
library(dplyr)
```

## 10. The risk assessment model

`{riskmetric}` evaluates packages on multiple **risk dimensions**:

| Dimension | What it measures |
|---|---|
| **`has_news`** | Does the package have a NEWS / NEWS.md file? |
| **`has_vignettes`** | Number of vignettes |
| **`has_website`** | Does the package have a website? |
| **`bugs_status`** | Open bugs as a fraction of total |
| **`license`** | License type (permissive vs restrictive) |
| **`dependencies`** | Number and type of dependencies |
| **`covr_coverage`** | Test coverage percentage |
| **`size_codebase`** | Lines of R code |
| **`reverse_dependencies`** | How many other packages depend on this one |
| **`downloads_1yr`** | CRAN downloads in last year (popularity) |
| **`released`** | Time since first release |
| **`updated`** | Time since last update |

Each dimension produces a numeric score (typically 0-1, where lower = lower risk). The composite is a single risk score per package.

The methodology is documented in the R Validation Hub's framework. Sponsors can use these scores to support an internal "approved packages" decision — high-risk packages need additional review.

## 11. The minimum-viable risk assessment

```r
library(riskmetric)
library(dplyr)

# Assess a single package
package <- pkg_ref("admiral")
metrics <- pkg_assess(package)
score <- pkg_score(metrics)

print(score)
# A tibble: 1 × 13
#   package overall_risk has_news has_vignettes ...
#   admiral 0.18         0.0      0.0           ...
```

`pkg_ref()` looks up a package on CRAN; `pkg_assess()` computes all metrics; `pkg_score()` aggregates into an overall score.

For a list of packages (your study's dependencies):

```r
study_packages <- c("admiral", "metacore", "metatools", "xportr",
                    "cards", "gtsummary", "dplyr", "haven")

results <- tibble(package = study_packages) |>
  mutate(
    ref = lapply(package, pkg_ref),
    assessment = lapply(ref, pkg_assess),
    score = lapply(assessment, pkg_score)
  ) |>
  tidyr::unnest_wider(score)

results |>
  select(package, overall_risk, has_news, has_vignettes, dependencies, downloads_1yr)
```

The result: a tibble showing risk scores for every package in your study. Sponsors typically generate this once at study start, archive it, and re-generate at study end or major releases.

## 12. Interpreting risk scores

A risk score is a **decision support tool**, not a yes/no answer. Pharma teams typically:

- **Score < 0.3**: low risk, standard validation paperwork
- **Score 0.3 - 0.6**: moderate risk, additional review of test coverage and usage patterns
- **Score > 0.6**: high risk, deeper review (or substitute a lower-risk package if possible)

For core pharmaverse packages (admiral, metacore, xportr, cards):

- Risk scores are typically low — frequent releases, good test coverage, broad adoption, multiple sponsors involved
- These are de facto "approved" across the industry

For non-pharmaverse packages (e.g., a single-author package with no tests):

- May score higher
- Substitution to a pharmaverse equivalent is often possible
- Otherwise, internal validation paperwork is needed

The R Validation Hub maintains [https://www.pharmar.org/](https://www.pharmar.org/) with risk assessments for popular packages — useful starting point.

## 13. Risk assessment as part of pipeline setup

A typical pharma project includes a risk assessment as part of project initialization:

```r
# risk_assessment.R
library(riskmetric)
library(dplyr)
library(writexl)

# Identify all dependencies (from renv.lock)
lockfile <- jsonlite::read_json("renv.lock")
packages <- names(lockfile$Packages)

# Assess
results <- tibble(package = packages) |>
  mutate(
    ref = lapply(package, pkg_ref),
    score = lapply(lapply(ref, pkg_assess), pkg_score)
  ) |>
  tidyr::unnest_wider(score)

# Save report
write_xlsx(results, "qc/package_risk_assessment.xlsx")

# Highlight high-risk packages
high_risk <- results |> filter(overall_risk > 0.6)
if (nrow(high_risk) > 0) {
  message("HIGH RISK PACKAGES:")
  print(high_risk |> select(package, overall_risk))
}
```

Run once at project start; archive the report; re-run at project close to verify nothing changed.

For CI/CD pipelines, the risk assessment can be automated to fail the build if any package exceeds the sponsor's threshold.

## 14. Pharma R Adoption framework integration

`{riskmetric}` is part of a broader R Validation Hub toolkit:

- **`{riskmetric}`**: the scoring engine
- **`{riskassessment}`**: a Shiny app on top of riskmetric for team-based review
- **R Validation Hub website**: framework documentation, FAQ, validation patterns
- **Pharma R Adoption book**: a community-maintained guide

For sponsors building formal R validation programs, the R Validation Hub framework is the reference. It's the pharma equivalent of CSA-style risk-based validation.

## 15. Combining diffdf + logrx + riskmetric — the QC toolkit

These three packages together form a complete validation toolkit:

```
Package risk assessed once       ← riskmetric (project setup)
       ↓
Each script runs with logging    ← logrx (every execution)
       ↓
Output compared to QC programmer ← diffdf (dual programming sign-off)
       ↓
Archive: logs + diff reports + risk assessment + outputs
```

For each ADaM build:

1. **Pre-execution**: confirm package risk assessment is current
2. **Execution**: `axecute("ad_adsl.R")` produces XPT + log
3. **QC**: independent QC programmer's run produces second XPT + log
4. **Comparison**: `diffdf` compares primary vs QC, produces report
5. **Sign-off**: archive all artifacts (XPTs, logs, diff report, risk assessment)

For an entire submission, multiply by ~10-20 ADaMs and ~50 TLGs. The pattern remains the same; tooling automates the repetition.

This is **the** pharma R production pattern circa 2026. Tooling matures; the workflow stabilizes.

## 16. Validation strategies — packages vs scripts vs outputs

A useful distinction:

- **Package-level validation**: riskmetric scores packages; vendor (CRAN, R-universe) provides packages; sponsor accepts risk
- **Script-level validation**: programmer writes script; QC programmer writes independent version; diffdf compares
- **Output-level validation**: rendered outputs (RTFs, ARDs) compared to spec; final approval

Each layer catches different issues. Together they provide defense-in-depth.

For a number in a CSR table that ultimately influences a regulatory decision:

- **The package** (admiral, cards) is validated via risk assessment
- **The script** producing the ADaM is validated via dual programming
- **The output** (the rendered table) is validated via spec compliance

If any layer fails, the issue is caught before reaching the submission. This is the regulatory-grade R adoption story.

## 17. diffdf for SDTM comparison

For SDTM (not ADaM) work, diffdf works too:

```r
diffdf(
  primary_dm,
  qc_dm,
  keys = "USUBJID"
)
```

SDTM datasets typically have simpler structure than ADaMs; comparison is similarly straightforward. The pattern (primary + QC + diff) applies the same way.

For sponsors using `{sdtm.oak}` (Module 2) with admiral-style metadata workflows, the QC cycle works identically: dual programming of the mapping, diffdf comparison, sign-off.

## 18. Limitations and edge cases

### Cross-dataset relationships
diffdf compares one dataset to one dataset. Cross-dataset integrity (e.g., every USUBJID in ADAE exists in ADSL) needs separate checks — typically Pinnacle 21 or sponsor-specific scripts.

### Order-dependent differences
If two datasets have the same content but different row ordering, diffdf may report them as different. Ensure both datasets are sorted by the keys before comparison (or pass keys to align).

### Encoding issues
Character encoding differences (UTF-8 vs Latin-1) can cause false discrepancies. Standardize encoding upstream.

### riskmetric vs sponsor policy
Risk scores are inputs to policy, not policy itself. A package may score "moderate risk" but be accepted by sponsor policy based on the broader context (years of pharma use, multi-sponsor maintenance, etc.). riskmetric informs; humans decide.

## 19. Maintainers and direction

- **`{diffdf}`**: pharmaverse-aligned; broader contributor base; mature and stable
- **`{riskmetric}`**: R Validation Hub / R Consortium; active development; expanding metrics

Strategic direction:

- More CDISC-aware comparison features (e.g., understand SUPP-- relationships)
- Tighter integration with Pinnacle 21 outputs
- riskmetric expansion to assess more package facets
- Better Shiny app (riskassessment) for team-based review

For pharma teams investing in R QC infrastructure, both packages will continue evolving in alignment with industry needs.

## 20. Key takeaways

- **Dual programming** is pharma's standard QC: two independent programmers produce same output; differences investigated
- **`{diffdf}`** compares two data frames with structured discrepancy reporting (PROC COMPARE equivalent for R)
- Comparison categories: variables, classes, attributes, row values, missing keys
- Tolerance allows floating-point fuzz; `strict_numeric = FALSE` is typical for clinical data
- **`{riskmetric}`** assesses R package risk for regulated use
- Risk dimensions: documentation, dependencies, coverage, popularity, maintenance frequency
- Risk scores inform sponsor decisions but don't dictate them
- Combined with logrx (Lesson 45), the three packages form a complete QC/validation toolkit
- Validation strategies layer: package risk + script comparison + output spec compliance

## 21. What's next

**Module 10 is complete.** With logrx (Lesson 45), diffdf, and riskmetric, you have the complete traceability and validation toolkit alongside the production tools.

**The capstone (Lessons 47-48)** ties everything together. Lesson 47 walks through the **data pipeline** for a synthetic oncology study — raw EDC → SDTM → ADaM. Lesson 48 walks through the **deliverables** — ARDs → tables → teal app → XPT submission package. Both lessons use the actual pharmaverse test data so you can execute them end-to-end.

This is where the curriculum comes together. Every concept from Modules 0-10 appears in code form, integrated into a cohesive whole.

---

## Self-check questions

1. Explain dual programming in your own words.
2. What does `diffdf(df_a, df_b, keys = "USUBJID")` produce?
3. When would you set `strict_numeric = FALSE`?
4. List four risk dimensions that `{riskmetric}` evaluates.
5. How does `{riskmetric}` differ from sponsor-internal package approval?
6. How do logrx + diffdf + riskmetric combine to form a complete QC toolkit?

## Glossary

- **Dual programming** — Pharma QC: two independent programmers produce the same output; comparison surfaces issues
- **`{diffdf}`** — R package for comparing data frames; PROC COMPARE analog
- **`diffdf()`** — Main comparison function
- **`keys`** — Variables identifying rows for alignment in comparison
- **`tolerance`** — Numeric difference threshold below which values are considered equal
- **`strict_numeric`** — TRUE for exact comparison; FALSE allows tolerance-based fuzzing
- **`{riskmetric}`** — R package for assessing R package risk for regulated use
- **`pkg_ref(name)`** — Reference a CRAN package for assessment
- **`pkg_assess(ref)`** — Compute risk metrics for a package
- **`pkg_score(assessment)`** — Aggregate to a risk score
- **R Validation Hub** — R Consortium effort systematizing R package validation
- **R Validation Framework** — Documented methodology underlying riskmetric
- **`{riskassessment}`** — Shiny app on top of riskmetric for team-based review
- **CSA / risk-based validation** — Computer Software Assurance; the FDA's modern guidance favoring risk-based approaches
- **Defense-in-depth validation** — Layered validation: packages + scripts + outputs each checked
