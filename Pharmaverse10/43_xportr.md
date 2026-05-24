# Lesson 43 — `{xportr}`: SAS XPT v5 Transport Files for Submission

**Module**: 9 — Submission and transport
**Estimated length**: ~22 min spoken
**Prerequisites**: Lessons 12–13 (metacore, metatools); Lessons 14–19 (admiral)

---

## Learning objectives

By the end of this lesson, you will be able to:

1. Explain why XPT v5 is the FDA-accepted transport format and why it constrains your data
2. Use the six core `xportr_*()` functions: `xportr_type()`, `xportr_length()`, `xportr_label()`, `xportr_order()`, `xportr_format()`, `xportr_df_label()`
3. Apply `xportr_metadata()` and `xportr_write()` to wire up the full pipeline
4. Convert R types (factor, date, time) to XPT-compatible character/numeric
5. Use specifications (Excel or metacore object) as the source of truth for metadata
6. Recognize common xportr errors and how to fix them at the data, spec, or pipeline level

---

## 1. Why XPT v5 and why this lesson matters

When you submit clinical data to the FDA via eCTD, the **SDTM and ADaM datasets must be in SAS Version 5 transport file format (.xpt)**. This format was defined by SAS in the late 1980s. It has hard constraints:

- Variable names ≤ 8 characters
- Variable labels ≤ 40 characters
- Character values ≤ 200 characters
- Only two data types: character and numeric
- File format is binary, big-endian, with specific header structure

Despite obvious limitations relative to modern formats (parquet, arrow, JSON), XPT v5 remains the regulatory standard. CDISC has tried to replace it (Dataset XML pilot in 2015 — failed due to file size bloat; Dataset JSON in 2023-2026 — making progress, covered in Lesson 44). For now and for some years to come, **if you submit to the FDA, you ship XPT v5**.

R doesn't natively produce XPT v5 with proper attributes. The `{haven}` package can write `.xpt` files but doesn't enforce CDISC compliance — variable labels, lengths, formats, ordering all need careful attention. `{xportr}` is the pharmaverse-aligned package that fills this gap.

