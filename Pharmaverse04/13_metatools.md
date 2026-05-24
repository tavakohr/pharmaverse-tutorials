# Lesson 13 — `{metatools}`: Using the Spec to Build and Validate Datasets

**Module**: 3 — Metadata-driven programming
**Estimated length**: ~22 min spoken
**Prerequisites**: Lesson 12 (metacore)

---

## Learning objectives

By the end of this lesson, you will be able to:

1. Articulate the relationship between metacore (the spec) and metatools (the spec-driven tools)
2. Use `build_from_derived()` to construct a base dataset from predecessor SDTM domains
3. Use `create_var_from_codelist()` to derive numeric companions from coded variables (e.g., RACE → RACEN)
4. Apply spec metadata to a dataset: variable order, labels, types, allowed values
5. Run conformance checks against the spec with `check_*` functions
6. Combine metatools with admiral for spec-driven ADaM construction

---

## 1. Where metatools sits in the stack

Recall the metadata-driven pipeline:

```
spec (Excel / Define-XML)
       ↓
   metacore object
       ↓
  metatools functions  ←  this lesson
       ↓
   shaped/checked datasets
```

`metacore` is read-only; `metatools` is where the work happens. Every metatools function takes a metacore object (or DatasetMeta) as one of its arguments and uses the metadata to do something useful with your data.

```r
install.packages("metatools")
library(metatools)
```

The current package line is 0.2.x, jointly maintained by GSK and Atorus contributors. The 0.2.0 release in 2025 harmonized the API so all metatools functions require a single-dataset DatasetMeta (built via `select_dataset()`), removing earlier inconsistencies.

## 2. The five things metatools does

The package is small (~25 exported functions), all clustered around five capabilities:

1. **Build datasets from predecessors**: `build_from_derived()` constructs a starting dataset by stacking columns from SDTM source domains
2. **Derive from codelists**: turn coded character values into numeric companions or expanded labels
3. **Apply spec attributes**: enforce variable order, apply labels, types, formats from the spec
4. **Check conformance**: verify a dataset matches its spec — variables, types, lengths, codelist values
5. **Add common derivations**: a handful of convenience functions for typical ADaM patterns

Let's walk through each, in the order you'd use them in a real ADSL build.

## 3. Setup: a working example

We'll mirror the pharmaverse ADSL example. Load metacore, the spec, and SDTM source data:

```r
library(dplyr)
library(metacore)
library(metatools)
library(pharmaversesdtm)
library(admiral)

# Source SDTM
dm <- pharmaversesdtm::dm |> convert_blanks_to_na()
ds <- pharmaversesdtm::ds |> convert_blanks_to_na()
ex <- pharmaversesdtm::ex |> convert_blanks_to_na()
suppdm <- pharmaversesdtm::suppdm |> convert_blanks_to_na()

# Spec
md <- spec_to_metacore("path/to/adsl_spec.xlsx")
md_adsl <- select_dataset(md, "ADSL")
```

`convert_blanks_to_na()` is from admiral; it converts empty-string character values to proper `NA`. SDTM data from XPT files often has empty strings; you want them as NA before deriving against them.

## 4. `build_from_derived()` — the spec-driven base dataset

If your ADSL spec says it builds from DM (and SUPPDM, ADaM-specific extensions), `build_from_derived()` constructs a starting tibble with the right variables in the right order. Variables marked in the spec as having predecessors from those source datasets are automatically pulled in.

```r
adsl_base <- build_from_derived(
  metacore = md_adsl,
  ds_list = list("dm" = dm, "suppdm" = suppdm),
  predecessor_only = FALSE,
  keep = FALSE
)
```

Arguments:

- `metacore`: the `DatasetMeta` for ADSL
- `ds_list`: a named list of source SDTM datasets
- `predecessor_only = FALSE`: include variables whose spec entry says "Predecessor" *and* directly-named variables; if `TRUE`, only predecessors
- `keep = FALSE`: don't keep the source variable names if they were renamed in the spec

The result: a tibble with the columns in your spec for ADSL, populated where they have predecessors. Derived variables are present as `NA` columns, waiting to be filled.

