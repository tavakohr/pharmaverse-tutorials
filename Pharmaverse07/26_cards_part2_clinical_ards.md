# Lesson 26 — `{cards}` Part 2: Full Clinical ARD Pipeline

**Module**: 6 — TLG: the Cardinal-future stack
**Estimated length**: ~35 min spoken
**Prerequisites**: Lesson 25 (cards Part 1)

---

## Learning objectives

By the end of this lesson, you will be able to:

1. Build a complete study-wide ARD covering demographics, AE incidence, labs, vitals, exposure, and disposition
2. Apply the correct population filter and denominator strategy for each table type
3. Handle the "missing zero-count levels" problem with factor typing and denominator data frames
4. Build multi-level grouping ARDs for lab shift tables and subgroup analyses
5. Use the `ard_*()` traceability metadata pattern for ARS-aligned output
6. Construct ARDs for concomitant medications, disposition, and vital signs
7. Understand the validation strategy: dual-program the ARD, not the display
8. Prepare a study-wide ARD package for archival and submission

---

## 1. Setup

```r
library(cards)
library(dplyr)
library(pharmaverseadam)
library(purrr)

# Load and filter ADaMs
adsl   <- pharmaverseadam::adsl
adae   <- pharmaverseadam::adae
adlb   <- pharmaverseadam::adlb
adtte  <- pharmaverseadam::adtte

# Safety population
adsl_saf  <- adsl |> filter(SAFFL == "Y")
adae_saf  <- adae |> filter(SAFFL == "Y")
adlb_saf  <- adlb |> filter(SAFFL == "Y")
```

---

## 2. Demographics ARD — the canonical template

The standard demographics table: continuous variables (AGE, BMI, Weight, Height) and categorical variables (Age Group, Sex, Race, Ethnicity) by treatment arm with an Overall column.

```r
demog_ard <- ard_stack(
  adsl_saf,
  # Continuous variables: N, Mean, SD, Median, Q1, Q3, Min, Max
  ard_continuous(
    variables = c(AGE, BMIBL, WEIGHTBL, HEIGHTBL),
    statistic = ~ continuous_summary_fns(
      c("N", "mean", "sd", "median", "p25", "p75", "min", "max")
    )
  ),
  # Categorical variables: n, N, p per level
  ard_categorical(
    variables = c(AGEGR1, SEX, RACE, ETHNIC)
  ),
  .by      = TRT01A,        # columns by treatment arm
  .overall = TRUE,          # add "Overall" column
  .total_n = TRUE           # add Big-N header rows
)
```

### Validating the demographics ARD

```r
# Structure check
check_ard_structure(demog_ard)

# Condition check (warnings / errors)
print_ard_conditions(demog_ard)

# Spot-check: mean age by arm
demog_ard |>
  filter(variable == "AGE" & stat_name == "mean") |>
  mutate(mean_age = map_dbl(stat, 1)) |>
  select(group1_level, mean_age)
#   group1_level           mean_age
# 1 Placebo                75.209
# 2 Xanomeline Low Dose    74.381
# 3 Xanomeline High Dose   75.667
# 4 Overall                75.087

# Spot-check: Sex frequency (Female, Placebo)
get_ard_statistics(
  demog_ard,
  filter = variable == "SEX" & variable_level == "F" &
           group1_level == "Placebo" & stat_name %in% c("n", "p")
)
# list(n = 53, p = 0.616)  → 53/86 = 61.6% female in placebo
```

### The factor-typing pattern for categorical variables

If any arm has zero subjects in a category level, that level disappears from the ARD. For consistency across all arms, factor-type before building the ARD:

```r
adsl_factored <- adsl_saf |>
  mutate(
    AGEGR1 = factor(AGEGR1, levels = c("<65", "65-80", ">80")),
    SEX    = factor(SEX,    levels = c("F", "M")),
    RACE   = factor(RACE,   levels = c(
      "WHITE", "BLACK OR AFRICAN AMERICAN", "ASIAN",
      "AMERICAN INDIAN OR ALASKA NATIVE", "OTHER"
    )),
    ETHNIC = factor(ETHNIC, levels = c(
      "NOT HISPANIC OR LATINO", "HISPANIC OR LATINO", "NOT REPORTED", "UNKNOWN"
    ))
  )

demog_ard <- ard_stack(
  adsl_factored,
  ard_categorical(variables = c(AGEGR1, SEX, RACE, ETHNIC)),
  .by = TRT01A,
  .overall = TRUE,
  .total_n = TRUE
)
# Now every arm has every level, even if n = 0
```

