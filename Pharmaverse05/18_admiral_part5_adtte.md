# Lesson 18 — `{admiral}` Part 5: Time-to-Event ADaMs (ADTTE)

**Module**: 4 — ADaM core
**Estimated length**: ~25 min spoken
**Prerequisites**: Lessons 14–17

---

## Learning objectives

By the end of this lesson, you will be able to:

1. Explain the time-to-event ADaM shape and the role of CNSR (censor) variable
2. Use `event_source()` and `censor_source()` to define event and censoring rules declaratively
3. Use `derive_param_tte()` to add a time-to-event parameter to ADTTE
4. Build Overall Survival, Progression-Free Survival, and Time to First Serious AE parameters
5. Handle multi-source events (e.g., progression OR death for PFS)
6. Apply `call_derivation()` to compose multiple time-to-event parameters efficiently

---

## 1. The time-to-event ADaM shape

ADTTE follows BDS conventions with a few specific variables. **One row per (subject × parameter)**. Each row encodes:

- The time from a start date to either the event date or the censoring date
- A censor flag (CNSR): 0 = event happened, 1+ = censored
- A description of what event or censoring took place

A typical ADTTE looks like:

```
USUBJID    PARAMCD  PARAM                       STARTDT     ADT         AVAL  CNSR  EVNTDESC
01-001     OS       Overall Survival            2023-01-15  2024-06-22  524    1    LAST DATE KNOWN ALIVE
01-002     OS       Overall Survival            2023-02-10  2024-01-08  332    0    DEATH
01-001     PFS      Progression-Free Survival   2023-01-15  2024-03-10  420    0    DISEASE PROGRESSION
01-002     PFS      Progression-Free Survival   2023-02-10  2024-01-08  332    0    DEATH
```

Key variables:

- **STARTDT**: when the time-at-risk clock starts (usually TRTSDT or RANDDT)
- **ADT**: when the clock stops (event date OR censoring date)
- **AVAL**: ADT - STARTDT + 1 (days; sometimes converted to months or years)
- **CNSR**: 0 if event occurred, 1+ if censored (no event by ADT)
- **EVNTDESC**: human-readable description of what happened ("DEATH", "DISEASE PROGRESSION", "LAST DATE KNOWN ALIVE")
- **SRCDOM / SRCVAR**: which source domain and variable provided ADT — provenance

This shape is exactly what survival-analysis packages (`survival`, `survminer`, `tern` for KM plots) expect.

## 2. The big idea: source objects

Admiral's time-to-event design is one of the package's most elegant pieces. Instead of writing imperative code for each parameter ("for OS: if subject is dead, use death date; else use last alive date"), you **declaratively describe** the possible events and possible censorings, then admiral does the work.

Two object types:

- **`event_source()`** — describes one possible *event* (a thing that, if it happens, stops the clock with CNSR = 0)
- **`censor_source()`** — describes one possible *censoring* (a thing that, if no event happened by then, stops the clock with CNSR = 1+)

A time-to-event parameter is built from one or more of each. `derive_param_tte()` consumes the source objects and produces the parameter row.

## 3. Defining event and censor sources

A minimal Overall Survival definition: the event is death; the censoring is last known alive date.

```r
library(admiral)
library(dplyr)
library(lubridate)

# Event: death (from ADSL — already includes DTHDT)
death_event <- event_source(
  dataset_name = "adsl",
  filter = !is.na(DTHDT),
  date = DTHDT,
  set_values_to = exprs(
    EVNTDESC = "DEATH",
    SRCDOM = "ADSL",
    SRCVAR = "DTHDT"
  )
)

# Censoring: last known alive (from ADSL)
last_alive_censor <- censor_source(
  dataset_name = "adsl",
  date = LSTALVDT,
  set_values_to = exprs(
    EVNTDESC = "LAST DATE KNOWN ALIVE",
    SRCDOM = "ADSL",
    SRCVAR = "LSTALVDT"
  )
)
```

