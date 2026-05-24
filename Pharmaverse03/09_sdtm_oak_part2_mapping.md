# Lesson 09 — `{sdtm.oak}` Part 2: Building SDTM Domains End-to-End

**Module**: 2 — Raw data and SDTM
**Estimated length**: ~30 min spoken
**Prerequisites**: Lesson 08 (sdtm.oak Part 1)

---

## Learning objectives

By the end of this lesson, you will be able to:

1. Distinguish the four SDTM observation classes — **Findings**, **Events**, **Interventions**, **Findings About** — and choose the right OAK pattern for each
2. Build a complete **Findings** domain (Vital Signs, VS) end-to-end from raw data
3. Build a complete **Events** domain (Adverse Events, AE) end-to-end
4. Apply common domain-wide derivations: USUBJID, `--SEQ`, `--DY` (study day), `--BLFL` (baseline flag)
5. Bind topic-variable results into a single domain dataset
6. Compare your OAK output to the canonical SDTM in `{pharmaversesdtm}` to validate your derivation

---

## 1. The four SDTM observation classes

Before writing code, you need to know which class your domain belongs to. SDTMIG defines four observation classes, each with a different shape:

| Class | Example domains | Structure |
|---|---|---|
| **Findings** | VS, LB, EG, QS, FA | One row per **finding** (test result), with `--TESTCD` topic |
| **Events** | AE, DS, MH, CE | One row per **event**, with `--TERM` topic |
| **Interventions** | EX, EC, CM, SU | One row per **intervention** (drug administration), with `--TRT` topic |
| **Findings About** | FA | Findings about another domain (e.g., AE-specific findings); topic = `--OBJ` |

The class determines the OAK pattern:

- **Findings** typically use **transpose** semantics — a single raw row with columns SYS_BP, DIA_BP, PULSE becomes three SDTM rows
- **Events** typically map **one raw row → one SDTM row** with the event term in `--TERM`
- **Interventions** are similar to events — one raw row → one SDTM row with the treatment name in `--TRT`
- **Findings About** are typically derived from Events data with an explicit `--OBJ` linking back

For this lesson we'll build VS (Findings) and AE (Events). Interventions follow the Events pattern; Findings About is rare and follows Findings.

## 2. Setting up our working session

We'll use `pharmaverseraw` as input and compare to `pharmaversesdtm` as the expected output.

```r
library(sdtm.oak)
library(pharmaverseraw)
library(pharmaversesdtm)
library(dplyr)

# Raw inputs
data("vs_raw")
data("ae_raw")
data("dm_raw")    # we'll need DM for reference dates

# Expected outputs (for comparison)
data("vs", package = "pharmaversesdtm")
data("ae", package = "pharmaversesdtm")
```

Note: the exact contents of `vs_raw`, `ae_raw`, etc. depend on your installed version. The patterns shown below match how OAK code is typically structured; adapt column names to whatever your version contains.

## 3. Building VS (Findings) — overview

In raw data, vital signs are typically collected **wide**: one row per visit, with SYS_BP, DIA_BP, PULSE, RESP, TEMP as columns. In SDTM, VS is **long**: one row per parameter per visit, with the parameter name in VSTESTCD.

So our derivation has to:

1. For each parameter (SYS_BP, DIA_BP, PULSE, RESP, TEMP), build a separate "topic block" of rows
2. Bind those topic blocks together (the implicit transpose)
3. Apply visit-level qualifiers (VSDTC, VISIT, VISITNUM, VSTPT, VSTPTNUM) to all rows
4. Apply subject-level keys (STUDYID, DOMAIN, USUBJID)
5. Derive --SEQ and --DY

## 4. VS — preparing the raw data

```r
# Attach OAK identifiers to the raw data
vs_raw <- vs_raw |>
  generate_oak_id_vars(
    pat_var = "PATNUM",
    raw_src = "vs_raw"
  )

# Load CT spec — assume the file is "study_ct.csv" in your project root
study_ct <- read_ct_spec("study_ct.csv")
```

For demo purposes, you can use the example CT spec from sdtm.oak:

```r
study_ct <- read_ct_spec_example("ct-01-cm")
# (Note: this is a CM-flavored example; for VS, you'd typically have your own spec)
```

## 5. VS — building topic blocks

For each parameter, we build a topic block by:

1. Hardcoding `VSTESTCD` and `VSTEST`
2. Mapping `VSORRES` (original result) from the raw value column
3. Hardcoding `VSORRESU` (units)
4. Mapping any topic-specific qualifiers