---

## 3. AE incidence ARD — the safety table

The canonical adverse event table: subjects with at least one TEAE (overall row), then counts by System Organ Class, then by Preferred Term within each SOC.

```r
# Key filters for TEAEs
adae_te <- adae_saf |>
  filter(TRTEMFL == "Y")

# AE incidence by SOC and PT
ae_incidence_ard <- adae_te |>
  ard_hierarchical(
    by       = "ARM",
    variables = c("AEBODSYS", "AEDECOD"),
    denominator = adsl_saf,    # N = safety-pop subjects per arm
    id       = "USUBJID"       # count distinct subjects, not events
  )

# "Subjects with at least one TEAE" — the overall header row
# Method 1: flag approach (preferred)
adae_any_ard <- adae_te |>
  distinct(USUBJID, ARM) |>               # one row per subject with any TEAE
  mutate(any_teae = "Y") |>
  ard_categorical(
    by          = "ARM",
    variables   = "any_teae",
    denominator = adsl_saf
  )

# Combine
ae_full_ard <- bind_ard(adae_any_ard, ae_incidence_ard)
```

### Why `denominator = adsl_saf` is non-negotiable

Without the denominator argument:

```r
# WRONG: N would be the count of TEAE *rows* in adae_te per arm
# (some subjects have multiple AEs → N is inflated → percentages wrong)
ard_hierarchical(adae_te, by = "ARM", variables = c("AEBODSYS", "AEDECOD"))
# stat for N might be 120 for Placebo even though only 86 subjects exist
```

With the denominator:

```r
# CORRECT: N is the safety-population subject count per arm
ard_hierarchical(adae_te, by = "ARM", variables = c("AEBODSYS", "AEDECOD"),
                 denominator = adsl_saf)
# stat for N is 86 for Placebo — the actual population
```

### Variants: serious TEAEs, drug-related TEAEs

```r
# Serious TEAEs
ae_serious_ard <- adae_saf |>
  filter(TRTEMFL == "Y" & AESER == "Y") |>
  ard_hierarchical(
    by          = "ARM",
    variables   = c("AEBODSYS", "AEDECOD"),
    denominator = adsl_saf,
    id          = "USUBJID"
  )

# Drug-related TEAEs
ae_related_ard <- adae_saf |>
  filter(TRTEMFL == "Y" & AEREL %in% c("POSSIBLE", "PROBABLE", "DEFINITE")) |>
  ard_hierarchical(
    by          = "ARM",
    variables   = c("AEBODSYS", "AEDECOD"),
    denominator = adsl_saf,
    id          = "USUBJID"
  )

# Severity grading (CTCAE)
ae_grade_ard <- adae_saf |>
  filter(TRTEMFL == "Y") |>
  mutate(AETOXGR = factor(AETOXGR, levels = c("1", "2", "3", "4", "5"))) |>
  ard_categorical(
    by          = "ARM",
    variables   = "AETOXGR",
    denominator = adsl_saf
  )
```

---

## 4. Lab change-from-baseline ARD

For a "Lab Values by Visit" table: N, mean, SD, median, min, max of AVAL and CHG per PARAMCD × AVISIT × treatment arm.

```r
# Filter to analysis observations
adlb_analysis <- adlb_saf |>
  filter(ANL01FL == "Y" & !is.na(AVISIT)) |>
  filter(PARAMCD %in% c("HGB", "ALT", "AST", "ALK", "BILI", "CREAT",
                         "SODIUM", "POTASSIUM", "CHOL"))

# Build the ARD: 3-level grouping
lab_ard <- ard_stack(
  adlb_analysis,
  ard_continuous(
    variables = c(AVAL, CHG),
    statistic = ~ continuous_summary_fns(c("N", "mean", "sd", "median", "min", "max"))
  ),
  .by = c(PARAMCD, AVISIT, TRTA)
)

# Inspect structure: 3 group columns
names(lab_ard)[startsWith(names(lab_ard), "group")]
# [1] "group1"       "group1_level"  "group2"       "group2_level"
# [5] "group3"       "group3_level"

# Example: mean CHG of ALT at Week 4 across arms
lab_ard |>
  filter(group1_level == "ALT" &  # PARAMCD = ALT
         group2_level == "Week 4" & # AVISIT = Week 4
         variable == "CHG" &
         stat_name == "mean") |>
  mutate(mean_chg = map_dbl(stat, 1)) |>
  select(group3_level, mean_chg)
```

