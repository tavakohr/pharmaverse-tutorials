# Lesson 12 — `{metacore}`: The Centralized Spec Object

**Module**: 3 — Metadata-driven programming
**Estimated length**: ~22 min spoken
**Prerequisites**: Lessons 03–06 (R foundations)

---

## Learning objectives

By the end of this lesson, you will be able to:

1. Explain why a "spec object" in R is preferable to passing around an Excel file
2. Describe the six tables that make up a metacore object
3. Build a metacore object from an Excel specification, Define-XML, or constructed manually
4. Use `select_dataset()` to focus a metacore object on a single dataset
5. Extract specific metadata from a metacore object (variable labels, codelists, derivations)
6. Recognize what changed in metacore 0.2.0 — the `DatasetMeta` subclass

---

## 1. Why metadata matters

Every clinical study has a **specification document** — usually an Excel workbook — that describes every dataset and every variable: name, label, type, length, codelist, derivation logic, whether it's required for define.xml. The spec is the source of truth. Your code is supposed to implement it.

In SAS practice, the spec lives in Excel and you transcribe parts of it into your code: a `length` statement gives the spec's length, a `label` statement gives the spec's label, a `proc format` reflects the spec's codelist. This is brittle. When the spec changes, you must remember to update the code. When the code drifts from the spec, you find out during validation — or worse, during the FDA review.

**Metadata-driven programming** means treating the spec as a programmable artifact. Your code *reads* the spec and uses it to build/validate datasets. Spec changes propagate automatically. The code can never drift from the spec because the spec is the input.

`{metacore}` is the R package that turns the spec into a programmable object. `{metatools}` (next lesson) is the package that *uses* metacore objects to build and check datasets.

## 2. The clinical reporting pipeline with metadata

The metadata-driven approach helps ensure that clinical trial data is consistently structured and aligned with regulatory standards:

```
Metadata (Excel / Define-XML)
       │
       │  read into R via metacore
       ▼
   metacore object
       │
       ├─ feeds {sdtm.oak}  → builds SDTM
       ├─ feeds {admiral}   → builds ADaM
       ├─ feeds {metatools} → checks both
       └─ feeds {xportr}    → applies labels/lengths/formats at export
```

The same metacore object threads through every step. Update the spec; re-run the pipeline; everything stays in sync.

## 3. Origin and maintenance

`metacore` was originally developed by Atorus Research and is now maintained collaboratively. The package is on CRAN. The current major version line is 0.2.x. Notable maintainers include Atorus and GSK contributors.

```r
install.packages("metacore")
library(metacore)
```

For the development version:

```r
remotes::install_github("atorus-research/metacore")
```

## 4. The metacore object structure

A metacore object is built on R6 — an object-oriented system in R that produces immutable, attribute-bag-style objects. The package's design is: an immutable container holding six related tables.

The six tables:

| Table | What it holds |
|---|---|
| `ds_spec` | Dataset-level info: dataset names, labels, structure |
| `ds_vars` | Dataset-variable relationships: which variables belong to which dataset, in what order, with what `mandatory` flag and `core` setting |
| `var_spec` | Variable-level info shared across datasets: label, type, length, format, common to a variable wherever it appears |
| `value_spec` | Value-level info: codelist IDs, where-clauses (BDS-style "valid AVAL for PARAMCD = HGB"), origin |
| `code_list` | Codelists: every CDISC controlled terminology + sponsor-defined codelist |
| `derivations` | Derivation algorithms: written-out logic for each derived variable |

Together they encode everything a Define-XML expresses, in a structure that's queryable in R.

## 5. Reading a Define-XML directly

For mature studies that already have a Define-XML 2.0 or 2.1 file:

```r
library(metacore)

# Read directly from Define-XML
md <- metacore_from_define("path/to/define.xml")

print(md)
```

You get back a metacore object with all six tables populated.

Under the hood, the package uses xml-reading helpers to extract each piece:

```r
doc <- xml2::read_xml("define.xml")

ds_spec2 <- xml_to_ds_spec(doc)
ds_vars <- xml_to_ds_vars(doc)
var_spec <- xml_to_var_spec(doc)
value_spec <- xml_to_value_spec(doc)
code_list <- xml_to_codelist(doc)
derivations <- xml_to_derivations(doc)
```

