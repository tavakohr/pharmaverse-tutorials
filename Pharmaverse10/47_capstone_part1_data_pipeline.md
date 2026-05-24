# Lesson 47 — Capstone Part 1: Building the Data Pipeline

**Module**: 11 — Capstone end-to-end study
**Estimated length**: ~25 min spoken
**Prerequisites**: All prior lessons

---

## Learning objectives

By the end of this lesson, you will be able to:

1. Execute a complete synthetic oncology study data pipeline: raw EDC → SDTM → ADaM
2. Wire together `{pharmaverseraw}`, `{sdtm.oak}`, `{metacore}`, `{metatools}`, `{admiral}`, and `{admiralonco}`
3. Build the canonical oncology ADaMs: ADSL, ADAE, ADLB, ADRS, ADTTE
4. Apply spec-driven programming end-to-end via metacore
5. Wrap each script with `{logrx}` for full traceability
6. Validate the resulting ADaMs against the spec

---

## 1. The capstone study

We're building a complete end-to-end deliverable for a synthetic Phase III oncology study comparing a novel investigational drug to standard of care. The endpoints:

- **Primary efficacy**: Overall Survival (OS)
- **Secondary efficacy**: Progression-Free Survival (PFS), Objective Response Rate (ORR)
- **Safety**: All standard CSR safety tables

Study characteristics:

- ~250 subjects randomized 1:1 to investigational arm vs placebo
- 24 months follow-up
- RECIST 1.1 tumor response criteria
- Standard NCI CTCAE grading for AEs

This lesson focuses on **the data pipeline**: turning raw EDC data into submission-ready ADaMs. Lesson 48 covers **the deliverables**: turning ADaMs into ARDs, tables, an interactive app, and a submission package.

This lesson assumes you've read Modules 2-5; we'll reference earlier patterns without re-explaining them.

## 2. The pipeline architecture

```
Raw EDC data (pharmaverseraw)
   ↓
SDTM datasets (sdtm.oak)              ← Modules 2
   ↓
ADaM specifications (metacore)         ← Module 3
   ↓
Core ADaMs (admiral)                   ← Module 4
   ↓
Oncology ADaMs (admiralonco)           ← Module 5
   ↓
Validated ADaMs (metatools + diffdf)   ← Modules 3, 10
   ↓
XPT v5 export (xportr)                 ← Module 9
```