### Lab shift table ARD

For shift tables (normal-to-high, etc.), you need baseline category and post-baseline category:

```r
adlb_shift <- adlb_saf |>
  filter(ANL01FL == "Y" & AVISIT == "End of Treatment") |>
  filter(!is.na(BNRIND) & !is.na(ANRIND)) |>
  mutate(
    BNRIND = factor(BNRIND, levels = c("L", "N", "H")),
    ANRIND = factor(ANRIND, levels = c("L", "N", "H"))
  )

lab_shift_ard <- adlb_shift |>
  ard_categorical(
    by        = c("PARAMCD", "TRTA"),
    variables = "ANRIND",
    # denominator stratified by BNRIND (baseline category):
    # this requires a nested approach
  )

# For a true shift table (baseline × post-baseline):
lab_shift_nested_ard <- adlb_shift |>
  ard_hierarchical(
    by        = c("PARAMCD", "TRTA"),
    variables = c("BNRIND", "ANRIND"),
    denominator = adlb_shift |> distinct(USUBJID, PARAMCD, TRTA)
  )
```

---

## 5. Vital signs ARD

Vital signs follow the same pattern as labs but typically need analysis flags for specific visit windows:

```r
library(pharmaverseadam)  # contains advs

advs <- pharmaverseadam::advs |>
  filter(SAFFL == "Y" & ANL01FL == "Y")

# Build the vital signs ARD
vs_ard <- ard_stack(
  advs |> filter(!is.na(AVISIT)),
  ard_continuous(
    variables = c(AVAL, CHG),
    statistic = ~ continuous_summary_fns(c("N", "mean", "sd", "median", "min", "max"))
  ),
  .by = c(PARAMCD, AVISIT, TRTA)
)

# Worst post-baseline value (maximum AVAL per subject):
advs_worst <- advs |>
  filter(AVISITN > 0) |>
  group_by(USUBJID, PARAMCD, TRTA) |>
  slice_max(AVAL, n = 1, with_ties = FALSE) |>
  ungroup()

vs_worst_ard <- ard_stack(
  advs_worst,
  ard_continuous(
    variables = AVAL,
    statistic = ~ continuous_summary_fns(c("N", "mean", "sd", "min", "max"))
  ),
  .by = c(PARAMCD, TRTA)
)
```

---

## 6. Disposition ARD

Subject disposition (enrolled, treated, completed, discontinued):

```r
# Flag enrolled (all), treated (at least one dose), completed, discontinued
adsl_disp <- adsl |>
  mutate(
    ENROLLED = "Y",
    DCREASFL = if_else(!is.na(DCREASCD), "Y", "N"),
    DCREASCD = factor(
      DCREASCD,
      levels = c("ADVERSE EVENT", "LACK OF EFFICACY", "WITHDREW CONSENT",
                  "LOST TO FOLLOW-UP", "PHYSICIAN DECISION", "OTHER")
    )
  )

# Disposition counts
disp_ard <- ard_stack(
  adsl_disp,
  # Overall: treated / completed / discontinued
  ard_categorical(
    variables = c(SAFFL, EFFFL, DCREASFL),
    statistic = ~ list(n = \(x, ...) sum(x == "Y", na.rm = TRUE),
                       p = \(x, ...) mean(x == "Y", na.rm = TRUE))
  ),
  # Discontinuation reasons
  ard_categorical(
    variables = DCREASCD
  ),
  .by      = TRT01A,
  .total_n = TRUE
)
```

---

## 7. Concomitant medications ARD

```r
# ADCM if available, or similar
# Using a simulated structure as example:
# adcm has CMTRT (medication name), CMCLAS (class), CMSTDY, CMENDY, TRT01A, SAFFL

# adcm <- pharmaverseadam::adcm  # (if available in your version)

# Standard concomitant meds table pattern:
cm_ard <- adcm |>
  filter(SAFFL == "Y" & CMCAT == "CONCOMITANT") |>
  distinct(USUBJID, TRT01A, CMCLAS, CMTRT) |>
  ard_hierarchical(
    by          = "TRT01A",
    variables   = c("CMCLAS", "CMTRT"),
    denominator = adsl_saf,
    id          = "USUBJID"
  )
```

---

## 8. Exposure ARD

Treatment duration and dose intensity:

```r
adex <- pharmaverseadam::adex |> filter(SAFFL == "Y")

# Duration of treatment (from ADSL typically)
expo_ard <- ard_stack(
  adsl_saf,
  ard_continuous(
    variables = TRTDURD,
    statistic = ~ continuous_summary_fns(c("N", "mean", "sd", "median", "min", "max"))
  ),
  .by      = TRT01A,
  .total_n = TRUE
)

# Cumulative dose
adex_dose <- adex |> filter(PARAMCD == "DOSEINTNS")

dose_ard <- ard_stack(
  adex_dose,
  ard_continuous(
    variables = AVAL,
    statistic = ~ continuous_summary_fns(c("N", "mean", "sd", "median", "min", "max"))
  ),
  .by = TRTA
)
```

---

## 9. Adding ARS traceability metadata

For ARS-aligned submission, each ARD row should carry the Analysis ID, Method ID, and Output ID that produced it. The base `{cards}` package doesn't add these automatically, but they're easy to add post-hoc:

```r
# Tag the demographics ARD with ARS metadata
demog_ard_tagged <- demog_ard |>
  mutate(
    OutputId   = "T_DEMOG",
    AnalysisId = case_when(
      variable == "AGE"     ~ "AN_DEMOG_AGE",
      variable == "BMIBL"   ~ "AN_DEMOG_BMI",
      variable == "SEX"     ~ "AN_DEMOG_SEX",
      variable == "AGEGR1"  ~ "AN_DEMOG_AGEGR",
      variable == "RACE"    ~ "AN_DEMOG_RACE",
      variable == "ETHNIC"  ~ "AN_DEMOG_ETHNIC",
      .default = NA_character_
    ),
    MethodId = case_when(
      context == "continuous"   ~ "MTH_SUMMARY_STATISTICS_CONTINUOUS",
      context == "categorical"  ~ "MTH_COUNT_AND_PERCENTAGE",
      context == "total_n"      ~ "MTH_SUBJECT_COUNT",
      .default = NA_character_
    )
  )
```

When using `{siera}`, this tagging is done automatically — siera reads the Analysis IDs from the ARS file and injects them as columns. When using `{arsbridge}`, the tagging is also automatic via `ars_to_ard()`.

---

## 10. Putting it together: the study-wide ARD pipeline

A complete script building all ARDs for a CSR:

```r
library(cards)
library(dplyr)
library(pharmaverseadam)
library(purrr)

# ─── 1. Load and filter data ──────────────────────────────────────────────────
adsl   <- pharmaverseadam::adsl
adae   <- pharmaverseadam::adae
adlb   <- pharmaverseadam::adlb

adsl_saf <- adsl |> filter(SAFFL == "Y")
adae_te  <- adae |> filter(SAFFL == "Y" & TRTEMFL == "Y")
adlb_an  <- adlb |> filter(SAFFL == "Y" & ANL01FL == "Y")

# ─── 2. Demographics ARD ──────────────────────────────────────────────────────
demog_ard <- ard_stack(
  adsl_saf |>
    mutate(
      AGEGR1 = factor(AGEGR1, c("<65", "65-80", ">80")),
      SEX    = factor(SEX,    c("F", "M")),
      RACE   = factor(RACE,   sort(unique(RACE)))
    ),
  ard_continuous(
    variables = c(AGE, BMIBL, WEIGHTBL),
    statistic = ~ continuous_summary_fns(c("N", "mean", "sd", "median", "min", "max"))
  ),
  ard_categorical(variables = c(AGEGR1, SEX, RACE)),
  .by = TRT01A,  .overall = TRUE,  .total_n = TRUE
)

# ─── 3. AE incidence ARD ──────────────────────────────────────────────────────
ae_ard <- bind_ard(
  # Overall "any TEAE" row
  adae_te |>
    distinct(USUBJID, ARM) |>
    mutate(any_teae = "Y") |>
    ard_categorical(by = "ARM", variables = "any_teae",
                    denominator = adsl_saf),
  # SOC × PT hierarchy
  adae_te |>
    ard_hierarchical(by = "ARM", variables = c("AEBODSYS", "AEDECOD"),
                     denominator = adsl_saf, id = "USUBJID")
)

# ─── 4. Lab change-from-baseline ARD ──────────────────────────────────────────
lab_ard <- ard_stack(
  adlb_an |> filter(PARAMCD %in% c("HGB", "ALT", "AST")),
  ard_continuous(
    variables = c(AVAL, CHG),
    statistic = ~ continuous_summary_fns(c("N", "mean", "sd", "median", "min", "max"))
  ),
  .by = c(PARAMCD, AVISIT, TRTA)
)

# ─── 5. Validate all ARDs ─────────────────────────────────────────────────────
walk(
  list(demog_ard = demog_ard, ae_ard = ae_ard, lab_ard = lab_ard),
  function(ard) {
    check_ard_structure(ard)
    print_ard_conditions(ard)
  }
)

# ─── 6. Combine for study archive ─────────────────────────────────────────────
study_ard <- bind_ard(demog_ard, ae_ard, lab_ard)

# ─── 7. Save ──────────────────────────────────────────────────────────────────
saveRDS(demog_ard, "ards/demog_ard.rds")
saveRDS(ae_ard,    "ards/ae_ard.rds")
saveRDS(lab_ard,   "ards/lab_ard.rds")
saveRDS(study_ard, "ards/study_ard.rds")

message("Study ARD complete: ", nrow(study_ard), " rows")
```

