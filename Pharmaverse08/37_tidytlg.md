# Lesson 37 — `{tidytlg}`: Tidyverse-Style TLG Production

**Module**: 7 — TLG: the legacy/Roche stack
**Estimated length**: ~18 min spoken
**Prerequisites**: Lessons 33-36

---

## Learning objectives

By the end of this lesson, you will be able to:

1. Explain tidytlg's position — tidyverse-style functional TLG construction at Janssen
2. Use the three core functions: `freq()` (categorical counts), `univar()` (continuous summaries), `nested_freq()` (hierarchical counts)
3. Build a table by stacking individual layer outputs with `bind_table()`
4. Apply tidytlg's row-type and metadata system for downstream formatting
5. Differentiate the functional method vs. the metadata-driven method
6. Position tidytlg relative to Tplyr, gtsummary, and tern

---

## 1. What tidytlg is

`{tidytlg}` is **Janssen R&D's** open-source TLG package, released under pharmaverse. Its goal: generate tables, listings, and graphs using tidyverse-style syntax. Each analysis is a function call returning a tibble; tibbles stack together to form the final table.

The mental model differs from the other tools:

- **rtables**: layout-tree (splits and analyses, built before data)
- **Tplyr**: layered table specification (object with layers, then build)
- **gtsummary**: composable function chain (table builder with modifiers)
- **tidytlg**: functional analysis pieces returning tibbles, stacked together

tidytlg's primary author is Nicholas Masel (Janssen), with contributors from Pelagia Papadopoulou, Steven Haesendonckx, Sheng-Wei Wang, Eli Miller, Nathan Kosiba (note Eli and Nathan also work on Tplyr; Atorus and Janssen collaborate). Current version 0.10.x as of mid-2026.

## 2. Installation

```r
install.packages("tidytlg")
# Or for the development version
# devtools::install_github("pharmaverse/tidytlg")

library(tidytlg)
library(dplyr)
```

tidytlg ships with `cdisc_adsl`, `cdisc_adae` test datasets — variants of the CDISC pilot data.

## 3. The three core functions

| Function | What it produces |
|---|---|
| `freq()` | Categorical frequency counts: n (%) per level per column variable |
| `univar()` | Continuous univariate summaries: N, mean (SD), median, range, quartiles |
| `nested_freq()` | Nested categorical counts: hierarchical (e.g., SOC × PT) |

Each function takes data, a row variable, a column variable, and configuration; returns a tibble in tidytlg's "stack-ready" format.

## 4. A first table

```r
library(tidytlg)
library(dplyr)

# Filter to ITT population
ittpop <- cdisc_adsl |> filter(ITTFL == "Y")

# Layer 1: subject count (Big-N)
tbl1 <- freq(
  ittpop,
  rowvar = "ITTFL",
  statlist = statlist("n"),
  colvar = "TRT01P",
  rowtext = "Analysis Set: Intent-to-Treat Population",
  subset = ITTFL == "Y"
)

# Layer 2: AGE summary
tbl2 <- univar(
  ittpop,
  rowvar = "AGE",
  colvar = "TRT01P",
  row_header = "Age (Years)"
)

# Layer 3: RACE counts
tbl3 <- freq(
  ittpop,
  rowvar = "RACE",
  statlist = statlist(c("N", "n (x.x%)")),
  colvar = "TRT01P",
  row_header = "Race"
)

# Stack into one table
final_tbl <- bind_table(tbl1, tbl2, tbl3)

final_tbl
```

Each layer is one analysis. `bind_table()` stacks the resulting tibbles into a single output table. The pattern resembles Tplyr's `add_layer()` but each layer is its own function call rather than chained method.

## 5. The `statlist()` configuration

`statlist()` controls which statistics to include and their format:

```r
# Standard frequency
statlist(c("N", "n (x.x%)"))   # Big-N row + n (pct) rows

# Just counts
statlist("n")

# Custom continuous summary
statlist(c("N", "Mean (SD)", "Median", "Range"))

# Quantile-based
statlist(c("N", "Mean (SD)", "Median (Q1, Q3)", "Min, Max"))
```

The string format is intentionally close to how SAS programmers describe table contents — declarative rather than procedural.

## 6. Categorical counts

```r
freq(
  data = ittpop,
  rowvar = "SEX",
  colvar = "TRT01P",
  statlist = statlist(c("N", "n (x.x%)")),
  rowtext = "Sex"
)
```

