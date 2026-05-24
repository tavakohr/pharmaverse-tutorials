# Lesson 20 — `{admiralonco}`: Oncology Therapeutic Area Extension

**Module**: 5 — ADaM therapeutic area extensions
**Estimated length**: ~30 min spoken
**Prerequisites**: Lessons 14–19 (admiral core)

---

## Learning objectives

By the end of this lesson, you will be able to:

1. Identify what `{admiralonco}` adds on top of admiral core
2. Build an ADRS (Response Analysis Dataset) for RECIST 1.1 endpoints
3. Use admiralonco's pre-defined event/censor sources to derive OS, PFS, and Duration of Response
4. Apply RECIST-based event objects: `rsp_event`, `pd_event`, `death_event`, `lasta_censor`, `rand_censor`
5. Recognize oncology-specific ADaM patterns: ANL01FL, confirmation periods, ORR computation
6. Adapt admiralonco for alternative response criteria (iRECIST, PCWG3, IMWG)

---

## 1. The TA extension model

Admiral core covers ADSL, BDS, OCCDS, and time-to-event in a therapeutic-area-agnostic way. But each TA has specifics:

- **Oncology**: RECIST-based response, tumor assessments, confirmation requirements
- **Vaccines**: reactogenicity events, immunogenicity titers
- **Ophthalmology**: study eye, BCVA on a logMAR scale, ETDRS letters
- **Pediatrics**: growth percentiles by age and sex
- **Metabolic**: HOMA-IR, FLI, insulin sensitivity computations

Pharmaverse handles these with **extension packages**: one TA package per therapeutic area, each depending on admiral. Functions in the extension follow the same naming conventions. You load both:

```r
library(admiral)
library(admiralonco)   # the oncology extension
```

And the admiralonco vocabulary slots in next to admiral's, available in your derivation pipelines.

This lesson covers the oncology extension. The four lessons after this cover vaccines, ophthalmology, pediatrics, and metabolic.

## 2. What admiralonco provides

The package adds:

- **Pre-defined event/censor source objects** for canonical oncology endpoints (OS, PFS, DOR, TTR, …)
- **Functions for building ADRS** — `derive_param_bor()` (Best Overall Response), `derive_param_clinbenefit()` (Clinical Benefit Rate, deprecated in favor of `admiral::derive_extreme_event()` in newer versions)
- **Vignettes for several response criteria**: RECIST 1.1, iRECIST, IMWG (multiple myeloma), GCIG (gynecological), PCWG3 (prostate cancer)
- **Templates** for ADRS and ADTTE

Critically, admiralonco does *not* replace admiral. It adds oncology-specific convenience on top. Your pipeline uses both packages together.

```r
install.packages("admiralonco")
```

## 3. The ADRS dataset

ADRS is a BDS-style dataset where each row is **one response assessment** for one subject:

```
USUBJID    PARAMCD  PARAM                       AVALC  AVAL  ADT          ANL01FL
01-001     OVR      Overall Response by Inv     PR     2     2024-04-15   Y
01-001     OVR      Overall Response by Inv     PR     2     2024-06-30   Y
01-001     OVR      Overall Response by Inv     PD     5     2024-09-10   Y
01-001     RSP      Response (Y/N)              Y      1     2024-04-15   Y
01-001     BOR      Best Overall Response       PR     2     2024-04-15   Y
01-001     PFSEVNT  PFS Event Occurred          Y      1     2024-09-10   Y
```

Common PARAMCDs:

- **OVR**: overall response at each visit (CR, PR, SD, PD, NE)
- **RSP**: ever-responded (CR or PR) — derived as Y/N at the response date if ever met
- **BOR**: best overall response — single value per subject
- **CB**: clinical benefit (CR + PR + SD ≥ 6 months) — Y/N
- **PFSEVNT**: progression-free survival event indicator (death or PD)
- **DOR**: response duration measurements (for responders)

The ADTTE dataset built later (Lesson 18) consumes ADRS-based events to compute time-to-event durations.

## 4. Setup

```r
library(admiral)
library(admiralonco)
library(dplyr)
library(pharmaversesdtm)
library(pharmaverseadam)
library(lubridate)
library(stringr)

# Source data
data("adsl", package = "pharmaverseadam")
data("rs_onco_recist", package = "pharmaversesdtm")
data("tu_onco_recist", package = "pharmaversesdtm")

rs <- rs_onco_recist |> convert_blanks_to_na()
tu <- tu_onco_recist |> convert_blanks_to_na()
```

