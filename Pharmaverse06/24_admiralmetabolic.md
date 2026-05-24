# Lesson 24 — `{admiralmetabolic}`: Metabolic & Cardiovascular Extension

**Module**: 5 — ADaM therapeutic area extensions
**Estimated length**: ~18 min spoken
**Prerequisites**: Lessons 14–19

---

## Learning objectives

By the end of this lesson, you will be able to:

1. Recognize the metabolic ADaM landscape: ADVS with waist/hip metrics, ADLB with metabolic indices
2. Use `derive_param_computed()` with metabolic formulas to add HOMA-IR, FLI, NAFLD scores
3. Cross-derive parameters across ADaMs (e.g., bring BMI from ADVS into ADLB for FLI computation)
4. Apply the metabolic ADLB workflow for obesity, NAFLD, and diabetes trials
5. Understand where admiralmetabolic fits among the TA extensions (newest, focused on obesity initially)

---

## 1. The metabolic study context

Metabolic trials (obesity, type 2 diabetes, NAFLD, dyslipidemia, cardiovascular risk) share an analysis signature:

- Continuous **anthropometric measurements** matter heavily — weight, waist circumference, BMI, waist-to-hip ratio
- **Composite scores** from lab values — HOMA-IR (insulin resistance), FLI (Fatty Liver Index), NAFLD scores
- **Cross-ADaM derivations** — combining ADVS metrics (BMI, WSTCIR) with ADLB values (triglycerides, GGT, insulin, glucose) to compute scores
- **Long durations** — these are often chronic-disease trials measured over months to years

`{admiralmetabolic}` was kicked off in 2024 with an initial focus on **obesity**. Subsequent releases extend to diabetes and NAFLD. The package complements admiral; you load both together.

## 2. Installation

```r
install.packages("admiralmetabolic")

library(admiral)
library(admiralmetabolic)
library(dplyr)
library(pharmaversesdtm)
library(pharmaverseadam)
```

## 3. Metabolic-flavored ADVS

For metabolic trials, ADVS picks up several beyond-standard parameters:

- **WSTCIR** — waist circumference (cm)
- **HIPCIR** — hip circumference (cm)
- **WTHIRATIO** — waist-to-hip ratio (derived)
- **BMI** — body mass index (already covered by admiral core `derive_param_bmi()`)
- **WSTBMI** — waist-to-BMI ratio (some studies)

Most of these are raw values from VS; some are computed parameters. The pattern is standard BDS (Lesson 16):

```r
advs <- vs |>
  filter(VSTESTCD %in% c("WEIGHT", "HEIGHT", "WSTCIR", "HIPCIR")) |>
  derive_vars_merged(dataset_add = adsl, new_vars = exprs(TRTSDT, TRTEDT),
                     by_vars = exprs(STUDYID, USUBJID)) |>
  derive_vars_dt(new_vars_prefix = "A", dtc = VSDTC) |>
  mutate(
    PARAMCD = VSTESTCD,
    PARAM = case_when(
      VSTESTCD == "WEIGHT" ~ "Weight (kg)",
      VSTESTCD == "HEIGHT" ~ "Height (cm)",
      VSTESTCD == "WSTCIR" ~ "Waist Circumference (cm)",
      VSTESTCD == "HIPCIR" ~ "Hip Circumference (cm)"
    ),
    AVAL = VSSTRESN
  ) |>
  # Add BMI
  derive_param_bmi(
    by_vars = exprs(STUDYID, USUBJID, AVISIT, AVISITN),
    weight_code = "WEIGHT",
    height_code = "HEIGHT",
    constant_by_vars = exprs(USUBJID),
    set_values_to = exprs(PARAMCD = "BMI", PARAM = "Body Mass Index (kg/m^2)")
  ) |>
  # Add Waist-to-Hip Ratio as a custom computed parameter
  derive_param_computed(
    by_vars = exprs(STUDYID, USUBJID, AVISIT, AVISITN),
    parameters = c("WSTCIR", "HIPCIR"),
    set_values_to = exprs(
      AVAL = AVAL.WSTCIR / AVAL.HIPCIR,
      PARAMCD = "WTHIRATIO",
      PARAM = "Waist-to-Hip Ratio"
    )
  )
```

