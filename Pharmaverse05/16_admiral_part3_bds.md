# Lesson 16 — `{admiral}` Part 3: BDS Datasets (ADLB, ADVS, ADEG)

**Module**: 4 — ADaM core
**Estimated length**: ~30 min spoken
**Prerequisites**: Lessons 14–15 (admiral foundations + ADSL)

---

## Learning objectives

By the end of this lesson, you will be able to:

1. Recognize the BDS (Basic Data Structure) shape and identify which ADaMs use it
2. Build an ADVS (Vital Signs) dataset end-to-end with admiral
3. Derive analysis date/time variables (ADT, ADTM, ADY) and analysis values (AVAL, AVALC)
4. Add computed parameters with `derive_param_bmi()`, `derive_param_map()`, `derive_param_computed()`
5. Derive baseline (ABLFL, BASE, BASEC) and change-from-baseline (CHG, PCHG) variables
6. Apply reference range (ANRIND), shift (SHIFTy), and on-treatment flags
7. Apply the same patterns to ADLB (Lab) and ADEG (ECG)

---

## 1. What "BDS" means

The Basic Data Structure (BDS) is the CDISC convention for **long-format analysis datasets**: one row per parameter per subject per visit (or timepoint). The shape:

```
USUBJID   PARAMCD   PARAM            AVAL    AVISIT     ABLFL  ANRIND  ...
01-001    SYSBP     Systolic BP      120     SCREENING  Y      NORMAL
01-001    SYSBP     Systolic BP      125     WEEK 4     N      NORMAL
01-001    DIABP     Diastolic BP     78      SCREENING  Y      NORMAL
01-001    HGB       Hemoglobin       13.5    SCREENING  Y      NORMAL
01-002    SYSBP     Systolic BP      145     SCREENING  Y      HIGH
...
```

PARAMCD identifies the parameter; AVAL holds the numeric analysis value; AVISIT names the visit; ABLFL flags the baseline row; ANRIND categorizes the value vs. the reference range.

Compare to ADSL's wide structure (one row per subject, many columns). The BDS shape makes it trivial to compute summaries per parameter, build forest plots, or filter for one test at a time — all dplyr-friendly operations.

**Which ADaMs are BDS?**

| ADaM | Source domain | What it analyzes |
|---|---|---|
| ADVS | VS | Vital signs |
| ADLB | LB | Laboratory values |
| ADEG | EG | Electrocardiogram |
| ADQS | QS | Questionnaire scores |
| ADPP | PP, PC | Pharmacokinetic parameters |
| ADEX | EX | Exposure (also fits BDS) |

The pattern below works for all of them with minor adaptations.

## 2. The BDS finding workflow

Admiral's vignette outlines the canonical workflow:

1. **Read in data**: load source SDTM (e.g., VS) and ADSL
2. **Merge ADSL variables**: bring TRTSDT, TRTEDT, and treatment vars from ADSL
3. **Derive ADT/ADTM/ADY**: numeric date, datetime, and study day from the SDTM date string
4. **Assign PARAMCD, PARAM, PARAMN, PARCAT1**: parameter identifiers
5. **Derive AVAL, AVALC**: analysis values
6. **Derive additional parameters**: BMI, MAP, BSA, etc.
7. **Assign timing variables**: AVISIT, AVISITN, ATPT, ATPTN, APERIOD
8. **Derive timing flags**: ONTRTFL, ANL01FL
9. **Assign reference range indicator**: ANRIND (e.g., NORMAL, LOW, HIGH)
10. **Derive baseline**: ABLFL, BASE, BASEC, BNRIND
11. **Derive change from baseline**: CHG, PCHG
12. **Derive shift**: SHIFT1 (e.g., NORMAL→HIGH)
13. **Derive analysis flags**: ANL01FL for inclusion in specific analyses

We'll walk this for ADVS.

## 3. Setup and ADSL merge

