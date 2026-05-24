# Lesson 08 — `{sdtm.oak}` Part 1: Concepts and Architecture

**Module**: 2 — Raw data and SDTM
**Estimated length**: ~25 min spoken
**Prerequisites**: Lesson 07 (pharmaverseraw)

---

## Learning objectives

By the end of this lesson, you will be able to:

1. Explain what makes `sdtm.oak` different from "just doing SDTM in dplyr"
2. Describe the **reusable algorithm** concept that anchors the package's design
3. Identify the core algorithm functions: `assign_no_ct()`, `assign_ct()`, `hardcode_no_ct()`, `hardcode_ct()`, `assign_datetime()`, `condition_add()`
4. Use `generate_oak_id_vars()` to attach the OAK identifier columns that thread through all derivations
5. Understand controlled terminology spec format and load it with `read_ct_spec()`
6. Read the OAK pipeline pattern: raw data → algorithm chain → SDTM-shaped target

---

## 1. Why a special package for SDTM mapping?

You could, in principle, build SDTM datasets with nothing but `dplyr`. Filter the raw data, rename columns, derive USUBJID, mutate AESEQ — done. So why does pharmaverse maintain `{sdtm.oak}`?

The answer is **standardization through algorithms**. Roche's analysis of their internal SDTM mapping efforts found that ~80% of their 13,000+ SDTM variable mappings across 6 therapeutic areas could be expressed as instances of just 22 reusable algorithm patterns. That insight — that SDTM mapping is much more repetitive than it looks — is the foundation of OAK.

By turning each algorithm into a function, you get three benefits:

1. **Consistency.** Every "hardcode a value subject to controlled terminology" call uses the same function with the same arguments. No ad-hoc dplyr that reinvents the wheel differently each time.
2. **Metadata-readiness.** If algorithms are functions called with explicit arguments, those arguments can be stored in a spec spreadsheet. The package then has a path to **automate** SDTM generation from a metadata spec — that's the long-term roadmap.
3. **Validation.** Each algorithm is one tested function. Once `assign_ct()` is validated against its specification, every use of it inherits that validation. Compare to maintaining dozens of bespoke dplyr pipelines.

OAK stands for "Open Algorithm K" (variations exist) — but functionally, the name is just a brand. What matters is the algorithm-centric design.

## 2. The governance backdrop

`sdtm.oak` is collaboratively developed by Roche, Pfizer, GSK, Vertex, and Merck, sponsored by **CDISC COSA** (CDISC Open Source Alliance). It was inspired by Roche's internal `{roak}` package, then re-engineered from scratch to be open-source, EDC-agnostic, and standards-agnostic. The package version is still in its 0.x lifecycle — features are stable enough for production trial use but new domains and algorithms are added with each release.

Important scope note: the v0.1.0 release supports a majority of SDTM domains. Domains NOT in scope for the initial release include DM (added in v0.2.0), Trial Design Domains, SV, SE, RELREC, Associated Person domains, and the EPOCH variable across all domains. We'll cover what's available and call out gaps as we go.

## 3. Installation

```r
install.packages("sdtm.oak")
```

`sdtm.oak` depends on tidyverse packages but has a small overall footprint. If you've installed pharmaverse packages before, this one slots in alongside them.

## 4. The algorithm catalog

The package distinguishes **primary algorithms** (the main mapping action) from **sub-algorithms** (modifiers like "only if condition X"). The primary algorithms shipped (as of the current release) include:

| Algorithm | Function | Purpose |
|---|---|---|
| `assign_no_ct` | `assign_no_ct()` | Map a raw variable to an SDTM variable with no controlled terminology |
| `assign_ct` | `assign_ct()` | Map a raw variable to an SDTM variable subject to CT recoding |
| `assign_datetime` | `assign_datetime()` | Map date/time component(s) to an ISO 8601 SDTM datetime variable |
| `hardcode_no_ct` | `hardcode_no_ct()` | Set an SDTM variable to a fixed value (no CT) |
| `hardcode_ct` | `hardcode_ct()` | Set an SDTM variable to a fixed value (with CT check) |
| `condition_add` | `condition_add()` | Apply subsequent mappings only when a condition holds |

There are additional algorithms on the roadmap (multi-response, group-by, dataset-level, RELREC, etc.) that will arrive in future releases. For now, these six cover the bulk of mapping patterns.

A few derivation-focused functions complement the algorithms:

| Function | What it does |
|---|---|
| `generate_oak_id_vars()` | Attach the `oak_id` and `raw_source` columns required for tracing |
| `derive_seq()` | Derive a `--SEQ` (sequence number) variable per domain |
| `derive_study_day()` | Calculate study day (`--DY`) from an ISO 8601 date |
| `derive_blfl()` | Derive `--BLFL` (baseline flag) or `--LOBXFL` (last observation before exposure flag) |
| `create_iso8601()` | Convert collected date/time strings to ISO 8601 |
| `read_ct_spec()` | Read a controlled terminology spec from a file |
| `ct_map()` | Recode a vector according to a CT spec |

