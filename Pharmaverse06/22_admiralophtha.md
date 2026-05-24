# Lesson 22 — `{admiralophtha}`: Ophthalmology Extension

**Module**: 5 — ADaM therapeutic area extensions
**Estimated length**: ~20 min spoken
**Prerequisites**: Lessons 14–19 (admiral core)

---

## Learning objectives

By the end of this lesson, you will be able to:

1. Recognize the ophthalmology ADaM landscape: ADOE, ADBCVA, ADVFQ, ADIOP
2. Use `derive_var_studyeye()` to identify each subject's study eye
3. Use `derive_var_afeye()` to flag observations as STUDY EYE / FELLOW EYE / BOTH EYES
4. Apply LogMAR ↔ ETDRS conversion for BCVA outcomes
5. Use `derive_var_bcvacritxfl()` to derive criterion flags for BCVA change endpoints
6. Understand the "study eye design" considerations driving the ophthalmology ADaM split

---

## 1. The ophthalmology challenge

Ophthalmology studies have an unusual structural feature: **most measurements come in pairs — one per eye.** Vital signs and labs are subject-level. Ophthalmic measurements (BCVA, IOP, retinal thickness) are eye-level.

The CDISC convention: SDTM stores eye laterality in `xxLAT` (e.g., `OELAT`) with values `"LEFT"`, `"RIGHT"`, or `"BILATERAL"`. ADaM needs to know which eye is the **study eye** (the one being treated or evaluated as the primary endpoint) versus the **fellow eye** (the control or non-study eye).

For most clinical analyses, only the study eye matters. But you derive both for completeness, and you handle the case where some patients have bilateral involvement (both eyes are study eyes).

`{admiralophtha}` adds this domain-specific logic on top of admiral core.

## 2. The ophthalmology ADaM partition

admiralophtha recommends partitioning ophthalmology data across multiple ADaMs:

| ADaM | Content |
|---|---|
| **ADOE** | General miscellaneous ophthalmology tests — exams not used for primary efficacy |
| **ADBCVA** | Best Corrected Visual Acuity (BCVA) data only — typically the primary/secondary endpoint |
| **ADIOP** | Intraocular pressure (if a study endpoint) |
| **ADVFQ** | Visual Functioning Questionnaire (NEI VFQ-25) responses |

The rationale: BCVA and similar endpoints require extensive custom programming (criterion flags for "gain of N letters", responder analyses). Keeping them in their own dataset isolates that programming from the simpler ADOE.

For routine studies the partition is more granular than necessary — many sponsors put everything in ADOE plus a separate ADBCVA. For studies with multiple eye endpoints (e.g., diabetic retinopathy trials with BCVA, OCT thickness, fluorescein angiography), the granularity pays off.

## 3. Setup

```r
library(admiral)
library(admiralophtha)
library(admiraldev)
library(dplyr)
library(stringr)
library(pharmaversesdtm)
library(pharmaverseadam)

# Source data
data("oe_ophtha", package = "pharmaversesdtm")   # Ophthalmic Examinations
data("admiralophtha_adsl", package = "pharmaverseadam")

oe <- oe_ophtha |> convert_blanks_to_na()
adsl <- admiralophtha_adsl
```

## 4. Identifying the study eye

The starting concept: every subject has one (or both) eyes designated as the study eye. In a unilateral study, the protocol specifies which eye. In a bilateral study, both eyes may be study eyes.

CDISC convention stores this as `STUDYEYE` in ADSL with values `"LEFT"`, `"RIGHT"`, or `"BILATERAL"`. The source might be:

- Directly recorded in DM or SC (Supplemental Subject Characteristics)
- Derived from a specific clinical assessment indicating worse-eye selection
- Pre-specified by the randomization

`derive_var_studyeye()` does the derivation from SC:

```r
adsl <- adsl |>
  derive_var_studyeye(
    dataset_add = sc,
    by_vars = exprs(STUDYID, USUBJID),
    filter_add = SCTESTCD == "FOCID"     # "Focus Identification" test code
  )
```