```r
library(admiral)
library(dplyr, warn.conflicts = FALSE)
library(stringr)
library(pharmaversesdtm)

vs <- pharmaversesdtm::vs |> convert_blanks_to_na()

# Assume adsl is already built (from Lesson 15)
adsl <- admiral::admiral_adsl   # admiral ships an example ADSL

# Variables we'll pull from ADSL
adsl_vars <- exprs(TRTSDT, TRTEDT, TRT01A, TRT01P)

advs <- vs |>
  derive_vars_merged(
    dataset_add = adsl,
    new_vars = adsl_vars,
    by_vars = exprs(STUDYID, USUBJID)
  )
```

After this, every row in advs has TRTSDT/TRTEDT — needed for ADY computation and on-treatment flags.

## 4. Derive ADT, ADTM, ADY

```r
advs <- advs |>
  derive_vars_dt(
    new_vars_prefix = "A",       # produces ADT and ADTF
    dtc = VSDTC
  ) |>
  derive_vars_dtm(
    new_vars_prefix = "A",       # produces ADTM, ADTF, ATMF
    dtc = VSDTC,
    highest_imputation = "M"     # impute month if missing (rare)
  ) |>
  derive_vars_dy(
    reference_date = TRTSDT,
    source_vars = exprs(ADT)     # produces ADY
  )
```

The `new_vars_prefix = "A"` convention means admiral names the output `ADT`, `ADTF`, `ADTM`, etc. — the ADaM canonical names. If you wanted different names, change the prefix.

`highest_imputation = "M"` says: if a date component is missing, impute up to (but no higher than) the month level. Use `"D"` for day-only imputation; `"n"` (or NULL) for no imputation; `"Y"` if you'd allow year-level imputation (rare and risky).

## 5. Assign PARAMCD, PARAM, PARAMN

The convention: copy from VSTESTCD/VSTEST, plus add a numeric companion (PARAMN). Some sponsors also add PARCAT1 (parameter category):

```r
param_lookup <- tribble(
  ~VSTESTCD, ~PARAMCD, ~PARAM,                              ~PARAMN, ~PARCAT1,
  "SYSBP",   "SYSBP",  "Systolic Blood Pressure (mmHg)",    1,       "Hemodynamic",
  "DIABP",   "DIABP",  "Diastolic Blood Pressure (mmHg)",   2,       "Hemodynamic",
  "PULSE",   "PULSE",  "Pulse Rate (beats/min)",            3,       "Hemodynamic",
  "TEMP",    "TEMP",   "Temperature (C)",                   4,       "Body System",
  "RESP",    "RESP",   "Respiratory Rate (breaths/min)",    5,       "Respiratory",
  "WEIGHT",  "WEIGHT", "Weight (kg)",                       10,      "Anthropometric",
  "HEIGHT",  "HEIGHT", "Height (cm)",                       11,      "Anthropometric"
)

advs <- advs |>
  derive_vars_merged_lookup(
    dataset_add = param_lookup,
    by_vars = exprs(VSTESTCD),
    new_vars = exprs(PARAMCD, PARAM, PARAMN, PARCAT1)
  )
```

`derive_vars_merged_lookup()` is similar to `derive_vars_merged()` but explicitly meant for static lookups; it also warns if rows in your data have a VSTESTCD that isn't in the lookup table — useful for catching unexpected parameters.

## 6. Derive AVAL and AVALC

In admiral conventions, **AVAL is the numeric analysis value**; **AVALC is the character analysis value**, used when results are categorical (e.g., "POSITIVE"/"NEGATIVE") or when numeric isn't applicable.

For most vital signs, AVAL comes directly from VSSTRESN (the standardized numeric result from SDTM):

```r
advs <- advs |>
  mutate(
    AVAL = VSSTRESN
    # AVALC = VSSTRESC   # only if applicable
  )
```

For ADLB, you'd map LBSTRESN → AVAL. For ADQS (questionnaires) where responses are categorical, you'd map QSSTRESC → AVALC and possibly transform to AVAL with a scoring lookup.

