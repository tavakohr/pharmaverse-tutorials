# Lesson 17 — `{admiral}` Part 4: OCCDS Datasets (ADAE, ADCM)

**Module**: 4 — ADaM core
**Estimated length**: ~25 min spoken
**Prerequisites**: Lessons 14–16

---

## Learning objectives

By the end of this lesson, you will be able to:

1. Identify the OCCDS (Occurrence Data Structure) shape and which ADaMs use it
2. Build an ADAE (Adverse Events analysis dataset) end-to-end
3. Derive treatment-emergent flag (TRTEMFL) using `derive_var_trtemfl()`
4. Derive occurrence flags (AOCCFL, AOCCSFL, AOCC02FL) using `derive_var_extreme_flag()`
5. Apply MedDRA queries (SMQ, CQ) with `derive_vars_query()`
6. Adapt the same pattern to ADCM (Concomitant Medications) with WHODrug ATC classes

---

## 1. OCCDS at a glance

The Occurrence Data Structure (OCCDS) is for ADaMs where the row unit is **an event or an occurrence** rather than a measurement at a visit:

| ADaM | What each row represents |
|---|---|
| ADAE | One adverse event per subject |
| ADCM | One concomitant medication record per subject |
| ADMH | One medical history entry per subject |
| ADDV | One protocol deviation per subject |

The shape: every row has subject identifiers, the event/medication identifier (AETERM/CMTRT), start/end dates, severity/relationship variables, and a constellation of analysis flags. There's no PARAMCD/PARAM convention — the events are heterogeneous.

OCCDS datasets are usually narrower than BDS in row count (a typical AE dataset has a few thousand rows; a typical ADLB has hundreds of thousands), but the analysis flags are more numerous and the derivation logic more nuanced.

## 2. The OCCDS workflow

The canonical steps for building ADAE:

1. **Read AE and ADSL**
2. **Merge ADSL variables** onto AE
3. **Derive analysis dates**: ASTDT, AENDT, ASTDTM, AENDTM, ASTDY, AENDY
4. **Map severity / relationship**: ASEV, AREL (often direct copies of AESEV, AEREL)
5. **Derive treatment-emergent flag**: TRTEMFL
6. **Derive on-treatment flag**: ONTRTFL (sometimes same as TRTEMFL, sometimes different)
7. **Apply MedDRA queries**: SMQs (Standardized Queries) and sponsor CQs (Customized Queries)
8. **Derive occurrence flags**: AOCCFL, AOCCSFL (first occurrence per subject, per system organ class, etc.)
9. **Derive last-dose date** and other linked variables
10. **Derive analysis sequence**: ASEQ
11. **Finalize column ordering and labels**

## 3. Setup

```r
library(admiral)
library(dplyr, warn.conflicts = FALSE)
library(lubridate)
library(pharmaversesdtm)

ae <- pharmaversesdtm::ae |> convert_blanks_to_na()
adsl <- admiral::admiral_adsl
ex <- pharmaversesdtm::ex |> convert_blanks_to_na()

# Variables to bring from ADSL
adsl_vars <- exprs(TRTSDT, TRTEDT, TRT01A, TRT01P, AGE, SEX, RACE, SAFFL)
```

## 4. Merge ADSL and derive analysis dates

```r
adae <- ae |>
  derive_vars_merged(
    dataset_add = adsl,
    new_vars = adsl_vars,
    by_vars = exprs(STUDYID, USUBJID)
  ) |>
  # Numeric dates with imputation
  derive_vars_dt(
    new_vars_prefix = "AST",
    dtc = AESTDTC,
    highest_imputation = "M",
    date_imputation = "first",
    flag_imputation = "auto"
  ) |>
  derive_vars_dt(
    new_vars_prefix = "AEN",
    dtc = AEENDTC,
    highest_imputation = "M",
    date_imputation = "last"     # impute partial end dates to last
  ) |>
  # Datetimes (for ADaMs that need time precision)
  derive_vars_dtm(
    new_vars_prefix = "AST",
    dtc = AESTDTC,
    highest_imputation = "M"
  ) |>
  derive_vars_dtm(
    new_vars_prefix = "AEN",
    dtc = AEENDTC,
    highest_imputation = "M",
    date_imputation = "last",
    time_imputation = "last"
  ) |>
  # Study days
  derive_vars_dy(
    reference_date = TRTSDT,
    source_vars = exprs(ASTDT, AENDT)
  )
```

