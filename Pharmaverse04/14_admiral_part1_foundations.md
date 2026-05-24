# Lesson 14 — `{admiral}` Part 1: Foundations and Philosophy

**Module**: 4 — ADaM core
**Estimated length**: ~25 min spoken
**Prerequisites**: Modules 1–3

---

## Learning objectives

By the end of this lesson, you will be able to:

1. State admiral's design manifesto and explain why it matters
2. Distinguish the four function families: `derive_var_*`, `derive_vars_*`, `derive_param_*`, and helper utilities
3. Explain admiral's use of `exprs()` for expression arguments
4. Apply the convention of `convert_blanks_to_na()` at the SDTM-load step
5. Use date/time helpers `derive_vars_dt()`, `derive_vars_dtm()`, `derive_vars_dy()` for ISO 8601 conversion and study day
6. Recognize common admiral patterns you'll see repeated across ADSL, BDS, and OCCDS

---

## 1. What admiral is

`{admiral}` is the **ADaM in R Asset Library** — pharmaverse's flagship package for building ADaM datasets. As of 2026 it's the most heavily used package in pharmaverse, with the largest contributor team (Roche, GSK, J&J, Pfizer, GlaxoSmithKline, and more) and the most active development.

The mission statement, in the maintainers' own words:

> Provide users with an open source, modularized toolbox with which to create ADaM datasets in R. As opposed to a "run one line and an ADaM appears" black-box solution or an attempt to automate ADaM.

This is the most important sentence to understand about admiral. **Admiral is not an automation tool.** You don't call `make_adsl()` and get an ADSL. You assemble an ADSL from many small admiral function calls, each doing one thing — much like building a SAS DATA step from many explicit statements.

The trade-off: more code than a black box, but every line is auditable, customizable, and matches CDISC convention. This is the philosophy that won admiral acceptance from regulators and Quality teams across the industry.

## 2. The manifesto

The maintainers publish an explicit "manifesto" of design principles:

> All admiral functions have a clear purpose. We try not to ever design single functions that could achieve numerous very different derivations.

Translation: if you see a function name like `derive_vars_dt()`, it does *one* thing — convert character ISO 8601 dates to numeric dates. If you needed to derive a flag, you'd reach for a different function (`derive_var_extreme_flag()`).

> We try to combine similar tasks and algorithms into one function where applicable to reduce the amount of repetitive functions with similar algorithms.

Translation: there's one study day calculation function, not one per ADaM variable name.

> Modularity is a focus — we don't try to achieve too many steps in one.

Translation: small functions, composed via pipes.

> All code has to be well commented.