The convention from ADaMIG v1.3: don't populate AVALC if all AVAL values are numeric without a corresponding text value. Sponsor-specific rules apply.

## 7. Derive additional parameters: BMI, MAP, BSA

A common BDS pattern: derive *new* parameter rows from existing ones. BMI from WEIGHT and HEIGHT. MAP (Mean Arterial Pressure) from SYSBP and DIABP. BSA (Body Surface Area) from WEIGHT and HEIGHT using DuBois or other formulas.

Admiral provides specialized derivation helpers:

```r
# Derive BMI rows
advs <- advs |>
  derive_param_bmi(
    by_vars = exprs(STUDYID, USUBJID, !!!adsl_vars, AVISIT, AVISITN),
    weight_code = "WEIGHT",
    height_code = "HEIGHT",
    set_values_to = exprs(
      PARAMCD = "BMI",
      PARAM = "Body Mass Index (kg/m^2)",
      PARAMN = 20
    ),
    constant_by_vars = exprs(USUBJID)    # height collected once per subject
  )

# Derive MAP rows
advs <- advs |>
  derive_param_map(
    by_vars = exprs(STUDYID, USUBJID, !!!adsl_vars, AVISIT, AVISITN),
    set_values_to = exprs(
      PARAMCD = "MAP",
      PARAM = "Mean Arterial Pressure (mmHg)",
      PARAMN = 21
    )
  )
```

`constant_by_vars = exprs(USUBJID)` in the BMI call says: "height is collected only once per subject; use that single height with every visit's weight." Without it, BMI is computed only for visits where *both* height and weight are recorded — which is fine for some studies, wrong for others.

The pattern generalizes via `derive_param_computed()`:

```r
# Custom-formula parameter (illustrates the general pattern)
advs <- advs |>
  derive_param_computed(
    by_vars = exprs(STUDYID, USUBJID, AVISIT, AVISITN),
    parameters = c("SYSBP", "DIABP"),
    set_values_to = exprs(
      AVAL = (AVAL.SYSBP + 2 * AVAL.DIABP) / 3,
      PARAMCD = "MAP",
      PARAM = "Mean Arterial Pressure (mmHg)",
      AVALU = "mmHg"
    )
  )
```

`derive_param_computed()` is the general-purpose tool. You pass `parameters` (the PARAMCDs needed as inputs) and a formula using `AVAL.<paramcd>` syntax for each. It adds rows for the new computed parameter.

For one-off complex derivations (HOMA-IR, FLI, etc.), you'd use `derive_param_computed()` with arbitrary R inside `set_values_to`. We saw this in the metabolic ADLB example for FLI:

```r
adlb <- adlb |>
  derive_param_computed(
    by_vars = exprs(USUBJID, AVISIT, AVISITN),
    parameters = c("TRIG", "GGT"),
    set_values_to = exprs(
      AVAL = {
        lambda <- 0.953 * log(AVAL.TRIG) + 0.139 * BMI + 0.718 * log(AVAL.GGT) +
                  0.053 * WSTCIR - 15.745
        (exp(lambda) / (1 + exp(lambda))) * 100
      },
      PARAMCD = "FLI",
      PARAM = "Fatty Liver Index"
    )
  )
```

The `AVAL` expression is arbitrary R; the function handles the row creation and `AVAL.<paramcd>` substitutions.

## 8. Timing variables: AVISIT, AVISITN

Sometimes AVISIT can come directly from VSVISIT. Sometimes you need to derive it (e.g., to combine "BASELINE" and "SCREENING" into a single "BASELINE", or to relabel "VISIT 1" → "WEEK 1").