A few patterns worth noticing:

- **End-date imputation defaults to "last"**: a partial end date like `"2024-07"` becomes `2024-07-31`, which is the appropriate conservative imputation for "we know the AE was still ongoing at the end of July."
- **Imputation flags are derived**: `ASTDTF` records what was imputed for the start date (M = month imputed, D = day imputed). This is required for FDA submission documentation.
- **Date vs datetime**: ADAE often needs both. `ASTDT` for day-level analyses; `ASTDTM` for time-of-day-sensitive logic like treatment-emergent (where AE start time vs treatment time matters within the same day).

## 5. Severity and relatedness

Convention: copy SDTM severity (AESEV) to analysis severity (ASEV), and SDTM relatedness (AEREL) to analysis relatedness (AREL). You can also add numeric companions:

```r
adae <- adae |>
  mutate(
    ASEV = AESEV,
    AREL = AEREL,
    ASEVN = case_when(
      ASEV == "MILD"     ~ 1,
      ASEV == "MODERATE" ~ 2,
      ASEV == "SEVERE"   ~ 3,
      ASEV == "DEATH THREATENING" ~ 4
    )
  )
```

Sponsor-specific severity scales (e.g., NCI CTCAE grades for oncology) replace ASEV with grade variables (ATOXGR, ATOXGRN); we cover those in Module 5 with `{admiralonco}`.

## 6. Treatment-emergent flag: TRTEMFL

The single most important AE flag. CDISC ADaMIG defines TRTEMFL as "Y" when the AE was either:

- New (started after first dose), OR
- Worsened during treatment (started before first dose but increased in severity during the treatment window)

`derive_var_trtemfl()` handles this logic:

```r
adae <- adae |>
  derive_var_trtemfl(
    start_date = ASTDT,
    end_date = AENDT,
    trt_start_date = TRTSDT,
    trt_end_date = TRTEDT,
    end_window = 30,                  # how many days after treatment end to still count as TE
    initial_intensity = AESEV,        # not always available; CDISC convention uses AEITOXGR/AETOXGR
    intensity = AETOXGR                # for worsening logic
  )
```

The function returns the dataset with `TRTEMFL` populated. Optional arguments:

- `end_window`: extends the treatment window by N days for AE start consideration. Common values: 30 (oncology), 28 (typical), 0 (strict). Studies define this in the SAP.
- `initial_intensity` / `intensity`: required for "worsening" logic — without them, only new AEs are flagged TE.

When intensity (toxicity grade) is captured for both the start and the worst-during-AE, admiral can distinguish "AE present at baseline but worsened on treatment" from "AE present at baseline and didn't change." The former gets TRTEMFL = "Y", the latter doesn't.

For simpler studies without grade data, just provide start_date / trt_start_date / trt_end_date:

```r
adae <- adae |>
  derive_var_trtemfl(
    start_date = ASTDT,
    end_date = AENDT,
    trt_start_date = TRTSDT,
    trt_end_date = TRTEDT
  )
```

This flags AEs starting on or after TRTSDT and on or before TRTEDT (or within an end_window).

## 7. Linked variables: last dose date, dose at AE onset

Many submissions require knowing the dose at the time of each AE — particularly oncology and dose-finding studies. The pattern: use `derive_vars_joined()` to attach the last dose record before each AE start.