Defaults are subject-aware (each USUBJID counted once per category). The output tibble has columns: `label` (row label), one column per arm (`Placebo`, `Xanomeline High Dose`, etc.), plus a `row_type` column distinguishing N rows from value rows (essential for downstream formatting).

## 7. Continuous summaries

```r
univar(
  data = ittpop,
  rowvar = "AGE",
  colvar = "TRT01P",
  row_header = "Age (Years)",
  statlist = statlist(c("N", "Mean (SD)", "Median (Q1, Q3)", "Min, Max"))
)
```

Output: header row plus stat rows ("N", "Mean (SD)", "Median (Q1, Q3)", "Min, Max"), with values per arm.

The format strings like `"x.x"` are tidytlg's mini-language (similar to rtables/Tplyr). Defaults match SAS conventions; override with the `format` arguments.

## 8. Nested counts for AE tables

```r
nested_freq(
  data = cdisc_adae,
  rowvar = c("AESOC", "AETERM"),    # hierarchy
  colvar = "TRT01P",
  statlist = statlist(c("N", "n (x.x%)"))
)
```

The output: SOC-level rows followed by AETERM-level rows within each SOC. The structure is flat (not nested in the data frame sense — just a tall tibble with hierarchical labels and `row_type` indicating level), but renders as a hierarchical table when written to RTF.

For canonical AE tables, this is the workhorse function.

## 9. The metadata-driven method

For batch TLG generation, tidytlg supports a metadata-driven approach: instead of writing one R script per table, you write a column metadata file and a table metadata file, and tidytlg generates outputs from them.

The metadata files (typically CSV or Excel):

```
table_metadata.csv:
table_id, layer, function, rowvar, statlist, ...
t_14_2_1, 1, freq, ITTFL, "n", ...
t_14_2_1, 2, univar, AGE, "N, Mean (SD), Median, Range", ...
t_14_2_1, 3, freq, SEX, "N, n (x.x%)", ...
```

Then a single script reads the metadata and produces all tables:

```r
# Conceptual flow
tables_meta <- read_csv("table_metadata.csv")
columns_meta <- read_csv("column_metadata.csv")

for (tbl_id in unique(tables_meta$table_id)) {
  # Build the table per its metadata spec
  layers <- tables_meta |> filter(table_id == tbl_id)
  tbl <- generate_table(layers, columns_meta, data)
  write_output(tbl, tbl_id)
}
```

The pattern enables a "data-driven" TLG batch: change the metadata file, get new tables. For sponsors that need to maintain hundreds of tables across studies, this is powerful — the metadata becomes the spec, and the R code is generic.

This metadata approach is similar to tfrmt's metadata-driven philosophy but more focused on the analysis side (which stats to compute) vs. the display side (how to format).

## 10. The `row_type` system

A signature tidytlg feature: every row in the output has a `row_type` column indicating what kind of row it is:

| `row_type` value | What it means |
|---|---|
| `HEADER` | Variable-label header row (e.g., "Age (Years)") |
| `N` | Big-N denominator row |
| `VALUE` | A normal data row (a statistic) |
| `NESTED` | A nested sub-row (e.g., PT within SOC) |
| `BY_HEADER1`, `BY_HEADER2`, etc. | Group-by headers |

The `row_type` enables downstream formatters (RTF generators, gt renderers) to apply different styling per row type — e.g., HEADER rows in bold, VALUE rows indented, N rows centered. This separation of "what the row is" from "how it's displayed" is one of tidytlg's strengths.

## 11. Stacking and final output

`bind_table()` is tidytlg's `rbind()` equivalent that preserves the `row_type` column and label structure:

```r
final <- bind_table(layer1, layer2, layer3, ...)
```

The output is a tibble ready for downstream RTF generation. The typical chain:

```r
final |>
  add_count_to_header(big_n = TRUE) |>   # adds "(N=xx)" subtitles to column headers
  gentlg(                                 # tidytlg's RTF generation helper
    tlf = "TABLE",
    filename = "outputs/t_14_2_1",
    title = "Demographics — Safety Population",
    footers = c("Source: ADSL")
  )
```

`gentlg()` is tidytlg's RTF output function — analogous to r2rtf's pipeline but tighter integrated with tidytlg's output format. Under the hood, it uses `flextable` for RTF generation.

For maximum control, you can also pipe the tidytlg output into `r2rtf` directly:

```r
final |>
  rtf_title(...) |>
  rtf_body(...) |>
  rtf_encode() |>
  write_rtf("outputs/t_14_2_1.rtf")
```