---

## 11. Preparing ARDs for display: `shuffle_ard()`

`{tfrmt}` expects ARDs in a slightly wider format with the group columns pivoted. The `shuffle_ard()` function (also called `shuffle_card()`) does this pivot:

```r
demog_ard_wide <- demog_ard |>
  shuffle_ard()
# Now: TRT01A is a regular column, not group1/group1_level

# Compare shapes:
# Before shuffle: group1 = "TRT01A", group1_level = "Placebo"
# After shuffle:  TRT01A = "Placebo" (as a proper column)
```

`{gtsummary}` consumes the standard long format directly — no `shuffle_ard()` needed. `{tfrmt}` requires `shuffle_ard()`. Be clear on which display layer you're targeting.

---

## 12. Dual-programming strategy for ARD validation

The key paradigm shift in validation: **you validate the ARD, not the display.**

**Traditional SAS approach**: Programmer 1 produces Table 14.1.1 in RTF. Programmer 2 independently produces the same table. QA compares the two RTFs cell by cell.

**ARD-first approach**:

```r
# Programmer 1's ARD
ard_p1 <- readRDS("validation/demog_ard_programmer1.rds")

# Programmer 2's ARD
ard_p2 <- readRDS("validation/demog_ard_programmer2.rds")

# Compare: any rows in P1 not in P2 (after rounding floats)?
ard_p1_flat <- ard_p1 |>
  filter(!is.na(stat)) |>
  mutate(stat_value = map_dbl(stat, ~ round(.x[[1]], 4))) |>
  select(group1_level, variable, variable_level, stat_name, stat_value)

ard_p2_flat <- ard_p2 |>
  filter(!is.na(stat)) |>
  mutate(stat_value = map_dbl(stat, ~ round(.x[[1]], 4))) |>
  select(group1_level, variable, variable_level, stat_name, stat_value)

# Find discrepancies:
anti_join(ard_p1_flat, ard_p2_flat)  # rows in P1 but not P2
anti_join(ard_p2_flat, ard_p1_flat)  # rows in P2 but not P1

# Check specific values:
full_join(ard_p1_flat, ard_p2_flat,
          by = c("group1_level", "variable", "variable_level", "stat_name"),
          suffix = c("_p1", "_p2")) |>
  filter(abs(stat_value_p1 - stat_value_p2) > 0.001)
```

The display (the table layout) can then be validated separately, with much less effort: confirm that the values in the table match the ARD values by filtering and comparing.

---

## 13. Common pitfalls — production checklist

Use this as a code review checklist:

| Pitfall | Detection | Fix |
|---|---|---|
| Missing `denominator` on AE ARD | AE percentages > 100% or implausibly high | `denominator = adsl_saf` in every `ard_*()` for AEs |
| Inconsistent population filters | Percentages computed on different N | Apply SAFFL/ITTFL filter consistently in both data and denominator |
| Missing categorical levels | Some arms lack rows for a level | Factor-type all categorical variables before `ard_*()` calls |
| Computing on post-baseline only | Baseline N ≠ post-baseline N | Review `AVISITN > 0` filters; include baseline rows where needed |
| Using `bind_rows()` instead of `bind_ard()` | Silent column misalignment | Always use `bind_ard()` for ARD combination |
| Not checking conditions | Silent errors in specific statistics | Always call `print_ard_conditions(ard)` after building |
| Wrong `id` variable | Event counts instead of subject counts | Set `id = "USUBJID"` in `ard_hierarchical()` |
| Forgetting `.total_n = TRUE` | gtsummary can't build column headers | Include `.total_n = TRUE` in `ard_stack()` for tables that need Big-N headers |