```r
adae <- adae |>
  derive_vars_joined(
    dataset_add = ex |> filter(EXDOSE > 0),
    by_vars = exprs(USUBJID),
    order = exprs(convert_dtc_to_dt(EXSTDTC)),
    new_vars = exprs(
      LDOSEDT = convert_dtc_to_dt(EXSTDTC),
      LDOSEDOSE = EXDOSE
    ),
    join_vars = exprs(EXSTDTC),
    filter_join = ASTDT >= convert_dtc_to_dt(EXSTDTC),
    mode = "last"
  )
```

`derive_vars_joined()` is the more powerful cousin of `derive_vars_merged()`. The key difference: the filter can reference *both* datasets' variables (here, `ASTDT >= EXSTDTC`). This is impossible with `derive_vars_merged()`.

The verbal interpretation: "For each AE row, look at all EX rows with EXDOSE > 0 where the EX start date is on or before the AE start date. Take the *last* such EX row. Bring across the EX start date as LDOSEDT and the dose as LDOSEDOSE."

After this, every AE row has the most recent prior dose date — critical for safety review.

## 8. Occurrence flags

Occurrence flags answer questions like:

- AOCCFL: Is this the first occurrence of *any* AE for this subject?
- AOCCSFL: Is this the first occurrence of an AE in this body system organ class (AESOC)?
- AOCC02FL: First occurrence of a grade ≥ 2 AE per subject?
- AOCC03FL: First occurrence of a grade ≥ 3 AE per subject?

The pattern: filter to relevant AEs, sort, and use `derive_var_extreme_flag()`:

```r
# AOCCFL: first treatment-emergent AE per subject
adae <- adae |>
  restrict_derivation(
    derivation = derive_var_extreme_flag,
    args = params(
      by_vars = exprs(STUDYID, USUBJID),
      order = exprs(ASTDT, AESEQ),
      new_var = AOCCFL,
      mode = "first"
    ),
    filter = TRTEMFL == "Y"
  )

# AOCCSFL: first treatment-emergent AE per subject per SOC
adae <- adae |>
  restrict_derivation(
    derivation = derive_var_extreme_flag,
    args = params(
      by_vars = exprs(STUDYID, USUBJID, AESOC),
      order = exprs(ASTDT, AESEQ),
      new_var = AOCCSFL,
      mode = "first"
    ),
    filter = TRTEMFL == "Y"
  )

# AOCC02FL: first grade ≥ 2 treatment-emergent AE per subject
adae <- adae |>
  restrict_derivation(
    derivation = derive_var_extreme_flag,
    args = params(
      by_vars = exprs(STUDYID, USUBJID),
      order = exprs(ASTDT, AESEQ),
      new_var = AOCC02FL,
      mode = "first"
    ),
    filter = TRTEMFL == "Y" & AETOXGR >= 2
  )
```

This pattern produces a family of flags that drive most AE summary tables (incidence by SOC, by severity, by relationship, etc.). The exact set you derive depends on your SAP.

For "first occurrence of *maximum* severity" — `slice_derivation()` is your friend:

```r
adae <- adae |>
  slice_derivation(
    derivation = derive_var_extreme_flag,
    args = params(
      by_vars = exprs(STUDYID, USUBJID),
      new_var = AOCCIFL,
      mode = "first"
    ),
    derivation_slice(
      filter = TRTEMFL == "Y",
      args = params(order = exprs(desc(ASEVN), ASTDT))
    )
  )
```

Order by ASEVN descending: max severity comes first; ties broken by start date.

## 9. MedDRA queries: SMQs and Customized Queries

A core safety analysis pattern: count AEs falling within a Standardized MedDRA Query (SMQ) — predefined hierarchical MedDRA groupings like "Hypersensitivity (Narrow)," "Convulsions (Broad)," "Hepatic Disorders (SMQ)."