`derive_param_computed()` is the general admiral function for "add a new parameter as a formula of existing parameters." We saw it in Lesson 16; it's the workhorse for metabolic studies because so many endpoints are computed.

## 4. Metabolic-flavored ADLB

The bigger work is in ADLB. The standard BDS pattern applies, plus several computed metabolic indices.

### HOMA-IR (Homeostasis Model Assessment of Insulin Resistance)

Formula: `HOMA-IR = (Insulin × Glucose) / 22.5`, where insulin is in mIU/L and glucose in mmol/L.

```r
adlb <- adlb |>
  derive_param_computed(
    by_vars = exprs(STUDYID, USUBJID, AVISIT, AVISITN, ADT, ADY),
    parameters = c("INSULIN", "GLUC"),
    set_values_to = exprs(
      AVAL = AVAL.INSULIN * AVAL.GLUC / 22.5,
      PARAMCD = "HOMAIR",
      PARAM = "Homeostasis Model Assessment - Insulin Resistance",
      PARAMN = 10
    )
  )
```

For each (subject × visit), if both INSULIN and GLUC rows exist, a new HOMAIR row is added. HOMA-IR > 2.5 is a common threshold for insulin resistance.

### FLI (Fatty Liver Index)

A more complex score requiring data from multiple ADaMs:

```
Lambda = 0.953 × ln(TRIG) + 0.139 × BMI + 0.718 × ln(GGT) + 0.053 × WSTCIR - 15.745
FLI = (e^Lambda / (1 + e^Lambda)) × 100
```

Inputs: TRIG (triglycerides) and GGT (gamma-glutamyl transferase) from ADLB; BMI and WSTCIR from ADVS. So you have to **first merge BMI and WSTCIR into ADLB** before computing FLI.

```r
# Bring BMI and WSTCIR from ADVS into ADLB
adlb <- adlb |>
  derive_vars_transposed(
    dataset_merge = advs,
    by_vars = exprs(STUDYID, USUBJID, ADT),
    key_var = PARAMCD,
    value_var = AVAL,
    filter = PARAMCD %in% c("BMI", "WSTCIR")
  )
# Now adlb has BMI and WSTCIR columns added where the date matches a visit

# Derive FLI
adlb <- adlb |>
  derive_param_computed(
    by_vars = exprs(STUDYID, USUBJID, AVISIT, AVISITN, ADT, ADY, BMI, WSTCIR),
    parameters = c("TRIG", "GGT"),
    set_values_to = exprs(
      AVAL = {
        lambda <- 0.953 * log(AVAL.TRIG) + 0.139 * BMI +
                  0.718 * log(AVAL.GGT) + 0.053 * WSTCIR - 15.745
        (exp(lambda) / (1 + exp(lambda))) * 100
      },
      PARAMCD = "FLI",
      PARAM = "Fatty Liver Index",
      PARAMN = 11
    )
  )
```

The `set_values_to = exprs(AVAL = { ... })` allows arbitrary R expression inside `{ }`. Inside, `AVAL.TRIG` and `AVAL.GGT` are admiral's substitutions for "this row's TRIG value" and "this row's GGT value." `BMI` and `WSTCIR` are the columns we merged in from ADVS.

The resulting FLI rows give a per-visit Fatty Liver Index. Cutoffs: FLI < 30 rules out fatty liver; FLI ≥ 60 strongly suggests fatty liver disease.

### NAFLD Score, HSI, and other indices

Similar patterns apply to:

- **NAFLD Fibrosis Score** — uses age, BMI, IFG (impaired fasting glucose) flag, AST/ALT ratio, platelets, albumin
- **HSI** (Hepatic Steatosis Index): `HSI = 8 × (ALT/AST) + BMI + (2 if female) + (2 if diabetes)`
- **TyG Index** (Triglyceride-Glucose): `TyG = ln(TG × FG / 2)`, a surrogate marker for insulin resistance