Here's the SYSBP block:

```r
vs_sysbp <-
  hardcode_ct(
    raw_dat = vs_raw,
    raw_var = "SYS_BP",
    tgt_var = "VSTESTCD",
    tgt_val = "SYSBP",
    ct_spec = study_ct,
    ct_clst = "C66741"
  ) |>
  hardcode_ct(
    raw_dat = vs_raw,
    raw_var = "SYS_BP",
    tgt_var = "VSTEST",
    tgt_val = "Systolic Blood Pressure",
    ct_spec = study_ct,
    ct_clst = "C67153",
    id_vars = oak_id_vars()
  ) |>
  assign_no_ct(
    raw_dat = vs_raw,
    raw_var = "SYS_BP",
    tgt_var = "VSORRES",
    id_vars = oak_id_vars()
  ) |>
  hardcode_ct(
    raw_dat = vs_raw,
    raw_var = "SYS_BP",
    tgt_var = "VSORRESU",
    tgt_val = "mmHg",
    ct_spec = study_ct,
    ct_clst = "C66770",
    id_vars = oak_id_vars()
  )
```

Some things worth noticing:

- **The first call has no `id_vars = oak_id_vars()`** — it's establishing the result tibble. Subsequent calls pass `id_vars` to merge correctly.
- **Each call writes to one target variable** — the API enforces "one mapping at a time."
- **`raw_var = "SYS_BP"` is used even for hardcoded values** — it identifies which raw rows become SDTM rows for this topic. Effectively: "for every raw row where SYS_BP exists, create a VSTESTCD = 'SYSBP' row."

Repeat for DIASBP:

```r
vs_diabp <-
  hardcode_ct(vs_raw, raw_var = "DIA_BP", tgt_var = "VSTESTCD",
              tgt_val = "DIABP", ct_spec = study_ct, ct_clst = "C66741") |>
  hardcode_ct(vs_raw, raw_var = "DIA_BP", tgt_var = "VSTEST",
              tgt_val = "Diastolic Blood Pressure", ct_spec = study_ct,
              ct_clst = "C67153", id_vars = oak_id_vars()) |>
  assign_no_ct(vs_raw, raw_var = "DIA_BP", tgt_var = "VSORRES",
               id_vars = oak_id_vars()) |>
  hardcode_ct(vs_raw, raw_var = "DIA_BP", tgt_var = "VSORRESU",
              tgt_val = "mmHg", ct_spec = study_ct, ct_clst = "C66770",
              id_vars = oak_id_vars())
```

And similarly for PULSE, RESP, TEMP. The pattern is identical; only the raw column name, codelist, and unit change.

## 6. VS — binding topic blocks and adding visit qualifiers

```r
# Bind all topic blocks together
vs <- bind_rows(vs_sysbp, vs_diabp, vs_pulse, vs_resp, vs_temp)

# Apply qualifiers that are common to all topic rows
vs <- vs |>
  # Date/time as ISO 8601
  assign_datetime(
    raw_dat = vs_raw,
    raw_var = c("VS_DT", "VS_TM"),
    tgt_var = "VSDTC",
    raw_fmt = c("dd-mmm-yyyy", "H:M"),
    id_vars = oak_id_vars()
  ) |>
  # Visit qualifiers
  assign_ct(
    raw_dat = vs_raw,
    raw_var = "VISIT",
    tgt_var = "VISIT",
    ct_spec = study_ct,
    ct_clst = "VISIT",
    id_vars = oak_id_vars()
  ) |>
  assign_ct(
    raw_dat = vs_raw,
    raw_var = "VISIT",
    tgt_var = "VISITNUM",
    ct_spec = study_ct,
    ct_clst = "VISITNUM",
    id_vars = oak_id_vars()
  )
```

Visit and visit number both come from the same raw VISIT column — controlled terminology gives us both the human-readable visit name and the numeric visit number. The CT spec encodes that mapping (each `VISIT` value in the spec has both a `term_value` like "Screening" and a corresponding number).

## 7. VS — domain-level mappings

Now the variables that apply to every row regardless of topic:

```r
vs <- vs |>
  mutate(
    STUDYID = "TEST_STUDY",
    DOMAIN = "VS",
    USUBJID = paste("TEST_STUDY", patient_number, sep = "-")
  )
```