CDISC ADaM convention: a variable like `SMQ01NAM` names the SMQ; `SMQ01CD` is its numeric code; `SMQ01SC` is the scope (Narrow/Broad). Similar for sponsor Customized Queries: `CQ01NAM`, `CQ02NAM`, etc.

To populate these, admiral's `derive_vars_query()` takes a **queries dataset** (typically built from sponsor MedDRA dictionary licenses) and matches each AE's AEDECOD/AELLT against the query members.

```r
# A queries dataset: long format with one row per (query × term)
queries <- tribble(
  ~PREFIX, ~GRPNAME,                       ~SCOPE,   ~SCOPEN, ~TERM_NAME,
  "SMQ01", "Hypersensitivity (SMQ)",       "NARROW", 2,       "ANAPHYLACTIC SHOCK",
  "SMQ01", "Hypersensitivity (SMQ)",       "NARROW", 2,       "RASH",
  "SMQ01", "Hypersensitivity (SMQ)",       "BROAD",  1,       "URTICARIA",
  "CQ02",  "GI Disorders (Customized)",    NA,       NA,      "NAUSEA",
  "CQ02",  "GI Disorders (Customized)",    NA,       NA,      "VOMITING"
)

adae <- adae |>
  derive_vars_query(dataset_queries = queries)
```

Output: `adae` now has columns `SMQ01NAM`, `SMQ01CD`, `SMQ01SC`, `CQ02NAM`, etc., populated where the AE belongs to the query. Each row can belong to multiple queries (one row per AE × query match could be needed; check current admiral docs for exact semantics).

Building the queries dataset: admiral provides `create_query_data()` to construct it from CDISC MedDRA-Q definitions or sponsor specs. The full process integrates with `{pharma-meddra}` and similar packages for MedDRA dictionary access.

For simpler studies without SMQs, you may have just sponsor-defined CQs (which are essentially "give me a list of preferred terms and a group name"). Those use the same `derive_vars_query()` machinery.

## 10. Multi-dose-frequency expansion: `create_single_dose_dataset()`

For long-running studies, EX records often summarize multiple doses ("subject took 50mg QD from Day 1 to Day 30"). For ADAE analyses that ask "what was the dose on the day this AE started?", you need one row per actual dose date.

`create_single_dose_dataset()` does this expansion:

```r
ex_single <- ex |>
  create_single_dose_dataset(
    dose_freq = EXDOSFRQ,                  # SDTM frequency variable
    start_date = EXSTDT,
    end_date = EXENDT,
    keep_source_vars = exprs(USUBJID, EXSTDT, EXENDT, EXDOSFRQ, EXDOSE)
  )
```

A row "QD from 2024-07-01 to 2024-07-15" expands to 15 rows, one per day. Now you can join `ex_single` to AE on USUBJID + date for an exact dose-on-day lookup.

This is used heavily in oncology PK and dose-modification analyses.

## 11. Derive ASEQ — analysis sequence

The final touch: a 1-based sequence number per (USUBJID × adjusted ordering) for sorting and ID purposes:

```r
adae <- adae |>
  derive_var_obs_number(
    new_var = ASEQ,
    by_vars = exprs(STUDYID, USUBJID),
    order = exprs(ASTDT, AESEQ),
    check_type = "error"
  )
```

`check_type = "error"` errors if the sorting doesn't produce a unique sequence; useful for catching tied records you forgot about.

## 12. ADCM follows the same pattern

ADCM (Concomitant Medications) reuses essentially the entire ADAE skeleton:

- Source SDTM is `cm` instead of `ae`
- `CMTRT` is the topic; `CMSTDTC`, `CMENDTC` are the dates
- `CMINDC` (indication), `CMDOSE`, `CMDOSU`, `CMDOSFRQ`, `CMROUTE` are commonly carried forward
- Treatment-emergent equivalent is `TRTEMFL` (same function works)
- Occurrence flag: AOCCFL, AOCCxFL similar to ADAE

