# Lesson 28 — `{gtsummary}` Part 1: From ARD to Publication Table

**Module**: 6 — TLG: the Cardinal-future stack
**Estimated length**: ~22 min spoken
**Prerequisites**: Lessons 25–27 (cards, cardx)

---

## Learning objectives

By the end of this lesson, you will be able to:

1. Explain gtsummary's position as the display layer for cards/cardx ARDs
2. Use `tbl_ard_summary()` to render an ARD as a publication-quality table
3. Use direct (non-ARD) gtsummary functions like `tbl_summary()` and `tbl_continuous()` for quick analyses
4. Apply `add_p()`, `add_stat_label()`, and `modify_*()` to customize tables
5. Output gtsummary tables as RTF, HTML, Word, or LaTeX
6. Compose multi-section tables with `tbl_stack()` and `tbl_merge()`

---

## 1. What gtsummary is

`{gtsummary}` is the most widely-used table-making package in pharma R (and in academic medicine generally). Originally a Memorial Sloan Kettering project led by Daniel Sjoberg, it's now a pharmaverse-aligned package with active Roche, GSK, and Novartis contributions.

gtsummary produces **publication-quality** tables from statistical analyses:

- Demographics tables
- Adverse event tables
- Regression result tables
- Survival summary tables

The output is a `gtsummary` object that renders to HTML in the Quarto/R Markdown environment, and exports to Word, RTF, LaTeX, or PDF via the `gt` or `flextable` packages it builds on.

```r
install.packages("gtsummary")
library(gtsummary)
```

gtsummary integrates with cards/cardx in a clean ARD-first way (the topic of this lesson) and also has its own direct API that bypasses ARDs for simpler use cases.

## 2. Two ways to use gtsummary

**Path A — ARD-first** (the Cardinal-future approach):

```
ADaM → cards/cardx ARD → tbl_ard_summary() → gtsummary table
```

The ARD is computed once, then passed to gtsummary for display. Multiple tables can share one ARD.