Each source object holds:

- `dataset_name`: an identifier (string) telling admiral which dataset this source pulls from
- `filter`: condition rows must meet to qualify (e.g., DTHFL = "Y" for death event)
- `date`: which variable provides the event/censoring date
- `set_values_to`: literal values to copy into the result row (descriptions, source domain/variable for provenance)

`censor_source()` also has an optional `censor` argument (defaulting to 1). For multi-censoring rules (e.g., "censored at last visit = 1, censored at randomization = 2"), pass `censor = 2` to differentiate.

## 4. Building the parameter with `derive_param_tte()`

```r
adsl <- admiral::admiral_adsl    # ships with admiral; has DTHDT and LSTALVDT

adtte <- derive_param_tte(
  dataset_adsl = adsl,
  start_date = TRTSDT,
  event_conditions = list(death_event),
  censor_conditions = list(last_alive_censor),
  source_datasets = list(adsl = adsl),
  set_values_to = exprs(
    PARAMCD = "OS",
    PARAM = "Overall Survival"
  )
)

# Inspect
adtte |>
  select(USUBJID, PARAMCD, STARTDT, ADT, AVAL, CNSR, EVNTDESC) |>
  head()
```

Arguments unpacked:

- `dataset_adsl`: defines the subject population (one row per subject = one TTE row per subject)
- `start_date`: column in ADSL providing the "clock start" date for each subject
- `event_conditions`: list of `event_source()` objects (may be more than one — see PFS below)
- `censor_conditions`: list of `censor_source()` objects (also can be multiple)
- `source_datasets`: named list mapping the `dataset_name` strings used in source objects to actual datasets in scope
- `set_values_to`: literal PARAMCD/PARAM values

Algorithm: for each subject in `dataset_adsl`, look at each event_source and censor_source in turn. If any event condition fires with a valid date ≤ start_date + max-time, set ADT to the earliest event date and CNSR = 0. Otherwise set ADT to the latest valid censoring date and CNSR = 1+. Compute AVAL = ADT - STARTDT + 1.

The output: a tibble with one row per subject, ready for survival analysis.

## 5. Multi-source events: Progression-Free Survival

PFS is the canonical example of a **composite event**: either disease progression OR death stops the clock. Either is acceptable as "an event."

We need an oncology-style ADRS dataset (Response) with progression dates:

```r
# Suppose adrs has rows like:
# USUBJID, PARAMCD, AVALC ("PD" for progression), ADT
adrs <- pharmaverseadam::adrs        # for illustration; structure varies

# Define the progression event
pd_event <- event_source(
  dataset_name = "adrs",
  filter = PARAMCD == "OVR" & AVALC == "PD",
  date = ADT,
  set_values_to = exprs(
    EVNTDESC = "DISEASE PROGRESSION",
    SRCDOM = "ADRS",
    SRCVAR = "ADT"
  )
)

# Death event reuses our earlier definition
# (death_event from above)

# Censor: last tumor assessment
last_assess_censor <- censor_source(
  dataset_name = "adrs",
  filter = PARAMCD == "OVR" & AVALC %in% c("CR", "PR", "SD", "NE"),
  date = ADT,
  set_values_to = exprs(
    EVNTDESC = "LAST TUMOR ASSESSMENT",
    SRCDOM = "ADRS",
    SRCVAR = "ADT"
  )
)

# Build PFS
adtte <- adtte |>
  derive_param_tte(
    dataset_adsl = adsl,
    start_date = RANDDT,
    event_conditions = list(pd_event, death_event),
    censor_conditions = list(last_assess_censor, last_alive_censor),
    source_datasets = list(adsl = adsl, adrs = adrs),
    set_values_to = exprs(
      PARAMCD = "PFS",
      PARAM = "Progression-Free Survival"
    )
  )
```

What admiral does:

- For each subject, check `pd_event`: did they progress? Note the date.
- Check `death_event`: did they die? Note the date.
- If either occurred: CNSR = 0; ADT = the earliest of progression date and death date; EVNTDESC reflects whichever fired.
- If neither occurred: CNSR = 1; ADT = the latest of last assessment and last alive; EVNTDESC reflects whichever.

This pattern generalizes to any composite endpoint — Disease-Free Survival (relapse OR death), Event-Free Survival (any of progression/relapse/death/secondary cancer), etc.

## 6. Including a randomization-date censor (oncology convention)

In oncology, some subjects are randomized but never have a tumor assessment (lost to follow-up early). To prevent these from being completely missing in the analysis, the convention is to **censor them at the randomization date**:

```r
# Censor: randomization date (catches subjects with no assessments)
rand_censor <- censor_source(
  dataset_name = "adsl",
  date = RANDDT,
  censor = 2,        # different censor reason from last_alive
  set_values_to = exprs(
    EVNTDESC = "RANDOMIZATION (NO ASSESSMENT)",
    SRCDOM = "ADSL",
    SRCVAR = "RANDDT"
  )
)

# Add to the censor list
adtte <- adtte |>
  derive_param_tte(
    dataset_adsl = adsl,
    start_date = RANDDT,
    event_conditions = list(pd_event, death_event),
    censor_conditions = list(last_assess_censor, last_alive_censor, rand_censor),
    source_datasets = list(adsl = adsl, adrs = adrs),
    set_values_to = exprs(PARAMCD = "PFS", PARAM = "Progression-Free Survival")
  )
```

If a subject has none of: progression, death, assessment, alive-date, then `RANDDT` becomes the (zero-time) censor — AVAL = 1 (one day from RANDDT to RANDDT, given the +1 convention), CNSR = 2.

Different censor values let downstream analyses distinguish (e.g., the SAP might require sensitivity analyses with rand_censor subjects excluded).

## 7. Multiple parameters: `call_derivation()`

If you need several TTE parameters with similar structure (OS, PFS, DFS, Time to Response, ...), `call_derivation()` calls `derive_param_tte()` multiple times with varying arguments:

```r
adtte <- adsl |>
  select(USUBJID) |>
  filter(FALSE) |>   # start with empty tibble
  call_derivation(
    derivation = derive_param_tte,
    variable_params = list(
      params(
        event_conditions = list(death_event),
        censor_conditions = list(last_alive_censor),
        set_values_to = exprs(PARAMCD = "OS",  PARAM = "Overall Survival")
      ),
      params(
        event_conditions = list(pd_event, death_event),
        censor_conditions = list(last_assess_censor, last_alive_censor, rand_censor),
        set_values_to = exprs(PARAMCD = "PFS", PARAM = "Progression-Free Survival")
      )
    ),
    # Shared arguments
    dataset_adsl = adsl,
    start_date = RANDDT,
    source_datasets = list(adsl = adsl, adrs = adrs)
  )
```

This is admiral's higher-order pattern again. Cleaner than stacking five `derive_param_tte()` calls.

## 8. Time to First Serious AE — using ADAE as source

Not all time-to-event analyses are about death. Safety analyses commonly use Time to First Serious AE:

```r
# Event: first serious AE
first_sae_event <- event_source(
  dataset_name = "adae",
  filter = AESER == "Y" & TRTEMFL == "Y",
  date = ASTDT,
  set_values_to = exprs(
    EVNTDESC = "FIRST SERIOUS AE",
    SRCDOM = "ADAE",
    SRCVAR = "ASTDT"
  )
)

# Censor: end of study or end of treatment window
eot_censor <- censor_source(
  dataset_name = "adsl",
  date = EOSDT,
  set_values_to = exprs(
    EVNTDESC = "END OF STUDY",
    SRCDOM = "ADSL",
    SRCVAR = "EOSDT"
  )
)

adtte <- adtte |>
  derive_param_tte(
    dataset_adsl = adsl |> filter(SAFFL == "Y"),
    start_date = TRTSDT,
    event_conditions = list(first_sae_event),
    censor_conditions = list(eot_censor, last_alive_censor),
    source_datasets = list(adsl = adsl, adae = adae),
    set_values_to = exprs(PARAMCD = "TTAESER",
                          PARAM = "Time to First Serious AE")
  )
```