ADCM-specific: **ATC class hierarchies** from WHODrug. CMs are coded to ATC codes (Anatomical Therapeutic Chemical classification system) at four levels — ATC1, ATC2, ATC3, ATC4 — typically held in the FACM (Findings About CM) SDTM dataset.

To bring them into ADCM:

```r
adcm <- adcm |>
  derive_vars_transposed(
    dataset_merge = facm,
    by_vars = exprs(USUBJID, CMGRPID, CMREFID),
    key_var = FATESTCD,
    value_var = FASTRESC,
    filter = FATESTCD %in% c("CMATC1CD", "CMATC2CD", "CMATC3CD", "CMATC4CD")
  )
```

`derive_vars_transposed()` pivots wide-from-long: pulls FACM rows for the four ATC test codes and adds them as columns on ADCM. There's a dedicated `derive_vars_atc()` that wraps this for the specific ATC use case.

After that, the rest of ADCM follows the ADAE pattern — treatment-emergent, occurrence flags, ASEQ.

## 13. Putting it together: a complete ADAE skeleton

```r
library(admiral)
library(dplyr)
library(pharmaversesdtm)
library(lubridate)

ae <- pharmaversesdtm::ae |> convert_blanks_to_na()
ex <- pharmaversesdtm::ex |> convert_blanks_to_na()
adsl <- admiral::admiral_adsl

adsl_vars <- exprs(TRTSDT, TRTEDT, TRT01A, TRT01P, AGE, SEX, RACE, SAFFL)

adae <- ae |>
  derive_vars_merged(dataset_add = adsl, new_vars = adsl_vars,
                     by_vars = exprs(STUDYID, USUBJID)) |>
  derive_vars_dt(new_vars_prefix = "AST", dtc = AESTDTC,
                 highest_imputation = "M", date_imputation = "first") |>
  derive_vars_dt(new_vars_prefix = "AEN", dtc = AEENDTC,
                 highest_imputation = "M", date_imputation = "last") |>
  derive_vars_dtm(new_vars_prefix = "AST", dtc = AESTDTC,
                  highest_imputation = "M") |>
  derive_vars_dtm(new_vars_prefix = "AEN", dtc = AEENDTC,
                  highest_imputation = "M", time_imputation = "last") |>
  derive_vars_dy(reference_date = TRTSDT,
                 source_vars = exprs(ASTDT, AENDT)) |>
  mutate(
    ASEV = AESEV,
    AREL = AEREL,
    ASEVN = case_when(
      ASEV == "MILD"     ~ 1,
      ASEV == "MODERATE" ~ 2,
      ASEV == "SEVERE"   ~ 3
    )
  ) |>
  derive_var_trtemfl(
    start_date = ASTDT,
    end_date = AENDT,
    trt_start_date = TRTSDT,
    trt_end_date = TRTEDT,
    end_window = 30
  ) |>
  derive_var_ontrtfl(
    start_date = ASTDT,
    ref_start_date = TRTSDT,
    ref_end_date = TRTEDT,
    ref_end_window = 30
  ) |>
  restrict_derivation(
    derivation = derive_var_extreme_flag,
    args = params(
      by_vars = exprs(STUDYID, USUBJID),
      order = exprs(ASTDT, AESEQ),
      new_var = AOCCFL,
      mode = "first"
    ),
    filter = TRTEMFL == "Y"
  ) |>
  restrict_derivation(
    derivation = derive_var_extreme_flag,
    args = params(
      by_vars = exprs(STUDYID, USUBJID, AESOC),
      order = exprs(ASTDT, AESEQ),
      new_var = AOCCSFL,
      mode = "first"
    ),
    filter = TRTEMFL == "Y"
  ) |>
  derive_var_obs_number(
    new_var = ASEQ,
    by_vars = exprs(STUDYID, USUBJID),
    order = exprs(ASTDT, AESEQ)
  )

glimpse(adae)
```

