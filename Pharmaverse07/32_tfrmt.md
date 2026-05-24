# Lesson 32 — `{tfrmt}`: Display Metadata for ARDs

**Module**: 6 — TLG: the Cardinal-future stack
**Estimated length**: ~20 min spoken
**Prerequisites**: Lessons 25–31

---

## Learning objectives

By the end of this lesson, you will be able to:

1. Explain what tfrmt adds beyond gtsummary: a metadata-driven display layer for ARDs
2. Use `shuffle_card()`, `prep_big_n()`, `prep_combine_vars()`, `prep_label()` to tidy ARDs for tfrmt
3. Build a `tfrmt` object that specifies row groups, column groups, value formats, and labels
4. Generate mock tables before data is available — testing display logic against table shells
5. Apply tfrmt for complex multi-dimensional layouts (visit × arm × statistic) where gtsummary falls short
6. Recognize tfrmt's role in CDISC ARS-aligned reporting workflows

---

## 1. Why tfrmt exists

gtsummary works well for standard table types — demographics, AE summaries, simple shift tables. It hits limits when:

- **Multi-dimensional column structure**: Visit → Arm → Statistic, three levels deep
- **Mock table workflow**: needing to design and review the table layout before any data exists
- **Highly bespoke layouts**: sponsor templates that don't fit any preset
- **Pure separation of layout from data**: metadata describes the display; data fills it in

`{tfrmt}`, developed by GSK and contributed to pharmaverse in 2022, addresses these by providing a **metadata-first display framework**. You describe the table structure as data; tfrmt renders it from any ARD that matches the description.

The split:

```
ARD (data)
   ↓
tfrmt object (metadata describing layout)
   ↓
Rendered table
```

This pure separation supports the "mock then build" workflow that pharma SOPs often require: design the table shell first, get sponsor sign-off on the layout, then plug in the data once it's available.

## 2. Installation

```r
install.packages("tfrmt")
library(tfrmt)
```

tfrmt depends on `{gt}` (and optionally `{flextable}`) for the actual rendering. Output formats: HTML, Word (via gt), RTF (via flextable conversion), PDF (via LaTeX).

## 3. The conceptual pieces of a tfrmt

A `tfrmt` object describes:

| Component | What it specifies |
|---|---|
| **`group`** | Row grouping variables (e.g., "AGE category") |
| **`label`** | The row-label column (the leftmost column) |
| **`column`** | Column variables (e.g., treatment arm) |
| **`param`** | The stat-name variable in the ARD |
| **`value`** | The stat-value column in the ARD |
| **`big_n`** | The Big-N row for column headers |
| **`body_plan`** | How statistics map to cell formats |
| **`row_grp_plan`** | Row group ordering, indentation, spacing |
| **`col_plan`** | Column ordering and spanning labels |
| **`page_plan`** | Pagination for long tables |
| **`footnote_plan`** | Footnotes with positioning |
| **`title`** | Table title |

That's a lot of pieces. The good news: most are optional with sensible defaults. The minimum tfrmt object specifies a few core components and renders.

## 4. Preparing an ARD for tfrmt: the `prep_*` and `shuffle_*` helpers

tfrmt expects ARDs in a slightly different shape than cards' native output. Specifically:

- Group columns are pivoted to actual columns (not in `group1`/`group2`)
- Stat names appear as a column named `stat_name`
- Stat values are in `stat`
- A row-label column ("label") is constructed from variable name and level

cards provides helpers that reshape:

```r
library(cards)
library(tfrmt)
library(forcats)
library(pharmaverseadam)

adsl <- pharmaverseadam::adsl |> dplyr::filter(SAFFL == "Y")

# Build ARD
ard <- ard_stack(
  adsl,
  ard_continuous(
    variables = AGE,
    statistic = ~ continuous_summary_fns(c("N", "mean", "sd", "min", "max"))
  ),
  ard_categorical(variables = c(AGEGR1, SEX, RACE)),
  .by = ACTARM,
  .overall = TRUE,
  .total_n = TRUE
)

# Reshape for tfrmt
ard_for_tfrmt <- ard |>
  shuffle_card(fill_overall = "Total") |>     # pivot group columns
  prep_big_n(vars = "ACTARM") |>              # convert Big-N rows to a separate row type
  prep_combine_vars(vars = c("AGE", "AGEGR1", "SEX", "RACE")) |>   # consolidate variable names
  prep_label()                                # build row labels from variable_level and stat_label
```

The pipeline:

1. **`shuffle_card()`**: pivots group columns (`group1`, `group1_level`) to actual columns (`ACTARM` as a column). `fill_overall = "Total"` names the all-subjects column "Total".
2. **`prep_big_n()`**: identifies Big-N rows (the per-arm subject counts) and marks them for use as column header subtitles.
3. **`prep_combine_vars()`**: combines multiple variable-name columns into a single `stat_variable` column. Used when ARDs have variables grouped (continuous: AGE; categorical: AGEGR1, SEX, RACE) and you want them in one column.
4. **`prep_label()`**: builds the leftmost row-label column by combining variable name and level/stat label appropriately.

After these four `prep_*` calls, your ARD is ready for tfrmt's `print_to_gt()` or `print_mock_gt()`.

## 5. A minimal tfrmt object

```r
demog_format <- tfrmt(
  group = "stat_variable",       # row grouping (one group per variable)
  label = "label",               # the row-label column
  column = "ACTARM",             # treatment arm as columns
  param = "stat_name",           # statistic name column
  value = "stat",                # the actual value column
  big_n = big_n_structure("..ard_total_n..", n_frmt = frmt("N = xx")),
  body_plan = body_plan(
    frmt_structure(
      group_val = ".default", label_val = ".default",
      frmt_combine("{N}", N = frmt("xx"))
    ),
    frmt_structure(
      group_val = ".default", label_val = "Mean (SD)",
      frmt_combine("{mean} ({sd})",
                   mean = frmt("xx.x"),
                   sd = frmt("xx.xx"))
    ),
    # ... more rows ...
  ),
  title = "Demographics Table"
)
```

`tfrmt()` builds the metadata object. Inside, `body_plan` specifies how statistics map to displayed cells:

- For variables matching pattern `.default` and label matching `Mean (SD)`, format as `"{mean} ({sd})"` with mean displayed as `xx.x` and sd as `xx.xx`

The `frmt()` and `frmt_combine()` functions are tfrmt's format-string mini-language. `"xx.x"` means "one decimal"; `"xx.xx"` means "two decimals"; `"xx"` means integer.

This declarative format is more verbose than a typical R format string but is unambiguous: a reviewer can read the body_plan and know exactly how each cell will display.

## 6. Rendering to a table

Once you have ARD and tfrmt:

```r
# Render as gt table
demog_format |>
  print_to_gt(ard_for_tfrmt)

# Render as mock (no actual data)
demog_format |>
  print_mock_gt()
```

`print_to_gt()` produces the actual table with data. `print_mock_gt()` produces a mock — same structure, placeholder values (`xx` or `xx.x` literals). The mock is the artifact used for sponsor review before data is available.

## 7. The mock workflow

The "mock first" workflow is signature pharma:

```
1. Statistician designs the table structure (rows, columns, statistics)
2. Programmer builds a tfrmt object encoding the design
3. Programmer renders print_mock_gt() — produces an empty-shell version
4. Sponsor reviews and approves the layout
5. Programmer builds the ARD via cards/cardx
6. Programmer renders print_to_gt(ard) — same tfrmt, now filled with real values
```

The tfrmt object is the single source of truth for layout. Layout changes happen in one place. Data changes don't affect layout. Mock and real are guaranteed identical in structure.

This is a major advantage for SOP-heavy environments. In a gtsummary workflow, the layout is intermingled with the data; you can't easily produce a faithful mock without dummy data.