If your source data captures study eye differently (e.g., as a CRF field copied directly to DM), you can populate STUDYEYE manually:

```r
adsl <- adsl |>
  mutate(STUDYEYE = case_when(
    /* logic per your spec */
  ))
```

The end result is the same: `STUDYEYE` in ADSL, ready for downstream use.

## 5. Affected Eye (AFEYE)

For each row in an eye-level ADaM, you need to know whether the observation pertains to the study eye, the fellow eye, or both. CDISC convention uses `AFEYE` ("Affected Eye") with values `"STUDY EYE"`, `"FELLOW EYE"`, `"BOTH EYES"`.

The derivation is non-trivial because it depends on the interaction of `STUDYEYE` from ADSL and `xxLAT` from the observation. `derive_var_afeye()` automates it:

```r
adoe <- oe |>
  derive_vars_merged(
    dataset_add = adsl,
    new_vars = exprs(STUDYEYE),
    by_vars = exprs(STUDYID, USUBJID)
  ) |>
  derive_var_afeye(
    loc_var = OELOC,
    lat_var = OELAT,
    loc_vals = "EYE"
  )
```

The function's logic:

- If `OELOC == "EYE"` and `OELAT == "BILATERAL"` and STUDYEYE is non-missing → `AFEYE = "BOTH EYES"`
- If `OELAT` matches `STUDYEYE` (LEFT-LEFT or RIGHT-RIGHT) → `AFEYE = "STUDY EYE"`
- If `STUDYEYE == "BILATERAL"` and `OELAT` is non-missing → `AFEYE = "STUDY EYE"`
- If `OELAT` differs from `STUDYEYE` (LEFT-RIGHT or RIGHT-LEFT) → `AFEYE = "FELLOW EYE"`
- Otherwise → NA

For studies where `OELOC` and `OELAT` use non-standard values, the `loc_vals` and `lat_vals` arguments let you override.

After this, downstream analyses can filter `AFEYE == "STUDY EYE"` to focus on the relevant eye.

## 6. Building ADOE — the general ophthalmology dataset

ADOE follows the BDS pattern from Lesson 16, with eye-specific additions:

```r
adoe <- oe |>
  derive_vars_merged(
    dataset_add = adsl,
    new_vars = exprs(STUDYEYE, TRTSDT, TRTEDT),
    by_vars = exprs(STUDYID, USUBJID)
  ) |>
  derive_var_afeye(loc_var = OELOC, lat_var = OELAT) |>
  derive_vars_dt(new_vars_prefix = "A", dtc = OEDTC) |>
  derive_vars_dy(reference_date = TRTSDT, source_vars = exprs(ADT))
```

Then a parameter lookup specific to ophthalmology tests:

```r
param_lookup <- tribble(
  ~OETESTCD,  ~PARAMCD, ~PARAM,
  "IOP",      "IOP01",  "Intraocular Pressure (mmHg)",
  "CMT",      "CMT01",  "Central Macular Thickness (microns)",
  "CRT",      "CRT01",  "Central Retinal Thickness (microns)"
)

adoe <- adoe |>
  derive_vars_merged_lookup(
    dataset_add = param_lookup,
    by_vars = exprs(OETESTCD),
    new_vars = exprs(PARAMCD, PARAM)
  ) |>
  mutate(AVAL = OESTRESN)
```

From here, baseline derivation, change-from-baseline, and ANL01FL follow the standard BDS pattern.

## 7. Pre-to-Post-Dose IOP Difference

A common ophthalmology derivation: for each visit, compute the **change in IOP from pre-dose to post-dose** within that same visit (a same-day comparison rather than the typical baseline-to-visit). admiralophtha provides the building blocks:

```r
adoe_pre_post <- adoe |>
  filter(PARAMCD %in% c("IOP01_PRE", "IOP01_POST")) |>
  pivot_wider(
    id_cols = c(STUDYID, USUBJID, AVISIT, AVISITN, AFEYE),
    names_from = PARAMCD,
    values_from = AVAL
  ) |>
  mutate(
    AVAL = IOP01_POST - IOP01_PRE,
    PARAMCD = "IOPDIFF",
    PARAM = "IOP Pre to Post-Dose Difference (mmHg)"
  )

adoe <- bind_rows(adoe, adoe_pre_post)
```