In ~50 lines you have a working ADAE. With MedDRA queries, ATC classes (for ADCM), and last-dose linking, it grows to perhaps 100 lines — still far shorter than the SAS equivalent.

## 14. Validation considerations

OCCDS validation has a few additional concerns vs. BDS:

- **Row counts**: confirm every SDTM AE row is represented (or explicitly excluded with reason)
- **TRTEMFL distribution**: spot-check that the count of TRTEMFL = "Y" matches your SAP's expected denominator
- **Occurrence flag totals**: AOCCFL = "Y" should equal the unique subject count with at least one TE AE
- **Date imputation**: review the AESTDTF distribution; high imputation rates suggest poor data quality at source

`{diffdf}` (Module 10) handles the dataset-level comparison; manual spot-checks handle the analytical sanity-check layer.

## 15. Key takeaways

- OCCDS = Occurrence Data Structure; one row per event (AE, CM, MH, DV)
- The canonical workflow: load → merge ADSL → derive dates → severity → TRTEMFL → occurrence flags → queries → last-dose linkage → ASEQ
- `derive_var_trtemfl()` implements the CDISC-standard treatment-emergent logic, with `end_window` and intensity arguments for customization
- `derive_var_extreme_flag()` + `restrict_derivation()` produces the family of AOCCxFL occurrence flags
- `derive_vars_query()` populates SMQs and CQs from a queries dataset
- `derive_vars_joined()` handles relationships with date conditions (e.g., last dose before AE)
- ADCM follows the same pattern with CM-specific extensions (ATC hierarchies via `derive_vars_atc()`)

## 16. What's next

Lesson 18 covers **time-to-event ADaMs (ADTTE)** — the time-to-event ADaM class used for primary endpoints in survival analyses (Overall Survival, Progression-Free Survival, Time to First Serious AE). The `event_source` / `censor_source` / `derive_param_tte()` framework is one of admiral's most elegant designs; once you grasp it, building any time-to-event endpoint becomes a few-lines exercise.

Lesson 19 wraps the admiral series with advanced patterns: period datasets, expected records, locf imputation, and integration patterns.

---

## Self-check questions

1. What's the OCCDS shape, and how does it differ from BDS?
2. Why is `derive_vars_dt(date_imputation = "last")` used for AEENDT but `"first"` for ASTDT?
3. What does TRTEMFL mean and what arguments does `derive_var_trtemfl()` need?
4. Translate to admiral: "Flag the first grade ≥ 3 treatment-emergent AE per subject as AOCC03FL."
5. Why use `derive_vars_joined()` instead of `derive_vars_merged()` for the last-dose-before-AE pattern?
6. What's the purpose of `create_single_dose_dataset()`?

## Glossary

- **OCCDS** — Occurrence Data Structure; one row per event/occurrence
- **TRTEMFL** — Treatment-Emergent Flag; "Y" for AEs new or worsened during treatment
- **AOCCFL** — Anti-occurrence Flag #1 (first occurrence per subject)
- **AOCCSFL** — First occurrence per (subject × system organ class)
- **AOCCxFL** — Family of occurrence flags by severity threshold
- **ASTDT / AENDT** — Analysis Start Date / End Date
- **ASTDY / AENDY** — Analysis Start Day / End Day (relative to TRTSDT)
- **ASEV / AREL** — Analysis Severity / Relatedness (from AESEV / AEREL)
- **ATOXGR** — Analysis Toxicity Grade (NCI CTCAE); oncology-specific
- **SMQ** — Standardized MedDRA Query; predefined MedDRA grouping
- **CQ** — Customized Query; sponsor-defined grouping
- **`derive_vars_query()`** — Apply SMQs / CQs to AE data
- **`derive_vars_joined()`** — Conditional join supporting filters on both datasets' variables
- **`create_single_dose_dataset()`** — Expand multi-dose EX records to one row per dose date
- **`derive_vars_atc()`** — Add ATC1–ATC4 columns from FACM (for ADCM)