## 5. The OAK pipeline pattern

The conceptual flow for building an SDTM domain in `sdtm.oak`:

```
1. Load raw data
2. Attach OAK identifiers (generate_oak_id_vars)
3. Load CT spec (read_ct_spec)
4. For each topic variable in the domain:
     a. Map the topic variable (typically with hardcode_ct or assign_ct)
     b. Map qualifiers (--ORRES, --ORRESU, --STAT, etc.) using assign_* / hardcode_*
     c. Optionally filter with condition_add
5. Bind rows of all topic variables
6. Apply domain-level mappings (STUDYID, DOMAIN, USUBJID, --SEQ, --DY)
7. Derive baseline flags (derive_blfl)
8. Result: an SDTM domain dataset
```

This pattern is repeated for every domain, with the specifics determined by the raw data shape and the SDTM domain definition. In Lesson 09 we'll walk this end-to-end for a Findings domain (VS).

## 6. `oak_id_vars`: the threading concept

A key design choice in `sdtm.oak`: every raw row gets an `oak_id` column (a row identifier) and a `raw_source` column (a tag for which raw dataset it came from). Together with the original patient ID variable, these form what the package calls **OAK identifier variables** — `oak_id_vars()`.

The point: as a row flows through a chain of algorithm calls, OAK uses these identifiers to merge results back onto the right row. You're not modifying the original raw data; you're building up an SDTM-shaped result tibble, and the identifiers ensure each derived value lands on the correct row.

```r
library(sdtm.oak)
library(pharmaverseraw)
library(dplyr)

data("vs_raw", package = "pharmaverseraw")

# Attach the OAK identifier columns
vs_raw <- vs_raw |>
  generate_oak_id_vars(
    pat_var = "PATNUM",         # the raw patient ID column
    raw_src = "vs_raw"          # a label identifying this raw source
  )

glimpse(vs_raw)
```

You'll now see three new columns: `oak_id` (1, 2, 3, … assigned per row), `raw_source` (every value `"vs_raw"`), and `patient_number` (a renamed copy of `PATNUM`). Together these uniquely identify each raw row throughout the chain.

```r
oak_id_vars()
# c("oak_id", "raw_source", "patient_number")
```

This trio is what later algorithms pass as `id_vars = oak_id_vars()` to ensure correct row matching.

## 7. Algorithm walkthrough: `assign_no_ct()`

The simplest algorithm: copy a raw variable to an SDTM variable when no controlled terminology applies.

```r
# Example: in CM (Concomitant Medications), copy raw CMTRT to SDTM CMTRT
cm_with_trt <- assign_no_ct(
  raw_dat = cm_raw,
  raw_var = "IT.CMTRT",        # the raw variable name
  tgt_var = "CMTRT",           # the SDTM target variable name
  id_vars = oak_id_vars()
)
```

The function returns a tibble with the target variable populated. It can also accept a `tgt_dat` argument — if provided, the result is merged into that target dataset by `id_vars`, allowing you to chain mappings into a growing SDTM-shaped result.

A subtle behavior: only missing (NA) values are filled during each step — previously assigned (non-missing) values are retained. This means you can chain multiple `assign_no_ct()` calls with the same target, falling back from one source to another (e.g., try CMTRT first, then CMTRTOTH for "Other, specify" entries):

```r
cm_with_trt <- cm_raw |>
  assign_no_ct(raw_var = "IT.CMTRT",    tgt_var = "CMTRT") |>
  assign_no_ct(raw_var = "IT.CMTRTOTH", tgt_var = "CMTRT")
# First fills CMTRT from IT.CMTRT; second fills the remaining NAs from IT.CMTRTOTH
```

This priority-based filling is a common SAS DATA step pattern in SDTM mapping; `assign_no_ct()` makes it declarative.

## 8. Algorithm walkthrough: `assign_ct()`

The CT-aware sibling. When the SDTM variable is subject to a controlled terminology list (e.g., AESEV must be one of MILD/MODERATE/SEVERE), `assign_ct()` both maps the value and validates/recodes it against the CT spec.

```r
vs_position <- assign_ct(
  raw_dat = vs_raw,
  raw_var = "SUBPOS",          # raw value (might be "SITTING", "Sitting", "sit")
  tgt_var = "VSPOS",           # SDTM target subject to C71148 CT codelist
  ct_spec = study_ct,          # the CT spec data frame
  ct_clst = "C71148",          # the codelist ID (CDISC NCI code)
  id_vars = oak_id_vars()
)
```

