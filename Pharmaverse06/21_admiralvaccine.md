# Lesson 21 — `{admiralvaccine}`: Vaccine Studies (Reactogenicity & Immunogenicity)

**Module**: 5 — ADaM therapeutic area extensions
**Estimated length**: ~20 min spoken
**Prerequisites**: Lessons 14–20

---

## Learning objectives

By the end of this lesson, you will be able to:

1. Recognize the vaccine ADaM landscape: ADCE, ADFACE, ADIS — and which is for what
2. Build an ADFACE (Findings About Clinical Events) dataset for reactogenicity analyses
3. Apply `derive_fever_records()` to ensure FEVER events are captured from VS data
4. Use `derive_vars_merged_vaccine()` and `derive_diam_to_sev_records()` for severity derivation
5. Understand how diameter measurements convert to severity grades for injection-site reactions
6. Adapt the vaccine workflow patterns to your study's protocol

---

## 1. The vaccine ADaM landscape

Vaccine trials have a distinctive structure that doesn't map cleanly onto standard ADaMs. Three primary datasets:

| Dataset | Focus | Source SDTM |
|---|---|---|
| **ADCE** | Clinical Events (post-vaccination AEs from the diary) | CE |
| **ADFACE** | Reactogenicity events — solicited symptoms with severity grading | FACE |
| **ADIS** | Immunogenicity — antibody titers, neutralization assays | IS |

The structure stays BDS/OCCDS, but the **data sources** are vaccine-specific:

- **CE** (Clinical Events): post-vaccination AEs collected on the subject diary, often with structured solicitation (fever, fatigue, headache, injection-site reactions)
- **FACE** (Findings About Clinical Events): measurement findings about each clinical event — severity grades, diameter of injection-site swelling, fever temperature peak
- **IS** (Immunogenicity Specimen Assessments): antibody titers, neutralization assay results

`{admiralvaccine}` adds functions and vignettes for working with these sources. The patterns mirror admiral core but with vaccine-specific names and semantics.

## 2. CBER guidelines: the regulatory backdrop

`admiralvaccine` is explicitly aligned with the FDA Center for Biologics Evaluation and Research (CBER) guidelines for solicited reactogenicity analysis. This is the FDA division that reviews vaccines, and they have specific expectations for how reactogenicity is summarized:

- **Solicited events** (specifically prompted on the diary) are reported separately from unsolicited AEs
- **Local reactions** (at the injection site) and **systemic reactions** (fever, fatigue, etc.) are reported separately
- **Severity grading** follows defined scales (FDA toxicity grading for vaccines, often a 5-point grade)
- **Subject-level analyses** ask "did the subject experience any grade ≥ 3 fever during the 7-day post-vaccination window?"

These shape ADFACE's design.

## 3. Setup

```r
library(admiral)
library(admiralvaccine)
library(admiraldev)
library(metatools)
library(pharmaversesdtm)
library(dplyr, warn.conflicts = FALSE)
library(lubridate)
library(stringr)
library(tidyr)

# Test data ships with admiralvaccine
data("face_vaccine")        # FACE SDTM with reactogenicity FA records
data("suppface_vaccine")    # SUPPFACE (supplemental qualifiers)
data("ex_vaccine")          # EX with vaccination administration
data("suppex_vaccine")      # SUPPEX
data("vs_vaccine")          # VS with reactogenicity temperature data
data("admiralvaccine_adsl") # An ADSL with vaccine-relevant variables

face <- convert_blanks_to_na(face_vaccine)
ex <- convert_blanks_to_na(ex_vaccine)
vs <- convert_blanks_to_na(vs_vaccine)
adsl <- admiralvaccine_adsl
```

Note the `combine_supp()` pattern (from metatools) — you'll fold SUPPFACE back into FACE before processing.

## 4. Building ADFACE — step 1: filter and combine

The first task: keep only the rows you need (reactogenicity records) and combine with their SUPP-- qualifiers.

```r
face <- face |>
  filter(FACAT == "REACTOGENICITY" &
         grepl("ADMIN|SYS", FASCAT)) |>      # ADMIN-SITE or SYS-temic
  mutate(FAOBJ = str_to_upper(FAOBJ)) |>     # normalize topic names
  combine_supp(suppface_vaccine)             # bring in SUPP-- variables

ex <- combine_supp(ex, suppex_vaccine)
```

After this:

- `face` has only rows where FACAT = "REACTOGENICITY" and FASCAT is either administration-site or systemic. Other FACE rows (e.g., findings about unsolicited AEs) are dropped — they don't belong in the reactogenicity analysis.
- `FAOBJ` (the test "object" — "FEVER", "PAIN", "REDNESS", "SWELLING", "FATIGUE", etc.) is uppercased for consistent grouping.
- SUPP-- variables are now columns of `face` and `ex`, accessible by name.

