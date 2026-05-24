# Lesson 33 — `{rtables}`: Roche's Layered Table DSL

**Module**: 7 — TLG: the legacy/Roche stack
**Estimated length**: ~22 min spoken
**Prerequisites**: Lessons 25-32 (Cardinal-future stack) for comparison

---

## Learning objectives

By the end of this lesson, you will be able to:

1. Explain `{rtables}` as Roche's table-layout DSL — the foundation of the NEST stack
2. Build a layout with `basic_table()`, `split_cols_by()`, `split_rows_by()`, `analyze()`
3. Distinguish the layout (pre-data description) from the built table (`build_table(layout, data)`)
4. Use `in_rows()` to define multi-statistic analysis functions
5. Apply `split_fun` arguments to handle factor levels (drop, reorder, exclude)
6. Recognize where rtables sits relative to tern and the rest of NEST

---

## 1. Why this module exists

Module 6 covered the Cardinal-future TLG stack (cards + gtsummary + tfrmt + cardinal). That's the direction. But the **legacy stack — rtables, tern, r2rtf, Tplyr, tidytlg — is still production-dominant in most pharma sponsors as of 2026**.

Reasons:

- Existing CSR pipelines: thousands of validated templates already use rtables. Rewriting them costs millions.
- Roche, Novartis, AbbVie, BI, and other NEST-aligned sponsors are heavily invested
- Merck and many CROs default to r2rtf
- Tplyr is the SAS-programmer-friendly translation path
- tidytlg is mature and Janssen's go-to

Even if your future is Cardinal-future, your present probably involves the legacy stack. Understanding it lets you:

- Maintain existing pipelines
- Collaborate across teams with mixed tooling
- Choose intelligently for new work
- Migrate strategically (rtables → gtsummary, Tplyr → cards) when the time is right

This module covers each package. Patterns and tradeoffs first; gory implementation details second.

## 2. What rtables is

`{rtables}` is Roche's open-source R package for building **regulatory-grade tables**. It originated inside Roche around 2017–2018 as part of the NEST (Next-Generation Exploratory and Standardized Tools) initiative, externalized as open source in 2020, and is now hosted under the `insightsengineering` GitHub organization (Roche's open-source umbrella).

The headline design principle: a table is built in **two phases**:

1. **Layout**: a description of the table structure — splits, analyses, formatting — created without any data
2. **Build**: the layout is applied to data to produce a populated table

```r
library(rtables)

# Phase 1: layout (no data yet)
lyt <- basic_table() |>
  split_cols_by("ARM") |>
  analyze("AGE", mean)

# Phase 2: build (apply layout to data)
tbl <- build_table(lyt, DM)
tbl
```

The split-phase / build-phase distinction enables the "mock workflow" we saw with tfrmt — you can review and approve the layout before any real data is plugged in. (rtables predates tfrmt by years; tfrmt borrows the philosophy.)

## 3. Installation

```r
install.packages("rtables")
library(rtables)
```

rtables ships with a small test dataset `DM` (demographics) and `ex_adsl` (a CDISC-pilot-style ADSL) for examples.

## 4. The four core verbs

Most rtables layouts use just a few functions:

| Verb | What it does |
|---|---|
| `basic_table()` | Start a new layout with optional title/footer |
| `split_cols_by(var)` | Split columns by levels of a variable (e.g., one column per arm) |
| `split_rows_by(var)` | Split rows into groups by levels of a variable |
| `analyze(var, afun)` | Apply an analysis function to a variable, producing rows |

A minimal demographics table:

```r
lyt <- basic_table() |>
  split_cols_by("ARM") |>
  analyze(c("AGE", "BMRKR1", "BMRKR2"))

tbl <- build_table(lyt, ex_adsl)
tbl
```

The default `analyze()` summary depends on the variable type — numeric variables get summary stats; categorical variables get level counts. The result for `AGE`, `BMRKR1`, `BMRKR2` (the first two numeric, last categorical):

```
                A: Drug X     B: Placebo     C: Combination
————————————————————————————————————————————————————————————
AGE
  Mean (sd)     33.77 (6.55)  35.43 (7.90)   35.43 (7.72)
  Median        33.00         35.00          35.00
  Min - Max     21.00 - 50.00 21.00 - 62.00  20.00 - 69.00
BMRKR1
  Mean (sd)     5.97 (3.55)   5.70 (3.31)    5.62 (3.49)
  ...
BMRKR2
  LOW           50            45             40
  MEDIUM        37            56             42
  HIGH          47            33             50
```