If a raw value can't be mapped under the codelist, the function alerts the user — corrected controlled terminology functions to alert users when a value cannot be mapped according to the controlled terms. This prevents silent data quality issues from leaking into your SDTM.

## 9. Algorithm walkthrough: `hardcode_no_ct()` and `hardcode_ct()`

For SDTM variables whose value is fixed (not pulled from raw data):

```r
# Hardcode DOMAIN for the AE domain
ae <- hardcode_no_ct(
  raw_dat = ae_raw,
  raw_var = "AETERM",          # used to identify which rows get the value
  tgt_var = "DOMAIN",
  tgt_val = "AE",
  id_vars = oak_id_vars()
)
```

The `raw_var` argument here is a bit unusual: it's the raw variable used to determine *which rows* get the hardcoded value. Typically you use the topic variable for the row to be created. For DOMAIN, every row gets `"AE"`, so any non-null raw variable works to identify the row population.

`hardcode_ct()` is the CT-validated version — useful when the hardcoded value itself must conform to a codelist (e.g., setting `VSTESTCD = "SYSBP"` and validating against the VS Test Code codelist).

```r
vs_sysbp <- hardcode_ct(
  raw_dat = vs_raw,
  raw_var = "SYS_BP",
  tgt_var = "VSTESTCD",
  tgt_val = "SYSBP",
  ct_spec = study_ct,
  ct_clst = "C66741",          # VS Test Code codelist
  id_vars = oak_id_vars()
)
```

## 10. Algorithm walkthrough: `assign_datetime()`

ISO 8601 date/time variables (`--DTC` columns) are everywhere in SDTM. `assign_datetime()` handles the parsing-and-reformatting.

```r
vs_with_dt <- assign_datetime(
  raw_dat = vs_raw,
  raw_var = c("VTLD", "VTLTM"),                # date column + time column
  tgt_var = "VSDTC",                           # ISO 8601 SDTM target
  raw_fmt = c(list(c("d-m-y", "dd-mmm-yyyy")), # acceptable date formats
              "H:M"),                          # time format
  id_vars = oak_id_vars()
)
```

The function:

- Combines separate date and time inputs into a single ISO 8601 string
- Accepts a list of acceptable input formats for each component (handles real-world inconsistency, like dates entered as `15-JUL-2020` and `15-07-2020` in the same column)
- Returns partial ISO 8601 when components are missing (e.g., `"2020-07-15"` if time is missing — the package handles this gracefully)

If parsing fails for some rows, those rows are flagged. The `problems()` function gives you a tibble of parse failures to inspect:

```r
problems(vs_with_dt)
```

This is the package's way of saying "I didn't silently drop data; here's what went wrong."

## 11. Algorithm walkthrough: `condition_add()`

For "apply this mapping only when X holds." Creates a **conditioned data frame** — a tibble where a logical vector marks which rows are "active."

```r
# Map VSORRES only when the raw value is not blank
vs_orres_only_if_recorded <- vs_raw |>
  condition_add(SYS_BP != "" & !is.na(SYS_BP)) |>
  assign_no_ct(
    raw_var = "SYS_BP",
    tgt_var = "VSORRES",
    id_vars = oak_id_vars()
  )
```

The condition is held on the data frame; subsequent algorithm calls operate only on the rows where the condition is TRUE. This is OAK's answer to SAS's `IF condition THEN`. It composes cleanly with the algorithm chain.

## 12. Controlled terminology spec format

OAK's CT functions expect a **CT spec** — a data frame describing valid values per codelist, with columns roughly like:

```
codelist_code   codelist_name        term_code   term_value         collected_value
C66741          VS Test Code         SYSBP       Systolic BP        SYSBP
C66741          VS Test Code         DIABP       Diastolic BP       DIABP
C71148          Position             SITTING     Sitting            Sitting
C71148          Position             SITTING     Sitting            sit
C71148          Position             SITTING     Sitting            sitting
```

Note the multiple `collected_value` rows mapping to the same `term_value` — that's how OAK handles dirty raw data that uses inconsistent case or wording.

You read a spec from a file:

```r
study_ct <- read_ct_spec("study_ct.csv")
```

For exploration, OAK ships an example spec:

```r
example_path <- ct_spec_example("ct-01-cm")
study_ct <- read_ct_spec_example("ct-01-cm")
```

The example shows the expected columns and format. For your real study, you'll typically prepare the CT spec once per study (or per company-standard library), check it into version control, and reuse it across all domain derivations.

## 13. The "conditioned data frame" mechanic in detail

`condition_add()` doesn't subset the data — it tags it. This is a deliberate design choice: subsetting would lose rows, which matters when you're tracing each row back through the algorithm chain. Instead, OAK keeps all rows and applies subsequent mappings only to the active subset.

When you `print()` a conditioned tibble, it shows a special header line indicating it's conditioned, like `# Cond. tbl: 5/2/0` (5 TRUE, 2 FALSE, 0 NA). This is how you visually confirm the condition is doing what you expected.

