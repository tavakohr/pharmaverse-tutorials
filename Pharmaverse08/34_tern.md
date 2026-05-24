# Lesson 34 — `{tern}`: Standard Clinical Tables on rtables

**Module**: 7 — TLG: the legacy/Roche stack
**Estimated length**: ~22 min spoken
**Prerequisites**: Lesson 33 (rtables)

---

## Learning objectives

By the end of this lesson, you will be able to:

1. Explain `{tern}`'s role as the clinical-specific layer on top of rtables
2. Use `analyze_vars()` for standard continuous-variable summaries
3. Use `count_occurrences()` and `summarize_occurrences()` for AE-style tabulations
4. Use `summarize_ancova()`, `summarize_coxreg()`, `surv_time()` for inferential summaries
5. Apply tern's standardized "subject-level vs event-level" counting conventions
6. Build a typical CSR safety table using tern + rtables idiomatically

---

## 1. The role of tern

`{rtables}` (Lesson 33) is general-purpose — you can use it for any table, not just clinical. `{tern}` adds the **clinical reporting layer**: standard analyses every CSR needs (AE incidence, lab change-from-baseline, demographics, survival), packaged as rtables-compatible functions.

The relationship:

```
                          ┌──────────┐
                          │ rtables  │  general table-layout engine
                          └────┬─────┘
                               │
                       ┌───────┴────────┐
                       │     tern       │  clinical wrappers
                       │ (analyze_vars, │
                       │  count_occurr) │
                       └────────────────┘
```

You still call `basic_table() |> split_cols_by() |> ...`, but the analysis steps use tern's pre-built clinical functions instead of custom `afun`s. Less code, validated analytics, sponsor-consistent output.

`{tern}` is also a Roche NEST package, maintained alongside rtables in the `insightsengineering` organization. Active 2018-present, current version 0.9.x as of mid-2026.

## 2. Installation

```r
install.packages("tern")
library(tern)
library(rtables)    # tern depends on rtables
library(dplyr)
```

## 3. The standard verbs

Where rtables has `analyze()` with custom `afun`, tern provides standard analytic functions:

| Function | What it produces |
|---|---|
| `analyze_vars()` | Standard continuous-variable summaries (N, mean, SD, median, quartiles, min, max) |
| `count_occurrences()` | Subject-level count of categorical values (no double-counting) |
| `summarize_occurrences()` | Like count_occurrences but produces label rows |
| `count_patients_with_event()` | Counts subjects with specific events |
| `count_values()` | Counts of specific values (less subject-aware) |
| `summarize_ancova()` | ANCOVA-based change summaries |
| `summarize_coxreg()` | Cox regression summaries |
| `surv_time()` | Kaplan-Meier median survival summaries |
| `surv_timepoint()` | x-year survival rate summaries |
| `analyze_num_patients()` | Patient counts at each row level (denominators) |
| `count_patients_with_flags()` | Multiple-flag subject counting (any X, any Y, etc.) |
| `summarize_change()` | Change-from-baseline summaries |

These cover the bulk of CSR table content. The naming follows a loose convention: `analyze_*` for row-producing analyses; `count_*` for occurrence-based; `summarize_*` for higher-level summaries.

## 4. Standard continuous summary: `analyze_vars()`

```r
adsl <- ex_adsl |> filter(SAFFL == "Y")

lyt <- basic_table(show_colcounts = TRUE) |>
  split_cols_by("ARM") |>
  add_overall_col(label = "Overall") |>
  analyze_vars(
    vars = c("AGE", "BMRKR1"),
    .stats = c("n", "mean_sd", "median", "range")
  )

build_table(lyt, adsl)
```

The output: continuous variables AGE and BMRKR1 with standard stats (N, Mean (SD), Median, Min - Max) per arm plus Overall. The `.stats` argument specifies which to display; the full list is in `get_stats("analyze_vars_numeric")`.

For different format strings (e.g., specific decimal places):

```r
analyze_vars(
  vars = "AGE",
  .stats = c("n", "mean_sd"),
  .formats = c("n" = "xx", "mean_sd" = "xx.xx (xx.xxx)")
)
```

## 5. Categorical counts: `count_occurrences()`

For AE-style tabulations, the canonical function is `count_occurrences()`:

```r
adae <- ex_adae   # ships with tern

lyt <- basic_table(show_colcounts = TRUE) |>
  split_cols_by("ARM") |>
  split_rows_by("AEBODSYS",
                split_fun = drop_split_levels,
                label_pos = "topleft",
                split_label = "System Organ Class") |>
  summarize_occurrences(
    var = "AEDECOD",
    drop = FALSE
  )

build_table(lyt, adae)
```