Here we use straight `dplyr::mutate()` rather than OAK functions. STUDYID/DOMAIN/USUBJID are domain-wide constants where an OAK call would be overkill — `mutate()` is more readable.

Note: in newer versions, OAK includes helpers like `oak_calc_ref_dates()` and `calc_min_max_date()` for DM-domain-specific work. Outside DM, simple `mutate()` is fine.

## 8. VS — deriving `--SEQ` (sequence number)

```r
vs <- vs |>
  derive_seq(
    tgt_var = "VSSEQ",
    rec_vars = c("USUBJID", "VSTESTCD", "VISIT")
  )
```

`derive_seq()` produces a 1-based row sequence number within each combination of `rec_vars`. The choice of `rec_vars` determines the uniqueness — typically subject + topic + visit, but follow your SDTM spec.

## 9. VS — deriving `--DY` (study day)

Study day is the number of days from a reference date (typically `RFXSTDTC`, the first dose date) to the observation date. By convention, the reference day is Day 1; days before it are negative (no Day 0).

```r
# Suppose dm is the SDTM DM domain (we'd build this with sdtm.oak too,
# but for VS derivation we can use the test version):
data("dm", package = "pharmaversesdtm")

vs <- vs |>
  derive_study_day(
    sdtm_in = _,
    dm_domain = dm,
    tgdt = "VSDTC",
    refdt = "RFXSTDTC",
    study_day_var = "VSDY"
  )
```

`derive_study_day()` handles the date math and the "no Day 0" convention. It joins DM by USUBJID, parses both ISO 8601 dates, and computes the day.

Note the `sdtm_in = _` syntax — the underscore is base R's pipe placeholder for "the piped-in value." In dplyr chains with arguments not named `data`, this is how you pass the upstream tibble.

## 10. VS — deriving `--BLFL` (baseline flag)

```r
vs <- vs |>
  derive_blfl(
    sdtm_in = _,
    dm_domain = dm,
    tgt_var = "VSBLFL",
    ref_var = "RFXSTDTC",
    baseline_visits = c("SCREENING", "BASELINE")
  )
```

`derive_blfl()` implements the standard baseline flag derivation per CDISC convention:

- For each USUBJID × VSTESTCD combination
- Among rows where VSDTC ≤ RFXSTDTC AND the visit is in the listed baseline visits
- Flag the last (chronologically) row as `Y`
- Exclude rows where the result is missing or status indicates "NOT DONE"

This is a tedious derivation to write by hand; the function encodes the standard rules. It also accepts a `baseline_timepoints` argument for studies that collect multiple baseline timepoints (e.g., for cardiology with multiple ECG runs).

There's also a sibling `--LOBXFL` (Last Observation Before Exposure Flag) that uses the same function with a different `tgt_var`.

## 11. VS — final touch: column ordering and types

SDTM datasets have a defined variable order per SDTMIG. Reorder:

```r
vs_final <- vs |>
  select(
    STUDYID, DOMAIN, USUBJID, VSSEQ,
    VSTESTCD, VSTEST,
    VSORRES, VSORRESU,
    VISITNUM, VISIT,
    VSDTC, VSDY,
    VSBLFL,
    everything()
  )
```

Strictly, you'd also check that column types match the SDTM model (mostly character, with a few numeric like VSSEQ, VISITNUM, VSDY). XPT export (covered in Module 9) handles final type coercion.

## 12. Events: building AE end-to-end

Events are simpler than Findings because there's no transpose — one raw row becomes one SDTM row.

