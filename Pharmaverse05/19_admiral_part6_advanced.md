# Lesson 19 — `{admiral}` Part 6: Advanced Derivation Patterns

**Module**: 4 — ADaM core
**Estimated length**: ~25 min spoken
**Prerequisites**: Lessons 14–18

---

## Learning objectives

By the end of this lesson, you will be able to:

1. Use `create_period_dataset()` and `derive_vars_period()` for studies with periods and phases
2. Apply `derive_expected_records()` to insert "expected but missing" rows
3. Apply `derive_locf_records()` for Last Observation Carried Forward imputation
4. Combine `restrict_derivation()` and `slice_derivation()` for complex per-subset derivations
5. Use `derive_extreme_event()` for "worst event" patterns across mixed sources
6. Integrate admiral with `{metacore}` for spec-driven, validated ADaM construction
7. Extend admiral with your own helper functions following the package conventions

---

## 1. Period datasets — crossover and extension studies

For simple parallel-arm studies, "treatment" is a single window per subject (TRTSDT to TRTEDT). For studies with **periods** (crossover designs, extension phases, treatment-switch protocols), each subject moves through multiple distinct windows, each with its own arm assignment.

CDISC handles this with `APxxSDT` / `APxxEDT` variables in ADSL (one pair per period) and corresponding `APERIOD` / `APERSDT` / `APEREDT` columns in analysis datasets. Admiral provides a small framework for managing this.

### Building the period reference dataset

```r
library(admiral)
library(dplyr)

# Suppose ADSL has AP01SDT, AP01EDT, AP02SDT, AP02EDT (for two periods)
adsl_simple <- adsl |>
  select(USUBJID, STUDYID, AP01SDT, AP01EDT, AP02SDT, AP02EDT)

# Create the long-format period reference
adperiods <- create_period_dataset(
  dataset = adsl_simple,
  new_vars = exprs(APERSDT = APxxSDT, APEREDT = APxxEDT)
)

# Result: one row per (USUBJID × APERIOD) with start and end dates
head(adperiods)
# USUBJID  APERIOD  APERSDT     APEREDT
# 01-001   1        2023-01-15  2023-04-15
# 01-001   2        2023-04-15  2023-07-15
```

`create_period_dataset()` pivots the wide APxxSDT/APxxEDT columns into a long structure with APERIOD as the discriminator. This reference dataset feeds the next step.

### Adding period variables to a BDS or OCCDS dataset

```r
adae <- adae |>
  derive_vars_joined(
    dataset_add = adperiods,
    by_vars = exprs(USUBJID),
    filter_join = ASTDT >= APERSDT & ASTDT <= APEREDT,
    join_type = "all"
  )
# Now adae has APERIOD, APERSDT, APEREDT for each event
```

The `filter_join` condition references columns from both datasets (ASTDT from adae; APERSDT/APEREDT from adperiods) — exactly the use case for `derive_vars_joined()` rather than the simpler `derive_vars_merged()`.

After this, you can derive period-specific occurrence flags: AOCC01FL = first event per (subject × period 1), AOCC02FL = first per (subject × period 2), etc.

```r
adae <- adae |>
  restrict_derivation(
    derivation = derive_var_extreme_flag,
    args = params(
      by_vars = exprs(USUBJID, APERIOD),
      order = exprs(ASTDT, AESEQ),
      new_var = AOCCPRFL,
      mode = "first"
    ),
    filter = TRTEMFL == "Y" & !is.na(APERIOD)
  )
```

The same pattern handles **subperiods** (within a period) and **phases** (broader than a period) — admiral uses `APxxSDT` / `APxxEDT` / `APHASE` / `APHASESDT` / `APHASEEDT` conventions to handle all three levels.

For studies without periods (typical phase III parallel-arm), you skip this entirely. For complex crossover or oncology extension studies, this framework saves enormous amounts of code.

## 2. Expected records: `derive_expected_records()`

A common BDS QC pattern: a SAP says every subject should have a SYSBP reading at every visit. Some subjects miss a visit. In analysis, do you want a *missing* row (so the visit-level summary still shows "N subjects measured") or no row at all?

ADaM convention: insert an "expected but missing" row, typically with AVAL = NA and a flag (like `DTYPE = "EXPECTED"`) marking it as a placeholder. `derive_expected_records()` does this:

```r
# Suppose every subject in the safety pop should have SYSBP at visits 1-5
expected_visits <- tibble::tribble(
  ~PARAMCD,  ~AVISITN, ~AVISIT,
  "SYSBP",   1,        "Visit 1",
  "SYSBP",   2,        "Visit 2",
  "SYSBP",   3,        "Visit 3",
  "SYSBP",   4,        "Visit 4",
  "SYSBP",   5,        "Visit 5"
)

# For each safety-pop subject × expected visit, ensure a row exists
advs <- advs |>
  derive_expected_records(
    dataset_ref = adsl |> filter(SAFFL == "Y") |> select(USUBJID, STUDYID),
    by_vars = exprs(STUDYID, USUBJID, PARAMCD, AVISITN, AVISIT),
    set_values_to = exprs(DTYPE = "EXPECTED")
  )
```

Behavior: for any (USUBJID × PARAMCD × AVISIT) combination present in the cartesian product of `dataset_ref` and `by_vars` but *missing* in advs, an empty row is added with the requested `set_values_to` values (and NA elsewhere). Downstream tables see the expected denominator clearly.

This is a quietly important pattern for "subjects with completed visits" tables and incidence calculations.

## 3. LOCF imputation: `derive_locf_records()`

Last Observation Carried Forward — fill missing post-baseline values with the most recent prior observation. Used when the SAP allows LOCF (a contentious imputation method, but still used in older protocols and as sensitivity analyses).

```r
advs <- advs |>
  derive_locf_records(
    dataset_ref = expected_visits_per_subject,
    by_vars = exprs(STUDYID, USUBJID, PARAMCD),
    order = exprs(AVISITN, ADT),
    keep_vars = exprs(AVAL, AVALC, ANRIND, ANRLO, ANRHI)
  )
```

For each (subject × parameter) combination missing a value, this function takes the most recent prior non-missing value and copies it to the new "imputed" row, marking it with `DTYPE = "LOCF"` so downstream analyses can include or exclude as needed.

LOCF is the simplest of multiple imputation methods. For more sophisticated approaches (multiple imputation, mixed models), use specialized packages (`{mice}`, `{mmrm}`) — admiral focuses on ADaM construction, not on advanced imputation.

## 4. `derive_extreme_event()` — worst events across sources

A pattern that comes up often: derive a flag for "the worst AE per subject, across multiple types of severity scales." `derive_extreme_event()` is admiral's generalization of `derive_var_extreme_flag()` for cases where the "worst" requires considering multiple variables or sources with priority rules.

```r
adae <- adae |>
  derive_extreme_event(
    by_vars = exprs(USUBJID),
    events = list(
      event(
        condition = AETOXGR == "5",
        set_values_to = exprs(AOWORSEN = "Y")
      ),
      event(
        condition = AETOXGR == "4",
        set_values_to = exprs(AOWORSEN = "Y")
      ),
      event(
        condition = AESER == "Y",
        set_values_to = exprs(AOWORSEN = "Y")
      )
    ),
    new_vars = exprs(AOWORSEN),
    mode = "first",
    order = exprs(ASTDT)
  )
```

The function steps through events in order; the first one that matches per subject sets the new variables. Useful for hierarchical AE flag derivations.

The simpler `derive_var_extreme_flag()` from Lessons 15–17 covers the common case (find first/last by ordering). Use `derive_extreme_event()` when the "worst" rule depends on multiple conditions evaluated in priority order.

## 5. Higher-order pattern combinations

You've seen `restrict_derivation()` and `slice_derivation()` individually. Combined, they handle very specific needs:

```r
# Apply ABLFL derivation only to rows passing a filter,
# and use different ordering for two parameter groups
advs <- advs |>
  slice_derivation(
    derivation = derive_var_extreme_flag,
    args = params(
      by_vars = exprs(STUDYID, USUBJID, PARAMCD),
      new_var = ABLFL,
      mode = "last"
    ),
    derivation_slice(
      filter = PARAMCD %in% c("SYSBP", "DIABP", "PULSE") &
               !is.na(AVAL) & ADT <= TRTSDT,
      args = params(order = exprs(ADT, AVISITN))
    ),
    derivation_slice(
      filter = PARAMCD == "HEIGHT" &
               !is.na(AVAL) & ADT <= TRTSDT,
      args = params(
        order = exprs(ADT),
        by_vars = exprs(STUDYID, USUBJID)   # height: just per subject, not per visit
      )
    )
  )
```