## 5. Step 2: derive_vars_merged_vaccine — link to exposure

Reactogenicity events are post-vaccination. Each event belongs to a specific vaccine administration. `derive_vars_merged_vaccine()` (an admiralvaccine-specific wrapper of `derive_vars_merged()`) links each FACE row to the most recent prior EX (vaccination) row, attaching the vaccination date.

```r
adface <- face |>
  derive_vars_merged_vaccine(
    dataset_add = ex,
    by_vars = exprs(STUDYID, USUBJID),
    order = exprs(EXSTDT),
    mode = "last",
    new_vars = exprs(EXSTDT = EXSTDT,
                     EXSEQ = EXSEQ,
                     EXLNKID = EXLNKID),
    join_vars = exprs(EXSTDT),
    filter_join = FADTC >= EXSTDT
  )
```

The function attaches `EXSTDT` (the vaccination date) and related vars to each FACE row, choosing the most recent EX record on or before the FACE date.

After this, every reactogenicity event in ADFACE knows which vaccination it followed.

## 6. Step 3: derive_fever_records — ensure all subjects have fever rows

A subtle data-quality requirement: if FEVER wasn't recorded for a subject on a given day (because they had no fever), there may be no FACE row at all — only VS rows with temperature readings. To produce a complete reactogenicity summary, ADFACE needs explicit FEVER rows (with "no fever" outcome where appropriate).

`derive_fever_records()` handles this:

```r
adface <- adface |>
  derive_fever_records(
    dataset_source = ungroup(vs),
    filter_source = VSCAT == "REACTOGENICITY" & VSTESTCD == "TEMP",
    faobj = "FEVER"
  )
```

The function looks at the VS data for reactogenicity temperature measurements, and for any (subject × day) where no FACE FEVER row exists but a VS TEMP row does, inserts a FEVER row in ADFACE with appropriate values. The result: complete fever event capture across all subjects.

This pattern — "ensure expected records exist" — is what `admiral::derive_expected_records()` does in BDS. `derive_fever_records()` is the vaccine-specific specialization for FACE→fever logic.

## 7. Step 4: derive analysis dates and study days

Standard admiral patterns apply:

```r
adface <- adface |>
  derive_vars_dt(
    new_vars_prefix = "A",
    dtc = FADTC
  ) |>
  derive_vars_dtm(
    new_vars_prefix = "A",
    dtc = FADTC,
    highest_imputation = "n"
  ) |>
  derive_vars_dy(
    reference_date = EXSTDT,
    source_vars = exprs(ADT)
  )
```

The reference date is `EXSTDT` (the relevant vaccination date), not TRTSDT — because each reactogenicity event is timed relative to its triggering vaccination, not to the first dose. This is one of the bigger conceptual shifts from non-vaccine ADaMs.

## 8. Step 5: derive_diam_to_sev_records — convert diameter to severity

For injection-site reactions (redness, swelling), the SDTM data may capture the diameter in millimeters. The analysis dataset needs severity grades (mild, moderate, severe). `derive_diam_to_sev_records()` adds severity rows derived from diameter measurements per FDA grading rules:

```r
adface <- adface |>
  derive_diam_to_sev_records(
    dataset_source = ungroup(face),
    filter_source = FATESTCD == "DIAMETER" & FAOBJ %in% c("REDNESS", "SWELLING"),
    faobj = "REDNESS",
    grading_basis = "DIAMETER",
    grade_var = ASEV
  )
```

The standard CBER toxicity grading for redness/swelling:

- ≤ 2.5 cm → MILD
- > 2.5 to ≤ 5 cm → MODERATE
- > 5 to ≤ 10 cm → SEVERE
- > 10 cm → POTENTIALLY LIFE THREATENING

The function applies these rules and creates the severity rows. Most of the configurability you'd want — different cutoffs, custom labels — is supported via arguments.

## 9. Step 6: analysis flag (ANL01FL)

```r
adface <- adface |>
  mutate(ANL01FL = if_else(!is.na(ASEV), "Y", NA_character_))
```

Records with derived severity grades qualify for the "all reactogenicity analyses" inclusion flag. This pattern is sponsor-specific; check the SAP.

## 10. Period derivations — vaccination periods

Many vaccine studies have multiple vaccinations (e.g., 2-dose series). Each dose triggers a 7-day reactogenicity window. CDISC handles this with period variables — `APERIOD`, `APERSDT`, `APEREDT`. Admiral's `create_period_dataset()` and `derive_vars_period()` (Lesson 19) handle this:

```r
# Period reference: ADSL has APxxSDT and APxxEDT for each vaccination
adperiods <- create_period_dataset(
  dataset = adsl,
  new_vars = exprs(APERSDT = APxxSDT, APEREDT = APxxEDT)
)

# Add APERIOD to ADFACE based on event date
adface <- adface |>
  derive_vars_joined(
    dataset_add = adperiods,
    by_vars = exprs(STUDYID, USUBJID),
    filter_join = ADT >= APERSDT & ADT <= APEREDT,
    join_type = "all"
  )
```

After this, every reactogenicity event knows which vaccination period it belongs to. Downstream analyses can summarize "Period 1 reactogenicity" vs "Period 2 reactogenicity" separately.

## 11. ADCE — Clinical Events (post-vaccination AEs)

ADCE is similar in spirit to ADAE but with vaccine-specific source: the CE (Clinical Events) SDTM domain rather than AE. Reactogenicity events captured on the diary often live in CE rather than AE because they're solicited (asked about specifically), making them different in regulatory treatment.

The ADCE template follows the ADAE pattern from Lesson 17 with CE-flavored variable names: `CESTDTC` → `ASTDT`, etc. Most patterns transfer.

```r
adce <- ce |>
  derive_vars_merged(dataset_add = adsl, new_vars = adsl_vars,
                     by_vars = exprs(STUDYID, USUBJID)) |>
  derive_vars_dt(new_vars_prefix = "AST", dtc = CESTDTC) |>
  derive_vars_dt(new_vars_prefix = "AEN", dtc = CEENDTC) |>
  derive_vars_dy(reference_date = TRTSDT,
                 source_vars = exprs(ASTDT, AENDT)) |>
  mutate(ASEV = CESEV) |>
  # ... etc., following the ADAE pattern from Lesson 17
```

The vignette `vignette("adce", package = "admiralvaccine")` walks the full build.

## 12. ADIS — Immunogenicity

Immunogenicity data measures the immune response to the vaccine: antibody titers (e.g., ELISA), neutralizing antibody titers, T-cell responses. Source: IS (Immunogenicity Specimen Assessments) SDTM.

ADIS is BDS-shaped: one row per (subject × analyte × visit). Common parameters:

- Geometric Mean Titer (GMT) per analyte per visit
- Seroconversion rate: subjects who achieved a defined titer increase
- Fold-rise from baseline

The ADIS workflow uses standard admiral BDS patterns (Lesson 16) plus immunogenicity-specific computations:

```r
adis <- is |>
  derive_vars_merged(dataset_add = adsl, ...) |>
  derive_vars_dt(...) |>
  # Assign PARAMCD, PARAM
  mutate(PARAMCD = ISTESTCD, PARAM = ISTEST, AVAL = ISSTRESN) |>
  # Derive seroconversion flag
  derive_var_seroconversion(
    ...
  )
```

The current admiralvaccine version provides several immunogenicity-specific computations as helper functions; check the package's reference page for the current list.

## 13. Putting it together: an ADFACE skeleton

```r
library(admiral)
library(admiralvaccine)
library(metatools)
library(dplyr)
library(stringr)

# Load data
face <- face_vaccine |> convert_blanks_to_na()
ex   <- ex_vaccine   |> convert_blanks_to_na()
vs   <- vs_vaccine   |> convert_blanks_to_na()
adsl <- admiralvaccine_adsl

# Combine supps and filter
face <- face |>
  filter(FACAT == "REACTOGENICITY" & grepl("ADMIN|SYS", FASCAT)) |>
  mutate(FAOBJ = str_to_upper(FAOBJ)) |>
  combine_supp(suppface_vaccine)

ex <- combine_supp(ex, suppex_vaccine)

# Build ADFACE
adface <- face |>
  derive_vars_merged_vaccine(
    dataset_add = ex,
    by_vars = exprs(STUDYID, USUBJID),
    order = exprs(EXSTDT),
    mode = "last",
    new_vars = exprs(EXSTDT = EXSTDT, EXSEQ = EXSEQ),
    filter_join = FADTC >= EXSTDT
  ) |>
  derive_fever_records(
    dataset_source = ungroup(vs),
    filter_source = VSCAT == "REACTOGENICITY" & VSTESTCD == "TEMP",
    faobj = "FEVER"
  ) |>
  derive_vars_dt(new_vars_prefix = "A", dtc = FADTC) |>
  derive_vars_dy(reference_date = EXSTDT, source_vars = exprs(ADT)) |>
  derive_diam_to_sev_records(
    dataset_source = ungroup(face),
    filter_source = FATESTCD == "DIAMETER" & FAOBJ %in% c("REDNESS", "SWELLING"),
    faobj = "REDNESS",
    grading_basis = "DIAMETER",
    grade_var = ASEV
  ) |>
  mutate(ANL01FL = if_else(!is.na(ASEV), "Y", NA_character_)) |>
  derive_var_obs_number(
    new_var = ASEQ,
    by_vars = exprs(STUDYID, USUBJID),
    order = exprs(ADT, FAOBJ)
  )

glimpse(adface)
```

