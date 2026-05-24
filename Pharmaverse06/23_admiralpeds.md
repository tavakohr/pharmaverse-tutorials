# Lesson 23 — `{admiralpeds}`: Pediatrics Extension

**Module**: 5 — ADaM therapeutic area extensions
**Estimated length**: ~20 min spoken
**Prerequisites**: Lessons 14–19

---

## Learning objectives

By the end of this lesson, you will be able to:

1. Recognize what makes pediatric trial ADaMs different — primarily growth standardization
2. Use WHO and CDC reference data bundled in `admiralpeds` for growth-chart derivations
3. Compute age in appropriate units (days, months, years) for different age groups
4. Derive z-scores and percentiles for weight-for-age, height-for-age, BMI-for-age, and similar
5. Apply growth-reference logic that differs by sex
6. Build a pediatric ADVS dataset with growth-chart variables

---

## 1. The pediatric challenge

Adult clinical trials treat age as a continuous variable with relatively narrow distribution (often 18–75 years). Pediatric trials span birth through 18 years, with **age-dependent physiology at every endpoint**:

- A child's "normal" weight depends on age, sex, and developmental stage
- "Normal" height grows over time
- BMI cutoffs that define overweight/obese in adults don't apply directly to children
- Lab reference ranges shift with age

The standard approach: compare each measurement to a **growth reference** specific to the child's age and sex, producing a **z-score** (number of standard deviations from the reference mean) and **percentile** (where in the reference distribution this child sits).

`{admiralpeds}` packages the reference data (WHO and CDC charts) and the functions to compute these standardized metrics. Released in 2024, it's the newest of the admiral TA family.

## 2. Installation and setup

```r
install.packages("admiralpeds")

library(admiral)
library(admiralpeds)
library(pharmaversesdtm)
library(dplyr)
library(lubridate)
library(rlang)
library(stringr)
```

## 3. The bundled reference data

`admiralpeds` ships several reference data tables:

| Dataset | Source | Range |
|---|---|---|
| `who_wt_for_age_boys` / `..._girls` | WHO | Birth to 5 years |
| `who_ht_for_age_boys` / `..._girls` | WHO | Birth to 5 years |
| `who_bmi_for_age_boys` / `..._girls` | WHO | Birth to 5 years |
| `cdc_wtage` | CDC | 2–20 years (US-specific) |
| `cdc_htage` | CDC | 2–20 years |
| `cdc_bmiage` | CDC | 2–20 years |
| `cdc_headcir` | CDC | Birth to 3 years |

Each table has rows indexed by age (in days or months) and sex, with the parameters that define the reference distribution: typically L (Box-Cox transformation parameter), M (median), and S (coefficient of variation) at each age point. This is the standard LMS method for growth charts.

Loading:

```r
who_wt_boys <- admiralpeds::who_wt_for_age_boys
cdc_bmi <- admiralpeds::cdc_bmiage

head(who_wt_boys)
# A tibble with columns: AGEDAYS, L, M, S, ...
```

You can also use other reference sources — International Obesity Task Force, country-specific charts — as long as you assemble them into the same column structure.

## 4. Age computation: the central problem

Pediatric ages need precision. A 6-month-old and a 12-month-old are physiologically different in ways that matter for dose calculations and adverse-event analysis. So age must be computed accurately, often in **days** rather than years.

```r
adsl <- adsl |>
  mutate(
    AGE_DAYS = as.numeric(difftime(TRTSDT, BRTHDT, units = "days")),
    AGE_MONTHS = AGE_DAYS / (365.25 / 12),
    AGE_YEARS = AGE_DAYS / 365.25
  )
```

The reference data is indexed by `AGEDAYS`; you join against it using days-old to get exact reference values.

For neonatal subjects (less than 28 days old), some sponsors use even finer granularity — gestational age, post-conception age. Specialized variables like `GESTAGE`, `PNAAGE` handle this. admiralpeds vignettes cover both.

## 5. Building a pediatric ADVS

Standard ADVS pattern (Lesson 16) with growth-chart additions:

```r
vs <- pharmaversesdtm::vs |> convert_blanks_to_na()
adsl <- pharmaverseadam::adsl

adsl_vars <- exprs(TRTSDT, TRTEDT, BRTHDT, SEX, AGE)

advs <- vs |>
  filter(VSTESTCD %in% c("WEIGHT", "HEIGHT", "BMI")) |>
  derive_vars_merged(
    dataset_add = adsl,
    new_vars = adsl_vars,
    by_vars = exprs(STUDYID, USUBJID)
  ) |>
  derive_vars_dt(new_vars_prefix = "A", dtc = VSDTC) |>
  # Age at this measurement, in days
  mutate(
    AGEDAYS = as.numeric(difftime(ADT, BRTHDT, units = "days"))
  ) |>
  mutate(
    PARAMCD = VSTESTCD,
    PARAM = case_when(
      VSTESTCD == "WEIGHT" ~ "Weight (kg)",
      VSTESTCD == "HEIGHT" ~ "Height (cm)",
      VSTESTCD == "BMI"    ~ "Body Mass Index (kg/m^2)"
    ),
    AVAL = VSSTRESN
  )
```

