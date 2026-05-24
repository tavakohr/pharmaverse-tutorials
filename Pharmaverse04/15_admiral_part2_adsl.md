# Lesson 15 — `{admiral}` Part 2: Building ADSL End-to-End

**Module**: 4 — ADaM core
**Estimated length**: ~30 min spoken
**Prerequisites**: Lessons 12–14

---

## Learning objectives

By the end of this lesson, you will be able to:

1. Build a production-grade ADSL from SDTM source data using admiral
2. Derive treatment start/end datetimes with proper handling of placebo and zero doses
3. Compute treatment duration with `derive_var_trtdurd()`
4. Derive disposition dates (RANDDT, EOSDT) from DS
5. Derive cause of death (DTHCAUS) using `derive_vars_extreme_event()`
6. Build population flags (SAFFL, ITTFL, EFFFL)
7. Add age groups using `derive_vars_cat()` (admiral 1.2+)

---

## 1. ADSL: the subject-level dataset

ADSL is the Subject-Level Analysis Dataset. **One row per subject**, holding everything that's true about that subject for the study: demographics, treatments, key dates, populations, derived flags. Every other ADaM dataset references ADSL.

The variables you'll see in a typical ADSL:

- **Subject identifiers**: STUDYID, USUBJID, SUBJID, SITEID
- **Demographics**: AGE, AGEU, AGEGR1, AGEGR1N, SEX, RACE, RACEN, ETHNIC
- **Treatment assignment**: ARM, ACTARM, TRT01P, TRT01A, TRT01PN, TRT01AN
- **Key dates**: RFICDTC, RFXSTDTC, TRTSDT, TRTSDTM, TRTEDT, TRTEDTM, EOSDT, DTHDT, LSTALVDT, RANDDT
- **Durations**: TRTDURD, TRTDURM, LDDTHELD, DTHADY
- **Population flags**: SAFFL, ITTFL, EFFFL, RANDFL, COMPLFL
- **Disposition / outcome**: EOSSTT, EOTSTT, DCSREAS, DTHCAUS

We'll build a representative subset of these.

## 2. Setup

```r
library(admiral)
library(dplyr, warn.conflicts = FALSE)
library(stringr)
library(lubridate)
library(pharmaversesdtm)

# Source SDTM with blanks → NA
dm <- pharmaversesdtm::dm |> convert_blanks_to_na()
ds <- pharmaversesdtm::ds |> convert_blanks_to_na()
ex <- pharmaversesdtm::ex |> convert_blanks_to_na()
ae <- pharmaversesdtm::ae |> convert_blanks_to_na()
lb <- pharmaversesdtm::lb |> convert_blanks_to_na()
```

Optionally, you'd also load `suppdm` and combine using `metatools::combine_supp()` (Lesson 13) before proceeding. For this lesson we work with just `dm`.

## 3. Base ADSL from DM

The starting point: copy DM and keep the variables relevant to ADSL. In a metadata-driven flow this comes from `metatools::build_from_derived()`; without metadata, you can do it manually.

```r
adsl <- dm |>
  mutate(TRT01P = ARM,
         TRT01A = ACTARM)
```

We've copied DM and seeded `TRT01P` (planned treatment) and `TRT01A` (actual treatment) from `ARM` and `ACTARM`. These are the standard mappings; your spec may differ.

## 4. Treatment start/end datetimes

The treatment window is the foundation for many downstream calculations: study day, on-treatment flags, duration. ADSL conventionally has both datetime versions (TRTSDTM/TRTEDTM) and date versions (TRTSDT/TRTEDT).

The pattern: pre-process EX to add ISO 8601 datetimes with imputation, then merge the first / last qualifying record.

```r
# Step 1: Pre-process EX with datetime variables
ex_ext <- ex |>
  derive_vars_dtm(
    dtc = EXSTDTC,
    new_vars_prefix = "EXST"
  ) |>
  derive_vars_dtm(
    dtc = EXENDTC,
    new_vars_prefix = "EXEN",
    time_imputation = "last"
  )
```

This adds `EXSTDTM`, `EXSTDTF`, `EXSTTMF` (from EXSTDTC) and `EXENDTM`, `EXENDTF`, `EXENTMF` (from EXENDTC). For end times we impute to "last" (23:59:59); for start, we use the default ("first" = 00:00:00).