The pattern is always: gather inputs (possibly from multiple ADaMs), apply the formula, add as a new PARAMCD using `derive_param_computed()`.

The `{admiralmetabolic}` vignette "Creating a Metabolic ADLB ADaM" shows several worked examples. Read it once when you start a metabolic project; you'll reuse the templates extensively.

## 5. Templates

```r
admiralmetabolic::use_ad_template("adsl", save_path = "./ad_adsl.R")
admiralmetabolic::use_ad_template("advs", save_path = "./ad_advs.R")
admiralmetabolic::use_ad_template("adlb", save_path = "./ad_adlb.R")
```

The ADLB template is the most metabolic-specific, walking through several index derivations on test data.

## 6. Cross-ADaM data flow

A subtle architectural point: metabolic ADLB depends on ADVS being built first. The pipeline orders matter:

```
ADSL  →  ADVS (with BMI, WSTCIR computed)  →  ADLB (FLI uses BMI, WSTCIR)
```

If you regenerate ADVS, you must regenerate ADLB. Track this in your project's build script — many sponsors use a `targets` pipeline (the {targets} R package) to manage this automatically.

For larger projects, ADaM build dependencies can resemble a DAG (Directed Acyclic Graph): some ADaMs feed others. Tools like `{targets}` or just a numbered set of R scripts (`01_adsl.R`, `02_advs.R`, `03_adlb.R`) make the order explicit.

## 7. Subject-level "responder" flags for metabolic trials