After a mapping is applied, downstream operations see the result on active rows and NA on inactive rows. The conditioning gets "consumed" by the next operation that's aware of it.

## 14. Putting it together: the OAK style of code

A typical OAK derivation for one topic variable looks like this:

```r
library(sdtm.oak)
library(pharmaverseraw)
library(dplyr)

# Setup
data("vs_raw")
vs_raw <- generate_oak_id_vars(vs_raw, pat_var = "PATNUM", raw_src = "vitals")
study_ct <- read_ct_spec("study_ct.csv")

# Topic: SYSBP (systolic blood pressure)
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

This builds the SDTM rows for the SYSBP test from one raw column (`SYS_BP`). The same pattern repeats for DIABP, PULSE, RESP, etc. — at the end, you `bind_rows()` all the topic variables and apply domain-wide mappings (STUDYID, USUBJID, sequence number, study day).

We'll do this end-to-end in Lesson 09. For now, internalize the **shape** of OAK code:

- Functions are pipelined with `|>`
- Each function call deals with **one** target variable
- The pattern is: identify the row population, map the value, apply CT if needed
- Identifiers (`oak_id_vars()`) thread through to keep rows aligned

## 15. How OAK compares to alternatives

**vs. SAS macros for SDTM**: SAS approaches typically use big macro libraries per domain (one macro per AE, one per CM, etc.). OAK is more granular — one function per algorithm pattern, composed into domain pipelines.

**vs. plain dplyr**: dplyr can do everything OAK does. OAK adds standardization, validation against CT, declarative mapping intent, and a path toward metadata-driven automation. The trade-off is a learning curve for the OAK conventions.

**vs. proprietary tools like Pinnacle 21 or LSAF mapping**: those tools provide UIs for SDTM construction. OAK is code-first, scriptable, and version-controllable — preferred by programmers who want their derivations to be reviewable in git.

## 16. Key takeaways

- `sdtm.oak` turns SDTM mapping into a small set of **reusable algorithm functions** that compose into domain pipelines
- The core algorithms are `assign_no_ct`, `assign_ct`, `hardcode_no_ct`, `hardcode_ct`, `assign_datetime`, and `condition_add`
- `generate_oak_id_vars()` attaches the row-tracing identifiers that thread through every algorithm
- Controlled terminology is held in a spec data frame and validated automatically by CT-aware algorithms
- `condition_add()` creates conditioned data frames — apply mappings to row subsets without losing rows
- The package targets full metadata-driven automation in future releases; today, you write the pipelines in R

## 17. What's next

Lesson 09 — Part 2 of `sdtm.oak` — walks through actual domain creation end-to-end. We'll build a Findings domain (VS, Vital Signs) and an Events domain (AE, Adverse Events) from `pharmaverseraw`, compare results to `pharmaversesdtm`, and discuss the differences between Findings, Events, Interventions, and Findings About class derivations.

After that, Lesson 10 covers the harder parts: SUPP-- (Supplemental Qualifiers) domains and RELREC (related records). Then Lesson 11 introduces `{sdtmchecks}` for quality control.

---

## Self-check questions

1. What's the difference between `assign_ct()` and `assign_no_ct()`?
2. Why does `sdtm.oak` use a "conditioned data frame" instead of filtering rows for condition_add?
3. What information is in `oak_id_vars()` and why does it matter?
4. Translate to OAK: "Set `AESER` from raw `IT.SER`, with allowed values Y/N."
5. What happens when you chain two `assign_no_ct()` calls writing to the same target variable?
6. Why are algorithms preferable to bespoke dplyr code for SDTM mapping?

## Glossary

- **OAK** — The algorithm framework underlying `sdtm.oak`; originally from Roche's internal `{roak}`
- **Algorithm** — A standardized reusable mapping pattern (assign with CT, hardcode without CT, etc.)
- **Sub-algorithm** — A modifier applied alongside a primary algorithm (e.g., condition_add)
- **CT spec** — Controlled terminology specification; a data frame describing valid values per codelist
- **Codelist** — A CDISC-defined set of allowed values for a variable (e.g., C66741 for VS test codes)
- **`oak_id_vars`** — The set of row-tracing columns (`oak_id`, `raw_source`, `patient_number`) attached by `generate_oak_id_vars()`
- **Conditioned data frame** — A tibble tagged with a logical condition; subsequent algorithm calls apply only to active rows
- **Topic variable** — The variable in a Findings domain identifying *what* was measured (VSTESTCD, LBTESTCD)
- **Qualifier variable** — A variable describing/contextualizing the topic (VSORRES, VSORRESU, etc.)
- **CDISC COSA** — CDISC Open Source Alliance; sponsors collaborative pharmaverse projects