`rs_onco_recist` is the SDTM RS (Disease Response) domain pre-flavored with RECIST 1.1 data. `tu_onco_recist` is the TU (Tumor Identification) domain — typically used to derive the "first tumor assessment date" for time-on-study calculations.

## 5. Pre-processing RS

The standard cleanup: keep only the response evaluations from RECIST, attach key ADSL dates (RANDDT).

```r
adsl_vars <- exprs(RANDDT, TRTSDT)

adrs <- rs |>
  filter(RSEVAL == "INVESTIGATOR" & RSTESTCD == "OVRLRESP") |>
  derive_vars_merged(
    dataset_add = adsl,
    new_vars = adsl_vars,
    by_vars = exprs(STUDYID, USUBJID)
  ) |>
  derive_vars_dt(
    new_vars_prefix = "A",
    dtc = RSDTC,
    highest_imputation = "M"
  ) |>
  mutate(
    PARAMCD = "OVR",
    PARAM = "Overall Response by Investigator",
    AVALC = RSSTRESC,
    AVAL = case_when(
      RSSTRESC == "CR"        ~ 1,
      RSSTRESC == "PR"        ~ 2,
      RSSTRESC == "SD"        ~ 3,
      RSSTRESC == "NON-CR/NON-PD" ~ 4,
      RSSTRESC == "PD"        ~ 5,
      RSSTRESC == "NE"        ~ 6
    ),
    ANL01FL = "Y"
  )
```

`RSEVAL == "INVESTIGATOR"` keeps investigator-assessed responses (as opposed to BICR — Blinded Independent Central Review — assessments). Studies typically have both; you'd build separate parameters with PARAMCDs like `OVRINV` and `OVRICR`, or set up PARCATy variables to distinguish.

The character RSSTRESC values (CR, PR, SD, PD, NE) map to numeric AVAL with the standard ordering: lower = better response.

## 6. Best Overall Response (BOR)

BOR per subject is derived using `derive_extreme_event()` from admiral with oncology-specific event objects from admiralonco. The logic: walk through possible response categories in priority order; the first that holds per subject wins.

```r
adrs <- adrs |>
  derive_extreme_event(
    by_vars = exprs(STUDYID, USUBJID),
    events = list(
      admiralonco::rsp_event(),       # responder (CR or PR)
      admiralonco::sd_event(),         # stable disease
      admiralonco::pd_event(),         # progressive disease
      admiralonco::ne_event()          # not evaluable
    ),
    order = exprs(ADT),
    mode = "first",
    set_values_to = exprs(
      PARAMCD = "BOR",
      PARAM = "Best Overall Response by Investigator",
      AVAL = yn_to_numeric(AVALC),
      ANL01FL = "Y"
    )
  )
```

(In current admiralonco, the precise calling convention for these event objects may use slightly different names — `admiralonco::event_response`, etc. — depending on the package version. Consult the vignette `vignette("adrs", package = "admiralonco")` for your version.)

Older versions had `derive_param_bor()` for this; newer versions deprecate it in favor of `admiral::derive_extreme_event()` parameterized by admiralonco event objects. The deprecation cycle (3 years) means both APIs remain workable; check current docs.

## 7. Confirmation period for responses

A RECIST refinement: a response (PR or CR) only counts if **confirmed** by a subsequent assessment at least N days later. For RECIST 1.1, the canonical confirmation period is 4 weeks (28 days).

Without confirmation, a single transient improvement gets called a response — likely a measurement error. With confirmation, you require sustained improvement.

`derive_extreme_event()` with admiralonco events supports a `confirmation_period` argument that adjusts the rules:

```r
adrs <- adrs |>
  derive_extreme_event(
    by_vars = exprs(STUDYID, USUBJID),
    events = list(
      admiralonco::rsp_event(confirmation_period = 28),    # confirmation needed
      admiralonco::sd_event(),
      admiralonco::pd_event()
    ),
    order = exprs(ADT),
    mode = "first",
    set_values_to = exprs(
      PARAMCD = "BOR",
      PARAM = "Best Overall Response by Investigator (Confirmed)"
    )
  )
```

Studies typically derive *both* a confirmed and unconfirmed BOR, with PARCAT2 or similar distinguishing them.

## 8. The pre-defined source objects