A defining outcome in obesity trials: **5% weight loss responder** or **10% weight loss responder**. CDISC convention encodes this as a criterion flag in ADVS (per Lesson 16's CRITxFL pattern) or as a subject-level flag in ADSL.

```r
# Derive 5% weight loss at Week 52
adsl <- adsl |>
  derive_vars_merged(
    dataset_add = advs |>
      filter(PARAMCD == "WEIGHT" & AVISITN == 52 & ANL01FL == "Y"),
    by_vars = exprs(STUDYID, USUBJID),
    new_vars = exprs(WEIGHT_W52 = AVAL, BASE_WEIGHT = BASE)
  ) |>
  mutate(
    PCT_LOSS = (WEIGHT_W52 - BASE_WEIGHT) / BASE_WEIGHT * 100,
    RESP5FL = if_else(PCT_LOSS <= -5, "Y", NA_character_),
    RESP10FL = if_else(PCT_LOSS <= -10, "Y", NA_character_)
  )
```

These ADSL flags drive the primary efficacy summary: "% subjects with ≥ 5% weight loss at Week 52 by treatment arm."

## 8. Time-to-event for metabolic endpoints

Some metabolic trials use time-to-event endpoints — typically "time to first diabetes diagnosis" in prevention trials, or "time to first major adverse cardiovascular event (MACE)" in cardiovascular outcome trials.

These follow the standard admiral ADTTE pattern from Lesson 18:

```r
mace_event <- event_source(
  dataset_name = "adae",
  filter = AESOC == "Cardiac disorders" & AESER == "Y" &
           AEDECOD %in% c("Myocardial infarction", "Stroke",
                          "Cardiovascular death"),
  date = ASTDT,
  set_values_to = exprs(EVNTDESC = "MACE EVENT",
                        SRCDOM = "ADAE", SRCVAR = "ASTDT")
)
```

No new admiralmetabolic functions needed — the source-object pattern from admiral core handles it.

## 9. ADSL extensions for metabolic studies

Beyond standard ADSL variables (Lesson 15), metabolic ADSL often includes:

- **DIABFL** — Diabetes Flag (Y/N at baseline)
- **HTNFL** — Hypertension Flag
- **CADFL** — Coronary Artery Disease Flag
- **PREDIABFL** — Prediabetes Flag
- **BMI_BL_CAT** — BMI category at baseline (Lean / Overweight / Obese Class I/II/III)

These are sponsor-specific; derive them from MH (Medical History) or ADSL baseline VS/LB values.

## 10. Putting it together: a metabolic ADLB skeleton

```r
library(admiral)
library(admiralmetabolic)
library(dplyr)
library(pharmaversesdtm)
library(pharmaverseadam)

# Assume ADSL and ADVS already built
adsl <- pharmaverseadam::adsl
advs <- pharmaverseadam::admiralmetabolic_advs   # has BMI and WSTCIR

# Source LB
lb <- pharmaversesdtm::lb |> convert_blanks_to_na()

adlb <- lb |>
  filter(LBTESTCD %in% c("INSULIN", "GLUC", "TRIG", "GGT", "HBA1C", "HDL", "LDL")) |>
  derive_vars_merged(
    dataset_add = adsl,
    new_vars = exprs(TRTSDT, TRTEDT, TRT01A),
    by_vars = exprs(STUDYID, USUBJID)
  ) |>
  derive_vars_dt(new_vars_prefix = "A", dtc = LBDTC) |>
  derive_vars_dy(reference_date = TRTSDT, source_vars = exprs(ADT)) |>
  mutate(
    PARAMCD = LBTESTCD,
    PARAM = LBTEST,
    AVAL = LBSTRESN
  )

# Bring BMI and WSTCIR from ADVS for FLI derivation
adlb <- adlb |>
  derive_vars_transposed(
    dataset_merge = advs,
    by_vars = exprs(STUDYID, USUBJID, ADT),
    key_var = PARAMCD,
    value_var = AVAL,
    filter = PARAMCD %in% c("BMI", "WSTCIR")
  )

# Derive HOMA-IR
adlb <- adlb |>
  derive_param_computed(
    by_vars = exprs(STUDYID, USUBJID, AVISIT, AVISITN, ADT, ADY),
    parameters = c("INSULIN", "GLUC"),
    set_values_to = exprs(
      AVAL = AVAL.INSULIN * AVAL.GLUC / 22.5,
      PARAMCD = "HOMAIR",
      PARAM = "Homeostasis Model Assessment - Insulin Resistance"
    )
  )

# Derive FLI
adlb <- adlb |>
  derive_param_computed(
    by_vars = exprs(STUDYID, USUBJID, AVISIT, AVISITN, ADT, ADY, BMI, WSTCIR),
    parameters = c("TRIG", "GGT"),
    set_values_to = exprs(
      AVAL = {
        lambda <- 0.953 * log(AVAL.TRIG) + 0.139 * BMI +
                  0.718 * log(AVAL.GGT) + 0.053 * WSTCIR - 15.745
        (exp(lambda) / (1 + exp(lambda))) * 100
      },
      PARAMCD = "FLI",
      PARAM = "Fatty Liver Index"
    )
  )

# Standard BDS finalization: baseline, change, ANL01FL
adlb <- adlb |>
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
  derive_var_chg() |>
  derive_var_pchg() |>
  mutate(ANL01FL = if_else(!is.na(AVAL) & !is.na(AVISIT), "Y", NA_character_))

glimpse(adlb)
```

The metabolic indices appear as additional parameters within the same dataset. Downstream tables can summarize all parameters together or filter by PARAMCD.

## 11. Maintenance and team

`{admiralmetabolic}` had its team kickoff in 2024 and first release ~6 months later. The lead contributors are from Novo Nordisk (the most active obesity sponsor by far), with collaboration from Roche, Boehringer Ingelheim, and other metabolic-active sponsors.

Active development areas:

- Expansion into type 2 diabetes-specific endpoints (HbA1c-based responder rates, time to glycemic control)
- NAFLD-specific scores (FibroScan-CAP, ELF, NAFLD Activity Score)
- Cardiovascular outcome trial (CVOT) patterns

## 12. Where to learn more

- The package vignettes: `vignette("adlb", package = "admiralmetabolic")` and `vignette("advs", ...)`
- The Pharmaverse blog has periodic posts on admiralmetabolic releases
- For NAFLD specifically, the package's CRAN reference page documents which biomarker indices are currently implemented

## 13. Looking forward: `{admiralneuro}`

Worth mentioning briefly: `{admiralneuro}` is in development as the neurology TA extension, targeting Alzheimer's, Parkinson's, multiple sclerosis, and migraine studies. Expected initial release in 2026. Patterns will likely include:

- Cognitive test score derivations (MMSE, ADAS-Cog, MoCA)
- Disability scales (EDSS for MS, UPDRS for Parkinson's)
- Imaging biomarkers (brain volume changes from MRI)

When `{admiralneuro}` reaches CRAN, the same lesson pattern from this module applies: load alongside admiral, use TA-specific helpers, follow the standard ADaM workflow.

## 14. Key takeaways

- `{admiralmetabolic}` targets obesity, diabetes, NAFLD, and metabolic/cardiovascular endpoints
- Metabolic indices (HOMA-IR, FLI, NAFLD scores) are derived via `admiral::derive_param_computed()` — admiralmetabolic supplies vignettes more than dedicated functions
- Cross-ADaM derivations are common: ADVS BMI/WSTCIR feed into ADLB FLI computation
- Use `derive_vars_transposed()` to bring parameter values from one BDS dataset into another
- Templates available for ADSL, ADVS, ADLB
- Newer package (0.x version line) — expect API stabilization with each release
- Active focus on obesity initially, expanding to type 2 diabetes and NAFLD

## 15. What's next

Module 5 is complete. You've now covered all five admiral TA extensions: oncology, vaccines, ophthalmology, pediatrics, metabolic. The patterns generalize: each extension adds TA-specific functions and templates on top of admiral core.

**Module 6 — Cardinal-future TLG stack** — starts with `{cards}` Part 1: the ARD concept in code. This is where the curriculum's most strategically important content begins, in line with the Cardinal-future positioning we discussed back in Lesson 01.

The next module covers cards (Part 1: ARD concepts; Part 2: building clinical ARDs), cardx (regression/survival extensions), gtsummary (Part 1: basics; Part 2: clinical patterns), cardinal (Part 1: overview; Part 2: FDA Safety Templates), and tfrmt — eight lessons in the TLG-future stack.

---

## Self-check questions

1. What does `derive_param_computed()` do, and why is it central to metabolic ADaMs?
2. Why does FLI computation require pulling data from both ADVS and ADLB?
3. Compute HOMA-IR if INSULIN = 12 mIU/L and GLUC = 6.0 mmol/L.
4. Translate to admiralmetabolic: "Add a Waist-to-Hip Ratio parameter to ADVS using WSTCIR and HIPCIR."
5. Why do many metabolic trials use "% weight loss responder" as a primary endpoint rather than mean change?
6. What's the typical ADaM build order for a metabolic study with FLI as an endpoint?

## Glossary

- **HOMA-IR** — Homeostasis Model Assessment of Insulin Resistance
- **FLI** — Fatty Liver Index; predicts hepatic steatosis from 4 inputs
- **NAFLD** — Non-Alcoholic Fatty Liver Disease
- **NAFLD Fibrosis Score** — Predicts hepatic fibrosis from age, BMI, glucose, AST/ALT, platelets, albumin
- **HSI** — Hepatic Steatosis Index
- **TyG Index** — Triglyceride-Glucose Index; insulin resistance surrogate
- **MACE** — Major Adverse Cardiovascular Event; composite of myocardial infarction, stroke, CV death
- **WSTCIR / HIPCIR** — Waist Circumference / Hip Circumference
- **WTHIRATIO** — Waist-to-Hip Ratio
- **HbA1c** — Glycated hemoglobin; long-term glucose control marker
- **`derive_param_computed()`** — Add a new parameter row computed from existing parameters
- **`derive_vars_transposed()`** — Pull parameter values from one BDS dataset into another (wide-from-long)
- **CVOT** — Cardiovascular Outcome Trial; typical of post-marketing diabetes drugs
- **`{admiralneuro}`** — Forthcoming neurology TA extension (Alzheimer's, MS, Parkinson's, migraine)