---

## 14. Migration from Tplyr and rtables

If your team is migrating:

| Old approach | New approach |
|---|---|
| `Tplyr::tplyr_table() |> build()` → wide table | `ard_stack()` → long ARD + gtsummary/tfrmt |
| `rtables::basic_table() |> build_table()` → table object | `ard_*()` → ARD + gtsummary/tfrmt |
| Recompute for each display | One ARD, multiple displays |
| Dual prog = compare RTF files | Dual prog = compare ARD flat files |
| Study-level archive = pile of RTFs | Study-level archive = one RDS per topic |

The cards approach has more steps for a single table but pays dividends when you have 150 tables sharing overlapping analyses — which is every CSR.

---

## 15. Key takeaways

- A complete clinical ARD pipeline covers: demographics, AE incidence (hierarchical + any-AE overall), lab change-from-baseline, vital signs, disposition, exposure, concomitant medications
- Always specify `denominator = adsl_saf` for AE and any analysis where N = subjects not events
- Always `factor()` categorical variables with all expected levels to prevent missing zero-count rows
- For ARS traceability, add `OutputId`, `AnalysisId`, `MethodId` columns post-hoc (or let siera/arsbridge do it automatically)
- `shuffle_ard()` reshapes for tfrmt; gtsummary uses the standard long format directly
- Validation: compare ARD rows between dual programmers; the display validation is then trivial
- Use `bind_ard()`, not `bind_rows()`, to combine ARDs

---

## 16. What's next

Lesson 27 covers **`{cardx}`** — extending the ARD model to inferential statistics: t-tests, chi-squared, regression, survival analyses, and mixed models. Same ARD structure; the statistics come from model objects rather than simple summaries.

We also introduce **`{siera}`** in detail: how to read an ARS JSON file and auto-generate ARD programs, and **`{arsbridge}`**: the end-to-end pipeline from annotated TLF shells to formatted tables.

---

## Self-check questions

1. A TEAE incidence ARD shows percentages above 100% for some preferred terms. What caused this and how do you fix it?
2. Write the complete `ard_hierarchical()` call for serious TEAEs by SOC and PT, using the safety population denominator.
3. Your demographics ARD is missing ">80" rows for the High Dose arm (because no subjects were in that age group). What's the fix?
4. How would you compare two programmers' demographics ARDs to identify discrepancies?
5. Translate to cards: "Compute N, Mean, SD, Median, Min, Max of AVAL and CHG by PARAMCD × AVISIT × TRTA for subjects with SAFFL=Y and ANL01FL=Y."
6. What column and value would you filter on to find the Big-N rows added by `.total_n = TRUE`?

---

## Glossary

- **`ard_hierarchical()`** — Nested categorical tabulation; computes distinct-subject counts at each nesting level
- **`id = "USUBJID"`** — Ensures distinct-subject counting in hierarchical/categorical ARDs
- **`denominator = adsl_saf`** — Pass ADSL safety pop as denominator for correct AE N
- **`shuffle_ard()`** — Pivot group columns from `group1_level` to actual wide columns (for tfrmt)
- **`.overall = TRUE`** — Add "All subjects combined" rows to `ard_stack()` output
- **`.total_n = TRUE`** — Add Big-N per group to `ard_stack()` output
- **`context = "total_n"`** — Context value identifying Big-N rows
- **`OutputId`** — ARS traceability column linking ARD rows to the output they belong to
- **`AnalysisId`** — ARS traceability column linking rows to specific analyses in the ARS spec
- **`MethodId`** — ARS traceability column linking rows to the statistical method used
- **TRTEMFL** — Treatment-Emergent Flag in ADAE (`"Y"` = treatment-emergent AE)
- **ANL01FL** — Analysis Flag 01 in BDS ADaMs; marks the observation for primary analysis
- **PARAMCD** — Parameter Code in BDS ADaMs (e.g., `"ALT"`, `"HGB"`)
- **AVISIT** — Analysis Visit label in BDS ADaMs
- **CHG** — Change from Baseline in BDS ADaMs
- **BNRIND** — Baseline Normal Range Indicator (e.g., "L", "N", "H")
- **ANRIND** — Analysis Normal Range Indicator (post-baseline)