Either path works. tidytlg's `gentlg()` is the more integrated option; raw r2rtf gives finer control.

## 12. A complete demographics table example

```r
library(tidytlg)
library(dplyr)

adsl <- cdisc_adsl

# Build layers
ittpop <- adsl |> filter(ITTFL == "Y")

n_layer <- freq(
  ittpop,
  rowvar = "ITTFL",
  statlist = statlist("n"),
  colvar = "TRT01P",
  rowtext = "Analysis Set: Intent-to-Treat Population",
  subset = ITTFL == "Y"
)

age_layer <- univar(
  ittpop,
  rowvar = "AGE",
  colvar = "TRT01P",
  row_header = "Age (Years)",
  statlist = statlist(c("N", "Mean (SD)", "Median (Q1, Q3)", "Min, Max"))
)

agegr_layer <- freq(
  ittpop,
  rowvar = "AGEGR1",
  colvar = "TRT01P",
  statlist = statlist(c("n (x.x%)")),
  row_header = "Age Group"
)

sex_layer <- freq(
  ittpop,
  rowvar = "SEX",
  colvar = "TRT01P",
  statlist = statlist(c("n (x.x%)")),
  row_header = "Sex"
)

race_layer <- freq(
  ittpop,
  rowvar = "RACE",
  colvar = "TRT01P",
  statlist = statlist(c("n (x.x%)")),
  row_header = "Race"
)

# Stack
final_tbl <- bind_table(n_layer, age_layer, agegr_layer, sex_layer, race_layer)

# Output
final_tbl |>
  gentlg(
    tlf = "TABLE",
    filename = "outputs/t_14_2_1",
    title = c(
      "Table 14.2.1: Demographic and Baseline Characteristics",
      "Intent-to-Treat Population"
    ),
    footers = c(
      "Continuous: N, Mean (SD), Median (Q1, Q3), Min, Max.",
      "Categorical: n (%) based on Intent-to-Treat population per arm.",
      "Source: ADSL"
    ),
    orientation = "landscape"
  )
```

Result: a CSR-grade RTF in ~30 lines of clear, tidyverse-style code.

## 13. tidytlg vs Tplyr

Both are SAS-friendly. Both produce tibbles. Both excel at flat tables. What's different?

| Aspect | Tplyr | tidytlg |
|---|---|---|
| Mental model | Object-with-layers (tplyr_table → add_layer → build) | Functional pieces (freq, univar, nested_freq → bind_table) |
| Method chaining | Pipe through the object | Each layer is its own assignment + bind |
| Metadata-driven mode | Not native | Built-in (CSV/Excel metadata → batch generation) |
| Output structure | Tibble with formatted strings | Tibble with formatted strings + `row_type` column |
| Total handling | `add_total_group()`, `add_total_row()` | Configured per layer |
| RTF integration | r2rtf pipeline | `gentlg()` or r2rtf pipeline |
| Primary maintainer | Atorus | Janssen |
| Adoption | Atorus + transition sponsors | Janssen + adopters |

Both are excellent. Choice often follows organizational alignment (Atorus heritage → Tplyr; Janssen heritage → tidytlg) or stylistic preference (procedural object pattern vs. functional/tidyverse pattern).

## 14. tidytlg vs gtsummary

Both are tidyverse-flavored. But:

- **gtsummary** is more polished for direct display — its rendering produces beautiful HTML/Word/PDF output natively
- **tidytlg** is more focused on the RTF production pipeline — tibble output, then rendered to RTF
- **gtsummary** has the ARD-first architecture (Cardinal-future stack)
- **tidytlg** is "tibble-first" — tibbles are the data structure throughout

For sponsors heavily invested in tidyverse and RTF delivery, tidytlg is a natural fit. For sponsors aligning with Cardinal-future, gtsummary is the path.

## 15. The `{envsetup}` integration

Janssen also maintains `{envsetup}` — a companion package for setting up I/O paths consistently across studies. tidytlg integrates with envsetup for the typical "production folder structure" workflow:

```r
library(envsetup)

# Define paths once
set_input_dir("data/")
set_output_dir("outputs/")

# Now scripts can write to the right locations automatically
final_tbl |>
  gentlg(filename = "t_14_2_1", ...)
# Writes to outputs/t_14_2_1.rtf
```

For SOP-driven production environments, this kind of consistency reduces errors. envsetup is small and optional; you don't need it to use tidytlg.

## 16. When to choose tidytlg