This single function replaces the entire SAS pattern of "set dm; if first.usubjid; rename certain variables; merge suppdm; keep these columns" — and it's spec-driven, so changing the spec changes the output automatically.

## 5. `create_var_from_codelist()` — coded → numeric companion

CDISC ADaM convention: most categorical character variables have a numeric companion variable for sorting and statistics. RACE has RACEN, SEX has SEXN, ETHNIC has ETHNICN.

The numeric value comes from the codelist's encoded value. If your codelist for RACE looks like:

| code | decode |
|---|---|
| 1 | AMERICAN INDIAN OR ALASKA NATIVE |
| 2 | ASIAN |
| 3 | BLACK OR AFRICAN AMERICAN |
| 4 | NATIVE HAWAIIAN OR OTHER PACIFIC ISLANDER |
| 5 | WHITE |
| 6 | UNKNOWN |

Then RACE = "WHITE" implies RACEN = 5.

`create_var_from_codelist()` does this lookup against the metacore codelist:

```r
adsl <- adsl_base |>
  create_var_from_codelist(
    metacore = md_adsl,
    input_var = RACE,
    out_var = RACEN
  )
```

The function reads the codelist associated with RACE in the spec, looks up each subject's RACE value, and assigns the corresponding numeric code as RACEN.

This is the metadata-driven version of:

```r
# Manual (without metatools):
adsl <- adsl |>
  mutate(RACEN = case_when(
    RACE == "AMERICAN INDIAN OR ALASKA NATIVE" ~ 1,
    RACE == "ASIAN" ~ 2,
    RACE == "BLACK OR AFRICAN AMERICAN" ~ 3,
    # ... etc.
  ))
```

With the spec change-controlled, you don't need to update R code when the codelist changes — `create_var_from_codelist()` re-reads from the spec.

## 6. Applying labels, types, and lengths

Once you have a derived dataset, the final touches before export are:

- Set variable labels per the spec
- Coerce types to match the spec
- Set lengths (for character variables, this matters for XPT export)
- Order columns per the spec

metatools provides functions for each, but in practice this work is handled at the *export* step by `{xportr}` (Module 9), which uses the metacore object directly.

`metatools` does have helpers like `apply_variable_labels()` for in-memory labeling:

```r
adsl <- adsl |>
  apply_variable_labels(md_adsl)
```

This walks the `var_spec` table and sets the `label` attribute on every column. SAS programmers note: in R, labels live as attributes (`attr(x, "label")`); they're metadata, not displayed by default. They become important when exporting back to SAS XPT or using packages that respect them (`gtsummary`, `tern`).

## 7. Conformance checks: catching spec drift

The other major metatools capability: verifying that your derived dataset actually matches the spec. Run these as a final QC step before delivering ADSL.

`check_variables(...)` — does the dataset have exactly the variables the spec says it should?

```r
check_variables(adsl, md_adsl)
```

Returns an error or warning if there are missing or extra variables.

`check_ct_data(...)` — for variables with codelists, are all values in the dataset within the codelist?

```r
check_ct_data(adsl, md_adsl)
```

If your spec says RACE can only be one of the six standard values but your derived ADSL has RACE = "OTHER", this function flags it.

`check_unique_keys(...)` — does the dataset have unique rows on the spec's defined keys (e.g., USUBJID for ADSL)?

```r
check_unique_keys(adsl, md_adsl)
```

These are short helper checks; you'd run them as a block at the end of your ADSL derivation script:

```r
# Final QC block
check_variables(adsl, md_adsl)
check_ct_data(adsl, md_adsl)
check_unique_keys(adsl, md_adsl)
```

If any check errors, you stop and investigate. Together with `{sdtmchecks}` for SDTM and `{xportr}`'s export-time checks (Module 9), this is the conformance-check layer of your pipeline.

## 8. `combine_supp()` — folding SUPP-- back in

For ADSL, SUPP-- variables (subject-level supplemental qualifiers) are often "flattened back in" so ADSL has all subject metadata in one place — both the standard DM variables and the sponsor-specific SUPPDM extensions.

```r
dm_combined <- combine_supp(dm, suppdm)
```

