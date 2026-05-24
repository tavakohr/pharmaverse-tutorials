# Lesson 26 — `{cards}` Part 2: Building Clinical ARDs

**Module**: 6 — TLG: the Cardinal-future stack
**Estimated length**: ~22 min spoken
**Prerequisites**: Lesson 25 (cards Part 1)

---

## Learning objectives

By the end of this lesson, you will be able to:

1. Build a complete demographics ARD with continuous and categorical summaries
2. Build an AE incidence ARD using `ard_hierarchical()` with proper denominators
3. Build a lab change-from-baseline ARD with by-visit summaries
4. Apply `ard_stack()` with `.by`, `.overall`, and `.total_n` arguments for typical clinical layouts
5. Handle missing categories explicitly using `denominator` and `everything()`
6. Use cards' tidying utilities (`shuffle_ard()`, `bind_ard()`) to prepare ARDs for display

---

## 1. Setup

```r
library(cards)
library(dplyr)
library(pharmaverseadam)

adsl <- pharmaverseadam::adsl |> filter(SAFFL == "Y")
adae <- pharmaverseadam::adae
adlb <- pharmaverseadam::adlb |> filter(SAFFL == "Y")
adtte <- pharmaverseadam::adtte
```

We'll build four canonical ARDs against these datasets, then connect them to display layers in later lessons.

## 2. Demographics ARD

The standard demographics table has continuous variables (Age, BMI, Height, Weight) summarized as N/Mean/SD/Median/Min/Max and categorical variables (Age Group, Sex, Race, Ethnicity) summarized as n (%). Columns are treatment arms plus an Overall column with a Big-N header per arm.

```r
demog_ard <- ard_stack(
  adsl,
  ard_continuous(
    variables = c(AGE, BMIBL, WEIGHTBL, HEIGHTBL),
    statistic = ~ continuous_summary_fns(
      c("N", "mean", "sd", "median", "p25", "p75", "min", "max")
    )
  ),
  ard_categorical(
    variables = c(AGEGR1, SEX, RACE, ETHNIC)
  ),
  .by = TRT01A,
  .overall = TRUE,         # adds a column with all subjects combined
  .total_n = TRUE          # adds Big-N header per arm
)

head(demog_ard, 15)
```

A few comments on the design:

- `.by = TRT01A` splits results by treatment arm; each row gets `group1 = "TRT01A"` and `group1_level` = the arm name
- `.overall = TRUE` adds rows with `group1_level = "Overall"` for the all-subjects column
- `.total_n = TRUE` adds Big-N rows (one per group, the total count) — these become the column header subtitles like "Placebo (N=86)"
- Continuous variables use `continuous_summary_fns()` to limit to the specific stats your SAP requires
- Categorical variables get defaults (n, N, p)

The output ARD has potentially hundreds of rows, but each row is a single computed statistic with all metadata needed to identify it.

## 3. Inspecting the demographics ARD

```r
# Filter to see AGE stats per arm
demog_ard |>
  filter(variable == "AGE") |>
  select(group1_level, stat_name, stat_label, stat)
#   group1_level     stat_name  stat_label  stat
# 1 Placebo          N          N           86.000
# 2 Placebo          mean       Mean        75.209
# 3 Placebo          sd         SD          8.590
# ...
# 9 Xanomeline Low   N          N           84.000
# 10 Xanomeline Low  mean       Mean        74.381
# ...

# Filter to see SEX counts per arm
demog_ard |>
  filter(variable == "SEX" & stat_name %in% c("n", "p")) |>
  select(group1_level, variable_level, stat_name, stat)
```

This is the kind of ad-hoc validation you'd do during programming. The ARD is queryable like any tibble; you can sanity-check individual values before piping into a display.

## 4. AE incidence ARD

The signature safety table: "Adverse Event Incidence by System Organ Class and Preferred Term." Counts of subjects (with percentages) per SOC, with sub-rows per preferred term. The denominator: the safety population per arm.

```r
ae_incidence_ard <- adae |>
  filter(SAFFL == "Y" & TRTEMFL == "Y") |>
  ard_hierarchical(
    by = "ARM",
    variables = c("AEBODSYS", "AEDECOD"),
    denominator = adsl                       # uses ADSL row count per ARM as denominator
  )

head(ae_incidence_ard, 10)
```