Choose tidytlg when:

- Your team has Janssen heritage or alignment
- You want tidyverse-style functional code for TLG
- You need metadata-driven batch generation
- You prefer "each analysis is a function" mental model
- You want a tighter RTF generation flow than r2rtf alone

Skip tidytlg when:

- Your team is already on Tplyr or rtables
- You're transitioning to Cardinal-future (gtsummary)
- The Tplyr layered API feels more natural for your team

## 17. Maintainers and direction

Maintained by Nicholas Masel and other Janssen R&D contributors, with cross-pharma support. The package is in active development, with regular releases focusing on:

- Improved metadata-driven workflows
- Better integration with the broader pharmaverse (cards, admiral, etc.)
- Performance and edge-case handling
- Documentation expansion

Strategic direction: tidytlg is positioned as a mid-stack TLG tool — alongside Tplyr in the "tibble-first" family. As CDISC ARS develops, expect tidytlg to gain ARD-emission capabilities (similar to expected Tplyr evolution).

## 18. Module 7 wrap-up

You've now covered the legacy TLG stack:

- **rtables** (Roche): layout-tree DSL, foundation for NEST
- **tern**: clinical wrappers on top of rtables
- **r2rtf** (Merck): focused RTF generation, composes with any computation
- **Tplyr** (Atorus): SAS-style layered tables, SAS-matching numerics
- **tidytlg** (Janssen): tidyverse-style functional TLG with metadata-driven option

Combined with Module 6's Cardinal-future stack, you can navigate essentially any modern pharma TLG codebase. Most production environments use 2-3 of these packages together; understanding all five gives you flexibility to work across team and sponsor boundaries.

## 19. What's next

Module 8 covers **Shiny / teal** — interactive clinical data exploration. After producing static TLGs, the next layer is interactivity: dashboards that let study teams explore data, change filters, and generate ad-hoc analyses. teal is Roche's Shiny framework for this; teal.modules.clinical is the clinical-specific module library.

Three lessons in Module 8: teal foundations, teal modules and apps, teal.modules.clinical.

Then Module 9 (xportr + datasetjson for submission), Module 10 (logrx + diffdf + riskmetric for traceability/QC), and Module 11 (capstone — end-to-end synthetic oncology study).

## 20. Key takeaways

- `{tidytlg}` is Janssen's tidyverse-style TLG package: functional analyses returning tibbles, stacked into tables
- Three core functions: `freq()` (categorical), `univar()` (continuous), `nested_freq()` (hierarchical)
- `statlist()` configures which statistics appear
- `row_type` column on output enables downstream-aware formatting
- `bind_table()` stacks layer tibbles into the final table
- `gentlg()` is tidytlg's integrated RTF output function; r2rtf works as alternative
- Metadata-driven mode supports batch generation from CSV/Excel specs
- Coexists with Tplyr, rtables, gtsummary, and Cardinal-future

---

## Self-check questions

1. What's the difference between Tplyr's `add_layer()` and tidytlg's `bind_table()` approach?
2. Translate to tidytlg: build a layer summarizing AGE by TRT01P with N, Mean (SD), Median, Range.
3. What's the purpose of the `row_type` column in tidytlg output?
4. How does `nested_freq()` differ from `freq()` for AE-style tables?
5. What's the metadata-driven mode in tidytlg, and when is it useful?
6. Why does tidytlg integrate naturally with both `gentlg()` and `r2rtf`?

## Glossary

- **`{tidytlg}`** — Janssen's tidyverse-style TLG package
- **`freq()`** — Categorical frequency layer
- **`univar()`** — Continuous univariate summary layer
- **`nested_freq()`** — Hierarchical (nested) categorical layer
- **`statlist()`** — Configuration of which statistics to include
- **`bind_table()`** — Stack tibble layers into one output
- **`gentlg()`** — RTF generation function (tidytlg's integrated path)
- **`row_type`** — Output column identifying row category (HEADER, N, VALUE, NESTED, BY_HEADER)
- **Metadata-driven mode** — Batch TLG generation from CSV/Excel spec files
- **`{envsetup}`** — Janssen companion package for I/O path management
- **`gentlg(tlf = "TABLE", ...)`** — Specify output type (TABLE/LISTING/GRAPH)
- **Atorus-Janssen collaboration** — Shared developer base across Tplyr and tidytlg
- **NEST** — Roche-led TLG initiative (rtables family)
- **Tibble-first** — Mental model where tibbles are the throughout data structure