## 8. Advanced: column structure

For tables with nested column groups (e.g., Visit → Arm), tfrmt's `col_plan`:

```r
adlb_format <- tfrmt(
  group = "PARAMCD",
  label = "stat_label",
  column = c("AVISIT", "TRTA"),     # two-level column structure
  param = "stat_name",
  value = "stat",
  col_plan = col_plan(
    "Baseline" > c("Placebo", "Xanomeline High", "Xanomeline Low"),
    "Week 24"  > c("Placebo", "Xanomeline High", "Xanomeline Low"),
    "Week 52"  > c("Placebo", "Xanomeline High", "Xanomeline Low")
  ),
  body_plan = body_plan(
    frmt_structure(
      group_val = ".default",
      label_val = "N",
      frmt("xx")
    ),
    frmt_structure(
      group_val = ".default",
      label_val = "Mean (SD)",
      frmt_combine("{mean} ({sd})",
                   mean = frmt("xx.x"),
                   sd = frmt("xx.xx"))
    )
  )
)
```

The `col_plan` uses the `>` operator: `"Visit" > c("Arm1", "Arm2", ...)` says "under the Visit spanner, show columns for Arm1, Arm2, etc." Multiple `>` expressions stack to create the column structure.

For a 3-visit × 3-arm × 2-stat lab table, this is the cleanest way to express the layout. gtsummary's `tbl_merge()` can do similar but the syntax becomes unwieldy.

## 9. Row groups, indentation, spacing

For tables with grouped rows (e.g., SOC headers with PT sub-rows):

```r
ae_format <- tfrmt(
  group = "AEBODSYS",                   # row groups
  label = "AEDECOD",                    # row labels within groups
  column = "ARM",
  param = "stat_name",
  value = "stat",
  row_grp_plan = row_grp_plan(
    label_loc = element_row_grp_loc(
      location = "indented",            # SOC label indented to the side
      indent = "    "
    ),
    row_grp_structure(
      group_val = ".default",
      element_block(post_space = " ")   # blank line after each SOC group
    )
  ),
  body_plan = body_plan(
    frmt_structure(
      group_val = ".default",
      label_val = ".default",
      frmt_combine("{n} ({p}%)",
                   n = frmt("xx"),
                   p = frmt("xx.x"))
    )
  )
)
```

The `row_grp_plan` controls:

- **Where SOC labels appear**: "indented" (on a separate row, indented), "spanning" (header across the row), or "column" (in a separate column)
- **Spacing between groups**: `post_space` adds blank rows for visual separation
- **Indentation**: how PT sub-rows are indented

For complex SOC × PT tables with mixed severities, this is essential.

## 10. Footnotes

tfrmt supports targeted footnotes attached to specific cells:

```r
footnote_plan(
  footnote_structure(
    "Subjects with multiple events of the same term counted once.",
    column_val = ".default"
  ),
  footnote_structure(
    "Includes events from screening through end-of-study follow-up.",
    label_val = "Any AE"
  )
)
```

The footnote_structure says: attach this footnote to cells matching the column/label criteria. tfrmt automatically inserts footnote markers in the rendered output and lists the notes below.

## 11. The full pipeline: ARD → tfrmt → table

Pulling everything together for a demographics table:

```r
library(cards)
library(tfrmt)
library(forcats)
library(dplyr)
library(pharmaverseadam)

adsl <- pharmaverseadam::adsl |> filter(SAFFL == "Y")

# Build ARD
ard <- ard_stack(
  adsl,
  ard_continuous(
    variables = AGE,
    statistic = ~ continuous_summary_fns(c("N", "mean", "sd", "min", "max"))
  ),
  ard_categorical(variables = c(AGEGR1, SEX, RACE)),
  .by = ACTARM,
  .overall = TRUE,
  .total_n = TRUE
)

# Reshape for tfrmt
ard_tbl <- ard |>
  shuffle_card(fill_overall = "Total") |>
  prep_big_n(vars = "ACTARM") |>
  prep_combine_vars(vars = c("AGE", "AGEGR1", "SEX", "RACE")) |>
  prep_label() |>
  group_by(ACTARM, stat_variable)        # final grouping

# Build tfrmt
demog_format <- tfrmt(
  group = "stat_variable",
  label = "label",
  column = "ACTARM",
  param = "stat_name",
  value = "stat",
  big_n = big_n_structure("..ard_total_n..", n_frmt = frmt("(N = xx)")),
  body_plan = body_plan(
    frmt_structure(
      group_val = "AGE",
      label_val = "N",
      frmt("xx")
    ),
    frmt_structure(
      group_val = "AGE",
      label_val = "Mean (SD)",
      frmt_combine("{mean} ({sd})",
                   mean = frmt("xx.x"),
                   sd = frmt("xx.xx"))
    ),
    frmt_structure(
      group_val = ".default",
      label_val = ".default",
      frmt_combine("{n} ({p})",
                   n = frmt("xx"),
                   p = frmt("(xx.x%)"))
    )
  ),
  title = "Table 14.2.1: Demographic Characteristics"
)

# Render
table_gt <- demog_format |>
  print_to_gt(ard_tbl)

# Export
table_gt |>
  gt::gtsave("outputs/t_14_2_1.rtf")     # or .docx, .html, .pdf
```

The tfrmt object is reusable: pass any ARD with matching structure, get the same-formatted table. This is the basis for mocks and version compatibility.

## 12. Where tfrmt shines vs. gtsummary

A practical decision rule:

**Use gtsummary when:**

- The table is reasonably standard (demographics, AE summary, simple shift)
- You're moving fast and don't need a mock first
- Layout customization is mostly cosmetic (footnotes, headers)

**Use tfrmt when:**

- The table has multi-level column structure (Visit × Arm × Statistic)
- Sponsor SOP requires mock-then-render workflow
- You want a clean separation of layout metadata from data
- The table is bespoke enough that gtsummary's API feels stretched

In practice, many teams use both. gtsummary for ~70% of tables, tfrmt for the remaining ~30% (typically complex lab and efficacy tables). cardinal templates cover both styles.

## 13. tfrmt and CDISC ARS

A future-looking note: CDISC ARS expects machine-readable display metadata alongside the ARD. tfrmt objects are precisely that — display metadata in a structured form. As ARS adoption increases, tfrmt's role may expand because its metadata can be serialized for ARS submission alongside the corresponding ARD.

Watch CDISC ARS releases (2026–2027) for how this integration evolves. The tfrmt team is actively engaged with CDISC.

## 14. Maintenance and team

`{tfrmt}` is maintained primarily by GSK (Christina Fillmore, Ellis Hughes, Thomas Neitmann) with cross-pharma contributions. The package has been stable since ~2023 with regular minor releases adding features and polish.

Active development:

- Tighter integration with cards (better `shuffle_card()` + `prep_*` helpers)
- Improved Word/RTF output via flextable conversion
- More built-in `body_plan` presets for common cell formats
- CDISC ARS alignment

## 15. Comparing the layout abstractions

| Tool | Layout abstraction | Strengths |
|---|---|---|
| gtsummary | Function composition (`add_*`, `modify_*`) | Quick, fluent, covers standard cases |
| tfrmt | Declarative metadata object | Mock workflow, complex columns, full layout separation |
| rtables (Module 7) | Imperative layout DSL (`analyze`, `split_*`) | Maximum flexibility, NEST-stack alignment |

All three coexist. Cardinal templates use gtsummary and tfrmt; NEST templates use rtables. The future TLG stack favors gtsummary + tfrmt; the legacy stack favors rtables + tern.

## 16. Putting it together: a mock + render workflow

A realistic project script demonstrating the mock workflow:

```r
# Step 1: Design table — build tfrmt with no data yet
demog_format <- tfrmt(
  # ... layout definition ...
  title = "Table 14.2.1: Demographic Characteristics"
)

# Step 2: Render mock for sponsor review
demog_format |>
  print_mock_gt() |>
  gt::gtsave("mocks/t_14_2_1_mock.html")

# [Sponsor reviews and approves the mock]

# Step 3: Build the ARD once data is available
adsl <- haven::read_xpt("data/adsl.xpt")

ard <- ard_stack(adsl, ...) |>
  shuffle_card() |> prep_big_n(...) |> prep_combine_vars(...) |> prep_label()

# Step 4: Render the actual table with the same tfrmt
demog_format |>
  print_to_gt(ard) |>
  gt::gtsave("outputs/t_14_2_1.rtf")
```

The mock and the real table are guaranteed to match in layout because they share the tfrmt object. Layout review happens once; data changes don't break the layout.

## 17. Key takeaways

- `{tfrmt}` is a metadata-driven display layer for ARDs — complementary to gtsummary
- Built around a `tfrmt()` object specifying group, label, column, param, value, and format plans
- `shuffle_card()`, `prep_big_n()`, `prep_combine_vars()`, `prep_label()` reshape ARDs for tfrmt
- Mock-then-render workflow: design layout with `print_mock_gt()` first, render with `print_to_gt(ard)` later
- Excels at multi-dimensional column structures, complex row groupings, full layout separation
- Coexists with gtsummary in modern pharma reporting; cardinal templates use both
- Strategic role in CDISC ARS-aligned workflows for serializable display metadata

## 18. What's next

Module 6 is complete. You now know the entire Cardinal-future TLG stack: cards + cardx for ARDs, gtsummary for standard displays, tfrmt for complex layouts, cardinal templates as starting points.

**Module 7** covers the **legacy TLG stack**: rtables, tern, r2rtf, Tplyr, tidytlg. These packages dominate production today and remain essential for sponsors invested in NEST or similar workflows. Even if your future projects use Cardinal-future, understanding the legacy stack lets you collaborate with teams using it and maintain existing code.

After Module 7, Module 8 covers Shiny / teal, Module 9 covers submission packaging (xportr, datasetjson), Module 10 covers traceability (logrx, diffdf), and we finish with a capstone study (Module 11).

---

## Self-check questions

1. What does tfrmt provide that gtsummary doesn't?
2. What's the role of `shuffle_card()` in the tfrmt pipeline?
3. Explain the "mock first" workflow and why it's valuable in pharma.
4. What does `frmt_combine("{n} ({p})", n = frmt("xx"), p = frmt("(xx.x%)"))` do?
5. How does tfrmt support CDISC ARS-aligned workflows?
6. Translate to tfrmt-conceptual: "Render a table with rows grouped by AESOC, indented PT labels, columns of Placebo and Active, cell format `n (p%)`."

## Glossary

- **`tfrmt`** — A metadata-driven display layer for ARDs
- **`shuffle_card()`** — Pivot group columns to actual columns in an ARD
- **`prep_big_n()`** — Extract Big-N values for column headers
- **`prep_combine_vars()`** — Consolidate multiple variables into a single variable column
- **`prep_label()`** — Build the row-label column from variable name and level
- **`body_plan`** — Specifies cell-level formatting per group/label combination
- **`row_grp_plan`** — Controls row group display: indentation, spacing, label location
- **`col_plan`** — Defines column ordering and spanner labels
- **`big_n_structure()`** — Maps the Big-N rows to column header N counts
- **`frmt()` / `frmt_combine()`** — tfrmt's format-string mini-language
- **`print_to_gt()`** — Render tfrmt + ARD as a gt table
- **`print_mock_gt()`** — Render tfrmt with placeholder values (no real data)
- **Mock workflow** — Sponsor-review process: design layout first, plug data in later