## 14. Templates

```r
admiralvaccine::use_ad_template("adsl",   save_path = "./ad_adsl.R")
admiralvaccine::use_ad_template("adce",   save_path = "./ad_adce.R")
admiralvaccine::use_ad_template("adface", save_path = "./ad_adface.R")
admiralvaccine::use_ad_template("adis",   save_path = "./ad_adis.R")
```

Templates are runnable end-to-end against the vaccine test data.

## 15. Subject-level summaries: did subject X have any grade ≥ 3 event?

A signature analysis: subject-level "worst grade" across reactogenicity events. Pattern:

```r
worst_per_subject <- adface |>
  filter(ANL01FL == "Y" & APERIOD == 1) |>
  group_by(STUDYID, USUBJID, FAOBJ) |>
  slice_max(ASEVN, n = 1, with_ties = FALSE) |>
  ungroup() |>
  pivot_wider(
    id_cols = c(STUDYID, USUBJID),
    names_from = FAOBJ,
    values_from = ASEV,
    names_prefix = "WORST_"
  )
```

This gives one row per subject with `WORST_FEVER`, `WORST_PAIN`, `WORST_REDNESS`, etc. — the basis for the "% subjects with any grade ≥ 3 systemic reaction" summary in the CSR.

## 16. Maintenance and team

`{admiralvaccine}` is jointly developed by Roche and Pfizer (Pfizer being a major vaccine sponsor). The package is in active development (0.x version line); production-quality but the API still settling.

For vaccine studies specifically: read the current vignettes carefully because function signatures evolve as the package matures.

## 17. Key takeaways

- `{admiralvaccine}` handles vaccine-specific ADaMs: ADCE, ADFACE (reactogenicity), ADIS (immunogenicity)
- The source SDTM is FACE (Findings About Clinical Events) plus CE, EX, IS — different from generic ADAE work
- `derive_vars_merged_vaccine()` links each reactogenicity event to its triggering vaccination
- `derive_fever_records()` ensures complete fever event capture, even when no FACE row exists
- `derive_diam_to_sev_records()` converts diameter measurements to FDA-graded severity per CBER conventions
- Reference date is typically `EXSTDT` (vaccination date) rather than `TRTSDT` for reactogenicity analyses
- Period datasets handle multi-dose vaccination series — each vaccination triggers its own 7-day window
- Templates available for all four standard vaccine ADaMs

## 18. What's next

Lesson 22 covers **`{admiralophtha}`** — the ophthalmology extension. Ophthalmology has its own twists: study eye selection (which eye is being treated), BCVA measured on a logMAR scale, ETDRS letters, and criterion flags for clinically meaningful changes. The patterns differ enough from other TAs to warrant their own lesson.

---

## Self-check questions

1. What's the difference between ADCE and ADFACE?
2. Why is the reference date for reactogenicity analysis `EXSTDT` rather than `TRTSDT`?
3. What does `derive_fever_records()` do that simple filtering wouldn't?
4. Translate the conventional CBER reactogenicity grading: a redness diameter of 4 cm. What severity?
5. Why does vaccine reactogenicity analysis use periods (APERIOD) rather than a single treatment window?
6. Which SDTM domains feed ADFACE?

## Glossary

- **CBER** — FDA Center for Biologics Evaluation and Research; reviews vaccines and biologics
- **Reactogenicity** — Body's immediate response to a vaccine; solicited symptoms like fever, pain, redness
- **Immunogenicity** — Immune response to a vaccine, measured by antibody titers
- **Solicited / unsolicited AE** — Solicited = specifically prompted on the diary; unsolicited = spontaneous
- **FACE** — Findings About Clinical Events; SDTM domain holding qualifying measurements of CEs
- **CE** — Clinical Events; SDTM domain holding the events themselves
- **IS** — Immunogenicity Specimen assessments; SDTM domain for titers and similar
- **ADCE / ADFACE / ADIS** — Vaccine ADaM datasets for events / their qualifications / immunogenicity
- **`derive_vars_merged_vaccine()`** — Link reactogenicity event to triggering vaccination
- **`derive_fever_records()`** — Ensure all subjects have FEVER rows for analysis completeness
- **`derive_diam_to_sev_records()`** — Convert diameter measurements to severity grades
- **GMT** — Geometric Mean Titer; primary efficacy summary for antibody response
- **Seroconversion** — Achievement of a defined titer increase post-vaccination