`admiralonco` exports several `event_source()` and `censor_source()` objects covering the standard oncology TTE definitions. Reading the package source, the typical names are:

| Object | Source dataset | What it represents |
|---|---|---|
| `death_event` | ADSL | Death event |
| `lastalive_censor` | ADSL | Last known alive (censor) |
| `pd_event` | ADRS | Progressive Disease event |
| `lasta_censor` | ADRS | Last tumor assessment (censor) |
| `rand_censor` | ADSL | Randomization date (catch-all censor) |
| `rsp_event` | ADRS | First response event (for DOR) |

These are *function* exports — call them to get a configured event_source. You can also call them with arguments to override (e.g., a different `EVNTDESC` text). For variations like BICR-only events, you'd construct a custom event_source from scratch (Lesson 18) instead of using the pre-defined.

## 9. Building OS, PFS, and DOR with one block

The payoff of having pre-defined sources: a complete oncology ADTTE in a few `derive_param_tte()` calls.

```r
# Filter ADSL to responders for DOR
adsl_responders <- adsl |>
  inner_join(
    adrs |>
      filter(PARAMCD == "RSP" & AVALC == "Y" & ANL01FL == "Y") |>
      distinct(USUBJID),
    by = "USUBJID"
  )

# Build the time-to-event dataset
adtte <- adsl |>
  derive_param_tte(
    start_date = RANDDT,
    event_conditions = list(admiralonco::death_event),
    censor_conditions = list(admiralonco::lastalive_censor),
    source_datasets = list(adsl = adsl),
    set_values_to = exprs(PARAMCD = "OS",
                          PARAM = "Overall Survival")
  ) |>
  derive_param_tte(
    dataset_adsl = adsl,
    start_date = RANDDT,
    event_conditions = list(admiralonco::pd_event, admiralonco::death_event),
    censor_conditions = list(admiralonco::lasta_censor,
                              admiralonco::lastalive_censor,
                              admiralonco::rand_censor),
    source_datasets = list(adsl = adsl, adrs = adrs),
    set_values_to = exprs(PARAMCD = "PFS",
                          PARAM = "Progression-Free Survival")
  ) |>
  derive_param_tte(
    dataset_adsl = adsl_responders,
    start_date = TEMP_RESPDT,
    event_conditions = list(admiralonco::pd_event, admiralonco::death_event),
    censor_conditions = list(admiralonco::lasta_censor,
                              admiralonco::lastalive_censor),
    source_datasets = list(adsl = adsl_responders, adrs = adrs),
    set_values_to = exprs(PARAMCD = "DOR",
                          PARAM = "Duration of Response")
  )
```

Three TTE parameters in one block. The investment in defining event sources pays off when you need to also build Time to Response (TTR), PFS by BICR (replace event sources with BICR-specific ones), and similar variants. Each adds another `derive_param_tte()` call.

## 10. Overall Response Rate (ORR) — a count, not a TTE

ORR is the proportion of responders. It's not a time-to-event; it's a binary outcome per subject. You typically encode it as a parameter in ADRS:

```r
# Already in our adrs derivation block:
adrs <- adrs |>
  derive_extreme_event(
    by_vars = exprs(STUDYID, USUBJID),
    events = list(
      admiralonco::rsp_event(confirmation_period = 28)
    ),
    order = exprs(ADT),
    mode = "first",
    set_values_to = exprs(
      PARAMCD = "RSP",
      PARAM = "Confirmed Response (Y/N)",
      AVAL = yn_to_numeric(AVALC),
      ANL01FL = "Y"
    )
  )
```

If a subject ever achieves a confirmed response, `AVALC = "Y"` is set on the appropriate row; otherwise `AVALC = "N"` with ADT and other values set per the event/no-event rules. ORR analyses filter `PARAMCD == "RSP"` and count `AVALC == "Y"`.

`yn_to_numeric()` is a small admiralonco helper that converts "Y" → 1, "N" → 0, NA → NA — handy for derived AVAL columns where the analysis value is binary.

## 11. Tumor measurement-based endpoints

Some endpoints require the actual tumor measurements (sum of target lesion diameters), not just response codes. These come from TR (Tumor Results) SDTM, not RS.

Common derivations:

- **Percent change from baseline in sum of target lesions** at each visit — used for "best percent change" waterfall plots
- **Time to nadir** — when the tumor was smallest, useful for assessing response durability

For these, you'd:

1. Filter TR for `TRTESTCD == "DIAMETER"` and `TRLINKID` matching target lesions
2. Sum the diameters per (subject × visit) → produce a parameter `PARAMCD = "SUMDIAM"`
3. Derive change-from-baseline using the standard admiral `derive_var_chg()` and `derive_var_pchg()`

admiralonco doesn't have a single function for this; you compose admiral and tidyverse functions. Roche's NEST stack provides higher-level wrappers in some cases.

## 12. Adapting to other response criteria

admiralonco ships vignettes for several response criteria:

- **RECIST 1.1** (`adrs.Rmd`): the default, solid tumors
- **iRECIST** (`adrs_irecist.Rmd`): immunotherapy variation allowing temporary progression
- **IMWG** (`adrs_imwg.Rmd`): International Myeloma Working Group, multiple myeloma
- **GCIG** (`adrs_gcig.Rmd`): Gynecologic Cancer InterGroup, ovarian and similar
- **PCWG3** (`adrs_pcwg3.Rmd`): Prostate Cancer Working Group 3

Each vignette walks through a complete ADRS build for that criterion. The pattern is the same — filter SDTM RS, derive overall response per visit, derive BOR — but the events list, the confirmation rules, and sometimes the source SDTM tests differ.

For a non-standard criterion (e.g., a study using a sponsor-modified Cheson criteria for lymphoma): start from the closest vignette, modify the event definitions to match your protocol. Don't try to invent from scratch.

## 13. New Anti-Cancer Therapy (NACT) start date

A common censoring consideration: if a subject discontinues study treatment and starts a different anti-cancer therapy, downstream measurements aren't really evaluating the study drug anymore. They should be censored at the NACT start date.

`{admiralonco}` provides a "Creating and Using New Anti-Cancer Start Date" vignette describing how to:

1. Identify NACT records from CM (Concomitant Medications) using sponsor logic — typically `CMCAT == "ANTI-CANCER"` or similar
2. Take the earliest such date per subject as `NACTDT`
3. Use `NACTDT` as an additional censor in PFS / DOR computations

```r
nact_dates <- cm |>
  filter(CMCAT == "ANTI-CANCER" | grepl("ANTI-CANCER", CMINDC, ignore.case = TRUE)) |>
  derive_vars_dt(new_vars_prefix = "AST", dtc = CMSTDTC) |>
  group_by(USUBJID) |>
  summarise(NACTDT = min(ASTDT, na.rm = TRUE), .groups = "drop")

adsl <- adsl |>
  left_join(nact_dates, by = "USUBJID")

# Then add a NACT censor source for PFS
nact_censor <- censor_source(
  dataset_name = "adsl",
  filter = !is.na(NACTDT),
  date = NACTDT,
  set_values_to = exprs(EVNTDESC = "NEW ANTI-CANCER THERAPY",
                        SRCDOM = "ADSL", SRCVAR = "NACTDT")
)

# Use in PFS:
adtte <- adsl |>
  derive_param_tte(
    dataset_adsl = adsl,
    start_date = RANDDT,
    event_conditions = list(admiralonco::pd_event, admiralonco::death_event),
    censor_conditions = list(admiralonco::lasta_censor,
                              admiralonco::lastalive_censor,
                              admiralonco::rand_censor,
                              nact_censor),
    source_datasets = list(adsl = adsl, adrs = adrs),
    set_values_to = exprs(PARAMCD = "PFS",
                          PARAM = "Progression-Free Survival (censored at NACT)")
  )
```

A second PFS parameter with NACT censoring captures the "sensitivity" analysis without disturbing the primary.

## 14. Putting it together: oncology ADaM workflow

A typical oncology study generates:

1. **ADSL** — built with admiral (Lesson 15) plus oncology-specific subject flags (RESPONDER, COMPLFL)
2. **ADAE** — built with admiral OCCDS pattern (Lesson 17) with NCI CTCAE grade variables instead of MILD/MODERATE/SEVERE
3. **ADLB** — built with admiral BDS pattern (Lesson 16) plus toxicity grading via `derive_var_atoxgr()`
4. **ADVS** — standard BDS
5. **ADCM** — admiral OCCDS
6. **ADRS** — admiralonco-flavored response dataset
7. **ADTTE** — composite TTE dataset with multiple parameters (OS, PFS, DOR, TTR, etc.), built with admiralonco source objects
8. **ADTR** (sometimes) — tumor measurement-level analysis dataset
9. **Custom datasets** — for biomarker analyses, ADaE (efficacy AE), etc.