**Path B — Direct** (gtsummary's original API):

```
ADaM → tbl_summary() → gtsummary table
```

gtsummary computes statistics internally and renders the table in one step. Simpler for one-off tables; less reusable for multiple displays.

Modern pharma practice favors Path A for production CSR tables and Path B for exploratory analyses.

## 3. The ARD-first pattern: `tbl_ard_summary()`

A complete demographics table built from a cards ARD:

```r
library(cards)
library(gtsummary)
library(dplyr)
library(pharmaverseadam)

adsl <- pharmaverseadam::adsl |> filter(SAFFL == "Y")

# Build the ARD
demog_ard <- ard_stack(
  adsl,
  ard_continuous(variables = AGE),
  ard_categorical(variables = c(AGEGR1, SEX, RACE)),
  .by = TRT01A,
  .overall = TRUE,
  .total_n = TRUE,
  .attributes = TRUE
)

# Render as a gtsummary table
demog_tbl <- demog_ard |>
  tbl_ard_summary(
    by = TRT01A,
    type = AGE ~ "continuous2",
    statistic = AGE ~ c("{mean} ({sd})", "{median} ({p25}, {p75})"),
    overall = TRUE
  ) |>
  add_stat_label()

demog_tbl
```

What's happening:

- `tbl_ard_summary()` consumes the ARD; it knows the structure (group columns, statistics)
- `by = TRT01A` says "split into columns by the TRT01A variable"
- `type = AGE ~ "continuous2"` says treat AGE as a two-row continuous variable (mean/SD and median/IQR — the default "continuous2" preset)
- `statistic = AGE ~ c("{mean} ({sd})", "{median} ({p25}, {p75})")` controls the format string
- `overall = TRUE` adds an "Overall" column
- `add_stat_label()` adds the row labels ("Mean (SD)", "Median (Q1, Q3)", etc.)

The output renders as a familiar demographics table with arms as columns, characteristics as rows.

## 4. The direct pattern: `tbl_summary()`

For exploratory or one-off analyses, you can skip the ARD step:

```r
adsl |>
  select(TRT01A, AGE, AGEGR1, SEX, RACE) |>
  tbl_summary(by = TRT01A) |>
  add_overall() |>
  add_p()
```

This produces a similar demographics table directly. Under the hood, gtsummary builds an ARD internally and renders it. The output is functionally identical to the ARD-first path; the difference is reusability and traceability.

For production, prefer the ARD-first path because:

- The ARD is the validated artifact, used for multiple displays
- ARD generation is testable independently from display
- CDISC ARS submission expectations align with explicit ARD generation

For interactive exploration, `tbl_summary()` is much faster to write.

## 5. Adding p-values: `add_p()`

The signature gtsummary convenience: tack on a column of p-values for arm comparisons.

Direct pattern:

```r
adsl |>
  select(TRT01A, AGE, AGEGR1, SEX) |>
  tbl_summary(by = TRT01A) |>
  add_p()
```

gtsummary automatically chooses appropriate tests:

- Continuous variables (AGE) → Kruskal-Wallis test (default)
- Categorical variables (SEX, AGEGR1) → chi-squared or Fisher's exact (based on cell counts)

To override:

```r
adsl |>
  select(TRT01A, AGE, AGEGR1, SEX) |>
  tbl_summary(by = TRT01A) |>
  add_p(test = list(
    AGE ~ "t.test",          # parametric instead of Kruskal-Wallis
    SEX ~ "fisher.test"      # force Fisher's instead of chi-squared
  ))
```

ARD-first equivalent: build the p-value ARD via cardx (Lesson 27) and merge with the descriptive ARD before passing to `tbl_ard_summary()`. Or use `tbl_ard_summary()` followed by `add_p()` to invoke cardx automatically.

## 6. Customizing labels

Variable labels in the table come from the column's `label` attribute (set via `metatools::apply_variable_labels()` from your metacore object — Lesson 13). If your data doesn't have labels set:

```r
adsl |>
  select(TRT01A, AGE, SEX) |>
  tbl_summary(
    by = TRT01A,
    label = list(
      AGE ~ "Age, years",
      SEX ~ "Sex"
    )
  )
```

For ARD-based tables, the label can be set on the data before building the ARD, on the ARD itself, or in the `tbl_ard_summary()` call.

## 7. Formatting numbers

By default, gtsummary follows reasonable defaults:

- Means: 1 decimal place
- Percentages: 1 decimal place
- Counts: integer
- p-values: 3 decimal places, "<0.001" for very small values

To override, use `style_*()` helpers:

```r
adsl |>
  tbl_summary(
    by = TRT01A,
    statistic = list(
      AGE ~ "{mean} ({sd})",          # the format template
      all_categorical() ~ "{n} ({p}%)"
    ),
    digits = list(
      AGE ~ c(2, 2),                  # mean: 2 decimals, sd: 2 decimals
      all_categorical() ~ c(0, 1)     # n: 0 decimals, p: 1 decimal
    )
  )
```

The `{var}` syntax inside `statistic` refers to computed stats: `{mean}`, `{sd}`, `{median}`, `{p25}`, `{p75}`, `{min}`, `{max}`, `{n}`, `{N}`, `{p}`. You can mix and match.

## 8. The `modify_*()` family

To tweak the rendered table further:

```r
demog_tbl |>
  modify_header(label ~ "**Characteristic**") |>
  modify_caption("**Table 14.1.1 — Demographic and Baseline Characteristics**") |>
  modify_footnote(
    all_stat_cols() ~ "n (%); Mean (SD); Median (Q1, Q3)"
  )
```

- `modify_header()` changes column headers (e.g., the row-label column header)
- `modify_caption()` adds a title above the table
- `modify_footnote()` adds footnotes

Markdown formatting (`**bold**`, `*italic*`) is supported in headers, captions, and footnotes. For RTF / Word output, you can use HTML-ish formatting.

## 9. Output: HTML, Word, RTF, LaTeX

gtsummary tables render natively to HTML in Quarto/R Markdown. To export to other formats:

```r
# Render as an HTML widget
demog_tbl

# Save as a Word document
demog_tbl |>
  as_flex_table() |>
  flextable::save_as_docx(path = "demog_table.docx")

# Save as RTF
demog_tbl |>
  as_flex_table() |>
  flextable::save_as_rtf(path = "demog_table.rtf")

# Save as LaTeX (for PDF)
demog_tbl |>
  as_kable_extra() |>
  cat(file = "demog_table.tex")
```

For pharma CSR delivery, **RTF** is typically required (sponsor SOPs, regulator review software). `{flextable}` is the most reliable engine for high-fidelity RTF output. For maximum control, `{r2rtf}` (Module 7) is also widely used; the legacy stack route goes from `rtables` → r2rtf, while gtsummary→flextable→RTF is the Cardinal-future route.

## 10. Composing tables: `tbl_stack()` and `tbl_merge()`

Multi-section tables are common in clinical reports. Two compositional patterns:

**Vertical stacking** (e.g., demographics on top, baseline disease characteristics below):

```r
tbl_demog <- adsl |> tbl_summary(by = TRT01A, include = c(AGE, AGEGR1, SEX))
tbl_disease <- adsl |> tbl_summary(by = TRT01A, include = c(BMIBL, RACE))

stacked <- tbl_stack(
  list(tbl_demog, tbl_disease),
  group_header = c("Demographics", "Disease Characteristics")
)
```

**Horizontal merging** (e.g., demographics columns alongside efficacy columns):

```r
tbl_demog <- adsl |> tbl_summary(by = TRT01A, include = c(AGE))
tbl_eff <- ade_data |> tbl_summary(by = TRT01A, include = c(EFF_OUTCOME))

merged <- tbl_merge(
  list(tbl_demog, tbl_eff),
  tab_spanner = c("**Demographics**", "**Efficacy**")
)
```

`tab_spanner` adds the spanner rows visible above the column groups. The result is a single table object that exports as one.

## 11. Continuous summary types

gtsummary has presets for continuous variables:

| Type | Statistics displayed |
|---|---|
| `"continuous"` | Single row: median (Q1, Q3) |
| `"continuous2"` | Two rows: typically mean (SD) and median (IQR) |
| `"categorical"` | n (%) per level |
| `"dichotomous"` | n (%) for one level (e.g., "Y") only |

The default for numeric is `"continuous"`. For demographics tables, you typically want `"continuous2"`:

```r
tbl_summary(
  data = adsl,
  by = TRT01A,
  include = c(AGE, AGEGR1, SEX),
  type = list(AGE ~ "continuous2"),
  statistic = list(AGE ~ c("{mean} ({sd})", "{median} ({p25}, {p75})"))
)
```

The `statistic` list now has two format strings for AGE — one per row of the `"continuous2"` layout.

## 12. Themes and presets

For sponsor-consistent table styling, gtsummary supports themes:

```r
# Use the compact theme (smaller font, less padding) globally
theme_gtsummary_compact()

# Use the journal-style theme
theme_gtsummary_journal("jama")

# Reset to default
reset_gtsummary_theme()
```

For sponsor-specific styling, you can define a custom theme as a function:

```r
my_theme <- function() {
  list(
    "tbl_summary-arg:percent_fun" = function(x) sprintf("%.1f", x * 100),
    "style_number-arg:digits" = 2,
    # ... more configuration
  )
}

set_gtsummary_theme(my_theme())
```

The full theme system has dozens of configurable options. For deep customization, see `?set_gtsummary_theme`.

## 13. Hierarchical summaries (AE tables)

For AE tables with SOC-PT hierarchy, gtsummary provides `tbl_hierarchical()`:

```r
adae |>
  filter(TRTEMFL == "Y") |>
  tbl_hierarchical(
    variables = c(AEBODSYS, AEDECOD),
    by = TRTA,
    denominator = adsl,
    include = c(AEBODSYS, AEDECOD)
  )
```

The output is the canonical "AE table by System Organ Class and Preferred Term" with proper indentation and subject-level denominators. Internally it uses `ard_hierarchical()` (Lesson 26) and renders the result.

## 14. The composable API

A core gtsummary design principle: tables are **composable**. You build a basic table, then chain modifications:

```r
my_table <- adsl |>
  tbl_summary(by = TRT01A, include = c(AGE, SEX, AGEGR1)) |>
  add_overall() |>
  add_p() |>
  add_stat_label() |>
  bold_labels() |>
  italicize_levels() |>
  modify_header(label ~ "**Characteristic**") |>
  modify_caption("Demographic Summary")
```

Each function takes a `tbl_*` object as input, returns a modified one. The chain is read top-to-bottom. For unfamiliar functions, `?function_name` is your friend; gtsummary's docs are excellent.

## 15. Putting it together: a CSR-ready demographics table

```r
library(cards)
library(gtsummary)
library(pharmaverseadam)
library(dplyr)

# Theme: smaller / compact for CSR style
theme_gtsummary_compact()

adsl <- pharmaverseadam::adsl |> filter(SAFFL == "Y")

# Build the ARD
demog_ard <- ard_stack(
  adsl,
  ard_continuous(
    variables = AGE,
    statistic = ~ continuous_summary_fns(c("N", "mean", "sd", "median", "p25", "p75", "min", "max"))
  ),
  ard_categorical(variables = c(AGEGR1, SEX, RACE)),
  .by = TRT01A,
  .overall = TRUE,
  .total_n = TRUE,
  .attributes = TRUE
)

# Render as a gtsummary table
demog_tbl <- demog_ard |>
  tbl_ard_summary(
    by = TRT01A,
    type = AGE ~ "continuous2",
    statistic = AGE ~ c("{mean} ({sd})", "{median} ({p25}, {p75})"),
    overall = TRUE
  ) |>
  add_stat_label() |>
  modify_header(label ~ "**Characteristic**") |>
  modify_caption("**Table 14.1.1: Demographic and Baseline Characteristics — Safety Population**") |>
  modify_footnote(
    all_stat_cols() ~ "Continuous: Mean (SD); Median (Q1, Q3). Categorical: n (%)."
  )

# Export to RTF for CSR delivery
demog_tbl |>
  as_flex_table() |>
  flextable::save_as_rtf(path = "outputs/table_14_1_1.rtf")
```

This script produces a CSR-ready table from ADSL in about 40 lines of clear code. The same ARD can also feed slide decks, Shiny apps, or summary documents — separation of concerns paying off.

## 16. Validation

For submission-quality gtsummary tables:

1. **Validate the ARD** (Lesson 26): dual programming, `diffdf` comparison
2. **Spot-check the display**: extract specific values from the ARD and verify they appear correctly in the rendered table
3. **Layout review**: have a second person review the rendered RTF against the SAP table shell

Layout discrepancies (wrong column order, missing footnotes) typically come up during layout review. The numbers themselves are validated at the ARD layer.

## 17. Key takeaways

- `{gtsummary}` is the display layer for the Cardinal-future TLG stack
- Two patterns: ARD-first via `tbl_ard_summary()` (production) and direct via `tbl_summary()` (exploratory)
- `add_p()` adds inferential statistics; tests chosen automatically by variable type
- `modify_*()` family controls labels, headers, captions, footnotes
- Outputs render to HTML natively; export to Word/RTF/LaTeX via flextable or gt
- `tbl_stack()` and `tbl_merge()` compose multi-section tables
- Hierarchical AE tables via `tbl_hierarchical()`
- Themes (`theme_gtsummary_compact()`, journal styles) provide consistent styling

## 18. What's next

Lesson 29 — **`{gtsummary}` Part 2** — focuses on **clinical reporting patterns**: building the canonical CSR tables (demographics, AE, lab, survival) end-to-end with worked code. We'll cover patterns specific to pharma — handling missing data, footnoting test methodology, applying sponsor templates.

After gtsummary: Lesson 30 covers `{cardinal}` — the harmonized TLG catalog initiative.

---

## Self-check questions

1. What's the difference between `tbl_summary()` and `tbl_ard_summary()`?
2. Why does the ARD-first pattern preferred for production CSR tables?
3. What does `type = AGE ~ "continuous2"` change about the displayed table?
4. Translate to gtsummary: "Demographics by ARM with mean (SD) for AGE, n (%) for SEX, p-values."
5. How would you save a gtsummary table as an RTF file?
6. What's the role of `add_stat_label()` and `bold_labels()`?

## Glossary

- **`tbl_summary()`** — Main gtsummary function; produces a summary table directly from data
- **`tbl_ard_summary()`** — gtsummary function consuming an ARD; the Cardinal-future preferred pattern
- **`add_p()`** — Add p-value column; automatically selects appropriate tests
- **`add_overall()`** — Add an "Overall" column with all-subjects statistics
- **`add_stat_label()`** — Add stat-name labels (Mean, Median, etc.) as a column
- **`modify_header()` / `modify_caption()` / `modify_footnote()`** — Customize table chrome
- **`continuous2`** — Two-row continuous summary preset
- **`tbl_stack()` / `tbl_merge()`** — Compose multi-section tables vertically / horizontally
- **`tbl_hierarchical()`** — AE-style hierarchical table builder
- **`{flextable}`** — Display engine for Word/RTF export
- **`as_flex_table()`** — Convert gtsummary table to flextable for export
- **`theme_gtsummary_compact()`** — Compact styling preset