So far this is standard BDS. The pediatric extension comes next.

## 6. Deriving z-scores

For weight-for-age z-scores, you'd typically use a function like `derive_vars_growth_age()` that:

1. Identifies the appropriate reference (WHO for 0–5 years, CDC for ≥ 2 years; overlap zone you choose)
2. Looks up the L/M/S parameters at the subject's exact AGEDAYS
3. Sex-stratifies the lookup
4. Computes the z-score using the LMS formula:
   - For L ≠ 0: `Z = ((AVAL / M) ^ L − 1) / (L * S)`
   - For L = 0: `Z = ln(AVAL / M) / S`
5. Computes the percentile from the z-score using the standard normal distribution

The current `admiralpeds` API has evolved across versions; consult the package's reference for the exact function name and signature. The conceptual call:

```r
advs <- advs |>
  derive_vars_growth_age(
    by_vars = exprs(STUDYID, USUBJID, AGEDAYS, SEX, PARAMCD),
    metadata = list(
      WEIGHT = bind_rows(
        who_wt_for_age_boys |> mutate(SEX = "M"),
        who_wt_for_age_girls |> mutate(SEX = "F")
      ),
      HEIGHT = bind_rows(
        who_ht_for_age_boys |> mutate(SEX = "M"),
        who_ht_for_age_girls |> mutate(SEX = "F")
      ),
      BMI = bind_rows(
        cdc_bmiage |> mutate(SEX = "M"),
        cdc_bmiage |> mutate(SEX = "F")
      )
    ),
    new_vars = exprs(ZSCORE, PCTL)
  )
```

The result: each row in ADVS now has `ZSCORE` (e.g., `+0.5` means half a standard deviation above the reference median for that age/sex) and `PCTL` (e.g., `69%` means at the 69th percentile).

These z-scores and percentiles become the **analysis variables** in pediatric studies: "change in BMI z-score over 6 months" is a more meaningful endpoint than "change in BMI" because it accounts for the natural growth that would have happened anyway.

## 7. The boundary between WHO and CDC references

The two major reference systems overlap from age 2 to 5 years. Studies typically choose one of:

- **WHO for ≤ 5 years, CDC for > 5 years** — the standard global approach
- **WHO throughout** — international studies, WHO-aligned protocols
- **CDC throughout** — US-only studies, FDA-aligned protocols

`admiralpeds` doesn't force a choice; it provides both and lets you decide. Document your choice in the SAP and apply consistently.

```r
# Implementation pattern: combine and choose by age
combined_wt <- bind_rows(
  who_wt_for_age_boys |> filter(AGEDAYS <= 1826) |> mutate(SEX = "M", SOURCE = "WHO"),
  cdc_wtage          |> filter(AGEDAYS > 1826)  |> mutate(SOURCE = "CDC"),
  who_wt_for_age_girls |> filter(AGEDAYS <= 1826) |> mutate(SEX = "F", SOURCE = "WHO"),
  # ... etc.
)
```

Recording `SOURCE` per row keeps provenance — useful for QC and SAP documentation.

## 8. Age-stratified reference ranges for labs

For laboratory analyses (ADLB), the reference range itself (ANRLO/ANRHI) depends on age. A pediatric Hgb of 11 g/dL is normal for an infant but low for a teenager.

SDTM LB stores age-specific ranges in `LBORNRLO` / `LBORNRHI`, but only if the lab returned them per-subject. If they didn't (lab returned adult-only ranges), you'll need to overwrite with age-appropriate ranges from a reference table.

This is study-specific and not yet handled by a single admiralpeds function. The pattern: build an age-stratified ranges table (sponsor-internal), join onto ADLB, override ANRLO/ANRHI per age band.

## 9. Dose calculations

A pediatric-specific consideration: doses often depend on body weight or body surface area. For trials with weight-based dosing:

- **mg/kg dosing**: a 10 mg/kg dose for a 15 kg child is 150 mg
- **mg/m² dosing**: typical for oncology

The actual administered dose is in EX. But for analyses ("what was the dose per kg at the time of the AE?"), you need to know the subject's weight at the AE time.