This takes the long SUPPDM (with QNAM/QVAL columns) and pivots it back into wide form, joined onto DM. The result has DM's columns plus a new column for each QNAM in SUPPDM.

You typically call this very early — even before `build_from_derived()` — so the spec can refer to the flattened columns directly.

## 9. Working with admiral in a metadata-driven style

The full metadata-driven ADSL pattern:

```r
library(admiral)
library(metacore)
library(metatools)
library(pharmaversesdtm)
library(dplyr)

# 1. Load spec and SDTM
md <- spec_to_metacore("adsl_spec.xlsx")
md_adsl <- select_dataset(md, "ADSL")

dm <- pharmaversesdtm::dm |> convert_blanks_to_na()
suppdm <- pharmaversesdtm::suppdm |> convert_blanks_to_na()
ex <- pharmaversesdtm::ex |> convert_blanks_to_na()
ds <- pharmaversesdtm::ds |> convert_blanks_to_na()

# 2. Build base from spec
adsl <- build_from_derived(
  md_adsl,
  ds_list = list("dm" = combine_supp(dm, suppdm)),
  predecessor_only = FALSE
)

# 3. Derive codelist-driven companions
adsl <- adsl |>
  create_var_from_codelist(md_adsl, input_var = RACE, out_var = RACEN)

# 4. Derive admiral-style variables (Lesson 14+)
ex_ext <- ex |>
  derive_vars_dtm(dtc = EXSTDTC, new_vars_prefix = "EXST")

adsl <- adsl |>
  derive_vars_merged(
    dataset_add = ex_ext,
    filter_add = (EXDOSE > 0 | (EXDOSE == 0 & stringr::str_detect(EXTRT, "PLACEBO"))) &
                 !is.na(EXSTDTM),
    new_vars = exprs(TRTSDTM = EXSTDTM),
    order = exprs(EXSTDTM, EXSEQ),
    mode = "first",
    by_vars = exprs(STUDYID, USUBJID)
  )

# ... many more admiral derivations ...

# 5. Apply spec attributes (labels, etc.)
adsl <- adsl |>
  apply_variable_labels(md_adsl)

# 6. Run spec conformance checks
check_variables(adsl, md_adsl)
check_ct_data(adsl, md_adsl)
check_unique_keys(adsl, md_adsl)
```

This is the canonical pattern. The metacore object threads through every step. Spec changes? Update the Excel, rebuild the metacore object, rerun the script — everything updates automatically.

## 10. When you'd skip metacore/metatools

Honestly, sometimes the metadata-driven approach is overkill:

- **Small studies** with one or two ADaMs and minimal spec churn: writing direct dplyr/admiral code is simpler
- **Exploratory analyses** that aren't headed for submission: the spec discipline isn't worth the setup
- **First-time-in-R projects** where the team is still learning: add metadata-driven discipline incrementally

For **submission-quality work**, metacore/metatools is genuinely valuable because submission requires:

- Define-XML in the submission package, which the spec object can serialize
- Conformance: the dataset shape must match the documented spec exactly
- Auditability: a regulator should be able to trace each variable back to the spec

These are exactly the things metacore/metatools support. Don't fight the discipline if your work goes to FDA.

## 11. Inspecting helpful function lists

To remind yourself what's available:

```r
ls("package:metatools")
# [1] "add_labels"                "add_variables"
# [2] "apply_formats"             "apply_variable_labels"
# [3] "build_from_derived"        "check_ct_data"
# [4] "check_unique_keys"         "check_variables"
# ...
```

Each function has standard help: `?build_from_derived`. The package has vignettes worth reading once: `vignette("metatools", package = "metatools")`.

## 12. A worked example: deriving sex categories

Imagine you need both SEX (M/F) and SEXN (1/2) and SEXLBL ("Male"/"Female"). The spec defines a codelist for SEX with:

| code | decode |
|---|---|
| 1 | Male |
| 2 | Female |
| 3 | Unknown |

(SEX in the dataset stores "M", "F", "U" — the *codes*; SEXN stores 1/2/3; SEXLBL stores the decode.)

Wait — actually CDISC's convention is `SEX = "M"`, `SEXLBL = "Male"`, `SEXN = 1`. Codelists have both `code` and `decode`. The decode is the long form.