Three arm columns, four "row sections" (AGE / BMRKR1 / BMRKR2), each with sub-rows for individual statistics.

## 5. Custom analysis functions: `in_rows()`

The default analysis is generic. For control, write a custom `afun`:

```r
my_afun <- function(x, ...) {
  if (is.numeric(x)) {
    in_rows(
      "Mean (sd)" = c(mean(x, na.rm = TRUE), sd(x, na.rm = TRUE)),
      "Median"    = median(x, na.rm = TRUE),
      "Min - Max" = range(x, na.rm = TRUE),
      .formats = c(
        "Mean (sd)" = "xx.xx (xx.xx)",
        "Median"    = "xx.xx",
        "Min - Max" = "xx.xx - xx.xx"
      )
    )
  } else if (is.factor(x) || is.character(x)) {
    in_rows(.list = as.list(table(x)))
  } else {
    stop("type not supported")
  }
}

lyt <- basic_table() |>
  split_cols_by("ARM") |>
  analyze(c("AGE", "BMRKR1", "BMRKR2"), my_afun)

build_table(lyt, ex_adsl)
```

`in_rows()` is the workhorse: it returns multiple rows from one analysis, each with its own label and format spec. The format strings (`"xx.xx (xx.xx)"`, `"xx.xx"`, `"xx.xx - xx.xx"`) are rtables' format mini-language — same conventions as tfrmt's `frmt()`.

## 6. Multi-level columns

For Visit × Arm column splits:

```r
lyt <- basic_table() |>
  split_cols_by("ARM") |>
  split_cols_by("SEX") |>
  analyze("AGE", mean, format = "xx.xx")

build_table(lyt, DM_MF)
```

The columns become hierarchical: top-level header `ARM` with sub-columns for each arm; second-level `SEX` with sub-columns F/M under each arm. Reading from outside in: Arm A→F, Arm A→M, Arm B→F, Arm B→M, etc.

This is one of rtables' superpowers: arbitrarily nested column structures, harder to achieve in gtsummary.

## 7. Row splits and groups

Similar for rows:

```r
lyt <- basic_table() |>
  split_cols_by("ARM") |>
  split_rows_by("SEX") |>
  split_rows_by("RACE", split_fun = drop_split_levels) |>
  analyze("AGE")

build_table(lyt, DM)
```

This produces: top-level row groups by SEX (Female / Male); within each, row groups by RACE; within each RACE×SEX cell, analyze AGE.

The `split_fun` argument controls how factor levels are handled:

- `drop_split_levels` — exclude factor levels with zero observations
- `remove_split_levels(excl = "Asian")` — explicitly drop named levels
- `keep_split_levels(only = c("White", "Black"))` — keep only specified levels
- Custom split functions are supported

This level of control is essential for clinical tables where you want consistent layout across studies even when one study lacks certain demographic categories.

## 8. Summarize row groups

Adding label rows (e.g., "RACE (Total subjects)" before each race group):

```r
lyt <- basic_table() |>
  split_cols_by("ARM") |>
  split_rows_by("RACE", split_fun = drop_split_levels) |>
  summarize_row_groups(format = "xx") |>
  analyze("AGE", mean, format = "xx.xx")

build_table(lyt, DM)
```

`summarize_row_groups()` adds a row at the top of each row split with a summary stat (default: count). Useful for "Subjects with Event" rows in AE tables.

## 9. Column counts and Big-N

For arm columns showing `(N=86)` subtitles:

```r
lyt <- basic_table(show_colcounts = TRUE) |>
  split_cols_by("ARM") |>
  analyze("AGE")

build_table(lyt, DM)
```

`show_colcounts = TRUE` adds the column count as a subtitle. The format defaults to `"(N=xx)"` and can be customized via `colcount_format`.

## 10. Output: ASCII, RTF, Word

rtables tables print to the R console as monospace ASCII (suitable for log files). For RTF/Word output, rtables converts via the `tt_to_flextable()` helper, then exports through flextable:

```r
library(flextable)

tbl |>
  tt_to_flextable() |>
  save_as_rtf(path = "table.rtf")
```

For complex tables, the conversion may need adjustment to preserve all rtables features (e.g., spanning rows, formatting). Roche internally has additional helpers (some in `{rlistings}` and `{rtables.officer}`) for cleaner RTF output.