A few critical details:

- `filter(SAFFL == "Y" & TRTEMFL == "Y")` restricts to safety-population subjects with treatment-emergent AEs
- `ard_hierarchical()` produces counts and percentages at each level of the hierarchy. Top level: counts per (ARM × SOC). Bottom level: counts per (ARM × SOC × PT).
- `denominator = adsl` says: use ADSL (specifically, subject counts per ARM) as the proportion denominator. Otherwise the denominator would be event-level (wrong for "incidence" = subject-level).

For a "subjects with at least one AE" overall row (the typical first row of an AE table), you'd construct a separate ARD:

```r
ae_overall_ard <- adae |>
  filter(SAFFL == "Y" & TRTEMFL == "Y") |>
  distinct(USUBJID, ARM) |>
  ard_categorical(
    by = "ARM",
    variables = "USUBJID",        # "at least one AE" presence flag
    denominator = adsl
  )
```

Or use the `derive_var_extreme_flag()` pattern earlier in your pipeline (Lesson 17) to add `AOCCFL` and then count `AOCCFL = "Y"` records — typically cleaner.

The two ARDs (overall row + by SOC/PT) can be `bind_ard()`'d together for the full AE table.

## 5. The "missing categories" trap

A subtle pharma-specific issue: what if a treatment arm has zero subjects in a given category? The naive output drops that level entirely — but for safety tables, you want to *show* zeros explicitly ("Placebo: 0 / 86 (0.0%)").

cards handles this when categorical variables are explicitly **factor-typed** with all levels declared:

```r
adsl_with_factors <- adsl |>
  mutate(
    AGEGR1 = factor(AGEGR1, levels = c("<65", "65-80", ">80"))   # all expected levels
  )

ard_categorical(
  adsl_with_factors,
  by = "TRT01A",
  variables = "AGEGR1"
)
```

Now any arm with zero subjects in (say) ">80" gets explicit `n = 0`, `p = 0` rows, not omission. This matters for table consistency — every arm should have every category row.

If you can't declare factors upstream, `denominator` can take a data frame specifying the expected levels, but factor-typing is cleaner.

## 6. Lab change-from-baseline ARD

A typical lab summary: for each parameter (HGB, ALT, etc.), report N, mean, SD, median, min, max of the baseline value, the post-baseline value, and the change-from-baseline (CHG), per visit per arm.

The ADLB structure (long format, one row per visit per parameter) lends itself to this:

```r
adlb_chg_ard <- adlb |>
  filter(PARAMCD %in% c("HGB", "ALT") & !is.na(AVISIT) & ANL01FL == "Y") |>
  ard_stack(
    ard_continuous(
      variables = c(AVAL, CHG),
      statistic = ~ continuous_summary_fns(c("N", "mean", "sd", "median", "min", "max"))
    ),
    .by = c(PARAMCD, AVISIT, TRTA)
  )

adlb_chg_ard |> filter(PARAMCD == "HGB" & AVISIT == "Week 4") |> head()
```

`.by = c(PARAMCD, AVISIT, TRTA)` creates a three-level group split. The result has rows like `group1 = "PARAMCD"`, `group2 = "AVISIT"`, `group3 = "TRTA"` (cards extends to additional group columns as needed).

For each (parameter × visit × arm), you get N/mean/SD/median/min/max of both AVAL and CHG — exactly the data needed for the canonical "lab change from baseline by visit" table.

## 7. Exposure summary ARD

A simple but useful ARD: treatment duration summary from ADSL.

```r
expo_ard <- ard_stack(
  adsl,
  ard_continuous(
    variables = TRTDURD,
    statistic = ~ continuous_summary_fns(c("N", "mean", "sd", "median", "min", "max"))
  ),
  ard_categorical(
    variables = TRTDURD_CAT       # if you've derived a categorical version
  ),
  .by = TRT01A,
  .total_n = TRUE
)
```

For "categorical exposure durations" (the typical "Duration of Treatment by Category" table — < 1 month, 1-3 months, etc.), you'd add a derived `TRTDURD_CAT` in ADSL using admiral or simple `mutate()`, then summarize it categorically.

## 8. Combining ARDs with `bind_ard()`