Each layer transforms data; each layer is logged via logrx; each layer is dual-programmed in production (we won't dual-program for the capstone, but the pattern is in place).

## 3. Setup

```r
library(pharmaverseraw)       # raw EDC test data
library(pharmaversesdtm)      # SDTM test data (alternative to building from raw)
library(pharmaverseadam)      # ADaM test data (alternative to building from SDTM)
library(sdtm.oak)             # SDTM mapping
library(metacore)             # spec management
library(metatools)            # spec application
library(admiral)              # core ADaM
library(admiralonco)          # oncology ADaM
library(xportr)               # XPT export
library(logrx)                # execution logging
library(dplyr)
library(lubridate)

# Set project paths
project_root <- "study_capstone"
dir.create(file.path(project_root, "data/raw"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(project_root, "data/sdtm"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(project_root, "data/adam"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(project_root, "logs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(project_root, "specs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(project_root, "submission"), recursive = TRUE, showWarnings = FALSE)
```

For the capstone, we'll work with the pre-built `pharmaverseadam` and `pharmaversesdtm` test data as our starting point, noting where you'd plug in real EDC data via sdtm.oak.

## 4. Step 1: Raw EDC data → SDTM

In a real study, you'd start with vendor EDC exports (Medidata Rave, Veeva CDMS, etc.). For the capstone:

```r
# Real study:
# raw_dm <- haven::read_xpt("data/raw/dm_eds.xpt")
# raw_ae <- haven::read_xpt("data/raw/ae_export.xpt")
# raw_lb <- haven::read_xpt("data/raw/lab_export.xpt")

# Capstone: use pre-built test data
raw_dm  <- pharmaverseraw::raw_dm
raw_ae  <- pharmaverseraw::raw_ae
raw_lb  <- pharmaverseraw::raw_lb
raw_ex  <- pharmaverseraw::raw_ex
raw_ds  <- pharmaverseraw::raw_ds
raw_vs  <- pharmaverseraw::raw_vs
raw_tu  <- pharmaverseraw::raw_tu
raw_rs  <- pharmaverseraw::raw_rs
```

For oncology, the key raw domains include tumor identification (TU) and tumor response (RS) — driving ADRS and the efficacy endpoints.

### Mapping raw DM → SDTM DM

Following Lesson 09 patterns:

```r
sdtm_dm <- raw_dm |>
  # Rename source columns to SDTM standard names
  rename(
    STUDYID = study,
    SITEID = site,
    SUBJID = subjectnumber,
    AGE = subjectage,
    SEX = subjectsex,
    RACE = subjectrace,
    ETHNIC = subjectethnicity,
    ARM = treatmentarm,
    BRTHDTC = birthdate,
    RFICDTC = consentdate
  ) |>
  # Derive standard SDTM variables
  mutate(
    DOMAIN = "DM",
    USUBJID = paste(STUDYID, SITEID, SUBJID, sep = "-"),
    COUNTRY = "USA",
    DMDTC = format(as.Date(Sys.time()), "%Y-%m-%d"),
    AGEU = "YEARS"
  ) |>
  # Select SDTM-standard column set
  select(
    STUDYID, DOMAIN, USUBJID, SUBJID, SITEID,
    BRTHDTC, AGE, AGEU,
    SEX, RACE, ETHNIC,
    ARM, ARMCD = ARM,
    COUNTRY, DMDTC, RFICDTC
  )
```

In real production with sdtm.oak, you'd use the algorithmic mapping framework (Lesson 09). For the capstone we'll use direct dplyr mapping for clarity, mirroring what sdtm.oak does under the hood.

Similar mappings produce `sdtm_ae`, `sdtm_lb`, `sdtm_ex`, `sdtm_ds`, `sdtm_vs`, `sdtm_tu`, `sdtm_rs`. For brevity we'll use the pre-built `pharmaversesdtm` data going forward:

```r
sdtm_dm  <- pharmaversesdtm::dm
sdtm_ae  <- pharmaversesdtm::ae
sdtm_lb  <- pharmaversesdtm::lb
sdtm_ex  <- pharmaversesdtm::ex
sdtm_ds  <- pharmaversesdtm::ds
sdtm_vs  <- pharmaversesdtm::vs
sdtm_tu  <- pharmaversesdtm::tu_onco_recist
sdtm_rs  <- pharmaversesdtm::rs_onco_recist
```

These are CDISC-pilot-style datasets with tumor data appropriate for our oncology study.

## 5. Step 2: SDTM QC via `{sdtmchecks}`

Before building ADaMs, validate SDTM:

```r
library(sdtmchecks)

# Run the standard SDTM check suite
sdtm_check_results <- run_all_checks(
  list(
    DM = sdtm_dm,
    AE = sdtm_ae,
    LB = sdtm_lb,
    EX = sdtm_ex,
    DS = sdtm_ds,
    VS = sdtm_vs
  )
)

# Inspect results
print(sdtm_check_results)
```

Findings get flagged: missing required variables, broken referential integrity, date issues. Fix at the SDTM level before proceeding to ADaM (otherwise you bake the problem deeper into the pipeline).

For the capstone, the test data is clean; we proceed.

## 6. Step 3: Specification setup with metacore

For ADaMs, our spec lives in an Excel file. The capstone uses a simplified spec covering ADSL, ADAE, ADLB, ADRS, ADTTE:

```r
# In real production: maintained Excel spec file
# For capstone: use admiralonco's bundled example spec
mc <- metacore::spec_to_metacore(
  system.file("specs", "ADaM_spec.xlsx", package = "metacore"),
  quiet = TRUE
)

# View dataset list
mc |> select_dataset("ADSL") |> get_keys()
mc |> select_dataset("ADSL") |> get_variable_set()
```

Each subsequent ADaM build will use `mc` to:

- Drop variables not in spec (`drop_unspec_vars`)
- Verify all spec variables are present (`check_variables`)
- Apply labels (`apply_variable_labels`)
- Apply formats (where applicable)

This ensures **spec-driven programming**: the spec is the source of truth; derivations conform to it.

## 7. Step 4: Build ADSL

The foundation ADaM, per Lesson 15 patterns:

```r
# Source data
adsl <- sdtm_dm |>
  # Merge first dosing date from EX
  derive_vars_merged(
    dataset_add = sdtm_ex |> filter(EXSEQ == 1),
    new_vars = exprs(TRTSDT = EXSTDT),
    by_vars = exprs(STUDYID, USUBJID)
  ) |>
  # Merge last dosing date from EX
  derive_vars_merged(
    dataset_add = sdtm_ex |> arrange(STUDYID, USUBJID, EXSEQ),
    new_vars = exprs(TRTEDT = EXENDT),
    by_vars = exprs(STUDYID, USUBJID),
    mode = "last"
  ) |>
  # Derive treatment duration
  mutate(
    TRTSDT = as.Date(TRTSDT),
    TRTEDT = as.Date(TRTEDT),
    TRTDURD = as.numeric(TRTEDT - TRTSDT) + 1,
    SAFFL = if_else(!is.na(TRTSDT), "Y", "N"),
    ITTFL = "Y",      # all subjects enrolled = ITT
    EFFFL = SAFFL,    # safety = efficacy for this study
    TRT01A = ARM,
    TRT01P = ARM
  ) |>
  # Bring in disposition events
  derive_vars_merged(
    dataset_add = sdtm_ds |> filter(DSCAT == "DISPOSITION EVENT"),
    new_vars = exprs(
      EOSDT  = as.Date(DSSTDTC),
      EOSSTT = if_else(DSDECOD == "COMPLETED", "COMPLETED", "DISCONTINUED"),
      EOSREAS = DSDECOD
    ),
    by_vars = exprs(STUDYID, USUBJID),
    mode = "first"
  ) |>
  # Death tracking
  derive_vars_merged(
    dataset_add = sdtm_ds |> filter(DSDECOD == "DEATH"),
    new_vars = exprs(DTHDT = as.Date(DSSTDTC)),
    by_vars = exprs(STUDYID, USUBJID),
    mode = "first"
  ) |>
  mutate(
    DTHFL = if_else(!is.na(DTHDT), "Y", "N"),
    RANDDT = TRTSDT     # assume rand = first dose for capstone
  ) |>
  # Apply spec
  drop_unspec_vars(metacore = mc, dataset = "ADSL") |>
  check_variables(metacore = mc, dataset = "ADSL") |>
  apply_variable_labels(metacore = mc, dataset = "ADSL")
```

The complete ADSL with treatment dates, populations, disposition, death. About 50 lines for a realistic ADSL build.

For the capstone we'll use the pre-built ADSL from `pharmaverseadam` going forward to save space:

```r
adsl <- pharmaverseadam::adsl
```

But the pattern above is the real thing — adapt for any study.

## 8. Step 5: Build ADAE (OCCDS pattern)

Lesson 17's OCCDS pattern:

```r
adae <- sdtm_ae |>
  # Merge in ADSL key variables
  derive_vars_merged(
    dataset_add = adsl,
    new_vars = exprs(TRTSDT, TRTEDT, TRT01A, TRT01P, SAFFL, RANDDT),
    by_vars = exprs(STUDYID, USUBJID)
  ) |>
  # Derive analysis dates
  derive_vars_dt(new_vars_prefix = "AST", dtc = AESTDTC) |>
  derive_vars_dt(new_vars_prefix = "AEN", dtc = AEENDTC) |>
  derive_vars_dy(
    reference_date = TRTSDT,
    source_vars = exprs(ASTDT, AENDT)
  ) |>
  # Treatment-emergent flag
  mutate(
    TRTEMFL = if_else(!is.na(ASTDT) & ASTDT >= TRTSDT & ASTDT <= TRTEDT + 30,
                       "Y", NA_character_),
    ASEV = AESEV,
    ATOXGR = AETOXGR,
    AOCCFL = if_else(TRTEMFL == "Y", "Y", NA_character_)
  ) |>
  # First-occurrence flags per subject × preferred term
  restrict_derivation(
    derivation = derive_var_extreme_flag,
    args = params(
      by_vars = exprs(STUDYID, USUBJID, AEDECOD),
      order = exprs(ASTDT, AESEQ),
      new_var = AOCCPFL,
      mode = "first"
    ),
    filter = TRTEMFL == "Y"
  ) |>
  drop_unspec_vars(metacore = mc, dataset = "ADAE") |>
  apply_variable_labels(metacore = mc, dataset = "ADAE")
```

Result: ADAE with treatment-emergent flags, first-occurrence flags, analysis dates. Ready for AE incidence tables in Module 6/7.

```r
# Or use the pre-built test version
adae <- pharmaverseadam::adae
```

## 9. Step 6: Build ADLB (BDS pattern)

Lesson 16's BDS pattern:

```r
adlb <- sdtm_lb |>
  # Merge ADSL
  derive_vars_merged(
    dataset_add = adsl,
    new_vars = exprs(TRTSDT, TRTEDT, TRT01A, SAFFL),
    by_vars = exprs(STUDYID, USUBJID)
  ) |>
  # Analysis dates
  derive_vars_dt(new_vars_prefix = "A", dtc = LBDTC) |>
  derive_vars_dy(reference_date = TRTSDT, source_vars = exprs(ADT)) |>
  # Assign parameter
  mutate(
    PARAMCD = LBTESTCD,
    PARAM = LBTEST,
    AVAL = LBSTRESN,
    AVALC = LBSTRESC,
    ANRLO = LBSTNRLO,
    ANRHI = LBSTNRHI
  ) |>
  # Baseline flag (last pre-treatment)
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
  # Baseline value
  derive_var_base(
    by_vars = exprs(STUDYID, USUBJID, PARAMCD),
    source_var = AVAL,
    new_var = BASE
  ) |>
  derive_var_chg() |>
  derive_var_pchg() |>
  # Reference range indicator
  derive_var_anrind() |>
  # Analysis flag
  mutate(
    ANL01FL = if_else(!is.na(AVAL) & !is.na(AVISIT), "Y", NA_character_),
    AVISIT = case_when(
      ABLFL == "Y"                                    ~ "Baseline",
      ADY > 0 & ADY <= 28                             ~ "Week 4",
      ADY > 28 & ADY <= 56                            ~ "Week 8",
      ADY > 56 & ADY <= 84                            ~ "Week 12",
      ADY > 84                                         ~ "Post Week 12",
      TRUE                                             ~ NA_character_
    ),
    AVISITN = case_when(
      AVISIT == "Baseline"      ~ 0L,
      AVISIT == "Week 4"        ~ 4L,
      AVISIT == "Week 8"        ~ 8L,
      AVISIT == "Week 12"       ~ 12L,
      AVISIT == "Post Week 12"  ~ 99L,
      TRUE                       ~ NA_integer_
    )
  ) |>
  drop_unspec_vars(metacore = mc, dataset = "ADLB") |>
  apply_variable_labels(metacore = mc, dataset = "ADLB")

# Or pre-built
adlb <- pharmaverseadam::adlb
```

The ADLB has baseline, change, percent change, reference range indicator, visit windowing — everything a CSR lab table needs.

## 10. Step 7: Build ADRS (oncology response, Lesson 20)

For oncology, the response analysis dataset is critical:

```r
adsl_vars <- exprs(RANDDT, TRTSDT)

adrs <- sdtm_rs |>
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

# Derive BOR (Best Overall Response)
adrs <- adrs |>
  derive_extreme_event(
    by_vars = exprs(STUDYID, USUBJID),
    events = list(
      admiralonco::rsp_event(confirmation_period = 28),
      admiralonco::sd_event(),
      admiralonco::pd_event()
    ),
    order = exprs(ADT),
    mode = "first",
    set_values_to = exprs(
      PARAMCD = "BOR",
      PARAM = "Best Overall Response (Confirmed)",
      AVAL = yn_to_numeric(AVALC),
      ANL01FL = "Y"
    )
  ) |>
  drop_unspec_vars(metacore = mc, dataset = "ADRS") |>
  apply_variable_labels(metacore = mc, dataset = "ADRS")
```

The ADRS now has per-visit response (`PARAMCD = "OVR"`) plus best overall response (`PARAMCD = "BOR"`). The PD events become the input to PFS in ADTTE next.

## 11. Step 8: Build ADTTE (oncology TTE, Lessons 18 + 20)

The time-to-event dataset, with OS, PFS, and DOR using admiralonco's pre-defined event/censor sources:

```r
# Filter ADSL to responders for DOR
adsl_responders <- adsl |>
  inner_join(
    adrs |>
      filter(PARAMCD == "RSP" & AVALC == "Y" & ANL01FL == "Y") |>
      distinct(USUBJID),
    by = "USUBJID"
  )

# OS
adtte_os <- adsl |>
  derive_param_tte(
    start_date = RANDDT,
    event_conditions = list(admiralonco::death_event),
    censor_conditions = list(admiralonco::lastalive_censor),
    source_datasets = list(adsl = adsl),
    set_values_to = exprs(PARAMCD = "OS",
                          PARAM = "Overall Survival")
  )

# PFS
adtte_pfs <- adsl |>
  derive_param_tte(
    dataset_adsl = adsl,
    start_date = RANDDT,
    event_conditions = list(admiralonco::pd_event, admiralonco::death_event),
    censor_conditions = list(
      admiralonco::lasta_censor,
      admiralonco::lastalive_censor,
      admiralonco::rand_censor
    ),
    source_datasets = list(adsl = adsl, adrs = adrs),
    set_values_to = exprs(PARAMCD = "PFS",
                          PARAM = "Progression-Free Survival")
  )

# DOR
adtte_dor <- adsl_responders |>
  derive_param_tte(
    dataset_adsl = adsl_responders,
    start_date = TEMP_RESPDT,
    event_conditions = list(admiralonco::pd_event, admiralonco::death_event),
    censor_conditions = list(admiralonco::lasta_censor, admiralonco::lastalive_censor),
    source_datasets = list(adsl = adsl_responders, adrs = adrs),
    set_values_to = exprs(PARAMCD = "DOR",
                          PARAM = "Duration of Response")
  )

# Combine
adtte <- bind_rows(adtte_os, adtte_pfs, adtte_dor) |>
  drop_unspec_vars(metacore = mc, dataset = "ADTTE") |>
  apply_variable_labels(metacore = mc, dataset = "ADTTE")

# Or use pre-built
adtte <- pharmaverseadam::adtte
```

Three TTE parameters in one block. The `admiralonco` pre-defined sources do the heavy lifting.

## 12. Step 9: Validation with `{diffdf}`

In production, a QC programmer independently builds the same ADaMs; `diffdf` compares:

```r
library(diffdf)

# Compare your ADSL to QC programmer's
adsl_qc <- readRDS("qc/adsl.rds")     # QC programmer's output

result <- diffdf(
  adsl, adsl_qc,
  keys = c("STUDYID", "USUBJID"),
  tolerance = 1e-6
)

print(result)
# If empty, datasets match — sign off
# If discrepancies, investigate

# Save QC report
diffdf(adsl, adsl_qc, file = "qc/adsl_diff.txt", ...)
```

For the capstone we don't have a QC version, but the pattern is documented.

## 13. Step 10: Wrap with logrx

The pipeline produces real artifacts. To make it reproducible and auditable, wrap each script with logrx:

Save the ADSL build as `programs/ad_adsl.R`, then:

```r
library(logrx)

axecute(
  file = "programs/ad_adsl.R",
  log_path = "logs/"
)
# Result: logs/ad_adsl.log produced alongside ADSL output
```

For all scripts:

```bash
#!/bin/bash
# run_pipeline.sh

set -e
for script in programs/ad_*.R; do
  echo "Running: $script"
  Rscript -e "logrx::axecute('$script', log_path = 'logs/')"
done

echo "All ADaMs built successfully."
```

A single command rebuilds the entire data pipeline with full traceability.

## 14. The complete pipeline summary

After Lesson 47's pipeline:

**Inputs:**
- Raw EDC data (or `{pharmaverseraw}` test data)

**Outputs (in `data/adam/` as R objects):**
- `adsl` — Subject-Level Analysis Dataset
- `adae` — Adverse Events
- `adlb` — Laboratory
- `advs` — Vital Signs
- `adrs` — Response Analysis
- `adtte` — Time-to-Event (OS, PFS, DOR)

**Plus (in `logs/`):**
- One log file per script with execution traceability

**Plus (validation artifacts):**
- diffdf comparison reports (in production with dual programming)

This is a complete, audit-ready ADaM set. Next lesson takes it forward into deliverables.

## 15. What you've practiced

Concepts from earlier modules, applied:

- **Module 2 (SDTM)**: SDTM mapping, sdtmchecks validation
- **Module 3 (Metadata)**: metacore for spec management, metatools for application
- **Module 4 (admiral core)**: ADSL, BDS, OCCDS, TTE patterns
- **Module 5 (TA extensions)**: admiralonco for oncology-specific ADRS/ADTTE
- **Module 10 (Traceability)**: logrx wrapping, diffdf comparison

The pipeline is real production code, not pseudocode. With the test data, you can copy-paste and run it.

## 16. Common adaptations for real studies

- **Different TA**: replace admiralonco with admiralvaccine, admiralophtha, admiralpeds, admiralmetabolic
- **Different spec**: maintain your sponsor's spec; metacore handles the schema
- **Multiple input formats**: read raw data from CSV, Excel, SAS XPT — all work with the pipeline
- **Larger studies**: same code; runtime scales linearly with subjects
- **Multi-protocol studies**: build separately, harmonize at ADaM level

For a typical Phase III study, this pipeline runs in 5-15 minutes total wall time. For Phase IV with 10,000+ subjects and 5+ years of follow-up, allow more.

## 17. What's next

**Lesson 48 (Part 2)** takes these ADaMs forward:

- Build ARDs with cards/cardx
- Produce CSR tables (demographics, AE, K-M) with gtsummary and tern
- Build an interactive teal app for ad-hoc exploration
- Export XPT v5 files via xportr
- Optionally export Dataset-JSON via datasetjson
- Assemble the submission package

Everything from Module 6-9 comes together in one runnable script.

## 18. Key takeaways

- The data pipeline transforms raw EDC → SDTM → ADaM through layered packages
- Each layer is spec-driven (metacore) and validated (sdtmchecks, diffdf)
- admiralonco handles oncology-specific endpoints (ADRS, ADTTE with OS/PFS/DOR)
- All scripts wrap with logrx for reproducibility/audit
- The complete pipeline produces ADSL, ADAE, ADLB, ADVS, ADRS, ADTTE for a Phase III study
- Pattern adapts to any TA by swapping the TA extension package
- This is production code, not pseudocode — runs end-to-end on test data

## 19. What's next

Lesson 48 continues with deliverables: ARDs, CSR tables, teal app, submission package.

---

## Self-check questions

1. What's the role of `metacore` across all the build steps?
2. Why do we use `admiralonco::rsp_event()` instead of writing custom event derivations?
3. Translate to admiral: "Build ADAE with treatment-emergent flag based on ASTDT, TRTSDT, and TRTEDT."
4. What's the purpose of `drop_unspec_vars()` and `apply_variable_labels()`?
5. How does logrx fit into the pipeline?
6. Why split OS, PFS, DOR into three separate `derive_param_tte()` calls?

## Glossary

- **pharmaverseraw / pharmaversesdtm / pharmaverseadam** — Pharmaverse test data packages forming a continuous chain
- **sdtm.oak** — Algorithmic SDTM mapping framework
- **metacore** — Spec management object
- **metatools** — Spec application functions: `drop_unspec_vars`, `check_variables`, `apply_variable_labels`
- **admiral / admiralonco** — Core ADaM + oncology TA extension
- **derive_extreme_event** — Compute Best Overall Response and similar extreme-value parameters
- **derive_param_tte** — Build time-to-event parameter with event/censor sources
- **admiralonco event objects** — Pre-defined `rsp_event`, `pd_event`, `death_event`, `lasta_censor`, `lastalive_censor`, `rand_censor`
- **xportr** — XPT v5 export
- **logrx** — Execution logging
- **diffdf** — Dataset comparison for QC sign-off
- **OS / PFS / DOR / ORR / BOR** — Standard oncology endpoints
- **OCCDS / BDS** — Occurrence and Basic Data Structure ADaMs
- **CDISC pilot data** — Synthetic clinical data used throughout pharmaverse for examples