For sponsors who use `{r2rtf}` instead (the Merck path), the integration is even cleaner — rtables → flextable → r2rtf is a common chain.

## 11. Pagination

Long tables need to break across pages. `pag_indices_inner()` and the page-related functions handle this:

```r
tbl_paginated <- paginate_table(tbl, lpp = 70)   # max 70 lines per page
# returns a list of page-sized table fragments
```

For RTF output, the pagination logic is typically delegated to `{flextable}` or `{r2rtf}`. Each handles header repetition and continuation labels.

## 12. The mental model: layout as a tree

A useful mental model: a rtables layout is a **tree** of operations.

```
basic_table()
  ├── split_cols_by("ARM")
  │     └── (now we have one column per ARM)
  ├── split_rows_by("RACE")
  │     └── (within each ARM column, split rows by RACE)
  └── analyze("AGE", mean)
        └── (within each ARM×RACE cell, compute mean of AGE)
```

Reading the layout top-to-bottom is reading the tree. Each verb nests inside the previous. The build phase walks the tree against the data, producing one cell per leaf.

## 13. Templating: writing reusable layouts

Because layouts are pre-data, you can build a library of layout functions:

```r
demog_layout <- function() {
  basic_table(show_colcounts = TRUE) |>
    split_cols_by("ARM") |>
    add_overall_col() |>
    analyze(c("AGE", "WEIGHT"), demog_afun) |>
    analyze(c("SEX", "RACE"), demog_afun)
}

demog_afun <- function(x, ...) {
  # ... custom function
}

# Usage in any study
lyt <- demog_layout()
tbl <- build_table(lyt, study_adsl)
```

The function captures the layout once; multiple studies reuse it. This pattern underlies tern (Lesson 34), which packages dozens of pre-built layout templates.

## 14. rtables vs the Cardinal-future stack

A direct comparison:

| Aspect | rtables | cards + gtsummary + tfrmt |
|---|---|---|
| **Data model** | Computation embedded in layout | Computation (cards) separate from display (gtsummary/tfrmt) |
| **ARD-aligned** | No — produces tables directly | Yes — ARD is the durable artifact |
| **Mock workflow** | Yes — layout pre-data | Yes — tfrmt mocks |
| **Strength** | Maximum control over complex layouts; deep customization | Standard tables; ARD reusability; faster to write |
| **Weakness** | Layout-data coupling; harder to share computations | Less flexible for very bespoke layouts |
| **Production maturity** | Mature, dominant at Roche/Novartis/AbbVie/BI | Newer, gaining traction; production at adopters |

Both are valid. The rtables approach scales well for sponsors with hundreds of validated templates. The Cardinal-future approach scales well for sponsors prioritizing CDISC ARS alignment and ARD reusability.

## 15. The NEST family

rtables is the foundation of NEST. Other NEST packages build on it:

- **`{tern}`** (Lesson 34): pre-built clinical table layouts on top of rtables
- **`{chevron}`**: even higher-level orchestration; uses tern to generate full TLG batches with standardized inputs
- **`{rlistings}`**: listing generation companion to rtables
- **`{teal}`** and **`{teal.modules.clinical}`** (Module 8): Shiny apps consuming rtables outputs
- **`{nestcolor}`**, **`{cowplot}`** integration: figure styling for NEST graphs

The NEST stack is comprehensive: data prep → tables → listings → graphs → Shiny apps, all integrated. For Roche-style workflows, it's the default. Cardinal is positioned to replace parts of this over time, but the NEST footprint is large.

## 16. When to choose rtables

Use rtables when:

- You're working in a Roche/Novartis/AbbVie/BI environment with existing NEST infrastructure
- You need maximum layout control — nested column groups 3+ levels deep, custom span structures
- You're building a library of reusable layouts that multiple studies will share
- Your sponsor has invested in NEST training and validation

Use the Cardinal-future stack when:

- You're starting fresh
- CDISC ARS alignment is a priority
- ARD reusability across multiple displays is valuable
- You want simpler / faster code for standard tables

Many teams use both: rtables for complex tables, gtsummary for standard.

## 17. Putting it together: a complete demographics layout