```r
# Prepare raw
ae_raw <- ae_raw |>
  generate_oak_id_vars(pat_var = "PATNUM", raw_src = "ae_raw")

# Build the AE domain
ae <- ae_raw |>
  # Topic variable: AETERM
  assign_no_ct(
    raw_var = "AETERM",
    tgt_var = "AETERM",
    id_vars = oak_id_vars()
  ) |>
  # Severity (CT)
  assign_ct(
    raw_dat = ae_raw,
    raw_var = "AESEV",
    tgt_var = "AESEV",
    ct_spec = study_ct,
    ct_clst = "C66769",            # Severity codelist
    id_vars = oak_id_vars()
  ) |>
  # Seriousness (CT, Y/N)
  assign_ct(
    raw_dat = ae_raw,
    raw_var = "AESER",
    tgt_var = "AESER",
    ct_spec = study_ct,
    ct_clst = "NY",                # No/Yes codelist
    id_vars = oak_id_vars()
  ) |>
  # Outcome (CT)
  assign_ct(
    raw_dat = ae_raw,
    raw_var = "AEOUT",
    tgt_var = "AEOUT",
    ct_spec = study_ct,
    ct_clst = "C66768",            # Outcome codelist
    id_vars = oak_id_vars()
  ) |>
  # Start date as ISO 8601
  assign_datetime(
    raw_dat = ae_raw,
    raw_var = "AESTDT",
    tgt_var = "AESTDTC",
    raw_fmt = "dd-mmm-yyyy",
    id_vars = oak_id_vars()
  ) |>
  # End date as ISO 8601
  assign_datetime(
    raw_dat = ae_raw,
    raw_var = "AEENDT",
    tgt_var = "AEENDTC",
    raw_fmt = "dd-mmm-yyyy",
    id_vars = oak_id_vars()
  )

# Apply domain-wide keys
ae <- ae |>
  mutate(
    STUDYID = "TEST_STUDY",
    DOMAIN = "AE",
    USUBJID = paste("TEST_STUDY", patient_number, sep = "-")
  ) |>
  derive_seq(
    tgt_var = "AESEQ",
    rec_vars = c("USUBJID", "AETERM", "AESTDTC")
  ) |>
  derive_study_day(
    sdtm_in = _,
    dm_domain = dm,
    tgdt = "AESTDTC",
    refdt = "RFSTDTC",
    study_day_var = "AESTDY"
  ) |>
  derive_study_day(
    sdtm_in = _,
    dm_domain = dm,
    tgdt = "AEENDTC",
    refdt = "RFSTDTC",
    study_day_var = "AEENDY"
  )
```

Two study day calls — one for AESTDTC → AESTDY, one for AEENDTC → AEENDY — since AE has both a start and an end day to derive.

Note what's **not** in our AE derivation:

- **AEDECOD / AEBODSYS / AESOC**: these come from medical coding (MedDRA) and are typically added in a separate step using a coding service or sponsor-internal coding tool. They're not part of OAK's scope.
- **AEACN, AEACNOTH, AECONTRT**: action taken, other action, concomitant treatment. These need to be in the raw data; if collected, map them with `assign_ct()`.

## 13. Comparing your output to `pharmaversesdtm`

A sanity check: load the canonical SDTM and compare.

```r
data("ae", package = "pharmaversesdtm")
canonical_ae <- ae

# Quick shape check
nrow(ae)
nrow(canonical_ae)

# Column overlap
intersect(names(ae), names(canonical_ae))
setdiff(names(canonical_ae), names(ae))     # things we didn't derive
setdiff(names(ae), names(canonical_ae))     # things we have that the canonical doesn't
```

You won't get an identical match (the canonical version is built from a different process, includes MedDRA coding, etc.), but **shape** and **core variable presence** should agree.

For real validation in production, you'd use `{diffdf}` (covered in Module 10) to compare a custom-derived SDTM against an expected reference.

## 14. Conditional mappings — when to use `condition_add()`

In our examples above, every raw row produced a corresponding SDTM row. Sometimes you only want some raw rows to produce SDTM rows. Example: AE raw data might have a "Reported AE?" flag — only flagged rows belong in the SDTM AE domain.

```r
ae <- ae_raw |>
  condition_add(REPORTED == "Y") |>          # only rows where REPORTED is "Y"
  assign_no_ct(
    raw_var = "AETERM",
    tgt_var = "AETERM",
    id_vars = oak_id_vars()
  ) |>
  # ... rest of the chain
```

Or, to map a value only when a specific condition holds (without filtering out rows):

```r
ae <- ae_raw |>
  assign_no_ct(raw_var = "AETERM", tgt_var = "AETERM", id_vars = oak_id_vars()) |>
  # Only set AEACNOTH for non-serious events
  condition_add(AESER == "N") |>
  assign_no_ct(raw_var = "ACNOTH_TEXT", tgt_var = "AEACNOTH", id_vars = oak_id_vars())
```

The condition lasts until the data frame is reassigned. The conditioned print header (`# Cond. tbl: ...`) helps you verify what's active.

## 15. Splitting domains by raw source

It's common to have **multiple raw datasets feeding one SDTM domain**. Example: AE collected on the main CRF + Serious AE collected on a separate SAE CRF. Each is a different raw dataset.

The pattern: process each raw dataset independently to a partial result, then `bind_rows()`. Each independent processing uses its own `generate_oak_id_vars()` with a different `raw_src` label, so downstream you can tell which row came from which source.