```r
advs <- advs |>
  mutate(
    AVISIT = case_when(
      VISIT == "SCREENING"  ~ "Baseline",
      VISIT == "BASELINE"   ~ "Baseline",
      VISIT == "WEEK 2"     ~ "Week 2",
      VISIT == "WEEK 4"     ~ "Week 4",
      TRUE                  ~ NA_character_
    ),
    AVISITN = case_when(
      AVISIT == "Baseline" ~ 0,
      AVISIT == "Week 2"   ~ 2,
      AVISIT == "Week 4"   ~ 4
    )
  )
```

Slot in `ATPT` (analysis timepoint, for sub-visit timing) and `ATPTN` (numeric companion) similarly when relevant — e.g., for cardiology with multiple ECGs per visit.

## 9. On-treatment flag (ONTRTFL)

For BDS data, ONTRTFL flags observations during the treatment window. Use the dedicated function:

```r
advs <- advs |>
  derive_var_ontrtfl(
    start_date = ADT,
    ref_start_date = TRTSDT,
    ref_end_date = TRTEDT
  )
```

For "treatment + 30 days follow-up" or similar variations:

```r
advs <- advs |>
  derive_var_ontrtfl(
    start_date = ADT,
    ref_start_date = TRTSDT,
    ref_end_date = TRTEDT,
    ref_end_window = 30
  )
```

The function fills ONTRTFL with `"Y"` when the observation date falls within the window. Rows outside the window get NA.

## 10. Reference range indicator (ANRIND)

ANRIND categorizes AVAL against the reference range — NORMAL, LOW, HIGH (and sometimes additional categories like BLLLN, ABNRH for "below lower limit of normal" and "above normal high"). Source data typically provides ANRLO (low) and ANRHI (high); admiral's `derive_var_anrind()` computes the indicator:

```r
advs <- advs |>
  derive_var_anrind()
# Reads AVAL, ANRLO, ANRHI; populates ANRIND
```

The default rule:

- AVAL < ANRLO → "LOW"
- AVAL > ANRHI → "HIGH"
- Otherwise → "NORMAL"

For more nuanced grading (e.g., laboratory toxicity grades), see `derive_var_atoxgr()` and `derive_var_atoxgr_dir()` — these implement CTCAE / NCI toxicity grading and are workhorses for ADLB.

## 11. Baseline derivation: ABLFL, BASE, BASEC, BNRIND

The "baseline" concept in ADaM:

- **ABLFL = "Y"** marks the row(s) used as baseline (typically the latest pre-treatment value per parameter)
- **BASE** is the baseline AVAL, copied to every post-baseline row
- **BASEC** is the character version
- **BNRIND** is the baseline ANRIND

Step 1: flag the baseline rows. Typically the last pre-treatment observation:

```r
advs <- advs |>
  restrict_derivation(
    derivation = derive_var_extreme_flag,
    args = params(
      by_vars = exprs(STUDYID, USUBJID, PARAMCD),
      order = exprs(ADT, AVISITN),
      new_var = ABLFL,
      mode = "last"
    ),
    filter = (!is.na(AVAL) & ADT <= TRTSDT)
  )
```

`restrict_derivation()` is admiral's "apply this derivation only to rows matching a filter" wrapper. Here: only consider rows with non-missing AVAL on or before TRTSDT, and flag the latest as the baseline.

Step 2: copy BASE/BASEC/BNRIND to every row from the flagged baseline:

```r
advs <- advs |>
  derive_var_base(
    by_vars = exprs(STUDYID, USUBJID, PARAMCD),
    source_var = AVAL,
    new_var = BASE
  ) |>
  derive_var_base(
    by_vars = exprs(STUDYID, USUBJID, PARAMCD),
    source_var = ANRIND,
    new_var = BNRIND
  )
```

`derive_var_base()` finds the row with ABLFL == "Y" within each by-group and copies its `source_var` to `new_var` on every row of the group.

## 12. Change from baseline: CHG and PCHG

Once BASE exists, change-from-baseline is one function call:

```r
advs <- advs |>
  derive_var_chg() |>
  derive_var_pchg()
```

CHG = AVAL - BASE
PCHG = (AVAL - BASE) / |BASE| × 100