This pivots wide to compute the difference, then stacks the new parameter back into the long ADOE. The `vignette("adoe", package = "admiralophtha")` walks through this in detail.

## 8. BCVA — the visual acuity primary endpoint

BCVA is the most common primary endpoint in ophthalmology. It's measured in two scales:

- **LogMAR**: logarithm of the Minimum Angle of Resolution. Lower = better. Normal acuity = 0.0; legal blindness = 1.0.
- **ETDRS letters**: number of letters read on a standardized chart. Higher = better. Range typically 0–100.

The conversion (admiralophtha-specific helpers):

```r
# LogMAR → ETDRS
etdrs_score <- convert_logmar_to_etdrs(value = 0.3)
# Formula: ETDRS = -(logMAR - 1.7) / 0.02

# ETDRS → LogMAR
logmar_score <- convert_etdrs_to_logmar(value = 70)
```

Many studies collect ETDRS letters at sites; the protocol then specifies whether the primary analysis uses ETDRS or LogMAR. admiralophtha gives you both directions.

## 9. ADBCVA — the BCVA-specific dataset

ADBCVA builds the BCVA-only analysis dataset. The structure mirrors ADOE but with BCVA-specific parameters and criterion flags.

```r
adbcva <- oe |>
  filter(OETESTCD == "VACSCORE") |>           # visual acuity test code
  derive_vars_merged(dataset_add = adsl,
                     new_vars = exprs(STUDYEYE, TRTSDT, TRTEDT),
                     by_vars = exprs(STUDYID, USUBJID)) |>
  derive_var_afeye(loc_var = OELOC, lat_var = OELAT) |>
  derive_vars_dt(new_vars_prefix = "A", dtc = OEDTC) |>
  mutate(
    PARAMCD = case_when(
      OEMETHOD == "ETDRS"  ~ "BCVAETDRS",
      OEMETHOD == "LOGMAR" ~ "BCVALMAR",
      TRUE                 ~ NA_character_
    ),
    PARAM = case_when(
      PARAMCD == "BCVAETDRS" ~ "BCVA (ETDRS letters)",
      PARAMCD == "BCVALMAR"  ~ "BCVA (logMAR)"
    ),
    AVAL = OESTRESN
  )
```

If the study captures only one scale, you'd typically derive the other via the conversion functions:

```r
# Build complementary parameter
adbcva_alt <- adbcva |>
  filter(PARAMCD == "BCVAETDRS") |>
  mutate(
    PARAMCD = "BCVALMAR",
    PARAM = "BCVA (logMAR, derived)",
    AVAL = convert_etdrs_to_logmar(AVAL)
  )

adbcva <- bind_rows(adbcva, adbcva_alt)
```

Now you have both scales available; analyses pick by PARAMCD.

## 10. BCVA criterion flags

The headline BCVA analyses are typically:

- "Proportion of subjects gaining ≥ 15 ETDRS letters at Week 52"
- "Proportion of subjects losing ≥ 15 letters"
- "Mean change from baseline"
- Various secondary thresholds (≥ 5, ≥ 10, ≥ 30 letters)

Each "gain/loss of N letters" analysis needs a binary subject-level flag. Multiple flags = multiple `CRITxFL` pairs in ADBCVA.

`derive_var_bcvacritxfl()` automates this:

```r
adbcva <- adbcva |>
  derive_var_bcvacritxfl(
    crit_var = exprs(CHG),                # the change-from-baseline column
    bcva_ranges = list(
      list(name = "≥ 15 letter gain",       lower = 15,  upper = Inf),
      list(name = "≥ 10 letter gain",       lower = 10,  upper = Inf),
      list(name = "≥ 5 letter gain",        lower = 5,   upper = Inf),
      list(name = "Loss of < 15 letters",  lower = -14, upper = Inf),
      list(name = "≥ 15 letter loss",      lower = -Inf, upper = -15)
    )
  )
```