Origin: developed jointly by **GSK and Atorus Research**, released to CRAN 2022, current stable 0.x as of mid-2026. Maintained at [github.com/atorus-research/xportr](https://github.com/atorus-research/xportr).

## 2. Installation and the test data

```r
install.packages("xportr")

library(xportr)
library(dplyr)
library(labelled)
library(readxl)
```

The package ships with example data and an example spec file:

```r
# Test ADSL
data("adsl_xportr", package = "xportr")

# Example spec sheet
spec_path <- system.file("specs", "ADaM_spec.xlsx", package = "xportr")
var_spec <- read_excel(spec_path, sheet = "Variables") |>
  rename(type = "Data Type") |>
  rename_with(tolower)

dataset_spec <- read_excel(spec_path, sheet = "Datasets") |>
  rename(label = "Description") |>
  rename_with(tolower)
```

The spec file is Excel with sheets for `Datasets` (dataset-level metadata) and `Variables` (variable-level metadata). This is the **CDISC-conventional** structure — your sponsor's specs may differ slightly in column naming, but the schema is similar.

## 3. The six pipeline functions

xportr's API is a six-step pipeline. Each function applies one attribute to your data:

| Function | What it does |
|---|---|
| `xportr_type()` | Coerce R types (factor, date, time) to XPT-allowed (character or numeric) |
| `xportr_length()` | Set the SAS storage length for each variable (1-200 for char, 8 for numeric) |
| `xportr_label()` | Set variable labels (≤ 40 characters) |
| `xportr_order()` | Reorder columns per spec |
| `xportr_format()` | Set SAS format strings (e.g., `DATE9.`, `8.2`) |
| `xportr_df_label()` | Set the dataset-level label |
| `xportr_write()` | Write the XPT file with all attributes applied |

A complete pipeline:

```r
adsl_xpt_ready <- adsl_xportr |>
  xportr_metadata(var_spec, "ADSL", verbose = "warn") |>
  xportr_type() |>
  xportr_length() |>
  xportr_label() |>
  xportr_order() |>
  xportr_format() |>
  xportr_df_label(dataset_spec)

xportr_write(adsl_xpt_ready, "adsl.xpt")
```

That's it — an XPT v5 file at `adsl.xpt` with proper variable types, lengths, labels, ordering, and dataset label.

Each step is its own function so you can run them individually, inspect intermediate state, and catch errors early. For convenience, the wrapper `xportr()` runs all six in sequence:

```r
adsl_xpt_ready <- xportr(adsl_xportr, var_spec, "ADSL", verbose = "warn")
xportr_write(adsl_xpt_ready, "adsl.xpt")
```

For one-off conversions, `xportr()` is fine. For studies with many ADaMs and complex specs, the six-step pipeline gives more control.

## 4. `xportr_metadata()` — attaching the spec

The first function in any pipeline is `xportr_metadata()`. It attaches the specification to the data frame as an attribute, so downstream functions know what to apply:

```r
xportr_metadata(
  .df = adsl,
  metadata = var_spec,
  domain = "ADSL",
  verbose = "warn"
)
```

- `metadata`: a data frame of variable-level metadata (or a metacore object — covered in Section 12)
- `domain`: the CDISC dataset name (used to subset metadata if specs cover multiple datasets)
- `verbose`: how to handle issues — `"none"`, `"warn"`, `"message"`, `"stop"`

Critical: the spec data frame must have specific column names that xportr expects:

| Required column | Purpose |
|---|---|
| `dataset` | Dataset name (e.g., "ADSL", "ADAE") |
| `variable` | Variable name (e.g., "USUBJID", "AGE") |
| `type` | R type (`character`, `numeric`, `integer`, `Date`, etc.) |
| `length` | SAS storage length |
| `label` | Variable label (≤ 40 chars) |
| `order` | Column order (integer) |
| `format` | SAS format string (optional) |

If your sponsor's spec sheet uses different column names (e.g., "Variable Name" instead of "variable"), rename before calling:

```r
var_spec <- var_spec |>
  rename(variable = "Variable Name",
         label = "Variable Label",
         length = "Length",
         type = "Data Type",
         order = "Order",
         format = "Format")
```

## 5. `xportr_type()` — type coercion

XPT v5 supports only `character` and `numeric`. R has many more types: `integer`, `factor`, `Date`, `POSIXct`, `logical`, etc. `xportr_type()` coerces each variable per the spec:

```r
adsl |> xportr_type()
```

Behind the scenes:

- `factor` → `character` (using the factor's levels)
- `Date` → `numeric` (days since 1960-01-01, the SAS date origin)
- `POSIXct` / `POSIXt` → `numeric` (seconds since 1960-01-01 — SAS datetime origin)
- `integer` → `numeric`
- `logical` → `character` ("Y"/"N" or as configured)

The function reads the `type` column from your spec and coerces each variable accordingly. If a variable's R type can't be coerced to the spec'd type (e.g., character data marked as numeric in the spec), it raises a warning or error per `verbose`.

A common bug: dates stored as character strings ("2024-05-15") in R but marked as `numeric` in spec. `xportr_type()` will try to parse them; failures get flagged. Fix by ensuring dates are R `Date` objects before piping in.

## 6. `xportr_length()` — variable lengths

SAS XPT v5 needs explicit storage lengths:

- **Character variables**: 1-200 bytes; the spec sets the value
- **Numeric variables**: always 8 bytes (other lengths exist but rarely used)

```r
adsl |> xportr_length(metadata = var_spec, domain = "ADSL")
```

The function applies the `length` from spec to each variable, padding character variables and assigning the numeric length.

A common issue: a character value in your data exceeds the spec'd length. Example: spec says `USUBJID` length is 20, but you have `USUBJID = "STUDY/CENTER123/SUBJECT-0001"` which is 28 characters. xportr will:

- With `verbose = "warn"`: warn that the actual data exceeds spec length; truncate to spec length
- With `verbose = "stop"`: error out, requiring you to fix either the data or the spec

Always set `verbose = "warn"` minimum so silent truncation doesn't happen.

## 7. `xportr_label()` — variable labels

```r
adsl |> xportr_label()
```

Sets the `label` attribute on each variable (a SAS-style descriptive name shown by tools like Pinnacle 21, viewers, and SAS itself). XPT v5 caps labels at 40 characters.

If a spec label exceeds 40 chars, xportr truncates with a warning. Fix by editing the spec to a shorter label.

For data already labeled via `metatools::apply_variable_labels()` from a metacore object (Lesson 13), xportr respects the existing labels — you can skip this function. But running it is harmless: it confirms the labels match spec.

## 8. `xportr_order()` — column ordering

Per CDISC convention, variables in an ADaM appear in a defined order: typically `STUDYID, USUBJID, SUBJID, ...` first, then study-specific variables, ending with admin/audit variables. The spec encodes this via an `order` column (integer).

```r
adsl |> xportr_order()
```

Reorders columns per the spec's `order`. Variables present in the data but not in the spec stay at the end (with a warning). Variables in the spec but missing from the data are noted (depending on verbose setting).

For studies with complex variable lists (e.g., 100+ ADSL variables across multiple TA extensions), this catches "I forgot to derive variable X" errors at the right point — late enough to have most of the work done, early enough to fix before XPT.

## 9. `xportr_format()` — SAS format strings

For variables that should display with specific SAS formats (date display, decimal places):

```r
adsl |> xportr_format()
```

Sets the `format` attribute per spec. Common values:

- `DATE9.` for date variables (displays as `15MAY2024`)
- `DATETIME19.` for datetimes
- `8.2` for numeric with 2 decimals
- `$20.` for character of length 20

xportr doesn't validate that the format makes sense for the data — it just sets the attribute. SAS/Pinnacle 21 will validate on import.

## 10. `xportr_df_label()` — dataset-level label

```r
adsl |> xportr_df_label(dataset_spec, "ADSL")
```

Sets the dataset's overall label (e.g., "Subject-Level Analysis Dataset"). XPT v5 caps this at 40 characters too.

The dataset spec is typically separate from the variable spec — a sheet with one row per dataset listing name, label, structure, key variables. xportr's `xportr_df_label()` reads from this.

## 11. `xportr_write()` — produce the XPT file

```r
xportr_write(
  adsl_ready,
  path = "submission/datasets/adsl.xpt",
  metadata = dataset_spec,
  domain = "ADSL",
  strict_checks = FALSE
)
```

- `path`: where to write the file
- `metadata`: optional dataset spec (also enables `xportr_df_label()` automatically)
- `strict_checks`: if `TRUE`, validation errors prevent writing; if `FALSE` (default), warnings allow writing

Internally, `xportr_write()` calls `haven::write_xpt()` after applying any final checks.

For very large datasets approaching the XPT v5 ~2 GB practical limit, the `max_size_gb` argument splits the file into chunks (e.g., `adsl_001.xpt`, `adsl_002.xpt`, ...). Typically not needed for clinical data; useful for very large pharmacology / PK datasets.

## 12. Integration with `{metacore}` and `{metatools}`

If you've used `{metacore}` (Lesson 12) to manage your specs, xportr accepts metacore objects directly:

```r
library(metacore)

mc <- metacore::spec_to_metacore("specs/adam_spec.xlsx")

adsl_ready <- adsl |>
  xportr_metadata(mc, "ADSL", verbose = "warn") |>
  xportr_type() |>
  xportr_length() |>
  xportr_label() |>
  xportr_order() |>
  xportr_format() |>
  xportr_df_label(mc)
```

When the metadata argument is a metacore object, xportr extracts the variable spec internally — same behavior as passing a data frame, but with the type-safety and structure of metacore.

This is the recommended pattern: keep your spec as a metacore object throughout the ADaM build (Lesson 12-13) and pass the same object to xportr at the end. **One spec → one source of truth → consistent metadata everywhere**.

## 13. The complete ADaM → XPT pipeline

A full script combining metacore + admiral + xportr:

```r
library(admiral)
library(metacore)
library(metatools)
library(xportr)
library(dplyr)
library(haven)

# Load spec
mc <- metacore::spec_to_metacore("specs/adam_spec.xlsx")

# Load source SDTM
dm <- haven::read_xpt("sdtm/dm.xpt")
ex <- haven::read_xpt("sdtm/ex.xpt")
ae <- haven::read_xpt("sdtm/ae.xpt")

# Build ADSL with admiral
adsl <- dm |>
  derive_vars_merged(
    dataset_add = ex,
    new_vars = exprs(TRTSDT = EXSTDT, TRTEDT = EXENDT),
    by_vars = exprs(STUDYID, USUBJID),
    filter_add = EXSEQ == 1,
    mode = "first"
  ) |>
  # ... more derivations ...
  drop_unspec_vars(metacore = mc, dataset = "ADSL") |>     # metatools: drop vars not in spec
  check_variables(metacore = mc, dataset = "ADSL") |>      # metatools: verify all spec vars present
  apply_variable_labels(metacore = mc, dataset = "ADSL")   # metatools: apply labels

# Apply XPT pipeline
adsl_xpt <- adsl |>
  xportr_metadata(mc, "ADSL", verbose = "warn") |>
  xportr_type() |>
  xportr_length() |>
  xportr_label() |>
  xportr_order() |>
  xportr_format() |>
  xportr_df_label(mc)

# Write the XPT
xportr_write(adsl_xpt, "submission/datasets/adsl.xpt")
```

A few notes on this script:

- **Metacore is loaded once** and reused throughout — single source of truth
- **`metatools::drop_unspec_vars()`** drops variables you derived but didn't include in spec (e.g., temporary variables) — keeps the final dataset clean
- **`metatools::check_variables()`** validates that the dataset matches the spec
- **`metatools::apply_variable_labels()`** sets R labels from the spec
- **xportr pipeline** then prepares for XPT specifically

This is the standard pharmaverse production pattern. Many pharma teams have scripts that look essentially like this for each ADaM.

## 14. Batch processing — many ADaMs at once

A typical study has ~10-20 ADaMs. Don't write 20 scripts; use a loop:

```r
adam_names <- c("ADSL", "ADAE", "ADLB", "ADVS", "ADCM", "ADEX", "ADTTE")

mc <- metacore::spec_to_metacore("specs/adam_spec.xlsx")

for (name in adam_names) {
  message("Writing ", name, "...")
  data_obj <- get(tolower(name))     # assume you've built adsl, adae, etc.

  data_xpt <- data_obj |>
    xportr_metadata(mc, name, verbose = "warn") |>
    xportr_type() |>
    xportr_length() |>
    xportr_label() |>
    xportr_order() |>
    xportr_format() |>
    xportr_df_label(mc)

  xportr_write(data_xpt, file.path("submission/datasets", paste0(tolower(name), ".xpt")))
}
```

For larger projects, use `{targets}` to track which ADaMs need regeneration based on what changed.

## 15. Validation: what xportr catches vs what it doesn't

xportr catches:

- Variable name violations (>8 chars, invalid characters)
- Label length violations (>40 chars)
- Character length violations (>200 or beyond spec)
- Type mismatches (data type doesn't match spec)
- Variables in spec but missing from data (and vice versa)
- Column order mismatches

xportr does **not** catch (these need Pinnacle 21 or similar):

- CDISC controlled terminology compliance (e.g., AESEV must be from a specific code list)
- Cross-dataset referential integrity (e.g., every USUBJID in ADAE exists in ADSL)
- ADaM rule violations beyond simple length/type checks
- Define-XML / Define-JSON conformance

For full submission validation, xportr produces the XPT; Pinnacle 21 (commercial or community edition) validates it. Most sponsors run Pinnacle 21 on every ADaM before submission.

## 16. The `xpt_validate()` helper

For pre-submission sanity checking:

```r
xpt_validate(adsl_xpt)
```

Returns a list of warnings/errors. Common findings:

- "USUBJID exceeds spec length of 20 (max actual: 22)"
- "AESOC label exceeds 40 chars: 'System Organ Class - Highest Level Term'"
- "Variable RACEN in data but not in spec"

Run this before `xportr_write()` to catch issues early. For CI/CD pipelines, you can wrap it to fail the build on errors.

## 17. Working with non-CDISC data

xportr is built for CDISC datasets but works on any tabular data:

```r
# Generic spec for a non-CDISC dataset
my_spec <- data.frame(
  dataset = "MYDATA",
  variable = c("ID", "VALUE", "CATEGORY"),
  type = c("character", "numeric", "character"),
  length = c(10, 8, 20),
  label = c("Identifier", "Measured Value", "Category"),
  order = c(1, 2, 3)
)

my_data |>
  xportr_metadata(my_spec, "MYDATA") |>
  xportr_type() |>
  xportr_length() |>
  xportr_label() |>
  xportr_order() |>
  xportr_write("my_data.xpt")
```

XPT v5 is the format — CDISC conventions are layered on top. For non-CDISC use (transferring data to a SAS-using client, archival in regulatory-friendly format), xportr works.

## 18. Common errors and fixes

### "USUBJID exceeds maximum length"
- Cause: data USUBJID values longer than spec
- Fix: shorten USUBJID in upstream SDTM build, or increase spec length

### "Cannot convert column X to numeric"
- Cause: a value won't coerce (e.g., "NA" string in a column spec'd as numeric)
- Fix: clean the data, replace "NA" with `NA_real_` before xportr

### "Variable VAR1 in data but not in spec"
- Cause: derived variable not included in spec
- Fix: add to spec, or drop via `metatools::drop_unspec_vars()` before xportr

### "Date format mismatch"
- Cause: date variable as character in data, numeric in spec
- Fix: convert to Date with `as.Date()` before xportr, or use `xportr_type()` to coerce

### "Pinnacle 21 reports variable label exceeds 40 chars"
- Cause: label in spec is too long
- Fix: edit spec to shorten label

Most errors are spec/data alignment issues. Fix at the spec level (which is the source of truth) and re-run.

## 19. The Atorus ecosystem fit

xportr is part of Atorus's open-source toolkit, alongside Tplyr (Lesson 36), logrx (Lesson 45), datasetjson (Lesson 44), and contributions to admiral. The ecosystem is designed to work together:

- **admiral** builds the ADaMs
- **metacore** holds the spec
- **metatools** applies the spec to data during build
- **xportr** writes the final XPT
- **logrx** logs the execution for compliance
- **datasetjson** (alternative to xportr) writes the emerging Dataset-JSON format

For Atorus-aligned sponsors, this stack is the default. For other sponsors, xportr integrates fine with non-Atorus tooling — the package is sponsor-neutral.

## 20. Key takeaways

- `{xportr}` produces FDA-compliant XPT v5 transport files from R data frames
- Six-step pipeline: `xportr_metadata()` → `xportr_type()` → `xportr_length()` → `xportr_label()` → `xportr_order()` → `xportr_format()` → `xportr_df_label()`
- `xportr_write()` produces the actual .xpt file
- Required spec columns: `dataset`, `variable`, `type`, `length`, `label`, `order`, `format`
- Integrates with metacore objects for end-to-end spec-driven workflow
- `verbose = "warn"` (minimum) prevents silent data truncation
- Catches metadata-level issues; Pinnacle 21 handles the broader CDISC validation
- Joint GSK + Atorus maintenance; part of the Atorus open-source ecosystem

## 21. What's next

Lesson 44 covers **`{datasetjson}`** — the emerging successor to XPT v5. The FDA piloted Dataset-JSON v1.1 in 2025-2026; it's positioned to eventually replace XPT for new submissions. Understanding both formats lets you produce traditional XPT today while being ready for the JSON transition.

After Lesson 44: Module 10 (logrx, diffdf, riskmetric) and the capstone.

---

## Self-check questions

1. Why is XPT v5 still the FDA submission standard despite its limitations?
2. List the six core `xportr_*()` functions in pipeline order.
3. What does `xportr_metadata(metadata, "ADSL", verbose = "warn")` do, and why is `verbose` important?
4. How would xportr handle a column where the actual data values exceed the spec'd length?
5. How does xportr integrate with metacore?
6. What does xportr NOT validate, and which tool typically handles that?

## Glossary

- **XPT v5** — SAS Version 5 transport file format; the FDA-accepted submission format for SDTM/ADaM
- **`xportr_metadata()`** — Attach spec to data frame for downstream pipeline functions
- **`xportr_type()`** — Coerce R types to character or numeric
- **`xportr_length()`** — Set SAS storage lengths per spec
- **`xportr_label()`** — Set variable labels (≤ 40 chars)
- **`xportr_order()`** — Reorder columns per spec
- **`xportr_format()`** — Set SAS format strings
- **`xportr_df_label()`** — Set dataset-level label
- **`xportr_write()`** — Produce the .xpt file
- **`xportr()`** — Convenience wrapper running all six attribute functions
- **`xpt_validate()`** — Pre-submission validation helper
- **`metacore` object** — Spec management package; xportr accepts these natively
- **Pinnacle 21** — Industry-standard CDISC validation tool; complementary to xportr
- **SAS date origin** — 1960-01-01; numeric date values are days since this
- **Define-XML / Define-JSON** — CDISC metadata documents accompanying SDTM/ADaM submissions
- **eCTD** — Electronic Common Technical Document; FDA submission format
- **Atorus / GSK joint maintenance** — xportr's open-source stewardship