These are exposed so you can debug parsing issues or assemble a metacore object from a *partial* Define-XML.

## 6. Reading from a sponsor Excel spec

Most studies start from an Excel spec, not a Define-XML. The package provides spec readers for common Excel layouts. The most-used is the Pinnacle 21 specs template, but the package supports the older Mayo template and custom Excel layouts too.

```r
library(metacore)

md <- spec_to_metacore("spec.xlsx",
                       quiet = FALSE,
                       where_sep_sheet = TRUE)
```

The reader inspects the workbook structure, expects certain sheet names (Datasets, Variables, Value Level Metadata, Codelists, Derivations), and populates the six tables.

If your sponsor uses a non-standard Excel format, you'll write a custom reader once. The package exposes `spec_to_<table>()` builders for each of the six tables, so you assemble manually:

```r
# Read sheets directly with readxl
my_ds_spec <- readxl::read_excel("spec.xlsx", "Datasets")
my_ds_vars <- readxl::read_excel("spec.xlsx", "Variables")
# ... etc.

# Then assemble
md <- metacore(
  ds_spec = my_ds_spec,
  ds_vars = my_ds_vars,
  var_spec = my_var_spec,
  value_spec = my_value_spec,
  code_list = my_code_list,
  derivations = my_derivations
)
```

Each constructor validates its input (e.g., `ds_vars` must reference dataset names in `ds_spec`). If validation fails, you get a clear error message pinpointing the issue. This catches misconfigured specs *before* they cause cryptic bugs downstream.

## 7. The `mandatory` flag — what it replaces

Earlier metacore versions had a `keep` flag in `ds_vars`. In 0.3.0 it was renamed to `mandatory` to better align with CDISC terminology:

> Required items that have Mandatory set to "Yes" cannot have blank values. Variables in SDTM domains that have core = "Required" should have mandatory = TRUE.

If you're maintaining older code that uses `keep`, the migration is straightforward: rename `keep` to `mandatory` in your spec readers and downstream code. The package issues deprecation messages to help.

## 8. Looking inside a metacore object

```r
# After loading
md <- metacore_from_define("define.xml")

# What's in it?
print(md)
# Shows dimensions of each of the six tables

# Access individual tables
md$ds_spec
md$ds_vars
md$var_spec
md$value_spec
md$code_list
md$derivations
```

Each table is a tibble. You can use dplyr verbs on them just like any other data:

```r
# All variables in ADSL
md$ds_vars |>
  filter(dataset == "ADSL")

# All required variables across datasets
md$ds_vars |>
  filter(mandatory == TRUE)

# All codelists with their values
md$code_list |>
  arrange(name) |>
  head(20)
```

## 9. `select_dataset()` — focusing on one dataset

A metacore object built from a spec typically contains metadata for **many** datasets — every dataset in the study. When you're building a single dataset (say ADSL), you want a metacore object restricted to just that one.

`select_dataset()` does this:

```r
md_adsl <- md |> select_dataset("ADSL")
```

The result is a **`DatasetMeta` object** — a subclass of metacore specifically for one dataset. Most `{metatools}` functions expect a `DatasetMeta`, not the broader metacore.

This split between full-study and single-dataset objects is the key clarification in metacore 0.2.0:

> A metadata object about a single dataset will be required for users to work with `{metatools}` functions, which have had their API harmonised to accept only subsetted Metacore objects (via `metacore::select_dataset()`).

Before 0.2.0, the API was inconsistent — some functions accepted multi-dataset metacore, others didn't. After 0.2.0, the rule is clear: subset before passing to metatools.

```r
md <- metacore_from_define("define.xml")    # multi-dataset Metacore
md_adsl <- select_dataset(md, "ADSL")       # single-dataset DatasetMeta
md_adae <- select_dataset(md, "ADAE")       # another single-dataset DatasetMeta
```

You'll have one `DatasetMeta` per dataset you're building.

## 10. Common queries on a metacore object

In practice, you'll write helpers to extract spec info for a specific use. Some patterns:

### Get the variable label for one variable

```r
get_var_label <- function(md, varname) {
  md$var_spec |>
    filter(variable == varname) |>
    pull(label)
}

get_var_label(md_adsl, "AGE")
# "Age (years)"
```

### Get the codelist values for a variable

```r
get_codelist <- function(md, varname) {
  # Look up codelist_id for this variable
  cl_id <- md$value_spec |>
    filter(variable == varname) |>
    pull(code_id) |>
    first()

  # Pull the codelist
  md$code_list |>
    filter(code_id == cl_id)
}

get_codelist(md_adsl, "SEX")
# Returns a tibble with the SEX codelist (M, F, U)
```

(metatools provides cleaner versions of these, see Lesson 13.)

### Get the derivation logic for a variable

```r
md_adsl$derivations |>
  filter(derivation_id == "DR_TRTSDT") |>
  pull(derivation)
# "Treatment start date: first dose date from EX where..."
```

This is the spec's written description of *how* TRTSDT is derived. Your code should implement exactly this logic.

## 11. The relationship to Define-XML

Looking ahead to Module 9: a Define-XML 2.0 file is the canonical "spec" sent to FDA alongside your dataset submission. It encodes everything in the metacore object structure — datasets, variables, codelists, where-clauses, derivations, origin types.

`metacore` reads and writes Define-XML (write support is provided via companion packages; check the current ecosystem). The full round-trip:

```
spec.xlsx → metacore object → R code uses it → datasets produced
                ↓
            define.xml ← serialize for FDA submission
```

Some sponsors use Pinnacle 21 to convert specs to Define-XML directly, bypassing the round-trip. Either approach works; the key idea is that the metacore object is the in-memory representation that R code can program against.

## 12. Building a minimal metacore by hand

For testing, demos, or non-standard cases, you can build a metacore object from scratch. Useful for unit tests of your derivation functions:

```r
library(metacore)
library(tibble)

ds_spec <- tibble(
  dataset = "ADSL",
  structure = "One record per subject",
  label = "Subject-Level Analysis Dataset"
)

ds_vars <- tibble(
  dataset = "ADSL",
  variable = c("STUDYID", "USUBJID", "AGE", "SEX", "TRT01A"),
  order = c(1, 2, 3, 4, 5),
  mandatory = c(TRUE, TRUE, TRUE, TRUE, TRUE),
  core = c("Required", "Required", "Permissible", "Permissible", "Permissible")
)

var_spec <- tibble(
  variable = c("STUDYID", "USUBJID", "AGE", "SEX", "TRT01A"),
  label = c("Study Identifier", "Unique Subject Identifier",
            "Age (years)", "Sex", "Actual Treatment 01"),
  type = c("character", "character", "numeric", "character", "character"),
  length = c(20, 32, 8, 1, 40),
  format = c(NA, NA, NA, NA, NA)
)

value_spec <- tibble(
  variable = c("SEX"),
  dataset = c("ADSL"),
  where = c(NA),
  code_id = c("SEX_CL")
)

code_list <- tibble(
  code_id = c("SEX_CL", "SEX_CL", "SEX_CL"),
  name = c("SEX", "SEX", "SEX"),
  code = c("M", "F", "U"),
  decode = c("Male", "Female", "Unknown")
)

derivations <- tibble(
  derivation_id = c("DR_AGE"),
  derivation = c("From DM.AGE, no derivation")
)

md <- metacore(
  ds_spec, ds_vars, var_spec, value_spec, code_list, derivations
)

print(md)
```

This builds a tiny metacore object describing a minimal ADSL. You can pass it to metatools functions and verify they behave correctly without needing a real Excel spec.

## 13. Validation: what metacore checks for you

When you build a metacore object, the constructor checks:

- Every dataset in `ds_vars` exists in `ds_spec`
- Every variable in `ds_vars` exists in `var_spec`
- Every code_id in `value_spec` exists in `code_list`
- Every derivation_id referenced in `value_spec` exists in `derivations`
- Variable orders within a dataset are unique
- Mandatory variables have non-missing labels and types

These are exactly the kinds of bugs that, in an Excel-only workflow, would show up as runtime errors during data manipulation or — worse — silent data quality issues. metacore catches them at the moment you load the spec.