```r
ae_main_raw <- generate_oak_id_vars(ae_raw, pat_var = "PATNUM", raw_src = "ae_main")
sae_raw    <- generate_oak_id_vars(sae_raw, pat_var = "PATNUM", raw_src = "ae_sae")

ae_main_processed <- ae_main_raw |> ...    # full pipeline for main AE
sae_processed     <- sae_raw    |> ...    # full pipeline for SAE

ae_combined <- bind_rows(ae_main_processed, sae_processed)
```

OAK doesn't have a single "merge raw sources" function — you just compose with `bind_rows()`. The `raw_source` column in the result tells you which source each row came from, which is invaluable for QC and provenance.

## 16. Common gotchas

**Forgetting `id_vars = oak_id_vars()` after the first call.** Without it, the second call doesn't know how to merge into the result, leading to garbled output. The first call doesn't need it (no target dataset yet); every subsequent call does.

**Wrong codelist for `assign_ct()`.** If your raw value can't be found in the CT spec under the specified codelist, OAK alerts you. The fix is usually to check the spec's codelist code matches what you passed, or to extend the spec to handle the raw values you see.

**Date parsing failures.** `assign_datetime()` with the wrong `raw_fmt` will leave NA in the target. Use `problems()` after the call to see which rows failed:

```r
ae <- ae |>
  assign_datetime(...)
problems(ae)
```

**Confusing `raw_var` in hardcode calls.** The `raw_var` argument identifies which raw rows produce SDTM rows. For a hardcoded VSTESTCD value, `raw_var = "SYS_BP"` means "for every raw row where SYS_BP is recorded, create a VS row with VSTESTCD = 'SYSBP'." If you accidentally use a column that's always populated (like patient_number), you'd create an SDTM row for every raw row regardless of whether SYS_BP was measured — a common bug.

## 17. Key takeaways

- SDTM domains fall into four classes: Findings, Events, Interventions, Findings About
- Findings are built by topic-block + bind_rows; Events are one-to-one and simpler
- The standard OAK derivation flow: prepare raw (oak_id_vars) → topic mappings → bind rows → qualifiers → domain-wide keys → --SEQ → --DY → --BLFL
- `derive_seq()` numbers rows within a key combination; `derive_study_day()` does the date math with the no-Day-0 convention; `derive_blfl()` implements CDISC baseline rules
- Multiple raw datasets feeding one domain: process independently, bind_rows; the `raw_source` column tracks provenance
- Validate by comparing to the corresponding `pharmaversesdtm` dataset

## 18. What's next

Lesson 10 covers the harder edge cases: **SUPP-- (Supplemental Qualifiers)** domains and **RELREC** (related records). SUPP-- handles variables that don't fit the standard domain shape — common in real studies where you have sponsor-specific captured data. RELREC links rows across domains (e.g., an AE row linked to the EX row that caused it).

Lesson 11 wraps Module 2 with `{sdtmchecks}` — Roche-originated QC checks for analysis-impacting SDTM issues.

---

## Self-check questions

1. Why does a Findings domain need a "topic block + bind_rows" pattern, while an Events domain doesn't?
2. What's the role of `derive_seq()` in domain creation?
3. Translate to OAK: "Map raw `IT.RACE` to `RACE`, validate against codelist `C74457`."
4. How does `derive_study_day()` handle the "no Day 0" convention?
5. Why is `raw_source` set differently in `generate_oak_id_vars()` when you have multiple raw inputs for one domain?
6. What does `problems()` do after `assign_datetime()`?

## Glossary

- **Observation class** — One of Findings, Events, Interventions, Findings About (SDTM model categorization)
- **Topic variable** — The variable defining *what* the row is about (VSTESTCD, AETERM, EXTRT, FAOBJ)
- **Qualifier variable** — A variable describing the observation (VSORRES, AESEV, EXDOSE)
- **`--SEQ`** — The standard SDTM sequence number; unique within USUBJID per domain
- **`--DY`** — Study day; days from the reference dose date with no Day 0
- **`--BLFL`** — Baseline Flag; "Y" on the last pre-treatment observation per subject per test
- **`--LOBXFL`** — Last Observation Before Exposure Flag; related to BLFL but unconditional on the visit window
- **Topic block** — In Findings derivation, the rows for one parameter (e.g., all SYSBP rows) before binding
- **`raw_source`** — OAK column tagging which raw input each row came from; supports multi-source domains