Two slices, each with its own filter and its own argument overrides. This kind of expression is dense — read it carefully when you encounter it in code review.

The pharmaverse examples site has multi-slice examples for several real ADaMs; consult them when you need to write code like this.

## 6. Integrating admiral with metacore

Lesson 13 covered metatools' integration. Here we expand: a metadata-driven admiral workflow uses the metacore object at several points:

```r
library(admiral)
library(metacore)
library(metatools)

md <- spec_to_metacore("adsl_spec.xlsx")
md_adsl <- select_dataset(md, "ADSL")

# 1. Base from spec
adsl <- build_from_derived(md_adsl,
                            ds_list = list("dm" = dm, "suppdm" = suppdm),
                            predecessor_only = FALSE)

# 2. Admiral derivations (Lesson 15)
adsl <- adsl |>
  derive_vars_merged(...) |>
  derive_var_trtdurd() |>
  derive_var_merged_exist_flag(...)

# 3. Spec-driven companion variables
adsl <- adsl |>
  create_var_from_codelist(md_adsl, input_var = RACE, out_var = RACEN) |>
  create_var_from_codelist(md_adsl, input_var = SEX,  out_var = SEXN)

# 4. Apply spec labels and check conformance
adsl <- adsl |>
  apply_variable_labels(md_adsl)

check_variables(adsl, md_adsl)
check_ct_data(adsl, md_adsl)
check_unique_keys(adsl, md_adsl)
```

This is the canonical production pattern for submission-quality ADaMs:

- metacore = the spec object
- metatools = spec-driven building blocks
- admiral = derivation engine
- xportr (Module 9) = final transport, also using metacore

When the spec changes, the metacore object regenerates, and the same admiral code with the same metatools wrappers produces an updated ADSL conforming to the new spec.

## 7. Extending admiral with your own functions

Admiral covers most patterns, but sponsor-specific or therapeutic-area-specific needs sometimes require custom functions. The convention: write them in the admiral style.

```r
# Sponsor-specific: derive ANL_AOFL (analysis flag for special analysis)
derive_var_anl_aofl <- function(dataset,
                                 by_vars,
                                 filter,
                                 new_var,
                                 mode = "first") {
  # Defensive checks (admiral's convention)
  assert_data_frame(dataset, required_vars = by_vars)
  new_var <- assert_symbol(enexpr(new_var))

  # Implementation
  dataset |>
    restrict_derivation(
      derivation = derive_var_extreme_flag,
      args = params(
        by_vars = by_vars,
        new_var = !!new_var,
        mode = mode
      ),
      filter = !!filter
    )
}
```

Key admiral-style conventions:

- Use `assert_*` functions from `{admiraldev}` to validate inputs early
- Accept unquoted expressions via `enexpr()` and pass with `!!`
- Follow the `derive_var_*` / `derive_vars_*` naming
- Document with roxygen; provide `@examples`
- Test with `{testthat}` (see admiral's contribution guidelines)

If your function ends up being broadly useful (cross-company, cross-TA), propose it to admiral via GitHub issue. The maintainers welcome user-driven additions, especially when paired with tests and documentation.

For sponsor-internal patterns, you'd build a sponsor extension package (`{my_company_admiral}`) that depends on admiral and adds the helpers. Roche and GSK have internal versions (`admiralroche`, `admiralgsk`) that do exactly this.

## 8. `get_admiral_option()` and `set_admiral_options()`

Admiral has package-level options for things you use constantly. The biggest: `subject_keys` — the canonical set of identifier columns for subject-level joins.

```r
# Default: c("STUDYID", "USUBJID")
get_admiral_option("subject_keys")

# Some sponsors include SITEID or use different conventions
set_admiral_options(subject_keys = exprs(STUDYID, USUBJID, SITEID))
```

Once set, admiral functions that accept `subject_keys` (most do) use this default unless overridden per-call. Set it at the top of your script for the whole pipeline.

You'll see this pattern in admiralonco, admiralvaccine, etc. — get_admiral_option("subject_keys") is referenced inside template scripts so they adapt to whatever subject-key configuration the sponsor uses.

## 9. Handling missing TRTSDT — uncommon but real

If a subject's TRTSDT is missing (e.g., screen failure, dropped before dose), many admiral derivations produce NA. For BDS/OCCDS where you still want to handle these subjects:

```r
adae <- adae |>
  derive_var_trtemfl(
    start_date = ASTDT,
    end_date = AENDT,
    trt_start_date = TRTSDT,
    trt_end_date = TRTEDT,
    treatment_emergent_value = "Y",
    initial_intensity = AESEV
  )

# Subjects with NA TRTSDT will have NA TRTEMFL. Decide:
#  - drop them from analysis (filter SAFFL == "Y" earlier)
#  - explicitly set TRTEMFL = NA but include in subject counts

adae <- adae |>
  filter(SAFFL == "Y")
```

Don't try to impute TRTSDT inside admiral; deal with the data-quality issue upstream (in SDTM derivation or earlier ADSL logic), or explicitly exclude those subjects per SAP.

## 10. `vignette()`-level deep dives in admiral

The admiral package ships with detailed vignettes for the harder topics. Worth knowing they exist:

- `vignette("date_time", package = "admiral")` — full date/time imputation rules
- `vignette("higher_order", package = "admiral")` — slice_derivation, call_derivation, restrict_derivation in depth
- `vignette("queries_dataset_documentation", package = "admiral")` — building SMQ/CQ datasets
- `vignette("hys_law", package = "admiral")` — Hy's Law liver toxicity implementation
- `vignette("imputation", package = "admiral")` — date imputation deep-dive
- `vignette("visit_period", package = "admiral")` — period datasets
- `vignette("lab_grading", package = "admiral")` — NCI CTCAE grading

These are dense reads; tackle them when you have a specific need rather than upfront.

## 11. Performance considerations

Admiral is fast for typical study sizes (thousands to tens of thousands of subjects). For very large datasets (hundreds of thousands of rows per AE/LB), a few patterns help:

- **Filter early**: `convert_blanks_to_na()` then immediately filter to relevant population
- **Use `derive_vars_merged()` over `derive_vars_joined()` when possible**: the merged variant is faster when filter conditions don't reference both datasets
- **Avoid redundant `derive_vars_dtm()` calls**: derive once, reuse
- **Profile with `{profvis}`** if a script feels slow

For typical phase-III submission studies, performance isn't usually a concern. For phase-IV registry data with hundreds of thousands of subjects, it can be.

## 12. Putting it together: a metadata-driven ADAE

Bringing everything together:

```r
library(admiral)
library(admiraldev)
library(metacore)
library(metatools)
library(dplyr)
library(pharmaversesdtm)

# Set sponsor-specific options
set_admiral_options(subject_keys = exprs(STUDYID, USUBJID))

# Load spec
md <- spec_to_metacore("adae_spec.xlsx")
md_adae <- select_dataset(md, "ADAE")

# Load data
ae <- pharmaversesdtm::ae |> convert_blanks_to_na()
ex <- pharmaversesdtm::ex |> convert_blanks_to_na()
adsl <- pharmaverseadam::adsl

adsl_vars <- exprs(TRTSDT, TRTEDT, TRT01A, TRT01P, SAFFL)

# Base from spec
adae <- build_from_derived(md_adae,
                            ds_list = list("ae" = ae),
                            predecessor_only = FALSE)

# Standard admiral pipeline
adae <- adae |>
  derive_vars_merged(dataset_add = adsl, new_vars = adsl_vars,
                     by_vars = get_admiral_option("subject_keys")) |>
  derive_vars_dt(new_vars_prefix = "AST", dtc = AESTDTC,
                 highest_imputation = "M") |>
  derive_vars_dt(new_vars_prefix = "AEN", dtc = AEENDTC,
                 highest_imputation = "M", date_imputation = "last") |>
  derive_vars_dy(reference_date = TRTSDT,
                 source_vars = exprs(ASTDT, AENDT)) |>
  mutate(ASEV = AESEV, AREL = AEREL) |>
  derive_var_trtemfl(
    start_date = ASTDT, end_date = AENDT,
    trt_start_date = TRTSDT, trt_end_date = TRTEDT, end_window = 30
  ) |>
  restrict_derivation(
    derivation = derive_var_extreme_flag,
    args = params(
      by_vars = get_admiral_option("subject_keys"),
      order = exprs(ASTDT, AESEQ),
      new_var = AOCCFL, mode = "first"
    ),
    filter = TRTEMFL == "Y"
  ) |>
  derive_var_obs_number(
    new_var = ASEQ,
    by_vars = get_admiral_option("subject_keys"),
    order = exprs(ASTDT, AESEQ)
  )

# Apply labels and check spec conformance
adae <- adae |>
  apply_variable_labels(md_adae)

check_variables(adae, md_adae)
check_ct_data(adae, md_adae)
check_unique_keys(adae, md_adae)
```

This pattern — metacore + admiral + metatools — is the production architecture for submission-quality ADaMs. The setup overhead is real (you have to maintain the spec). Once it's in place, every ADaM build is a few dozen lines of structured, verifiable, traceable R.

## 13. Where admiral is heading

Active development directions (visible in admiral's GitHub roadmap and 2025–2026 release plans):

- **Better integration with the ARS/ARD direction** — admiral derivations producing direct inputs to cards/cardx ARDs
- **More TA extensions**: pediatric, dermatology, infectious disease — extension packages keep appearing
- **AGENTS.md and AI-assisted programming support**: admiral has begun formalizing how AI agents should write admiral code, encoded in AGENTS.md files at each package
- **Continued performance work**: especially for large studies and integrated summary of safety datasets

You're entering admiral at a productive moment. The 1.x line is stable, the patterns are settled, and the package is mature enough for confident production use.

## 14. Key takeaways

- Period datasets (`create_period_dataset()` + `derive_vars_joined()`) handle crossover and extension studies
- `derive_expected_records()` inserts missing-but-expected rows; `derive_locf_records()` does LOCF imputation
- `derive_extreme_event()` handles priority-based "worst event" patterns
- `restrict_derivation()` and `slice_derivation()` compose for complex per-subset rules
- Metacore + metatools + admiral together form the spec-driven ADaM production architecture
- Extend admiral with custom `derive_var_*` functions following the package conventions
- `set_admiral_options()` configures package-level defaults (subject_keys especially)

## 15. What's next

Module 4 is complete. Module 5 covers the **therapeutic area extensions** of admiral: `{admiralonco}`, `{admiralvaccine}`, `{admiralophtha}`, `{admiralpeds}`, `{admiralmetabolic}`. Each adds TA-specific functions and templates on top of admiral core. Oncology in particular is heavily developed because so many R-submission pioneers were oncology-focused.

After Module 5, we move into the TLG modules — Module 6 (Cardinal-future stack: cards, cardx, gtsummary, cardinal, tfrmt) and Module 7 (legacy stack: rtables, tern, r2rtf, Tplyr, tidytlg).

---

## Self-check questions

1. When would you use `create_period_dataset()`?
2. What does `derive_expected_records()` do that filtering can't?
3. What's the difference between `derive_var_extreme_flag()` and `derive_extreme_event()`?
4. Why does `set_admiral_options(subject_keys = ...)` save time across a project?
5. Translate to the integrated pattern: "Build ADAE base from spec, merge ADSL vars, derive TRTEMFL, apply labels, check conformance."
6. If you needed a sponsor-specific helper function, what conventions would you follow?

## Glossary

- **Period dataset** — Long-format reference of subject periods with start/end dates
- **APERIOD** — Period identifier
- **DTYPE** — Derivation Type; marks rows as "EXPECTED", "LOCF", "AVERAGE", etc.
- **LOCF** — Last Observation Carried Forward; an imputation method
- **`create_period_dataset()`** — Pivot APxxSDT/APxxEDT to long format
- **`derive_vars_period()`** — Add period variables to ADSL from the period reference
- **`derive_expected_records()`** — Insert missing-but-expected rows
- **`derive_locf_records()`** — Perform LOCF imputation
- **`derive_extreme_event()`** — Priority-based "worst event" derivation
- **`get_admiral_option()` / `set_admiral_options()`** — Package-level configuration
- **`{admiraldev}`** — Companion developer-utility package; defines `assert_*` checks