(The exact API has evolved across versions; consult `?derive_var_bcvacritxfl` for your installed version.)

The function adds pairs of variables: `CRIT1` (description), `CRIT1FL` (Y/N), `CRIT2`, `CRIT2FL`, etc. — one pair per criterion, in the order specified. Each `CRITxFL` is `"Y"` when the row's change meets the criterion, `NA` otherwise (or `"N"`, depending on convention).

Downstream gtsummary or tern tables tabulate the proportion of subjects with `CRITxFL == "Y"` to produce the response-rate output.

## 11. ADVFQ — Visual Functioning Questionnaire

The NEI VFQ-25 (National Eye Institute Visual Function Questionnaire) is a 25-item patient-reported outcome instrument commonly used in ophthalmology. ADVFQ stores the responses and derived subscale scores.

The structure is BDS-style: one row per (subject × question × visit), plus derived rows for subscales (overall score, distance vision subscale, ocular pain subscale, etc.).

Computing subscale scores follows the NEI scoring manual: recode item responses to 0–100, average within subscale, average subscales for overall. `admiralophtha` provides templates and a vignette walking the standard scoring.

For studies using VFQ, the build is mostly transformation logic (recoding, averaging) on top of the standard BDS skeleton. No new admiral patterns are required — just careful implementation of the scoring rules.

## 12. The ADSL extensions for ophthalmology

Beyond `STUDYEYE`, ophthalmology ADSL often has:

- `STUDYELD` — study eye laterality at start of study (some studies allow it to change)
- `BASELINE_BCVAxx` — baseline BCVA per eye, often saved subject-level for convenience
- Glaucoma-specific or AMD-specific baseline categorizations

These are study-specific; you derive them in your standard ADSL script using admiral merges and the spec's logic.

## 13. Putting it together: ADBCVA skeleton

```r
library(admiral)
library(admiralophtha)
library(dplyr)

adsl <- pharmaverseadam::admiralophtha_adsl
oe   <- pharmaversesdtm::oe_ophtha |> convert_blanks_to_na()

adbcva <- oe |>
  filter(OETESTCD == "VACSCORE") |>
  derive_vars_merged(
    dataset_add = adsl,
    new_vars = exprs(STUDYEYE, TRTSDT, TRTEDT, TRT01A, TRT01P),
    by_vars = exprs(STUDYID, USUBJID)
  ) |>
  derive_var_afeye(loc_var = OELOC, lat_var = OELAT) |>
  derive_vars_dt(new_vars_prefix = "A", dtc = OEDTC) |>
  derive_vars_dy(reference_date = TRTSDT, source_vars = exprs(ADT)) |>
  mutate(
    PARAMCD = "BCVAETDRS",
    PARAM = "BCVA (ETDRS letters)",
    AVAL = OESTRESN
  ) |>
  # Baseline flag (last pre-treatment per subject × eye × parameter)
  restrict_derivation(
    derivation = derive_var_extreme_flag,
    args = params(
      by_vars = exprs(STUDYID, USUBJID, AFEYE, PARAMCD),
      order = exprs(ADT),
      new_var = ABLFL,
      mode = "last"
    ),
    filter = !is.na(AVAL) & ADT <= TRTSDT
  ) |>
  derive_var_base(by_vars = exprs(STUDYID, USUBJID, AFEYE, PARAMCD),
                  source_var = AVAL, new_var = BASE) |>
  derive_var_chg() |>
  filter(AFEYE == "STUDY EYE")    # focus on the study eye for primary analyses

# Add criterion flags
adbcva <- adbcva |>
  derive_var_bcvacritxfl(
    crit_var = exprs(CHG),
    bcva_ranges = list(
      list(name = ">= 15 letter gain", lower = 15, upper = Inf),
      list(name = ">= 10 letter gain", lower = 10, upper = Inf),
      list(name = ">= 5 letter gain",  lower = 5,  upper = Inf)
    )
  ) |>
  derive_var_obs_number(
    new_var = ASEQ,
    by_vars = exprs(STUDYID, USUBJID),
    order = exprs(AFEYE, PARAMCD, ADT, AVISITN)
  )

glimpse(adbcva)
```