```r
# Get latest weight before each AE
adae <- adae |>
  derive_vars_joined(
    dataset_add = advs |> filter(PARAMCD == "WEIGHT"),
    by_vars = exprs(STUDYID, USUBJID),
    order = exprs(ADT),
    new_vars = exprs(WEIGHT_KG = AVAL),
    join_vars = exprs(ADT),
    filter_join = ASTDT >= ADT,
    mode = "last"
  ) |>
  mutate(DOSE_PER_KG = if_else(WEIGHT_KG > 0, EXDOSE / WEIGHT_KG, NA_real_))
```

## 10. Age units and groupings

Pediatric ADSL typically encodes age in days, months, AND years for different audiences:

```r
adsl <- adsl |>
  mutate(
    AGEDAYS = as.numeric(difftime(TRTSDT, BRTHDT, units = "days")),
    AGEMOS = AGEDAYS / (365.25 / 12),
    AGE = floor(AGEDAYS / 365.25),
    AGEU = "YEARS",
    # Pediatric age groups
    AGEGR1 = case_when(
      AGEDAYS < 28        ~ "Neonate (0-27 days)",
      AGEDAYS < 365.25    ~ "Infant (28-364 days)",
      AGEDAYS < 365.25*2  ~ "Toddler (1 year)",
      AGEDAYS < 365.25*12 ~ "Child (2-11 years)",
      AGEDAYS < 365.25*18 ~ "Adolescent (12-17 years)",
      TRUE                ~ "Adult"
    ),
    AGEGR1N = case_when(
      AGEDAYS < 28        ~ 1,
      AGEDAYS < 365.25    ~ 2,
      AGEDAYS < 365.25*2  ~ 3,
      AGEDAYS < 365.25*12 ~ 4,
      AGEDAYS < 365.25*18 ~ 5,
      TRUE                ~ 6
    )
  )
```

Sponsor- and protocol-specific age groupings vary. Some studies use the ICH E11 categories (newborn, infant, toddler, child, adolescent); others use sponsor-defined cuts.

## 11. Body Surface Area (BSA) — pediatric formulas

For weight-based dosing, BSA matters. Several formulas:

- **DuBois & DuBois**: BSA = 0.007184 × (Wt^0.425) × (Ht^0.725)
- **Mosteller**: BSA = sqrt((Ht × Wt) / 3600)
- **Haycock**: BSA = 0.024265 × (Wt^0.5378) × (Ht^0.3964) — preferred for pediatrics

admiral core provides `derive_param_bsa()` which accepts a `method` argument:

```r
advs <- advs |>
  derive_param_bsa(
    by_vars = exprs(STUDYID, USUBJID, AVISIT, AVISITN),
    weight_code = "WEIGHT",
    height_code = "HEIGHT",
    method = "Haycock",
    set_values_to = exprs(
      PARAMCD = "BSA",
      PARAM = "Body Surface Area (m^2) [Haycock]"
    )
  )
```

For pediatrics, Haycock is the typical default; check your SAP.

## 12. Templates

```r
admiralpeds::use_ad_template("adsl", save_path = "./ad_adsl.R")
admiralpeds::use_ad_template("advs", save_path = "./ad_advs.R")
```

The ADVS template specifically walks through the growth-chart pattern with WHO/CDC reference data joining.

## 13. Putting it together: pediatric ADVS skeleton

```r
library(admiral)
library(admiralpeds)
library(dplyr)
library(pharmaversesdtm)

vs <- pharmaversesdtm::vs |> convert_blanks_to_na()
adsl <- pharmaverseadam::adsl

# Reference data
who_wt <- bind_rows(
  who_wt_for_age_boys  |> mutate(SEX = "M"),
  who_wt_for_age_girls |> mutate(SEX = "F")
)
cdc_bmi_full <- bind_rows(
  cdc_bmiage |> mutate(SEX = "M"),
  cdc_bmiage |> mutate(SEX = "F")
)

# Build ADVS with growth derivations
advs <- vs |>
  filter(VSTESTCD %in% c("WEIGHT", "HEIGHT", "BMI")) |>
  derive_vars_merged(
    dataset_add = adsl,
    new_vars = exprs(TRTSDT, BRTHDT, SEX, AGE),
    by_vars = exprs(STUDYID, USUBJID)
  ) |>
  derive_vars_dt(new_vars_prefix = "A", dtc = VSDTC) |>
  mutate(
    AGEDAYS = as.numeric(difftime(ADT, BRTHDT, units = "days")),
    PARAMCD = VSTESTCD,
    PARAM = paste(VSTEST, paste0("(", VSORRESU, ")")),
    AVAL = VSSTRESN
  ) |>
  derive_vars_dy(reference_date = TRTSDT, source_vars = exprs(ADT))

# Compute z-scores (illustrative — exact function name varies by version)
advs <- advs |>
  left_join(
    who_wt |> select(AGEDAYS, SEX, L, M, S),
    by = c("AGEDAYS", "SEX")
  ) |>
  mutate(
    ZSCORE = if_else(
      PARAMCD == "WEIGHT" & !is.na(L),
      case_when(
        L != 0 ~ ((AVAL / M)^L - 1) / (L * S),
        L == 0 ~ log(AVAL / M) / S
      ),
      NA_real_
    ),
    PCTL = if_else(!is.na(ZSCORE), pnorm(ZSCORE) * 100, NA_real_)
  )

# Standard BDS finalization
advs <- advs |>
  restrict_derivation(
    derivation = derive_var_extreme_flag,
    args = params(
      by_vars = exprs(STUDYID, USUBJID, PARAMCD),
      order = exprs(ADT),
      new_var = ABLFL,
      mode = "last"
    ),
    filter = !is.na(AVAL) & ADT <= TRTSDT
  ) |>
  derive_var_base(by_vars = exprs(STUDYID, USUBJID, PARAMCD),
                  source_var = AVAL, new_var = BASE) |>
  derive_var_base(by_vars = exprs(STUDYID, USUBJID, PARAMCD),
                  source_var = ZSCORE, new_var = BASEZSCORE) |>
  derive_var_chg() |>
  mutate(CHG_ZSCORE = ZSCORE - BASEZSCORE)

glimpse(advs)
```