With metacore/metatools:

```r
adsl <- adsl |>
  create_var_from_codelist(md_adsl, input_var = SEX, out_var = SEXN, decode_to_code = FALSE)
# Looks up the codelist for SEX, finds code corresponding to each SEX value, populates SEXN

adsl <- adsl |>
  create_var_from_codelist(md_adsl, input_var = SEX, out_var = SEXLBL, decode_to_code = TRUE)
# Same, but pulls the decode (long form)
```

The exact arguments evolve across versions. Read the current function docs for your installed version.

## 13. A note on factor variables

`create_var_from_codelist()` produces character or numeric output. If you want the result as a factor with levels in codelist order:

```r
adsl <- adsl |>
  mutate(SEX = factor(SEX,
                      levels = c("M", "F", "U"),
                      labels = c("Male", "Female", "Unknown")))
```

This is a manual step; metatools doesn't (currently) build factors automatically. Keep factor-building for the TLG-prep stage, not in the stored ADaM (Lesson 06 covered why).

## 14. The big picture

After Modules 2 and 3, your clinical R toolkit looks like this:

| Stage | Package | Role |
|---|---|---|
| Raw → SDTM | `{sdtm.oak}` | Algorithm-driven SDTM construction |
| SDTM QC | `{sdtmchecks}` | Analysis-impact checks |
| Spec | `{metacore}` | The spec object |
| Build/check | `{metatools}` | Spec-driven dataset construction and validation |
| SDTM → ADaM | `{admiral}` (next module) | ADaM derivations |
| ADaM → XPT | `{xportr}` (later) | Final transport with spec-applied labels |

These integrate naturally. The metacore object you load in Module 3 is the same one xportr uses in Module 9 to label the XPT file correctly.

## 15. Key takeaways

- `{metatools}` consumes metacore objects to do real data work — build, derive, label, check
- `build_from_derived()` constructs a spec-shaped base dataset from named SDTM sources
- `create_var_from_codelist()` derives numeric companions (RACEN, SEXN) or decoded labels from codelists
- `check_variables()`, `check_ct_data()`, `check_unique_keys()` validate datasets against their spec
- `combine_supp()` folds SUPP-- back into the parent domain for ADSL-style work
- Together with admiral, this enables a fully metadata-driven ADaM build

## 16. What's next

Lesson 14 begins Module 4: **`{admiral}`** Part 1 — foundations and philosophy. We'll cover admiral's manifesto (modular, readable, no black-box automation), the convention-driven function naming (`derive_var_*`, `derive_vars_*`, `derive_param_*`), and the key date/time helpers that underpin every ADaM derivation. After that, four more admiral lessons cover ADSL, BDS, OCCDS, and time-to-event.

---

## Self-check questions

1. What's the typical first metatools function in an ADSL build, and what does it do?
2. Given a codelist with code=1/decode=Male, how would you derive both SEXN (numeric) and SEX (character) from it?
3. Which metatools function would catch a spec-mismatch in your final ADSL?
4. Why do most metatools functions require a `DatasetMeta` (not a full metacore)?
5. What does `combine_supp()` do, and when do you call it relative to `build_from_derived()`?
6. Should you store factor-typed variables in the final ADaM datasets you export?

## Glossary

- **Metadata-driven programming** — Approach where code reads spec metadata to build/check datasets, rather than hard-coding spec details
- **Predecessor variable** — In a spec, a variable whose source is directly named (e.g., ADSL.AGE comes from DM.AGE)
- **`build_from_derived()`** — Construct a base dataset from named source datasets per the spec
- **`create_var_from_codelist()`** — Derive a companion variable using a codelist's code↔decode mapping
- **`combine_supp()`** — Fold SUPP-- rows into the parent domain wide-format
- **Conformance check** — Verify a derived dataset matches its spec definition
- **`apply_variable_labels()`** — Set the `label` attribute on each column per the spec
- **`check_ct_data()`** — Verify all values of a coded variable are in its codelist
- **`check_unique_keys()`** — Verify the spec's unique-key columns identify rows uniquely
- **`exprs()`** — admiral/dplyr helper for passing variable names as expressions (not strings) to functions