Translation: when you read admiral source code (which you'll do, especially for understanding behavior or troubleshooting), the comments are extensive. This is part of the package's regulatory positioning.

Why does this manifesto matter to you as a user? It tells you what to expect:

- **Many small function calls** instead of a few large ones
- **Function names that describe specific actions**, not generic verbs
- **Predictable argument patterns** across functions
- **Composable** — you pipe outputs from one to the next

Once you internalize the manifesto, the API stops surprising you.

## 3. The function naming convention

Admiral has roughly 200+ exported functions. The names follow a strict convention that makes the catalog navigable:

| Prefix | Pattern | What it does |
|---|---|---|
| `derive_var_*` | One variable per call | Add or modify a single variable (e.g., `derive_var_trtdurd()` derives TRTDURD) |
| `derive_vars_*` | Multiple variables per call | Add multiple related variables in one call (e.g., `derive_vars_dt()` derives both the numeric date and its imputation flag) |
| `derive_param_*` | Add a new parameter row | Add observations for a new PARAMCD/PARAM (e.g., `derive_param_bmi()` derives BMI rows in ADVS) |
| `compute_*` | Pure scalar compute | Compute a single value without adding to a dataset (e.g., `compute_age_years()`) |
| `filter_*` | Filter dataset | Apply a filtering operation (e.g., `filter_extreme()` keeps first/last per group) |
| `convert_*` | Convert one type to another | Type/format conversions (e.g., `convert_dtc_to_dt()`) |
| `event_source()`, `date_source()` | Source objects | Build source-specification objects used by other derivations |

This is rigorously enforced. When you encounter a new admiral function, its prefix already tells you 80% of what it does.

Function names also embed the ADaM convention. `derive_vars_dt()` derives "DT" variables (analysis dates). `derive_vars_dtm()` derives "DTM" variables (analysis datetimes). `derive_vars_dy()` derives "DY" variables (study days). The package speaks fluent CDISC.

## 4. The expression argument pattern

Admiral arguments that take variable names use the `exprs()` helper:

```r
adsl |>
  derive_vars_merged(
    dataset_add = ex_ext,
    new_vars = exprs(TRTSDTM = EXSTDTM),
    order = exprs(EXSTDTM, EXSEQ),
    mode = "first",
    by_vars = exprs(STUDYID, USUBJID)
  )
```

`exprs(STUDYID, USUBJID)` is *not* a character vector `c("STUDYID", "USUBJID")`. It's a list of **unquoted expressions**. The difference matters because admiral uses these expressions internally to do filtering, sorting, and assignment in tidy-evaluation style.

A few rules:

- For arguments expecting **multiple variable names**: use `exprs(VAR1, VAR2)` — no quotes around variable names
- For arguments expecting **a single expression**: pass it directly — e.g., `filter = PARAMCD == "TEMP"`
- For arguments expecting **multiple expressions**: use `exprs(...)` — e.g., `order = exprs(AVISIT, desc(AESEV))`

This is the modern tidy-evaluation style. If you've used `dplyr::select(VAR1, VAR2)`, you've used the same pattern.

For deeper background: admiral's docs include a "Expressions in Scripts" section under Programming Concepts and Conventions. Worth reading once.

## 5. The first function you'll call: `convert_blanks_to_na()`

SAS XPT files often store missing character values as empty strings (`""`), not as proper NAs. R doesn't treat empty strings as missing; logical tests like `is.na(VAR)` return `FALSE` for empty strings.

Always start your admiral session by converting blanks to NA:

```r
library(admiral)
library(pharmaversesdtm)
library(dplyr)

dm <- pharmaversesdtm::dm |> convert_blanks_to_na()
ds <- pharmaversesdtm::ds |> convert_blanks_to_na()
ex <- pharmaversesdtm::ex |> convert_blanks_to_na()
ae <- pharmaversesdtm::ae |> convert_blanks_to_na()
```

This is the canonical opening of any admiral script. If you skip it, downstream derivations may silently produce wrong results because they treat empty strings as valid values rather than missing.

## 6. Date/time helpers — the foundation of every ADaM

ISO 8601 character dates (`--DTC`) come from SDTM. Most ADaM analyses need numeric dates (`ADT`, `ASTDT`) for math, or datetimes (`ADTM`) for time-of-day analyses. The three workhorse functions:

### `derive_vars_dt()` — character DTC → numeric Date

```r
adsl <- adsl |>
  derive_vars_dt(
    new_vars_prefix = "TRTS",
    dtc = RFXSTDTC,
    date_imputation = "first",
    flag_imputation = "auto"
  )
```

This derives two variables from `RFXSTDTC`:

- `TRTSDT`: the imputed numeric date
- `TRTSDTF`: an imputation flag indicating what was imputed (M = month imputed, D = day imputed, etc.)

`date_imputation = "first"` means: if day is missing, impute to first of month; if month is missing too, impute to first of year. Other options: `"last"` (last of month / last of year), `"none"` (return NA if any component is missing), and explicit dates.

This handles a famously tedious task — partial SDTM dates — that takes 50 lines of SAS to implement correctly.

### `derive_vars_dtm()` — character DTC → numeric Datetime

```r
ex_ext <- ex |>
  derive_vars_dtm(
    dtc = EXSTDTC,
    new_vars_prefix = "EXST",
    date_imputation = "first",
    time_imputation = "first"
  )
```

Derives `EXSTDTM` (numeric datetime) and `EXSTDTF` + `EXSTTMF` (date and time imputation flags). The `time_imputation` argument has its own conventions: `"first"` = 00:00:00, `"last"` = 23:59:59.

When you want a datetime that you'll later convert to just a date, `derive_vars_dtm_to_dt()` is the conversion:

```r
adsl <- adsl |>
  derive_vars_dtm_to_dt(source_vars = exprs(TRTSDTM, TRTEDTM))
# Produces TRTSDT and TRTEDT (the dates without time)
```

### `derive_vars_dy()` — derive study day

```r
advs <- advs |>
  derive_vars_dy(
    reference_date = TRTSDT,
    source_vars = exprs(ADT, AENDT)
  )
```

For each source variable (`ADT`, `AENDT`), this creates a corresponding day variable (`ADY`, `AENDY`) measured in days from the reference date (`TRTSDT`), with the "no Day 0" convention (Day 1 is the reference; Day -1 is the day before).

These three functions cover ~90% of date handling in ADaM construction. The remaining 10% is edge cases handled by `compute_duration()`, `derive_vars_duration()`, and a few others.

## 7. The most important function: `derive_vars_merged()`

This is the function you'll write the most. It joins variables from one dataset onto another, with filtering, ordering, and first/last selection.

The signature:

```r
derive_vars_merged(
  dataset,            # the target (left)
  dataset_add,        # the source (right)
  by_vars,            # join keys (as exprs())
  new_vars = NULL,    # which variables to add (with optional rename)
  order = NULL,       # how to order source rows
  filter_add = NULL,  # filter on source before joining
  mode = NULL,        # "first" / "last" / NULL
  match_flag = NULL,  # if TRUE, add a flag indicating match
  missing_values = NULL
)
```

Reading by example, here's the canonical "derive treatment start datetime" pattern:

```r
adsl <- adsl |>
  derive_vars_merged(
    dataset_add = ex_ext,
    filter_add = (EXDOSE > 0 |
                  (EXDOSE == 0 & str_detect(EXTRT, "PLACEBO"))) &
                  !is.na(EXSTDTM),
    new_vars = exprs(TRTSDTM = EXSTDTM, TRTSTMF = EXSTTMF),
    order = exprs(EXSTDTM, EXSEQ),
    mode = "first",
    by_vars = exprs(STUDYID, USUBJID)
  )
```

Verbal translation: "For each subject in adsl, look at ex_ext rows where the dose is non-zero (or zero for placebo) AND the start datetime is present. Order by EXSTDTM then EXSEQ. Take the first matching row. Bring across EXSTDTM and EXSTTMF, renaming them to TRTSDTM and TRTSTMF respectively."

That's the equivalent of:

```sas
proc sql;
  create table adsl as
  select a.*, b.EXSTDTM as TRTSDTM, b.EXSTTMF as TRTSTMF
  from adsl a left join (
    select usubjid, EXSTDTM, EXSEQ, EXSTTMF
    from ex_ext
    where (EXDOSE > 0 OR (EXDOSE = 0 AND prxmatch("/PLACEBO/", EXTRT) > 0))
      AND EXSTDTM is not missing
    group by usubjid
    having EXSTDTM = min(EXSTDTM) /* first */
  ) b on a.studyid = b.studyid and a.usubjid = b.usubjid;
quit;
```

The admiral version is shorter and far more readable. And it's testable — you can run it against test data and verify each argument's effect.

### When to use `derive_vars_merged()` vs. `derive_vars_joined()`

> If the observations from `dataset_add` to merge can be selected by a condition (`filter_add`) using only variables from `dataset_add`, then always use `derive_vars_merged()` as it requires less resources (time and memory).

The more powerful (and slower) cousin is `derive_vars_joined()`, which can join based on conditions involving variables from *both* datasets (e.g., "AE start date is between treatment start and end"). We'll see it in later lessons.

## 8. The other most-used functions

A short tour. Each of these will get detailed treatment in later lessons:

**`derive_var_extreme_flag()`** — Mark first/last record per group:

```r
advs <- advs |>
  derive_var_extreme_flag(
    by_vars = exprs(STUDYID, USUBJID, PARAMCD),
    order = exprs(ADT, ATPTN),
    new_var = WORSTFL,
    mode = "first"
  )
```

This is the equivalent of `slice_min/slice_max` + flagging — a heavily used pattern for baseline flags, worst-on-treatment, last-observation.

**`derive_var_merged_exist_flag()`** — Population flag based on existence in another dataset:

```r
adsl <- adsl |>
  derive_var_merged_exist_flag(
    dataset_add = ex,
    by_vars = exprs(STUDYID, USUBJID),
    new_var = SAFFL,
    condition = EXDOSE > 0
  )
# SAFFL = "Y" for subjects with at least one positive-dose EX record
```

This is the cleanest way to derive `SAFFL`, `ITTFL`, `EFFFL` and similar population flags.

**`derive_var_ontrtfl()`** — On-treatment flag:

```r
advs <- advs |>
  derive_var_ontrtfl(
    start_date = ADT,
    ref_start_date = TRTSDT,
    ref_end_date = TRTEDT
  )
```

For BDS data, this flags observations falling within the treatment window — a very common need.

**`derive_param_*()`** — Add a new parameter:

```r
advs <- advs |>
  derive_param_bmi(
    by_vars = exprs(STUDYID, USUBJID, VISIT, VISITNUM),
    weight_code = "WEIGHT",
    height_code = "HEIGHT",
    set_values_to = exprs(PARAMCD = "BMI")
  )
```

This adds BMI rows to ADVS, computed from existing WEIGHT and HEIGHT rows.

## 9. Higher-order functions: `slice_derivation()` and `call_derivation()`

A small but powerful piece of admiral: functions that take *other* admiral functions as arguments. These remove repetitive code when you need to apply a derivation differently across slices of your data.

`call_derivation()` calls one derivation function multiple times with varying arguments:

```r
ex <- ex |>
  call_derivation(
    derivation = derive_vars_dtm,
    variable_params = list(
      params(dtc = EXSTDTC, new_vars_prefix = "EXST"),
      params(dtc = EXENDTC, new_vars_prefix = "EXEN", time_imputation = "last")
    ),
    date_imputation = "first"          # shared across both calls
  )
```

This is equivalent to two `derive_vars_dtm()` calls but expressed in a single block. Useful when you want to convey "these are related operations."

`slice_derivation()` applies the same derivation differently to different subsets:

```r
advs <- advs |>
  slice_derivation(
    derivation = derive_var_extreme_flag,
    args = params(
      by_vars = exprs(STUDYID, USUBJID, BASETYPE, PARAMCD, AVISIT),
      order = exprs(ADT, ATPTN),
      new_var = WORSTFL,
      mode = "first"          # default
    ),
    derivation_slice(
      filter = PARAMCD %in% c("SYSBP", "DIABP")
    ),
    derivation_slice(
      filter = PARAMCD == "PULSE",
      args = params(mode = "last")    # override for this slice
    )
  )
```

For pressure parameters, take the **first** worst value; for pulse, take the **last**. One block, no repetition.

These higher-order functions are advanced. Don't worry about mastering them today; you'll see them in Module 5 (ADaM TA extensions) and recognize when they help.

## 10. The release cadence

> We strive for a regular 6 month release schedule for `{admiraldev}`, `{pharmaversesdtm}`, and `{admiral}`. Extension packages releases are on a content-basis and as such may be more infrequent.

In practice, admiral releases major versions roughly every 6 months. The 1.x line has been stable since 2024. Minor releases follow CRAN's semantic versioning rules.

A consequence: admiral has a **3-year deprecation cycle** for any function or argument that's being removed or renamed. Year 1: message. Year 2: warning. Year 3: removed. This is unusually long — it reflects admiral's regulatory-context audience, where studies can run for years and the package version may be pinned mid-study.

For your work: pin admiral version in `renv.lock`. Don't auto-update mid-study. Plan version bumps between studies, with revalidation.

## 11. Templates and example scripts

A practical kindness: admiral ships **template scripts** for common ADaMs.

```r
# Save an ADSL template to your project
use_ad_template(adam_name = "adsl", save_path = "./ad_adsl.R")

# List all available templates
list_all_templates()
# [1] "ADAE" "ADCM" "ADEG" "ADEX" "ADLB" "ADLBHY"
#     "ADMH" "ADPC" "ADPP" "ADPPK" "ADSL" "ADVS"
```

The templates are runnable scripts that build a working ADaM dataset against `pharmaversesdtm`. They're the *recommended starting point* for new ADaMs — copy the relevant template, adapt to your study's spec, and you've got 80% of the work done.

For the first few ADaMs you build, definitely start from templates. Once you've internalized admiral's patterns, you'll find yourself writing more from scratch.

## 12. The companion packages

Admiral has a small family:

- **`{admiraldev}`** — Developer utilities used by the family; user-facing only for advanced extension work
- **`{admiralonco}`, `{admiralvaccine}`, `{admiralophtha}`, `{admiralpeds}`, `{admiralmetabolic}`** — Therapeutic-area extensions, covered in Module 5

The TA extensions build *on top* of admiral core. If you're doing oncology, you'd `library(admiral); library(admiralonco)` — and you get both the core ADSL/BDS/OCCDS functions and oncology-specific ones for RECIST, PFS, ORR.

We'll cover each TA extension in Module 5.

## 13. The contribution model and what it means for you

Admiral is collaboratively maintained. Most active companies have one or more developers on the maintainer team. The contribution model uses GitHub: issues, pull requests, code reviews, release planning all visible.

If you discover a bug, open a GitHub issue. If you have a need that admiral doesn't cover, open an issue first to discuss — the team is responsive and welcoming to new contributors. If you've written a useful internal function that has broad applicability, propose it as a contribution.

The package has been growing steadily; the v1.2 release (2025) added the first new functions since v1.0 — `derive_vars_cat()`, `derive_vars_crit_flag()`, `transform_scale()` — all originating from user requests.

## 14. Reading the admiral documentation

The pkgdown documentation site is the authoritative reference: <https://pharmaverse.github.io/admiral/>

Key areas:

- **Get Started**: orientation; read this first
- **Articles → Creating ADSL/BDS/OCCDS/Time-to-Event**: the canonical guides for each ADaM class
- **Reference**: every exported function with examples
- **Articles → Programming Concepts and Conventions**: the conventions doc that admiral developers themselves follow
- **NEWS**: changelog

For specific function lookup, the in-RStudio `?function_name` is your fastest path.

## 15. Key takeaways

- Admiral is a **toolbox**, not an automation tool — you assemble ADaMs from many small function calls
- Function names follow a strict convention: `derive_var_*` (one var), `derive_vars_*` (multi var), `derive_param_*` (new parameter row), `compute_*` (scalar)
- Always start a script with `convert_blanks_to_na()` on every SDTM dataset
- `derive_vars_dt()`, `derive_vars_dtm()`, `derive_vars_dy()` handle 90% of date/datetime/study-day needs
- `derive_vars_merged()` is the most-used function — it's a sophisticated left-join with filter/order/first-last
- `exprs(VAR1, VAR2)` is the way to pass variable names; not character vectors
- Use `use_ad_template()` to bootstrap new ADaMs; templates are runnable scripts
- Pin admiral version with renv; don't auto-update mid-study

## 16. What's next

Lesson 15 — **`{admiral}` Part 2** — walks through a full ADSL build end-to-end, applying everything we covered in this lesson. We'll start from pharmaverse SDTM data, build the subject-level analysis dataset variable by variable, and produce a deliverable ADSL with all standard derivations: treatment dates, study durations, population flags, death cause, last known alive date, age groups.

Subsequent admiral lessons cover BDS (Lesson 16), OCCDS (Lesson 17), Time-to-Event (Lesson 18), and advanced patterns (Lesson 19).

---

## Self-check questions

1. What does "admiral is a toolbox, not an automation tool" mean in practice?
2. What's the difference between `derive_var_X()`, `derive_vars_X()`, and `derive_param_X()`?
3. Why must you call `convert_blanks_to_na()` at the start of an admiral script?
4. Translate: "for each subject, get the first non-zero dose date from EX as TRTSDT" using admiral functions.
5. When would you use `slice_derivation()` instead of two separate derivation calls?
6. How long is admiral's deprecation cycle, and why is it that long?

## Glossary

- **`{admiral}`** — The flagship pharmaverse package for ADaM derivation
- **`{admiraldev}`** — Developer utility package supporting the admiral family
- **TA extension** — Therapeutic-area-specific package extending admiral (admiralonco, etc.)
- **`derive_vars_dt()` / `derive_vars_dtm()`** — Convert ISO 8601 character to numeric date / datetime with imputation
- **`derive_vars_dy()`** — Derive study day variables (no Day 0)
- **`derive_vars_merged()`** — Left-join from one dataset to another with filter/order/first/last
- **`derive_var_extreme_flag()`** — Mark first or last record per group with a flag variable
- **`exprs()`** — Helper to pass unquoted expressions (variable names, function calls) to admiral functions
- **`convert_blanks_to_na()`** — Convert empty-string character cells to NA; called at the start of every script
- **Manifesto** — Admiral's published design principles; informs every API decision
- **`use_ad_template()`** — Save a starting-point script for a given ADaM (e.g., "adsl", "adae")
- **Deprecation cycle** — Admiral's 3-year process for retiring a function or argument