The headline analyses for many pediatric trials are summarized in terms of `ZSCORE` and `CHG_ZSCORE` rather than raw `AVAL` and `CHG` — because the age-standardization removes the confound of "this child is just naturally growing."

## 14. ICH E11(R1) and regulatory considerations

ICH E11(R1) is the FDA/EMA guideline for pediatric clinical investigation. It establishes:

- Pediatric age categories
- Special considerations for safety and efficacy assessment in children
- Expectations for adolescent inclusion in adult studies (often called "pediatric extrapolation")

`{admiralpeds}` is designed to align with E11(R1) expectations; the package's vignettes reference the relevant guidance documents. Stay current with the guideline — it's amended periodically, and FDA expectations for pediatric submissions evolve.

## 15. Maintenance and team

`{admiralpeds}` first released in 2024 with contributions from Pfizer, Roche, GSK, and other pediatric-active sponsors. The package is in the 0.x version line — production-usable but still evolving. New growth references, more standardized derivation helpers, and expanded vignettes appear with each release.

## 16. Key takeaways

- Pediatric ADaMs need **age- and sex-standardized growth metrics** rather than raw measurements
- `{admiralpeds}` bundles WHO (0–5 years) and CDC (2–20 years) reference data tables
- Age is computed in days for precise reference lookup, then optionally summarized in months or years
- z-scores and percentiles come from the LMS method using L/M/S parameters from the reference tables
- BSA derivations should typically use the Haycock formula for pediatrics, not DuBois
- Dose-per-kg derivations require linking the most recent weight to AE/EX events using `derive_vars_joined()`
- Templates available for pediatric ADSL and ADVS

## 17. What's next

Lesson 24 — the final TA extension lesson — covers **`{admiralmetabolic}`**, which targets metabolic and cardiovascular trials: obesity, type 2 diabetes, NAFLD. It adds computed parameters for HOMA-IR, FLI, NAFLD scores, and related metabolic derivations.

After Lesson 24, Module 5 is complete and we enter Module 6 — the Cardinal-future TLG stack with `{cards}` and `{gtsummary}` and `{cardinal}`.

---

## Self-check questions

1. Why are z-scores preferred to raw measurements for pediatric analysis?
2. What's the LMS method, and what do L, M, S stand for?
3. Why do most pediatric studies use WHO references for ≤ 5 years and CDC for older?
4. Which BSA formula is typically used for pediatrics, and why?
5. Translate: compute age at the time of an AE in days, given BRTHDT and AESTDT.
6. What's the practical difference between AGEDAYS, AGEMOS, and AGE in a pediatric ADSL?

## Glossary

- **Growth chart** — Reference distribution of a measurement (weight, height, BMI) by age and sex
- **z-score** — Number of standard deviations above or below the reference median
- **Percentile** — Position in the reference distribution (e.g., 50th percentile = median)
- **LMS method** — Standard growth-chart statistical method using L (skewness), M (median), S (CV)
- **WHO Growth Standards** — World Health Organization reference, 0–5 years
- **CDC Growth Charts** — US Centers for Disease Control reference, 2–20 years
- **AGEDAYS / AGEMOS / AGE** — Age in days / months / years (the most common pediatric age units)
- **ICH E11(R1)** — Guideline for clinical investigation in pediatric populations
- **Pediatric extrapolation** — Use of adult data to support pediatric efficacy claims
- **BSA** — Body Surface Area; Haycock formula typically preferred for pediatrics
- **Gestational age** — Age from conception; used for neonatal analyses