Notice the `filter = AESER == "Y" & TRTEMFL == "Y"` on the event_source — only treatment-emergent serious AEs qualify. The earliest such AE date wins.

The pattern: for each subject in the safety population, the event is the first treatment-emergent SAE; the censoring is EOSDT (or LSTALVDT, whichever's earlier as a fallback).

## 9. Duration of Response — a subject-subset parameter

Some TTE parameters apply only to a subject subset. Duration of Response (DOR) is only meaningful for responders.

```r
# Event: progression for responders only
pd_responders <- event_source(
  dataset_name = "adrs",
  filter = PARAMCD == "OVR" & AVALC == "PD",
  date = ADT,
  set_values_to = exprs(EVNTDESC = "DISEASE PROGRESSION",
                        SRCDOM = "ADRS", SRCVAR = "ADT")
)

# Filter ADSL to responders only
responders <- adsl |>
  inner_join(
    adrs |>
      filter(PARAMCD == "OVR" & AVALC %in% c("CR", "PR")) |>
      distinct(USUBJID) |>
      mutate(RESPONDER = TRUE),
    by = "USUBJID"
  )

# Build DOR (response start = RSPDT; clock to progression or death)
adtte <- adtte |>
  derive_param_tte(
    dataset_adsl = responders,
    start_date = RSPDT,
    event_conditions = list(pd_responders, death_event),
    censor_conditions = list(last_assess_censor),
    source_datasets = list(adsl = responders, adrs = adrs),
    set_values_to = exprs(PARAMCD = "DOR", PARAM = "Duration of Response")
  )
```

Restricting via `dataset_adsl = responders` means only responding subjects get a DOR row. Non-responders don't appear in the DOR parameter at all — the standard convention.

## 10. Converting AVAL to other time units

`derive_param_tte()` calculates AVAL in days by default. For analyses in months or years:

```r
adtte <- adtte |>
  mutate(
    AVAL_MONTHS = AVAL / (365.25 / 12),
    AVAL_YEARS  = AVAL / 365.25
  )
```

Or use `derive_vars_duration()` separately if you need it with months-as-units logic. Most survival analyses do the unit conversion at the analysis step (in the `survival::survfit()` formula or in the TLG step), not in the ADaM — but if your spec explicitly stores months, build it here.

## 11. Pre-defined source objects in `{admiralonco}`

`{admiralonco}` (Module 5) provides ready-made `event_source()` and `censor_source()` objects for the common oncology endpoints, so you don't have to define them yourself. Example:

```r
library(admiralonco)

# admiralonco exports:
# death_event, lastalive_censor, pd_event, lasta_censor, rand_censor, ...

adtte <- adsl |>
  derive_param_tte(
    start_date = RANDDT,
    event_conditions = list(admiralonco::death_event),
    censor_conditions = list(admiralonco::lastalive_censor),
    source_datasets = list(adsl = adsl),
    set_values_to = exprs(PARAMCD = "OS", PARAM = "Overall Survival")
  )
```

For non-oncology studies, you define your own source objects per your SAP. The pattern from this lesson is reusable across therapeutic areas.

## 12. Validation considerations

ADTTE validation focuses on:

- **CNSR distributions**: are expected event/censoring proportions in line with the SAP?
- **AVAL distributions**: any negative values? Implausibly large values? (>5 years for OS in many indications)
- **EVNTDESC distribution**: which events / censorings are firing? Are subjects accumulating in expected EVNTDESC categories?
- **Subject completeness**: every analysis subject (per ADSL filter) should have exactly one row per PARAMCD

`{diffdf}` for dataset comparison; manual SAP-aligned cross-checks for sanity.

## 13. Putting it together

A complete oncology-flavored ADTTE for OS + PFS:

```r
library(admiral)
library(admiralonco)
library(dplyr)
library(pharmaverseadam)

adsl <- pharmaverseadam::adsl
adrs <- pharmaverseadam::adrs

# Use admiralonco's pre-defined source objects
adtte <- adsl |>
  derive_param_tte(
    start_date = RANDDT,
    event_conditions = list(admiralonco::death_event),
    censor_conditions = list(admiralonco::lastalive_censor),
    source_datasets = list(adsl = adsl, adrs = adrs),
    set_values_to = exprs(PARAMCD = "OS", PARAM = "Overall Survival")
  ) |>
  derive_param_tte(
    dataset_adsl = adsl,
    start_date = RANDDT,
    event_conditions = list(admiralonco::pd_event, admiralonco::death_event),
    censor_conditions = list(admiralonco::lasta_censor,
                              admiralonco::lastalive_censor,
                              admiralonco::rand_censor),
    source_datasets = list(adsl = adsl, adrs = adrs),
    set_values_to = exprs(PARAMCD = "PFS", PARAM = "Progression-Free Survival")
  )
```

Two parameters, ~30 lines of code, fully traceable via SRCDOM/SRCVAR. The analysis (Kaplan-Meier curves, Cox models) consumes this directly.

## 14. Key takeaways

- ADTTE is BDS-shaped but with TTE-specific variables: STARTDT, ADT, AVAL, CNSR, EVNTDESC, SRCDOM, SRCVAR
- `event_source()` and `censor_source()` declaratively describe possible events and censorings
- `derive_param_tte()` consumes source objects and produces one TTE row per subject
- Composite endpoints (PFS = progression OR death) use multiple event_sources in one call
- Multiple censor sources distinguish reasons (last-alive, last-assessment, randomization-date fallback)
- `call_derivation()` builds multiple parameters efficiently
- `{admiralonco}` provides pre-defined source objects for oncology endpoints

## 15. What's next

Lesson 19 — the final admiral lesson — covers **advanced patterns**: period datasets for crossover and extension studies, `derive_expected_records()` for "expected but missing" rows, LOCF (last observation carried forward) imputation with `derive_locf_records()`, integration with `{metacore}` for spec-driven ADaM, and how to extend admiral with your own custom functions.

After Lesson 19, Module 4 is complete and we move into Module 5 — the therapeutic area extensions (`{admiralonco}`, `{admiralvaccine}`, etc.).

---

## Self-check questions

1. What is CNSR, and what do its values mean?
2. What's the structural difference between `event_source()` and `censor_source()`?
3. For PFS, you pass two event_sources. What logic does `derive_param_tte()` apply to combine them?
4. Why does the oncology convention include a `rand_censor` censor with `censor = 2`?
5. Translate: "Time to first treatment-emergent SAE for safety population subjects, censored at EOSDT" — write the event_source and censor_source.
6. How does `call_derivation()` simplify building multiple TTE parameters?

## Glossary

- **ADTTE** — Time-to-Event ADaM; one row per (subject × parameter)
- **CNSR** — Censor flag; 0 = event, 1+ = censored
- **STARTDT** — Start date for the time-at-risk clock (TRTSDT, RANDDT, etc.)
- **ADT** — Analysis date (event date or censoring date, whichever applies)
- **AVAL** — Time on study (ADT - STARTDT + 1, in days)
- **EVNTDESC** — Human-readable description of event or censoring
- **SRCDOM / SRCVAR** — Source domain and variable that provided ADT (provenance)
- **`event_source()`** — Object describing one possible event
- **`censor_source()`** — Object describing one possible censoring
- **`derive_param_tte()`** — Function that consumes source objects and produces TTE rows
- **Composite endpoint** — TTE parameter where multiple events qualify (PFS = progression OR death)
- **`call_derivation()`** — Higher-order function for composing multiple derivations