Now merge the first qualifying EX record onto ADSL:

```r
# Step 2: Derive TRTSDTM and TRTEDTM from EX
adsl <- adsl |>
  derive_vars_merged(
    dataset_add = ex_ext,
    filter_add = (EXDOSE > 0 |
                  (EXDOSE == 0 & str_detect(EXTRT, "PLACEBO"))) &
                 !is.na(EXSTDTM),
    new_vars = exprs(TRTSDTM = EXSTDTM, TRTSTMF = EXSTTMF),
    order = exprs(EXSTDTM, EXSEQ),
    mode = "first",
    by_vars = exprs(STUDYID, USUBJID)
  ) |>
  derive_vars_merged(
    dataset_add = ex_ext,
    filter_add = (EXDOSE > 0 |
                  (EXDOSE == 0 & str_detect(EXTRT, "PLACEBO"))) &
                 !is.na(EXENDTM),
    new_vars = exprs(TRTEDTM = EXENDTM, TRTETMF = EXENTMF),
    order = exprs(EXENDTM, EXSEQ),
    mode = "last",
    by_vars = exprs(STUDYID, USUBJID)
  )
```

Unpacking the filter: `(EXDOSE > 0 | (EXDOSE == 0 & str_detect(EXTRT, "PLACEBO")))` — keep records where the dose is positive, OR the dose is zero but it's labeled as placebo. This is the standard pattern because:

- Active doses must be > 0 (zero-dose treatment doesn't count as exposure)
- Placebo by convention has dose = 0; we want to count placebo as exposure for placebo arms

Now convert the datetimes to dates:

```r
adsl <- adsl |>
  derive_vars_dtm_to_dt(source_vars = exprs(TRTSDTM, TRTEDTM))
# Adds TRTSDT and TRTEDT (numeric dates)
```

## 5. Treatment duration

```r
adsl <- adsl |>
  derive_var_trtdurd()
```

That's it. The function reads TRTSDT and TRTEDT (it knows the names), calculates `TRTEDT - TRTSDT + 1` (the "+ 1" is the CDISC convention — Day 1 is the start day, so duration of "treatment from day 1 to day 1" is 1 day, not 0).

To customize variable names:

```r
adsl <- adsl |>
  derive_var_trtdurd(
    new_var = TRTDURD,
    start_date = TRTSDT,
    end_date = TRTEDT
  )
```

For duration in other units (months, years), use the more general `derive_vars_duration()`:

```r
adsl <- adsl |>
  derive_vars_duration(
    new_var = TRTDURM,
    new_var_unit = TRTDURMU,
    start_date = TRTSDT,
    end_date = TRTEDT,
    out_unit = "months"
  )
```

## 6. Disposition dates

Many ADSL dates come from DS (Disposition). Common: RANDDT (randomization), EOSDT (end of study), DCSREAS (discontinuation reason). The pattern: pre-process DS to a numeric date, then merge with appropriate filter.

```r
# Convert DSSTDTC to numeric date
ds_ext <- ds |>
  derive_vars_dt(
    dtc = DSSTDTC,
    new_vars_prefix = "DSST"
  )

# Randomization date
adsl <- adsl |>
  derive_vars_merged(
    dataset_add = ds_ext,
    filter_add = DSCAT == "PROTOCOL MILESTONE" & DSDECOD == "RANDOMIZED",
    new_vars = exprs(RANDDT = DSSTDT),
    by_vars = exprs(STUDYID, USUBJID)
  )

# End-of-study date
adsl <- adsl |>
  derive_vars_merged(
    dataset_add = ds_ext,
    filter_add = DSCAT == "DISPOSITION EVENT" & DSDECOD != "SCREEN FAILURE",
    new_vars = exprs(EOSDT = DSSTDT),
    by_vars = exprs(STUDYID, USUBJID)
  )
```

The structure repeats: filter DS for the relevant row, take its date, attach to ADSL.

## 7. Cause of death

DTHCAUS (Cause of Death) is one of the more interesting derivations because the cause can come from multiple sources — sometimes from DS, sometimes from AE with a "FATAL" outcome, sometimes from a separate DD (Death Details) domain. admiral's `derive_vars_extreme_event()` handles multi-source derivations with priority rules.

```r
# Source 1: DS (death recorded in disposition)
src_ds <- event_source(
  dataset_name = "ds",
  filter = DSDECOD == "DEATH",
  date = DSSTDT,
  set_values_to = exprs(
    DTHCAUS = DSTERM,
    DTHDT = DSSTDT
  )
)

# Source 2: AE (death recorded as adverse event outcome)
src_ae <- event_source(
  dataset_name = "ae",
  filter = AEOUT == "FATAL",
  date = convert_dtc_to_dt(AEDTHDTC),
  set_values_to = exprs(
    DTHCAUS = AEDECOD,
    DTHDT = convert_dtc_to_dt(AEDTHDTC)
  )
)

# Derive DTHCAUS and DTHDT from whichever source has the death event
adsl <- adsl |>
  derive_vars_extreme_event(
    by_vars = exprs(STUDYID, USUBJID),
    events = list(src_ds, src_ae),
    order = exprs(DTHDT),
    mode = "first",
    source_datasets = list(ds = ds_ext, ae = ae),
    new_vars = exprs(DTHCAUS, DTHDT)
  )
```

The pattern: define `event_source()` objects describing each possible source of a death event, then `derive_vars_extreme_event()` picks the *first* qualifying event (chronologically) and pulls the death cause and date from it.

This is the "right" way to do multi-source derivations in admiral. Once you internalize the `event_source()` / `derive_vars_extreme_event()` pattern, it generalizes to any "find the [extreme/first/last] event across multiple data sources" need — last known alive date, first occurrence of any AE, etc.

## 8. Last known alive date (LSTALVDT)

LSTALVDT is the latest date we have confirmation the subject was alive. It comes from many sources:

- Latest visit date in DS
- Latest AE start date (if alive at the time of the AE)
- Latest LB collection date
- Latest VS collection date
- ...etc.

If the subject is dead, we cap at the day before death (or the death date — sponsor convention).

`derive_vars_extreme_event()` again:

```r
src_ae_alive <- event_source(
  dataset_name = "ae",
  filter = !is.na(AESTDTC),
  date = convert_dtc_to_dt(AESTDTC),
  set_values_to = exprs(LSTALVDT = convert_dtc_to_dt(AESTDTC))
)

src_lb_alive <- event_source(
  dataset_name = "lb",
  filter = !is.na(LBDTC),
  date = convert_dtc_to_dt(LBDTC),
  set_values_to = exprs(LSTALVDT = convert_dtc_to_dt(LBDTC))
)

# add more sources as needed

adsl <- adsl |>
  derive_vars_extreme_event(
    by_vars = exprs(STUDYID, USUBJID),
    events = list(src_ae_alive, src_lb_alive),
    order = exprs(LSTALVDT),
    mode = "last",
    source_datasets = list(ae = ae, lb = lb),
    new_vars = exprs(LSTALVDT)
  )
```

For a subject with both an AE on 2024-07-15 and a lab on 2024-08-20, LSTALVDT will be 2024-08-20 (the later date across all sources).

## 9. Time-to-death durations

Two standard variables encode how long the subject was followed before death:

- **DTHADY**: study day of death (relative to TRTSDT)
- **LDDTHELD**: days elapsed from last dose to death

```r
adsl <- adsl |>
  derive_vars_duration(
    new_var = DTHADY,
    start_date = TRTSDT,
    end_date = DTHDT
  ) |>
  derive_vars_duration(
    new_var = LDDTHELD,
    start_date = TRTEDT,
    end_date = DTHDT,
    add_one = FALSE
  )
```

Note `add_one = FALSE` for LDDTHELD: that follows the convention where "days from last dose" counts the gap in calendar days without the "+1" adjustment.

## 10. Population flags

The standard ADSL population flags:

- **SAFFL** (Safety Flag): subject was in the safety analysis set — typically, took at least one dose
- **ITTFL** (Intent-to-Treat Flag): subject was randomized
- **EFFFL** (Efficacy Flag): subject is eligible for the efficacy analyses

Each flag is sponsor- and study-specific in the precise definition, but the typical patterns:

```r
# SAFFL — exposed (any non-zero or placebo dose)
adsl <- adsl |>
  derive_var_merged_exist_flag(
    dataset_add = ex,
    by_vars = exprs(STUDYID, USUBJID),
    new_var = SAFFL,
    condition = (EXDOSE > 0 | (EXDOSE == 0 & str_detect(EXTRT, "PLACEBO")))
  )

# ITTFL — randomized (has a RANDDT)
adsl <- adsl |>
  mutate(ITTFL = if_else(!is.na(RANDDT), "Y", NA_character_))

# RANDFL — same as above; some sponsors use a different name
adsl <- adsl |>
  mutate(RANDFL = if_else(!is.na(RANDDT), "Y", NA_character_))
```

Note the convention: flags take values `"Y"` or `NA` — never `"N"`. The CDISC ADaM IG specifies this.

For more nuanced flags involving conditions across multiple datasets, use `derive_var_merged_ef_msrc()`:

```r
# Hypothetical: EFFFL — completed treatment AND has at least one efficacy assessment
adsl <- adsl |>
  derive_var_merged_ef_msrc(
    by_vars = exprs(STUDYID, USUBJID),
    flag_events = list(
      flag_event(dataset_name = "ds", condition = DSDECOD == "COMPLETED"),
      flag_event(dataset_name = "lb", condition = !is.na(LBORRES))
    ),
    source_datasets = list(ds = ds, lb = lb),
    new_var = EFFFL,
    true_value = "Y"
  )
```

## 11. Age groups

ADSL conventionally includes age categorization: AGEGR1 (character) and AGEGR1N (numeric companion). Common categorizations:

- `<18` / `18-64` / `>=65` — or other study-specific buckets

In `admiral 1.2+`, `derive_vars_cat()` does both at once:

```r
age_grp <- exprs(
  AGEGR1 = case_when(
    AGE < 18              ~ "<18",
    between(AGE, 18, 64)  ~ "18-64",
    AGE >= 65             ~ ">=65"
  ),
  AGEGR1N = case_when(
    AGE < 18              ~ 1,
    between(AGE, 18, 64)  ~ 2,
    AGE >= 65             ~ 3
  )
)

adsl <- adsl |>
  mutate(!!!age_grp)
```

If you have metacore, `create_var_from_codelist()` is cleaner (Lesson 13). The `derive_vars_cat()` function in admiral uses a lookup-driven approach that integrates well with metadata-driven workflows.

## 12. Race numeric companion

RACEN (RACE Numeric) is set from RACE per a codelist. Without metacore, manual:

```r
adsl <- adsl |>
  mutate(RACEN = case_when(
    RACE == "AMERICAN INDIAN OR ALASKA NATIVE"          ~ 1,
    RACE == "ASIAN"                                     ~ 2,
    RACE == "BLACK OR AFRICAN AMERICAN"                 ~ 3,
    RACE == "NATIVE HAWAIIAN OR OTHER PACIFIC ISLANDER" ~ 4,
    RACE == "WHITE"                                     ~ 5,
    RACE == "MULTIPLE"                                  ~ 6,
    RACE == "UNKNOWN"                                   ~ 8,
    RACE == "NOT REPORTED"                              ~ 9,
    TRUE                                                ~ NA_real_
  ))
```

With metacore — much cleaner:

```r
adsl <- adsl |>
  create_var_from_codelist(metacore = md_adsl, input_var = RACE, out_var = RACEN)
```

The codelist is the single source of truth; the code references it.

## 13. Putting it all together

Here's a slimmed-down complete ADSL script. In production you'd have more derivations, but this captures the pattern:

```r
library(admiral)
library(dplyr)
library(stringr)
library(pharmaversesdtm)

# 1. Load and clean
dm <- pharmaversesdtm::dm |> convert_blanks_to_na()
ds <- pharmaversesdtm::ds |> convert_blanks_to_na()
ex <- pharmaversesdtm::ex |> convert_blanks_to_na()
ae <- pharmaversesdtm::ae |> convert_blanks_to_na()
lb <- pharmaversesdtm::lb |> convert_blanks_to_na()

# 2. Pre-process EX and DS
ex_ext <- ex |>
  derive_vars_dtm(dtc = EXSTDTC, new_vars_prefix = "EXST") |>
  derive_vars_dtm(dtc = EXENDTC, new_vars_prefix = "EXEN", time_imputation = "last")

ds_ext <- ds |>
  derive_vars_dt(dtc = DSSTDTC, new_vars_prefix = "DSST")

# 3. Build base from DM
adsl <- dm |>
  mutate(TRT01P = ARM, TRT01A = ACTARM)

# 4. Treatment dates
adsl <- adsl |>
  derive_vars_merged(
    dataset_add = ex_ext,
    filter_add = (EXDOSE > 0 | (EXDOSE == 0 & str_detect(EXTRT, "PLACEBO"))) & !is.na(EXSTDTM),
    new_vars = exprs(TRTSDTM = EXSTDTM, TRTSTMF = EXSTTMF),
    order = exprs(EXSTDTM, EXSEQ),
    mode = "first",
    by_vars = exprs(STUDYID, USUBJID)
  ) |>
  derive_vars_merged(
    dataset_add = ex_ext,
    filter_add = (EXDOSE > 0 | (EXDOSE == 0 & str_detect(EXTRT, "PLACEBO"))) & !is.na(EXENDTM),
    new_vars = exprs(TRTEDTM = EXENDTM, TRTETMF = EXENTMF),
    order = exprs(EXENDTM, EXSEQ),
    mode = "last",
    by_vars = exprs(STUDYID, USUBJID)
  ) |>
  derive_vars_dtm_to_dt(source_vars = exprs(TRTSDTM, TRTEDTM)) |>
  derive_var_trtdurd()

# 5. Disposition dates
adsl <- adsl |>
  derive_vars_merged(
    dataset_add = ds_ext,
    filter_add = DSCAT == "PROTOCOL MILESTONE" & DSDECOD == "RANDOMIZED",
    new_vars = exprs(RANDDT = DSSTDT),
    by_vars = exprs(STUDYID, USUBJID)
  ) |>
  derive_vars_merged(
    dataset_add = ds_ext,
    filter_add = DSCAT == "DISPOSITION EVENT" & DSDECOD != "SCREEN FAILURE",
    new_vars = exprs(EOSDT = DSSTDT),
    by_vars = exprs(STUDYID, USUBJID)
  )

# 6. Death cause and date (multi-source)
src_ds_death <- event_source(
  dataset_name = "ds",
  filter = DSDECOD == "DEATH",
  date = DSSTDT,
  set_values_to = exprs(DTHCAUS = DSTERM, DTHDT = DSSTDT)
)

src_ae_death <- event_source(
  dataset_name = "ae",
  filter = AEOUT == "FATAL",
  date = convert_dtc_to_dt(AEDTHDTC),
  set_values_to = exprs(DTHCAUS = AEDECOD, DTHDT = convert_dtc_to_dt(AEDTHDTC))
)

adsl <- adsl |>
  derive_vars_extreme_event(
    by_vars = exprs(STUDYID, USUBJID),
    events = list(src_ds_death, src_ae_death),
    order = exprs(DTHDT),
    mode = "first",
    source_datasets = list(ds = ds_ext, ae = ae),
    new_vars = exprs(DTHCAUS, DTHDT)
  )

# 7. Death-related durations
adsl <- adsl |>
  derive_vars_duration(new_var = DTHADY,   start_date = TRTSDT, end_date = DTHDT) |>
  derive_vars_duration(new_var = LDDTHELD, start_date = TRTEDT, end_date = DTHDT, add_one = FALSE)

# 8. Population flags
adsl <- adsl |>
  derive_var_merged_exist_flag(
    dataset_add = ex,
    by_vars = exprs(STUDYID, USUBJID),
    new_var = SAFFL,
    condition = (EXDOSE > 0 | (EXDOSE == 0 & str_detect(EXTRT, "PLACEBO")))
  ) |>
  mutate(
    ITTFL  = if_else(!is.na(RANDDT), "Y", NA_character_),
    RANDFL = if_else(!is.na(RANDDT), "Y", NA_character_)
  )

# 9. Age groups
adsl <- adsl |>
  mutate(
    AGEGR1 = case_when(
      AGE < 18             ~ "<18",
      between(AGE, 18, 64) ~ "18-64",
      AGE >= 65            ~ ">=65"
    ),
    AGEGR1N = case_when(
      AGE < 18             ~ 1,
      between(AGE, 18, 64) ~ 2,
      AGE >= 65            ~ 3
    )
  )

# Done — adsl is your subject-level analysis dataset
glimpse(adsl)
```

In ~100 lines of R, you've produced a working ADSL. In SAS, the equivalent — with proper SAS conventions, length statements, formats, and PROC SQL joins — is typically 300+ lines. The conciseness gain is real.

## 14. What's missing from this simplified ADSL

In production you'd typically also derive:

- More precise treatment variables (TRT01PN, TR01AN — numeric companions; TRTSEQA / TRTSEQP if treatments switch)
- Subject visit attendance variables
- Phase / Period / Subperiod variables for studies with crossover or extension designs
- Stratification factors (STRAT1, STRAT2, ...) from randomization data
- Customized population flags per the SAP
- Sponsor-specific derived variables documented in your spec

The admiral template (`use_ad_template("adsl")`) gives you a more complete starting point. Use it.

## 15. Validation strategy

For a study going to submission, you need to validate your ADSL. Standard approach:

1. **Dual programming**: a second programmer independently writes the ADSL derivation
2. **Compare**: use `{diffdf}` (Module 10) to compare the two outputs
3. **Discrepancy resolution**: any differences are investigated; the spec is updated where it was ambiguous

`{diffdf}` produces tidy comparison output that highlights value differences, missing rows, extra rows, type mismatches.

For a regulator-facing dataset, dual programming is essentially mandatory. Pharma quality programs require it for submission-quality work.

## 16. Key takeaways

- ADSL is the canonical subject-level dataset; built first because every other ADaM depends on it
- The standard derivation pattern: pre-process source SDTM (`derive_vars_dt()`, `derive_vars_dtm()`), then merge selectively with `derive_vars_merged()`
- Multi-source derivations (DTHCAUS, LSTALVDT) use `event_source()` + `derive_vars_extreme_event()`
- Population flags use `derive_var_merged_exist_flag()` for single-source, `derive_var_merged_ef_msrc()` for multi-source
- Standard CDISC conventions: flag values `"Y"` or `NA` (not `"N"`); `add_one = TRUE` for durations including endpoints
- Validate with dual programming + `{diffdf}` for submission-quality work

## 17. What's next

Lesson 16 — **`{admiral}` Part 3** — covers BDS (Basic Data Structure) ADaMs: ADLB, ADVS, ADEG. These are the long-format datasets with one row per parameter per visit, used for safety endpoints. The patterns are different from ADSL but reuse most of the same admiral functions.

After Lesson 16: OCCDS (ADAE, ADCM) in Lesson 17, time-to-event (ADTTE) in Lesson 18, and advanced patterns in Lesson 19.

---

## Self-check questions

1. Why do we pre-process EX with `derive_vars_dtm()` before merging onto ADSL?
2. What does the filter `(EXDOSE > 0 | (EXDOSE == 0 & str_detect(EXTRT, "PLACEBO")))` ensure?
3. Why is DTHCAUS derived using `derive_vars_extreme_event()` rather than a simple merge?
4. What's the CDISC convention for flag variable values, and why does it matter?
5. Translate to admiral: "for each subject, derive `RANDDT` as the DSSTDTC where DSDECOD = 'RANDOMIZED'."
6. Why is `add_one = FALSE` used for LDDTHELD but `add_one = TRUE` (default) for TRTDURD?

## Glossary

- **ADSL** — Subject-Level Analysis Dataset; one row per subject
- **TRTSDT / TRTEDT** — Treatment start date / end date (numeric)
- **TRTSDTM / TRTEDTM** — Treatment start/end datetime (numeric)
- **TRTDURD** — Treatment duration in days
- **RANDDT** — Randomization date
- **EOSDT** — End of Study date
- **DTHCAUS / DTHDT** — Cause of death / Death date
- **LSTALVDT** — Last Known Alive Date
- **SAFFL / ITTFL / EFFFL** — Safety / Intent-to-Treat / Efficacy population flags
- **AGEGR1 / AGEGR1N** — Age group (character) and numeric companion
- **`event_source()`** — Admiral object describing one possible source of an event
- **`derive_vars_extreme_event()`** — Pick the first/last event across multiple sources
- **`derive_var_merged_exist_flag()`** — Simple population flag based on existence in another dataset
- **`derive_var_merged_ef_msrc()`** — Multi-source existence flag