When you have several pre-built ARDs that go into one display, `bind_ard()` combines them while preserving structure:

```r
final_ard <- bind_ard(demog_ard, ae_incidence_ard, expo_ard)
# Single ARD with all three sets of statistics stacked
```

This is useful when ARDs are built in separate scripts, or when you want to construct a "study-wide ARD" for archival. The `context` column tells you which constructor produced each row, so you can filter as needed.

## 9. Pre-defined summary patterns

cards ships a few helpers to reduce boilerplate for canonical patterns:

```r
# continuous_summary_fns: helper returning a list of summary functions
continuous_summary_fns(c("N", "mean", "sd"))
# Returns a list of named functions

# everything(): tidyselect helper for "all variables"
ard_categorical(
  adsl,
  by = "TRT01A",
  variables = everything()       # all categorical variables
)
```

The `everything()` pattern is dangerous in practice — it computes statistics on every column, which usually generates noise. Prefer explicit variable lists.

## 10. Saving and loading ARDs

ARDs are just tibbles. Standard R serialization works:

```r
saveRDS(demog_ard, "ards/demog_ard.rds")
demog_ard <- readRDS("ards/demog_ard.rds")
```

For CDISC ARS submission, ARDs are typically serialized to JSON or as part of the broader submission package. CDISC publishes the ARS conceptual model; tools to serialize cards ARDs to ARS-JSON are emerging. Stay current with CDISC ARS releases (2025-2027 is when this is solidifying).

## 11. `shuffle_ard()` — preparing for display

cards' default ARD format is fully "long": every statistic is its own row, every group-by variable is in `group1`/`group2`/etc. For display, you typically want a more table-like shape with the group columns pivoted to columns.

`shuffle_ard()` (or the alias `shuffle_card()`) does this pivot:

```r
demog_ard |>
  shuffle_ard()
```

The result moves group columns to be actual columns (e.g., `TRT01A` becomes a column) and keeps statistics as rows. This is the shape `{tfrmt}` expects (Lesson 32).

`{gtsummary}` doesn't typically need `shuffle_ard()` — its `tbl_ard_*()` functions consume the long format directly.

## 12. Putting it together: a real ARD pipeline

A complete script that builds the demographics, AE, and lab ARDs and combines them:

```r
library(cards)
library(dplyr)
library(pharmaverseadam)

# Data
adsl <- pharmaverseadam::adsl |> filter(SAFFL == "Y")
adae <- pharmaverseadam::adae |> filter(SAFFL == "Y")
adlb <- pharmaverseadam::adlb |> filter(SAFFL == "Y" & ANL01FL == "Y")

# Demographics
demog_ard <- ard_stack(
  adsl,
  ard_continuous(
    variables = c(AGE, BMIBL),
    statistic = ~ continuous_summary_fns(c("N", "mean", "sd", "median", "min", "max"))
  ),
  ard_categorical(variables = c(AGEGR1, SEX, RACE)),
  .by = TRT01A,
  .overall = TRUE,
  .total_n = TRUE
)

# AE incidence
ae_ard <- adae |>
  filter(TRTEMFL == "Y") |>
  ard_hierarchical(
    by = "ARM",
    variables = c("AEBODSYS", "AEDECOD"),
    denominator = adsl
  )

# Lab change-from-baseline
lab_ard <- adlb |>
  filter(PARAMCD %in% c("HGB", "ALT")) |>
  ard_stack(
    ard_continuous(
      variables = c(AVAL, CHG),
      statistic = ~ continuous_summary_fns(c("N", "mean", "sd", "median", "min", "max"))
    ),
    .by = c(PARAMCD, AVISIT, TRTA)
  )

# Combine for archival
full_ard <- bind_ard(demog_ard, ae_ard, lab_ard)

# Validate
check_ard_structure(full_ard)
print_ard_conditions(full_ard)

# Save
saveRDS(full_ard, "study_ard.rds")
```

This single script generates the analysis results for an entire CSR's worth of tables. The display layer (gtsummary or tfrmt) takes this ARD and produces the actual tables — covered in the next lessons.

## 13. Validation strategy

For a study going to submission, ARD validation is the bedrock. Approach:

1. **Dual programming of the ARD**: a second programmer independently writes the cards code
2. **Compare ARDs**: use `{diffdf}` (Module 10) or simple `dplyr::anti_join()` to compare
3. **Spot-check the displays**: pull individual values from your ARD and confirm they appear in the displayed table

The key shift from traditional validation: you validate the *numbers* (the ARD) and the *layout* (the display) separately. Most validation effort goes into the ARD, because that's where the analysis decisions live. The display layer is usually a thin transformation.

## 14. Common pitfalls

A few patterns to avoid:

- **Forgetting `denominator`**: AE rates without an explicit ADSL denominator get the wrong N. Always specify when computing incidence.
- **Mixing population filters**: applying `SAFFL == "Y"` to the source data but forgetting it in the denominator can give wrong proportions. Apply consistently.
- **Not factor-typing categorical variables**: missing levels disappear from the ARD; tables show inconsistent rows across arms.
- **Computing post-baseline only**: filtering to `AVISITN > 0` before summarizing change-from-baseline excludes baseline rows that some tables need.

These show up at code review. Build a checklist into your project's QC process.

## 15. Comparing cards to old approaches

If your team is migrating from Tplyr or rtables:

| Old | New |
|---|---|
| `Tplyr::tplyr_table()` + layers + `build()` → wide table | `ard_stack()` → long ARD + gtsummary/tfrmt |
| `rtables::basic_table() %>% analyze(...)` → table object | `ard_*()` → ARD + gtsummary/tfrmt |
| Functions for each table | One ARD per analysis topic, multiple displays per ARD |
| Layout intertwined with computation | Computation and layout separated |

The cards approach has more steps for a single table but pays off when you have many tables sharing data — which is most CSRs.

## 16. Key takeaways

- A complete clinical ARD pipeline produces tidy datasets for demographics, AE incidence, lab change-from-baseline, and exposure — each from a single `ard_stack()` or `ard_*()` call
- `ard_hierarchical()` handles nested categorical tabulations (AE by SOC × PT)
- `denominator` controls the N used for proportion calculations — critical for AE incidence
- Factor-typing categorical variables ensures missing levels appear with zero counts
- `bind_ard()` combines pre-built ARDs; `shuffle_ard()` reshapes for display
- A study-wide ARD becomes the durable artifact; displays derive from it

## 17. What's next

Lesson 27 covers **`{cardx}`** — the cards extension for **regression and survival** ARDs. Where cards covers descriptive statistics (means, counts), cardx handles inferential outputs: t-tests, ANOVA, regression coefficients, hazard ratios from Cox models, Kaplan-Meier estimates. The same ARD structure, but the statistics are model outputs.

---

## Self-check questions

1. What's the difference between `ard_categorical(adae, by = "ARM", variables = "AEDECOD")` and `ard_hierarchical(adae, by = "ARM", variables = c("AESOC", "AEDECOD"))`?
2. Why does `denominator = adsl` matter for AE incidence?
3. Translate to cards: "Compute N, mean, SD, median, min, max of CHG by PARAMCD × AVISIT × TRTA."
4. Why factor-type categorical variables before passing to cards?
5. Given a demographics ARD with `.overall = TRUE`, what does `group1_level == "Overall"` represent?
6. How would you save an ARD for archival, and why is this useful?

## Glossary

- **`ard_stack()`** — Run multiple `ard_*()` constructors in one call
- **`.by`** — The grouping variable(s) for split-by-group statistics
- **`.overall = TRUE`** — Add a column-level for all subjects combined
- **`.total_n = TRUE`** — Add Big-N rows used for column header subtitles
- **`denominator`** — Override the default N for proportion calculations
- **`group1` / `group1_level`** — Standard ARD columns for the first grouping variable
- **`stat_name` / `stat_label`** — Machine and human-readable statistic identifiers
- **`shuffle_ard()` / `shuffle_card()`** — Pivot group columns to wide-table shape for display
- **`bind_ard()`** — Concatenate multiple ARDs
- **`check_ard_structure()`** — Validate that a tibble conforms to ARD structure
- **Big-N** — The total subject count per arm (denominator in proportions)
- **TRTEMFL** — Treatment-Emergent Flag (Lesson 17)
- **PARAMCD** — Parameter Code in BDS ADaMs