By default these are derived on every row, including the baseline (where they're 0). To restrict to post-baseline only:

```r
advs <- advs |>
  restrict_derivation(
    derivation = derive_var_chg,
    filter = ABLFL != "Y"
  )
```

## 13. Shift variables

Shift describes the change in reference range category from baseline to a given visit — useful for shift tables (e.g., "how many subjects went from NORMAL at baseline to HIGH at Week 4?").

```r
advs <- advs |>
  derive_var_shift(
    new_var = SHIFT1,
    from_var = BNRIND,
    to_var = ANRIND
  )
```

This produces `SHIFT1` values like `"NORMAL to HIGH"`, `"NORMAL to NORMAL"`, `"LOW to NORMAL"`, etc. — directly usable in shift table TLGs (covered in later modules).

## 14. Worst-on-treatment flag

For safety analyses you often want "worst value during treatment per subject per parameter." Admiral's `derive_var_extreme_flag()` covers this — and `slice_derivation()` lets you vary the rule per parameter:

```r
advs <- advs |>
  slice_derivation(
    derivation = derive_var_extreme_flag,
    args = params(
      by_vars = exprs(STUDYID, USUBJID, PARAMCD),
      order = exprs(ADT, AVISITN),
      new_var = WORSTFL,
      mode = "first"
    ),
    derivation_slice(
      filter = PARAMCD %in% c("SYSBP", "DIABP", "PULSE") &
               ONTRTFL == "Y" & !is.na(AVAL),
      args = params(order = exprs(desc(AVAL)))   # highest is worst
    ),
    derivation_slice(
      filter = PARAMCD == "TEMP" & ONTRTFL == "Y" & !is.na(AVAL),
      args = params(order = exprs(desc(AVAL)))   # highest is worst
    )
  )
```

`slice_derivation()` is admiral's higher-order pattern: same function, different arguments per data slice. Worth the learning curve — it's much cleaner than running `derive_var_extreme_flag()` separately per parameter.

## 15. Analysis flags (ANL01FL, ANL02FL, ...)

ANL01FL is a generic "this row is in analysis #1" flag. Studies define exactly what analysis 1, 2, 3, ... mean. Typical example: ANL01FL = "Y" for one row per (subject × parameter × visit) — selecting the appropriate row when there are duplicates.

```r
advs <- advs |>
  restrict_derivation(
    derivation = derive_var_extreme_flag,
    args = params(
      by_vars = exprs(STUDYID, USUBJID, PARAMCD, AVISIT),
      order = exprs(desc(ADT), AVISITN),
      new_var = ANL01FL,
      mode = "first"
    ),
    filter = !is.na(AVAL) & !is.na(AVISIT)
  )
```

This says: for each (USUBJID, PARAMCD, AVISIT), among rows with non-missing AVAL and AVISIT, flag the latest by date as ANL01FL = "Y." Now any analysis filtering on `ANL01FL == "Y"` gets one row per visit per parameter per subject — the canonical selection rule.

## 16. Finalize and clean up

```r
# Pick up remaining ADSL variables not used in derivations
remaining_adsl_vars <- exprs(SEX, AGE, AGEU, RACE, ETHNIC, SAFFL, ITTFL, EFFFL)

advs <- advs |>
  derive_vars_merged(
    dataset_add = adsl,
    new_vars = remaining_adsl_vars,
    by_vars = exprs(STUDYID, USUBJID)
  )

# Final ordering of rows
advs <- advs |>
  arrange(STUDYID, USUBJID, PARAMCD, ADT, AVISITN)
```

## 17. Putting it together: a complete ADVS skeleton

```r
library(admiral)
library(dplyr)
library(pharmaversesdtm)

vs <- pharmaversesdtm::vs |> convert_blanks_to_na()
adsl <- admiral::admiral_adsl

adsl_vars <- exprs(TRTSDT, TRTEDT, TRT01A, TRT01P)

param_lookup <- tribble(
  ~VSTESTCD, ~PARAMCD, ~PARAM, ~PARAMN,
  "SYSBP",   "SYSBP",  "Systolic Blood Pressure (mmHg)",  1,
  "DIABP",   "DIABP",  "Diastolic Blood Pressure (mmHg)", 2,
  "PULSE",   "PULSE",  "Pulse Rate (beats/min)",          3,
  "TEMP",    "TEMP",   "Temperature (C)",                 4,
  "WEIGHT",  "WEIGHT", "Weight (kg)",                     10,
  "HEIGHT",  "HEIGHT", "Height (cm)",                     11
)

advs <- vs |>
  derive_vars_merged(dataset_add = adsl, new_vars = adsl_vars,
                     by_vars = exprs(STUDYID, USUBJID)) |>
  derive_vars_dt(new_vars_prefix = "A", dtc = VSDTC) |>
  derive_vars_dy(reference_date = TRTSDT, source_vars = exprs(ADT)) |>
  derive_vars_merged_lookup(dataset_add = param_lookup,
                            by_vars = exprs(VSTESTCD),
                            new_vars = exprs(PARAMCD, PARAM, PARAMN)) |>
  mutate(AVAL = VSSTRESN) |>
  derive_param_bmi(
    by_vars = exprs(STUDYID, USUBJID, !!!adsl_vars, AVISIT, AVISITN),
    weight_code = "WEIGHT", height_code = "HEIGHT",
    constant_by_vars = exprs(USUBJID),
    set_values_to = exprs(PARAMCD = "BMI",
                          PARAM = "Body Mass Index (kg/m^2)",
                          PARAMN = 20)
  ) |>
  derive_param_map(
    by_vars = exprs(STUDYID, USUBJID, !!!adsl_vars, AVISIT, AVISITN),
    set_values_to = exprs(PARAMCD = "MAP",
                          PARAM = "Mean Arterial Pressure (mmHg)",
                          PARAMN = 21)
  ) |>
  derive_var_anrind() |>
  derive_var_ontrtfl(start_date = ADT,
                     ref_start_date = TRTSDT,
                     ref_end_date = TRTEDT) |>
  restrict_derivation(
    derivation = derive_var_extreme_flag,
    args = params(
      by_vars = exprs(STUDYID, USUBJID, PARAMCD),
      order = exprs(ADT, AVISITN),
      new_var = ABLFL,
      mode = "last"
    ),
    filter = !is.na(AVAL) & ADT <= TRTSDT
  ) |>
  derive_var_base(by_vars = exprs(STUDYID, USUBJID, PARAMCD),
                  source_var = AVAL, new_var = BASE) |>
  derive_var_base(by_vars = exprs(STUDYID, USUBJID, PARAMCD),
                  source_var = ANRIND, new_var = BNRIND) |>
  derive_var_chg() |>
  derive_var_pchg() |>
  derive_var_shift(new_var = SHIFT1, from_var = BNRIND, to_var = ANRIND)
```

A complete ADVS in roughly 30 lines. The same skeleton, with `lb` swapped for `vs` and LB-specific parameter lookups, gives you ADLB. With `eg` and ECG parameters, ADEG.

## 18. ADLB-specific considerations

ADLB has a few twists beyond the ADVS pattern:

- **Toxicity grading**: NCI CTCAE-based grades for lab values. Use `derive_var_atoxgr()` with appropriate grade-source datasets
- **Standardization**: SDTM provides LBSTRESN (standardized numeric); use that as AVAL. Don't try to standardize yourself.
- **Multiple normal ranges**: ANRLO/ANRHI can vary by age/sex/lab. SDTM stores age/sex-specific ranges; admiral's `derive_var_anrind()` handles this if you pass the right reference variables.
- **Hy's Law**: a special derivation for hepatotoxicity, with its own admiral vignette ("Hy's Law Implementation")

ADLB construction is a frequent ADaM in safety reporting; spend extra time reading the admiral ADLB vignette when you tackle this.

## 19. ADEG-specific considerations

ECG measurements often have multiple measurements per visit (triplicate ECGs are common). Plan for:

- **ATPT/ATPTN**: timepoint within a visit (TIME ZERO, 1 HOUR POST DOSE, etc.)
- **Averaging or selecting**: clinical convention often takes the mean of triplicate measurements
- **QT corrections**: QTcF (Fridericia) and QTcB (Bazett) are derived parameters; admiral provides `derive_param_qtc()`

```r
adeg <- adeg |>
  derive_param_qtc(
    by_vars = exprs(STUDYID, USUBJID, AVISIT, AVISITN, ATPT),
    method = "Fridericia",          # or "Bazett", "Sagie"
    set_values_to = exprs(PARAMCD = "QTCFR", PARAM = "QT Corrected (Fridericia, msec)")
  )
```

## 20. Key takeaways

- BDS datasets have one row per (subject × parameter × visit/timepoint)
- The canonical workflow has ~13 steps; admiral provides a function for each
- AVAL is the numeric analysis value; AVALC for character; PARAMCD identifies the parameter
- `derive_param_*()` functions add new rows for computed parameters (BMI, MAP, BSA, QTc)
- `derive_var_base()` copies baseline values to every row in the by-group; `derive_var_chg()`/`derive_var_pchg()` derive changes
- ABLFL = "Y" on the baseline rows; ANRIND categorizes vs. reference range; SHIFT shows baseline → on-treatment transitions
- `restrict_derivation()` applies a derivation only to filtered rows; `slice_derivation()` varies the derivation per slice
- ADLB, ADVS, ADEG, ADQS all share this pattern with minor variations

## 21. What's next

Lesson 17 covers **OCCDS ADaMs** — Occurrence Data Structure, used for ADAE (Adverse Events) and ADCM (Concomitant Medications). The shape is different (one row per event/medication rather than per visit), and the key derivations focus on treatment-emergent flags, occurrence flags, and standardized MedDRA/WHODrug queries.

After that, Lesson 18 covers Time-to-Event (ADTTE), and Lesson 19 wraps admiral with advanced patterns.

---

## Self-check questions

1. What's the difference between a BDS dataset and ADSL in terms of shape?
2. Why use `derive_vars_merged_lookup()` instead of `derive_vars_merged()` for parameter lookups?
3. What does `constant_by_vars = exprs(USUBJID)` do in `derive_param_bmi()`?
4. Translate to admiral: "For each subject and parameter, flag the latest pre-treatment row as ABLFL = Y."
5. What's the difference between `restrict_derivation()` and `slice_derivation()`?
6. Why is `AVAL.SYSBP` and `AVAL.DIABP` syntax used in `derive_param_computed()`?

## Glossary

- **BDS** — Basic Data Structure; CDISC convention for long-format ADaMs
- **PARAMCD / PARAM / PARAMN** — Parameter code, label, numeric companion
- **AVAL / AVALC** — Analysis Value (numeric / character)
- **ABLFL** — Baseline Flag (Y / NA); marks the row used as baseline
- **BASE / BASEC** — Baseline value (numeric / character) copied to every row
- **CHG / PCHG** — Change from baseline / Percent change from baseline
- **ANRIND** — Analysis Reference Range Indicator (NORMAL/LOW/HIGH)
- **BNRIND** — Baseline ANRIND
- **SHIFTy** — Shift from baseline to on-treatment reference range
- **ONTRTFL** — On-Treatment Flag
- **ANL01FL** — Generic analysis flag #1; sponsor-specific definition
- **`derive_param_*()`** — Functions that add new parameter rows (BMI, MAP, BSA, QTc, computed)
- **`restrict_derivation()`** — Apply a derivation only to rows matching a filter
- **`slice_derivation()`** — Apply a derivation differently to different data slices