## 14. Templates

```r
admiralophtha::use_ad_template("adoe",   save_path = "./ad_adoe.R")
admiralophtha::use_ad_template("adbcva", save_path = "./ad_adbcva.R")
admiralophtha::use_ad_template("advfq",  save_path = "./ad_advfq.R")
```

Each is runnable against pharmaversesdtm/pharmaverseadam test data.

## 15. Maintenance and team

`{admiralophtha}` was first released in 2023 as a Roche + Novartis collaboration — both major ophthalmology sponsors. The 1.x line has been stable since 2024. Active areas: more BCVA criterion-flag conveniences, VFQ improvements, OCT-derived endpoints.

## 16. Key takeaways

- `{admiralophtha}` adds ophthalmology-specific functions on top of admiral core
- ADaM partition: ADOE (general ophthalmic) + ADBCVA (visual acuity) + ADIOP (intraocular pressure, optional) + ADVFQ (questionnaire)
- `derive_var_studyeye()` derives `STUDYEYE` in ADSL from SC or another source
- `derive_var_afeye()` derives `AFEYE` ("STUDY EYE" / "FELLOW EYE" / "BOTH EYES") for each observation
- `convert_logmar_to_etdrs()` and `convert_etdrs_to_logmar()` handle BCVA scale conversions
- `derive_var_bcvacritxfl()` derives criterion flag pairs (CRIT1/CRIT1FL) for the standard "gain/loss of N letters" analyses
- Most analyses filter to `AFEYE == "STUDY EYE"` for the primary endpoint

## 17. What's next

Lesson 23 covers **`{admiralpeds}`** — pediatrics. The defining feature: **age- and sex-standardized growth metrics** (z-scores, percentiles) computed against WHO or CDC reference data. The package ships reference data tables and functions for height-for-age, weight-for-age, BMI-for-age, and similar derivations.

---

## Self-check questions

1. Why is the ophthalmology ADaM partition split across ADOE, ADBCVA, ADVFQ?
2. What does AFEYE represent and what are its possible values?
3. Translate to admiralophtha: "For each BCVA row, flag whether the change from baseline is at least a 15-letter gain."
4. Given LogMAR = 0.5, what's the equivalent ETDRS score? (Use the formula in `convert_logmar_to_etdrs`)
5. Why is the baseline derivation in ADBCVA grouped by `AFEYE` as well as PARAMCD?
6. Which ophthalmology study domain would you typically capture intraocular pressure measurements in?

## Glossary

- **Study eye** — The eye designated as the primary endpoint per protocol
- **Fellow eye** — The other (non-study) eye
- **STUDYEYE** — ADSL variable: "LEFT" / "RIGHT" / "BILATERAL"
- **AFEYE** — Affected Eye flag: "STUDY EYE" / "FELLOW EYE" / "BOTH EYES"
- **BCVA** — Best Corrected Visual Acuity
- **LogMAR** — Logarithm of Minimum Angle of Resolution; lower = better
- **ETDRS** — Early Treatment Diabetic Retinopathy Study chart; standardized acuity chart with letter scoring
- **IOP** — Intraocular Pressure
- **OCT** — Optical Coherence Tomography; retinal thickness imaging
- **NEI VFQ-25** — National Eye Institute Visual Functioning Questionnaire (25 items)
- **CRITxFL** — Criterion flag pair: CRITx (description) + CRITxFL (Y/N for each subject)
- **ADOE / ADBCVA / ADVFQ / ADIOP** — Ophthalmology ADaM datasets
- **`derive_var_studyeye()`** — Derive STUDYEYE in ADSL
- **`derive_var_afeye()`** — Derive AFEYE per row based on STUDYEYE and OELAT
- **`derive_var_bcvacritxfl()`** — Derive criterion flag pairs for BCVA change endpoints
- **`convert_logmar_to_etdrs()` / `convert_etdrs_to_logmar()`** — BCVA scale conversions