admiralonco's role concentrates on items 6, 7, and the tumor-specific aspects of 8. Everything else is admiral core.

## 15. Templates

```r
library(admiralonco)
admiralonco::use_ad_template("adrs", save_path = "./ad_adrs.R")
admiralonco::use_ad_template("adtte", save_path = "./ad_adtte.R")
```

The templates are fully runnable against `pharmaverseadam`/`pharmaversesdtm` test data — copy, adapt to your study spec, you have a starting point.

## 16. Maintenance and team

`{admiralonco}` is maintained primarily by Roche developers (oncology being Roche's largest TA), with contributions from GSK, Pfizer, and others. The package releases roughly every 6 months alongside admiral core; oncology-specific patches between cycles are common.

For sponsor-specific oncology needs not covered by admiralonco, the pattern is to write helper functions in a `sponsor_admiralonco/` internal package — analogous to admiralroche / admiralgsk for admiral core extensions. This keeps your sponsor-private logic out of the open-source repo but lets you reuse it across studies.

## 17. Key takeaways

- `{admiralonco}` is the oncology TA extension for admiral, providing pre-defined event/censor objects and ADRS-building functions
- Standard pattern: filter SDTM RS → derive OVR per visit → derive BOR with `derive_extreme_event()` and admiralonco event objects → derive RSP (Y/N)
- Confirmation periods (e.g., 28 days for RECIST 1.1) handled via `confirmation_period` argument on event objects
- Pre-defined sources `death_event`, `pd_event`, `lasta_censor`, `lastalive_censor`, `rand_censor` cover the standard endpoint definitions
- Building OS + PFS + DOR is a few `derive_param_tte()` calls with these sources
- NACT (New Anti-Cancer Therapy) censoring is a standard oncology refinement
- Vignettes cover RECIST 1.1, iRECIST, IMWG, GCIG, PCWG3 criteria — adapt the nearest one for your protocol

## 18. What's next

Lesson 21 covers **`{admiralvaccine}`** — the vaccines extension, which handles reactogenicity (post-vaccination adverse events captured on a structured diary) and immunogenicity (antibody titers). The patterns are different from oncology — FACE-based analysis datasets, fever derivation, severity scales tied to diameter measurements — but the same admiral foundation.

After admiralvaccine: ophthalmology (Lesson 22), pediatrics (Lesson 23), metabolic (Lesson 24). Then Module 5 is complete and we enter Module 6 — the Cardinal-future TLG stack.

---

## Self-check questions

1. What does admiralonco add on top of admiral core?
2. What's a "confirmed response" and why does RECIST require confirmation?
3. Translate to admiralonco: "Build OS where the event is death and the censoring is last known alive."
4. Why is a NACT censor often included in PFS sensitivity analyses?
5. Which admiralonco vignette would you adapt for a multiple myeloma study?
6. What's the difference between `RSP` (Response Y/N) and `BOR` (Best Overall Response) in ADRS?

## Glossary

- **RECIST 1.1** — Response Evaluation Criteria In Solid Tumors version 1.1; the canonical solid-tumor response standard
- **iRECIST** — Immune-modified RECIST; allows temporary "pseudo-progression" common in immunotherapy
- **IMWG** — International Myeloma Working Group; multiple myeloma response criteria
- **GCIG** — Gynecologic Cancer InterGroup; ovarian cancer criteria including CA-125 markers
- **PCWG3** — Prostate Cancer Working Group 3; prostate criteria including bone scan rules
- **BICR** — Blinded Independent Central Review; second-party tumor assessment for trial integrity
- **BOR** — Best Overall Response; single value per subject from confirmed responses across all visits
- **ORR** — Objective Response Rate; proportion of responders (numerator: CR or PR; denominator: response-evaluable subjects)
- **DOR** — Duration of Response; for responders only, time from response to progression or death
- **PFS** — Progression-Free Survival; time from start to progression or death
- **NACT** — New Anti-Cancer Therapy; subsequent therapy that triggers censoring for some endpoints
- **CR / PR / SD / PD / NE** — Complete Response / Partial Response / Stable Disease / Progressive Disease / Not Evaluable
- **ADRS** — Response Analysis Dataset; BDS-style with one row per response assessment plus derived parameters