```r
library(rtables)
library(dplyr)

# Load data (rtables ships with ex_adsl)
adsl <- ex_adsl |> filter(SAFFL == "Y")

# Custom analysis function: continuous variables
afun_cont <- function(x, ...) {
  in_rows(
    "N" = sum(!is.na(x)),
    "Mean (SD)" = c(mean(x, na.rm = TRUE), sd(x, na.rm = TRUE)),
    "Median (Q1, Q3)" = c(median(x, na.rm = TRUE),
                          quantile(x, 0.25, na.rm = TRUE),
                          quantile(x, 0.75, na.rm = TRUE)),
    "Min, Max" = range(x, na.rm = TRUE),
    .formats = c(
      "N" = "xx",
      "Mean (SD)" = "xx.x (xx.xx)",
      "Median (Q1, Q3)" = "xx.x (xx.x, xx.x)",
      "Min, Max" = "xx, xx"
    )
  )
}

# Build the layout
lyt <- basic_table(
  title = "Table 14.2.1: Demographic and Baseline Characteristics",
  subtitles = "Safety Population",
  main_footer = "Mean (SD); Median (Q1, Q3); Min, Max for continuous variables. n (%) for categorical."
) |>
  split_cols_by("ARM") |>
  add_overall_col(label = "Overall") |>
  analyze(c("AGE"), afun_cont, var_labels = c(AGE = "Age (years)")) |>
  analyze(c("AGEGR1", "SEX", "RACE"))

tbl <- build_table(lyt, adsl)
tbl

# Export
tbl |>
  tt_to_flextable() |>
  flextable::save_as_rtf(path = "outputs/t_14_2_1.rtf")
```

This produces a standard CSR demographics table. The pattern works because the layout captures the logical structure independently of the data, then `build_table()` does the work.

## 18. Key takeaways

- `{rtables}` is Roche's table-layout DSL — the foundation of the NEST clinical reporting stack
- Two-phase model: layout (pre-data description) + build (apply to data)
- Core verbs: `basic_table()`, `split_cols_by()`, `split_rows_by()`, `analyze()`, `summarize_row_groups()`
- `in_rows()` defines multi-statistic analyses with format strings
- `split_fun` controls factor level handling (drop unused, exclude specific, custom)
- Output: ASCII for logs; RTF/Word via flextable or r2rtf
- Mature, dominant in Roche/Novartis/AbbVie/BI environments
- Coexists with Cardinal-future; rtables excels at complex layouts, Cardinal-future excels at standard tables with ARD reusability

## 19. What's next

Lesson 34 covers **`{tern}`** — pre-built clinical table layouts on top of rtables. tern is what makes rtables practical for clinical reporting at scale: instead of writing custom `afun` functions for every table, you call `count_occurrences()`, `analyze_vars()`, `summarize_ancova()`, and similar functions that encapsulate the standard analyses.

After tern: r2rtf (Lesson 35), Tplyr (Lesson 36), tidytlg (Lesson 37). Then Module 7 is complete and we move to Module 8 (Shiny + teal).

---

## Self-check questions

1. What's the difference between an rtables "layout" and a "table"?
2. Translate to rtables: split columns by ARM, split rows by RACE, analyze AGE with mean.
3. What does `in_rows()` do, and why use it instead of returning a single value from `afun`?
4. How does `split_fun = drop_split_levels` change the output?
5. Why does rtables sit at the foundation of the NEST stack rather than serving as a standalone package?
6. When would you choose rtables over gtsummary, and vice versa?

## Glossary

- **NEST** — Next-Generation Exploratory and Standardized Tools; Roche-led TLG initiative
- **DSL** — Domain-Specific Language (here, for table layouts)
- **`basic_table()`** — Start a new rtables layout
- **`split_cols_by(var)`** — Split columns by variable levels
- **`split_rows_by(var)`** — Split rows by variable levels (creates row groups)
- **`analyze(var, afun)`** — Apply analysis function to a variable
- **`summarize_row_groups()`** — Add header/summary rows for each row group
- **`build_table(layout, data)`** — Apply a layout to data to produce a table
- **`in_rows()`** — Return multiple labeled rows from one analysis function
- **`split_fun`** — Argument controlling factor level handling
- **`add_overall_col()`** — Add a column with all subjects combined
- **`tt_to_flextable()`** — Convert rtables to flextable for export
- **`{rlistings}`** — NEST companion package for clinical listings
- **`{chevron}`** — Higher-level orchestration package; uses tern to generate TLG batches
- **Layout-as-tree** — Mental model: rtables layout is a nested tree of operations