## 14. `metacore` vs. `metatools` — clearing up confusion

This is the most common point of confusion. Let me say it explicitly:

- **`{metacore}`**: the *spec object*. Loads, stores, validates the spec. Read-only after construction.
- **`{metatools}`**: *uses* the metacore object to build, check, and manipulate clinical datasets.

You always load `metacore` first, build the spec object, then pass it to metatools functions to do actual data work. Lesson 13 is metatools.

## 15. Companion: where to find spec templates

If your sponsor doesn't yet have a spec template, several public ones exist:

- The **Pinnacle 21 spec template** (Excel) — widely adopted; `metacore` natively reads it
- **CDISC's CDASH** and **SDTMIG** templates — these describe the standards, not your study, but they're useful references
- **Atorus's open `{atorus.spec}` examples** on GitHub — example specs designed to work with metacore
- Pharmaverse `examples/` Quarto notebooks — show metacore objects in use

For learning, the pharmaverse examples site provides metacore objects bundled into the example notebooks; you can extract the code that builds them and adapt for your study.

## 16. A practical recommendation

For real study work, treat the metacore object as a **shared artifact** maintained by the dataset spec owner (typically a statistical programmer or biostatistician), not built on-demand inside each programmer's script. Best-practice pattern:

1. **One R script** in your project's `scripts/` folder that loads the spec and constructs the metacore object
2. The script is **owned by the spec lead**
3. Other scripts load the metacore object from an `.rds` file (`saveRDS()` / `readRDS()`) or by sourcing the constructor script
4. When the spec changes, only the constructor script changes; downstream scripts re-run with the updated object

This mirrors how SAS shops treat their spec macros: one central definition, many users.

## 17. Key takeaways

- A `metacore` object is the in-memory representation of your study spec — an R-programmable equivalent of the Excel/Define-XML spec
- It contains six related tables: ds_spec, ds_vars, var_spec, value_spec, code_list, derivations
- Build it with `metacore_from_define()` or `spec_to_metacore()` or by direct construction
- Use `select_dataset()` to focus on one dataset — this produces a `DatasetMeta` subclass required by metatools
- Validation happens at construction time, catching spec issues early
- `metacore` is read-only; `{metatools}` (next lesson) uses it to do actual data work

## 18. What's next

Lesson 13 covers **`{metatools}`** — the package that consumes metacore objects to build, validate, and check your clinical datasets. We'll see how to derive variables from codelists, apply labels and types, check that produced data conforms to the spec, and combine metatools with admiral for spec-driven ADaM construction.

After Module 3 you're ready for the heart of pharmaverse: Module 4 — admiral.

---

## Self-check questions

1. Why is "the spec is in Excel and the code transcribes it" a fragile workflow?
2. What's the difference between a metacore object and a `DatasetMeta` object?
3. Name the six tables inside a metacore object and what each holds.
4. Why did `keep` get renamed to `mandatory` in metacore 0.3.0?
5. What happens at the moment you call `metacore(...)` to construct an object?
6. Where in a metacore object would you look up "what codelist applies to SEX in ADSL"?

## Glossary

- **Spec / Specification** — The document defining every dataset and variable for a study; usually Excel
- **Define-XML** — CDISC standard XML representation of a study spec; submitted to FDA with the data
- **`metacore` object** — In-memory representation of the spec; six tibbles wrapped in R6
- **`DatasetMeta`** — Subclass of metacore restricted to a single dataset; required by metatools
- **`ds_spec`** — Dataset-level metadata (dataset name, label, structure)
- **`ds_vars`** — Variable-dataset relationships (which variables in which dataset, in what order)
- **`var_spec`** — Variable-level metadata shared across datasets (label, type, length)
- **`value_spec`** — Value-level metadata (where-clauses, codelist IDs per variable)
- **`code_list`** — Codelist definitions (CT terms, codes, decodes)
- **`derivations`** — Written derivation logic per derived variable
- **`mandatory`** — Boolean flag indicating a variable must have non-blank values
- **`core`** — CDISC field: "Required", "Expected", or "Permissible"