The output: rows grouped by SOC, with PT-level counts within each SOC. Each cell is "n (%)" — subjects with the event, percentage of arm subjects.

Critically, `count_occurrences()` is **subject-aware**: if a subject has 5 occurrences of "Headache", they're counted **once** in the Headache row. This matches the FDA safety-table expectation.

For the same task with non-subject-aware counting (e.g., counting events rather than subjects):

```r
count_values(var = "AEDECOD")
```

Less common in CSRs; specific use cases (event-level summaries) call for it.

## 6. Denominator management

The subtle but critical question: what's the denominator for the percentage?

tern's standard for AE tables: the safety-population N per arm. This is controlled by ensuring the data passed to `build_table()` is filtered (`SAFFL == "Y"`) and the column counts reflect arm sizes correctly.

For event tables where some subjects have no events (so they don't appear in ADAE), use the **denom population approach**:

```r
adsl_n <- adsl |> count(ARM, name = "N")

lyt <- basic_table() |>
  split_cols_by("ARM") |>
  add_colcounts() |>     # adds N=xx column headers from the data
  split_rows_by("AEBODSYS") |>
  count_occurrences(var = "AEDECOD",
                    denom = "N_col")   # use column counts as denominator

build_table(lyt, adae)
```

The `denom` argument controls denominator behavior:

- `"n"` — count of non-missing observations in the (row × column) cell (default for some functions)
- `"N_col"` — column total N (typical for AE incidence)
- `"N_row"` — row total N (less common)

Picking the right denom for each table is essential. The CSR table shell tells you which N goes in each percentage.

## 7. Pre-baked safety tables

For canonical safety tables, tern has higher-level functions that assemble standard rtables layouts:

```r
# Subjects with any TEAE, by SOC and PT
lyt <- basic_table(show_colcounts = TRUE) |>
  split_cols_by("ARM") |>
  analyze_num_patients(
    vars = "USUBJID",
    .stats = c("unique", "nonunique"),
    .labels = c(unique = "Subjects with at least one AE",
                nonunique = "Number of AEs")
  ) |>
  split_rows_by("AEBODSYS", split_fun = drop_split_levels) |>
  summarize_num_patients(
    var = "USUBJID",
    .stats = c("unique"),
    .labels = c(unique = "Subjects with at least one AE")
  ) |>
  count_occurrences(
    var = "AEDECOD",
    drop = FALSE
  )

build_table(lyt, adae)
```

This produces the canonical AE table: subjects-with-any-AE row at top, then SOC-level summaries, then PT-level counts within each SOC. The exact structure may vary by sponsor SOP; tern's vignettes show several variations.

## 8. Change-from-baseline (BDS analyses)

For lab/VS change-from-baseline tables:

```r
adlb <- ex_adlb |> filter(PARAMCD == "HGB" & !is.na(AVISIT))

lyt <- basic_table(show_colcounts = TRUE) |>
  split_cols_by("ARM") |>
  split_rows_by("AVISIT", split_fun = drop_split_levels) |>
  analyze_vars(
    vars = "AVAL",
    .stats = c("n", "mean_sd", "median", "range")
  ) |>
  analyze_vars(
    vars = "CHG",
    .stats = c("n", "mean_sd", "median", "range")
  )

build_table(lyt, adlb)
```

Two analyses per visit per arm: AVAL summaries and CHG summaries. tern handles the missing-data conventions (only non-missing AVAL counted).

For ANCOVA-based mean change summaries (treating baseline as a covariate):

```r
lyt <- basic_table(show_colcounts = TRUE) |>
  split_cols_by("ARM", ref_group = "B: Placebo") |>
  split_rows_by("AVISIT", split_fun = drop_split_levels) |>
  summarize_ancova(
    vars = "AVAL",
    variables = list(
      arm = "ARM",
      covariates = c("BASE")
    ),
    conf_level = 0.95
  )

build_table(lyt, adlb)
```

The output: per visit, LS Mean and difference-vs-reference for each non-reference arm, with 95% CI and p-value. The `ref_group` argument tells rtables which arm is the reference for the difference computation.

## 9. Survival summaries: `surv_time()` and `surv_timepoint()`

```r
adtte <- ex_adtte |> filter(PARAMCD == "OS")

# K-M median with 95% CI
lyt <- basic_table(show_colcounts = TRUE) |>
  split_cols_by("ARM", ref_group = "B: Placebo") |>
  add_colcounts() |>
  surv_time(
    vars = "AVAL",
    var_labels = "Survival Time (Months)",
    is_event = "is_event"        # is_event must exist in data; 1 = event, 0 = censor
  )

build_table(lyt, adtte)
```

Note: `surv_time()` expects an `is_event` flag with `1 = event`. ADTTE's CDISC convention is `CNSR = 1` for censor. Build the flag before calling:

```r
adtte <- adtte |> mutate(is_event = 1 - CNSR)
```

For x-year survival rates:

```r
lyt <- basic_table(show_colcounts = TRUE) |>
  split_cols_by("ARM") |>
  surv_timepoint(
    vars = "AVAL",
    is_event = "is_event",
    time_point = c(6, 12)       # 6 months and 12 months
  )

build_table(lyt, adtte)
```

The output: at each time point, % surviving per arm with CI.

For Cox HR:

```r
lyt <- basic_table(show_colcounts = TRUE) |>
  split_cols_by("ARM", ref_group = "B: Placebo") |>
  summarize_coxreg(
    variables = list(
      time = "AVAL",
      event = "is_event",
      arm = "ARM",
      covariates = c("AGE", "SEX")
    )
  )

build_table(lyt, adtte)
```

Cox regression with HR, CI, and p-value per non-reference arm, adjusting for age and sex. Same statistical engine as `cardx::ard_regression(coxph(...))` from Lesson 27, but presented as rtables output.

## 10. Format strings

tern uses rtables' format mini-language: `"xx.xx"`, `"xx.x (xx.x)"`, `"xx.xx - xx.xx"`, etc. To override defaults:

```r
analyze_vars(
  vars = "AGE",
  .stats = c("n", "mean_sd", "median"),
  .formats = c(
    "n" = "xx",
    "mean_sd" = "xx.x (xx.xx)",
    "median" = "xx.x"
  )
)
```

The named character vector maps statistic-names to format strings. The `n` stat is integer; `mean_sd` is paired (M (SD)); `median` is one decimal.

## 11. The tern + rtables typical script

A complete CSR-style table script using tern:

```r
library(tern)
library(rtables)
library(dplyr)

# Data
adsl <- ex_adsl |> filter(SAFFL == "Y")
adae <- ex_adae

# Demographics
demog_lyt <- basic_table(
  title = "Table 14.2.1: Demographic and Baseline Characteristics",
  subtitles = "Safety Population",
  main_footer = "Continuous: N, Mean (SD), Median, Min-Max. Categorical: n (%)."
) |>
  split_cols_by("ARM") |>
  add_overall_col(label = "Overall") |>
  add_colcounts() |>
  analyze_vars(
    vars = c("AGE", "BMRKR1"),
    .stats = c("n", "mean_sd", "median", "range")
  ) |>
  count_occurrences(vars = "SEX") |>
  count_occurrences(vars = "RACE")

demog_tbl <- build_table(demog_lyt, adsl)

# AE incidence
ae_lyt <- basic_table(
  title = "Table 14.4.1: Adverse Events by SOC and Preferred Term",
  subtitles = "Safety Population",
  show_colcounts = TRUE
) |>
  split_cols_by("ARM") |>
  add_colcounts() |>
  split_rows_by("AEBODSYS",
                split_fun = drop_split_levels,
                label_pos = "topleft",
                split_label = "System Organ Class") |>
  summarize_num_patients(
    var = "USUBJID",
    .stats = c("unique"),
    .labels = c(unique = "Subjects with at least one AE")
  ) |>
  count_occurrences(var = "AEDECOD", drop = FALSE)

ae_tbl <- build_table(ae_lyt, adae |> filter(USUBJID %in% adsl$USUBJID))

# Export both
demog_tbl |>
  tt_to_flextable() |>
  flextable::save_as_rtf("outputs/t_14_2_1.rtf")

ae_tbl |>
  tt_to_flextable() |>
  flextable::save_as_rtf("outputs/t_14_4_1.rtf")
```

This produces two CSR-grade RTF files. The pattern repeats for the rest of a CSR.

## 12. Compared to gtsummary / cardinal

The pattern differences:

| Aspect | tern + rtables | cardinal (gtsummary) |
|---|---|---|
| Code style | Layout-tree (split_cols, split_rows, analyze) | Function composition (tbl_summary → add_p → modify_*) |
| Data flow | Build layout pre-data; apply to data via build_table | Direct: data in, table out |
| ARD reuse | No native ARD; numbers are in the table | Native: cards ARD is the artifact |
| Layout flexibility | Very high (nested splits 3+ levels deep) | Moderate (one level deep cleanly) |
| Standard table coverage | Comprehensive via tern's analyze_* and count_* functions | Comprehensive via cardinal templates |
| Validation maturity | Extensively validated; production-proven for 5+ years | Newer; validation evidence growing |

Both work. Teams at Roche/Novartis/AbbVie use tern primarily. Teams starting fresh or aligned with Cardinal-future may choose gtsummary. Most large teams use both.

## 13. The `{chevron}` orchestration layer

For Roche-style end-to-end TLG generation, the package `{chevron}` builds on top of tern. chevron takes ADaM datasets, applies standardized table templates, and produces a batch of RTFs:

```r
library(chevron)

# Conceptual usage (specific API varies)
result <- run_workflow(
  workflow = "AET01",       # standard AE table template
  data = list(adsl = adsl, adae = adae),
  output_format = "rtf"
)
```

chevron encapsulates the tern + rtables code into one-line invocations. It's analogous to how cardinal templates encapsulate the cards + gtsummary code.

For Roche-style production, chevron's standardized templates are essential — they're what enables a CSR with 50 tables to be regenerated reproducibly.

## 14. When to choose tern

Use tern when:

- Working in a NEST-aligned environment (Roche, Novartis, AbbVie, BI)
- Need maximum control over table layout
- Have existing rtables-based pipelines
- Standard clinical analyses are the bulk of what you do

Skip tern in favor of cardinal/gtsummary when:

- Starting fresh, no NEST dependency
- CDISC ARS alignment is a strategic priority
- Need to share underlying data (ARDs) across multiple displays

## 15. Maintainers and direction

`{tern}` is maintained by Roche's NEST team (Joe Zhu, Davide Garolini, and others). Active development continues — regular releases adding new analyze functions, polishing existing ones, integrating with newer rtables features.

Strategic direction: tern remains the workhorse for Roche-style production while progressively integrating with cards/cardx for ARD-aligned outputs. Long-term, expect tern's analyze functions to optionally produce ARDs alongside the table.

## 16. Key takeaways

- `{tern}` is the clinical-specific layer on top of `{rtables}` — standard analyses packaged as rtables-compatible functions
- Core verbs: `analyze_vars()`, `count_occurrences()`, `summarize_occurrences()`, `summarize_ancova()`, `surv_time()`, `summarize_coxreg()`
- Subject-aware counting (`count_occurrences`) vs event-level counting (`count_values`) — critical distinction for AE tables
- Denominator control: `denom = "N_col"` for AE incidence with column-based denominators
- Survival functions need `is_event = 1 - CNSR` due to ADTTE censoring convention
- `summarize_coxreg()` and `summarize_ancova()` for inferential summaries with reference groups
- `{chevron}` orchestrates tern + rtables for batch CSR generation
- Mature, production-dominant at Roche/Novartis/AbbVie/BI

## 17. What's next

Lesson 35 covers **`{r2rtf}`** — Merck's RTF generation package. Where rtables and tern focus on table computation/layout, r2rtf focuses on **RTF output**: pagination, headers, footnotes, font control. Many pipelines use rtables/tern for the table, then pass the data to r2rtf for the final RTF rendering.

---

## Self-check questions

1. What's the relationship between rtables and tern?
2. Why is `count_occurrences()` preferred over raw counting for AE tables?
3. Translate to tern: "Summarize AGE with N, Mean (SD), Median, Range, by ARM."
4. Why does `surv_time()` need `is_event = 1 - CNSR` rather than CNSR directly?
5. What's the role of `summarize_num_patients()` in an AE table layout?
6. When would you use `{chevron}` instead of writing tern code directly?

## Glossary

- **`analyze_vars()`** — Standard continuous-variable summary (N, Mean, Median, Range)
- **`count_occurrences()`** — Subject-aware count of categorical levels (no double-counting)
- **`summarize_occurrences()`** — Like count_occurrences but with label rows
- **`count_patients_with_event()`** — Subjects with specific events (binary outcome counting)
- **`summarize_ancova()`** — ANCOVA-based change-from-baseline summary
- **`summarize_coxreg()`** — Cox regression summary with HR, CI, p-value
- **`surv_time()`** — K-M median survival summary
- **`surv_timepoint()`** — x-year survival rate summary
- **`analyze_num_patients()`** — Patient counts (denominators) at row level
- **`denom`** — Argument controlling proportion denominator: `n`, `N_col`, `N_row`
- **`{chevron}`** — Higher-level orchestration package on top of tern + rtables
- **NEST** — Roche-led TLG initiative (rtables, tern, chevron, etc.)
- **Subject-aware counting** — Each subject counted once per category regardless of event multiplicity
- **`ref_group`** — rtables argument identifying the reference arm for comparison statistics
