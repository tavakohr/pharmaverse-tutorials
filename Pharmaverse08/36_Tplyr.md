# Lesson 36 — `{Tplyr}`: SAS-Style Table Construction

**Module**: 7 — TLG: the legacy/Roche stack
**Estimated length**: ~20 min spoken
**Prerequisites**: Lessons 33-35

---

## Learning objectives

By the end of this lesson, you will be able to:

1. Explain Tplyr's design — a grammar of table summary, by analogy to dplyr's grammar of data manipulation
2. Build a table with `tplyr_table()` + `add_layer()` + `build()`
3. Use `group_desc()` for continuous summaries and `group_count()` for categorical
4. Customize statistics with `set_format_strings()`, `set_stats()`, and `set_*` family
5. Apply Tplyr's SAS-matching rounding (`round_half_up`) to match SAS output exactly
6. Recognize Tplyr's positioning as the SAS-friendly transition path

---

## 1. Tplyr's design philosophy

Where rtables thinks in "splits and analyses", and gtsummary thinks in "composable table functions", **`{Tplyr}` thinks in "layers"** — each layer is one analysis (e.g., "summary of AGE by treatment") that gets stacked into the final table.

Atorus Research (the team behind Tplyr) explicitly designed it to mirror how SAS programmers conceptualize tables. From the Tplyr docs:

> "In the same way that dplyr is a grammar of data manipulation, Tplyr aims to be a grammar of data summary. The goal of Tplyr is to allow you to program a summary table like you see it on the page, by breaking a larger problem into smaller 'layers', and combining them together like you see on the page."

The mental model: each row group in the final table is one Tplyr layer. Building the table = building the layers in sequence.

For SAS programmers used to thinking "one PROC FREQ for sex, one PROC MEANS for age, one PROC FREQ for race, then assemble" — Tplyr maps to that workflow directly.

## 2. Origin and adoption

Tplyr was developed by Mike Stackhouse at Atorus Research, with major contributions from Eli Miller and Nathan Kosiba. Open-sourced ~2020, current stable release 1.x.

Adoption pattern:

- **Strongest at Atorus-aligned sponsors and CROs** — Atorus is a CRO with significant pharma client base
- **Significant adoption at sponsors transitioning from SAS to R** — Tplyr's grammar maps cleanly to SAS workflows
- **Often used in combination with r2rtf** — Tplyr computes the table, r2rtf writes the RTF
- **Less common at NEST-aligned sponsors** (Roche, Novartis) who default to rtables/tern

The package ships with an extensive user-acceptance testing (UAT) document — Atorus established formal requirements, wrote test cases, and independently executed them. This validation work is part of why Tplyr is favored in regulated environments.

## 3. Installation

```r
install.packages("Tplyr")
library(Tplyr)
library(dplyr)
```

Tplyr ships with `tplyr_adsl` and `tplyr_adae` test datasets — PHUSE Test Data Factory variants of the CDISC pilot data.

## 4. The basic pattern

A minimum-viable Tplyr table:

```r
table <- tplyr_table(tplyr_adsl, TRT01P, where = SAFFL == "Y") |>
  add_layer(
    group_desc(AGE, by = "Age (years)")
  ) |>
  add_layer(
    group_count(AGEGR1, by = "Age Categories")
  )

result <- build(table)
result
```

Three pieces:

- **`tplyr_table(data, treat_var, where = ...)`**: defines the population. `data` is the ADaM dataset; `treat_var` is the column variable (e.g., TRT01P); `where` is an optional filter.
- **`add_layer(...)`**: adds an analysis layer. Each layer becomes one row group in the output.
- **`build(table)`**: executes all the layers and produces the final table as a tibble.

The result is a tibble in "display-ready" wide format — rows are characteristics, columns are arms.

## 5. The two main layer types

| Layer | Function | What it does |
|---|---|---|
| Descriptive (continuous) | `group_desc()` | Summary stats: N, Mean (SD), Median, Range |
| Count (categorical) | `group_count()` | n (%) per level of a categorical variable |

There's also `group_shift()` for shift tables (baseline category × on-treatment category) and `add_total_layer()` for a "Total" row, but `group_desc()` and `group_count()` cover the bulk of CSR work.

## 6. Customizing statistics

By default, `group_desc()` produces a fixed set of stats. To customize:

```r
table <- tplyr_table(tplyr_adsl, TRT01P, where = SAFFL == "Y") |>
  add_layer(
    group_desc(AGE) |>
      set_format_strings(
        "n" = f_str("xx", n),
        "Mean (SD)" = f_str("xx.x (xx.xx)", mean, sd),
        "Median (Q1, Q3)" = f_str("xx.x (xx.x, xx.x)", median, q1, q3),
        "Min, Max" = f_str("xx, xx", min, max)
      )
  )
```

`set_format_strings()` controls which stats appear and how they're formatted. `f_str()` defines a single format: `f_str("xx.x (xx.xx)", mean, sd)` produces a cell like "75.2 (8.59)" combining mean and sd.

This is more explicit than gtsummary's `statistic = "{mean} ({sd})"` shortcut, but gives finer control: you specify exactly which stats to compute and how to display them.

## 7. Customizing count layers

For `group_count()`:

```r
table <- tplyr_table(tplyr_adae, TRT01P, where = SAFFL == "Y") |>
  add_layer(
    group_count(AESOC) |>
      set_format_strings(
        f_str("xx (xx.x%)", n, pct)
      ) |>
      set_distinct_by(USUBJID)        # count each subject once per SOC
  )
```

`set_distinct_by(USUBJID)` makes the count subject-aware — equivalent to tern's `count_occurrences()`. Without it, you'd count events rather than subjects.

For nested SOC × PT counts:

```r
add_layer(
  group_count(c(AEBODSYS, AEDECOD)) |>
    set_format_strings(f_str("xx (xx.x%)", n, pct)) |>
    set_distinct_by(USUBJID)
)
```

A vector of variables in `group_count()` creates a nested counting layer — SOC totals followed by PT subtotals within each SOC.

## 8. The SAS-matching rounding

A signature Tplyr feature: rounding that matches SAS by default.

SAS uses banker's rounding (round-half-to-even) in some contexts and round-half-up in others. R's `round()` uses banker's rounding (round-half-to-even). This creates subtle differences in CSR tables that drive validation teams crazy.

Tplyr uses `round_half_up()` (round-half-away-from-zero) consistently, matching SAS's `round()` function. Result: numbers in Tplyr-produced tables typically match SAS-produced tables, simplifying validation.

For teams running dual programming in SAS and R, this is huge. The QC programmer's task — comparing two outputs — becomes about validating analytic decisions rather than chasing rounding discrepancies.

You can override with `set_format_strings(f_str(...))` if needed, but the default is SAS-compatible.

## 9. Total layers and overall columns

For "Total" rows or "Overall" columns:

```r
table <- tplyr_table(tplyr_adsl, TRT01P, where = SAFFL == "Y") |>
  add_total_group(group_name = "Total") |>      # adds overall column
  add_layer(
    group_count(SEX) |>
      add_total_row(fmt = f_str("xx", n))       # adds "Total" row at bottom of layer
  )
```

`add_total_group()` adds an "all subjects" column. `add_total_row()` adds a total row within a count layer.

The defaults work for most cases; sponsor-specific table shells may need overrides. Tplyr's docs describe many customizations for total handling.

## 10. Treatment-vs-baseline comparisons

For p-values and statistical tests on layers:

```r
table <- tplyr_table(tplyr_adsl, TRT01P, where = SAFFL == "Y") |>
  add_layer(
    group_desc(AGE) |>
      set_format_strings(
        "Mean (SD)" = f_str("xx.x (xx.xx)", mean, sd)
      ) |>
      add_risk_diff(
        c("Xanomeline Low Dose", "Placebo"),
        c("Xanomeline High Dose", "Placebo")
      )
  )
```

`add_risk_diff()` (or `add_total_row()`, `add_total_group()`, etc.) add inferential rows/columns. Tplyr's stats functions cover the major clinical comparisons.

For a full p-value column across multiple layers, sponsor-specific customization is typical.

## 11. The output: a tibble, ready for RTF

The result of `build(table)` is a standard tibble. From there, you typically chain into `r2rtf` or `flextable`:

```r
result <- build(table)

result |>
  rtf_title("Table 14.2.1", "Demographics") |>
  rtf_colheader(...) |>
  rtf_body(...) |>
  rtf_footnote(...) |>
  rtf_encode() |>
  write_rtf("outputs/t_14_2_1.rtf")
```

This is a Tplyr-strong pattern: Tplyr for the table computation, r2rtf for the RTF output. Many Atorus-aligned production pipelines look exactly like this.

## 12. The complete example: a demographics table

Putting it all together:

```r
library(Tplyr)
library(dplyr)
library(r2rtf)

# Setup
adsl <- tplyr_adsl

# Build the Tplyr table
table <- tplyr_table(adsl, TRT01P, where = SAFFL == "Y") |>
  add_total_group(group_name = "Total") |>
  # Continuous: AGE
  add_layer(
    group_desc(AGE, by = "Age (years)") |>
      set_format_strings(
        "n" = f_str("xx", n),
        "Mean (SD)" = f_str("xx.x (xx.xx)", mean, sd),
        "Median (Q1, Q3)" = f_str("xx.x (xx.x, xx.x)",
                                    median, q1, q3),
        "Min, Max" = f_str("xx, xx", min, max)
      )
  ) |>
  # Categorical: AGEGR1
  add_layer(
    group_count(AGEGR1, by = "Age Categories") |>
      set_format_strings(f_str("xx (xx.x%)", n, pct)) |>
      set_distinct_by(USUBJID)
  ) |>
  # Categorical: SEX
  add_layer(
    group_count(SEX, by = "Sex") |>
      set_format_strings(f_str("xx (xx.x%)", n, pct)) |>
      set_distinct_by(USUBJID)
  ) |>
  # Categorical: RACE
  add_layer(
    group_count(RACE, by = "Race") |>
      set_format_strings(f_str("xx (xx.x%)", n, pct)) |>
      set_distinct_by(USUBJID)
  )

# Compile
result <- build(table)

# Output to RTF
result |>
  rtf_title("Table 14.2.1: Demographic and Baseline Characteristics",
            subtitle = "Safety Population") |>
  rtf_colheader(
    colheader = "Characteristic | Placebo (N=86) | Xanomeline Low (N=84) | Xanomeline High (N=84) | Total (N=254)",
    col_rel_width = c(3, 2, 2, 2, 2),
    text_justification = c("l", "c", "c", "c", "c")
  ) |>
  rtf_body(
    col_rel_width = c(3, 2, 2, 2, 2),
    text_justification = c("l", "c", "c", "c", "c"),
    border_first = "single",
    border_last = "single"
  ) |>
  rtf_footnote(
    "Continuous: Mean (SD); Median (Q1, Q3); Min, Max. Categorical: n (%).\nPercentages based on number of subjects in the safety population."
  ) |>
  rtf_source("Source: ADSL") |>
  rtf_encode() |>
  write_rtf("outputs/t_14_2_1.rtf")
```

The whole script is ~50 lines and produces a CSR-grade RTF. The Tplyr code is verbose but readable: each layer is one analysis, statistics and formats are explicit.

## 13. Tplyr vs the alternatives

| Aspect | Tplyr | rtables/tern | gtsummary | tidytlg |
|---|---|---|---|---|
| Mental model | SAS-style layered table | Layout-tree | Composable functions | Function-based, tidyverse |
| SAS-friendly syntax | ✅ Very | ❌ Less | Moderate | ✅ Yes |
| SAS-matching rounding | ✅ Default | Requires config | Requires config | ✅ Yes |
| Validation evidence | ✅ Strong UAT | ✅ Strong | Growing | ✅ Strong |
| ARD-aligned | ❌ | ❌ | ✅ | ❌ |
| Tidy output | ✅ Tibble | Table object | gt/flextable object | Tibble |
| Easy r2rtf integration | ✅ Yes | Yes (via flextable) | ✅ Yes | ✅ Yes |
| Adoption | Atorus + transitioning sponsors | Roche/Novartis/AbbVie | Broad, growing | Janssen + others |

There's no objective "best." Each tool has its niche and its champions.

## 14. When to choose Tplyr

Choose Tplyr when:

- Your team has deep SAS heritage and needs a friendly transition path
- SAS-matching numeric output is important (e.g., dual programming with SAS QC)
- You want a tidy tibble output to pipe into r2rtf
- Your sponsor SOPs favor Atorus-aligned tooling
- Existing Tplyr-based pipelines exist (don't rewrite if it works)

Skip Tplyr in favor of alternatives when:

- You're already on rtables/tern (Roche-aligned)
- You're starting fresh and want ARD-first (Cardinal-future)
- Complex layouts that gtsummary handles cleanly are common

## 15. The Atorus ecosystem

Tplyr is part of a broader Atorus open-source ecosystem:

- **`{Tplyr}`**: this lesson — table computation
- **`{xportr}`** (Lesson 39): SAS XPT v5 transport file creation
- **`{pkglite}`**: package compression for submission (originated at Merck but Atorus is a major contributor)
- **`{logrx}`** (Lesson 41): R script execution logging for compliance
- Contributions to **`{admiral}`**, **`{admiralpeds}`**, **`{cardx}`**

If your sponsor is on the Atorus path, Tplyr is the default. The integration between Tplyr and the others is smooth.

## 16. Maintainers and direction

Tplyr is maintained at Atorus Research, with Mike Stackhouse as primary author. Major contributors include Eli Miller, Nathan Kosiba, Aidan Ceney. The package is stable; releases focus on incremental improvements, bug fixes, edge-case handling.

Strategic direction:

- Continued focus on SAS-matching output for validation simplification
- Possible ARD-output extension to align with CDISC ARS (Tplyr → ARD bridge under discussion)
- Expansion of stats coverage for inferential layers
- Continued integration with the Atorus open-source stack

## 17. Migration considerations

For sponsors with significant Tplyr investment considering migration to the Cardinal-future stack:

- **Don't rewrite mid-study**: stick with the validated tool for in-flight studies
- **For new studies**: evaluate Cardinal-future fit; many demographic and AE tables are easier in gtsummary
- **Bridge layer**: a converter from Tplyr output to ARD format would smooth migration; community contributions in progress

For mixed teams: Tplyr and gtsummary coexist fine. Use each where it fits. The output (RTF) is the same regardless of how it was computed.

## 18. Key takeaways

- `{Tplyr}` is Atorus's "grammar of table summary" — layered table construction designed for SAS programmers transitioning to R
- Three-piece pattern: `tplyr_table()` + `add_layer()` (one or more) + `build()`
- Core layers: `group_desc()` (continuous), `group_count()` (categorical), `group_shift()` (shift tables)
- `set_format_strings(f_str(...))` controls statistic display
- `set_distinct_by(USUBJID)` makes counts subject-aware (matches FDA convention)
- `round_half_up` default rounding matches SAS output (huge for validation)
- Output is a tibble — pipes cleanly into r2rtf or flextable
- Extensive UAT (User Acceptance Testing) documentation supports regulatory use
- Strong at Atorus-aligned sponsors and SAS-to-R transition teams
- Coexists with all other TLG tools

## 19. What's next

Lesson 37 — the final lesson in Module 7 — covers **`{tidytlg}`**: Janssen's tidyverse-based TLG package. tidytlg sits philosophically between Tplyr and gtsummary, producing flat tables with a tidyverse-style API. After Lesson 37, Module 7 is complete.

After Module 7 we move to Module 8 — Shiny / teal for interactive clinical analysis dashboards.

---

## Self-check questions

1. What does Tplyr mean by "grammar of table summary"? Compare to dplyr's "grammar of data manipulation."
2. Translate to Tplyr: "Build a table of AGE and SEX summaries, by TRT01P, on the safety population."
3. Why is SAS-matching rounding important for sponsors running dual programming?
4. What does `set_distinct_by(USUBJID)` do in `group_count()`?
5. What's the difference between `add_total_group()` and `add_total_row()`?
6. Why does Tplyr integrate naturally with r2rtf?

## Glossary

- **`tplyr_table(data, treat_var, where = ...)`** — Start a new Tplyr table specification
- **`add_layer()`** — Add an analysis layer (one row-group of analysis)
- **`group_desc(var, by = label)`** — Continuous summary layer
- **`group_count(var)`** — Categorical count layer
- **`group_shift(var, ...)`** — Shift table layer
- **`set_format_strings(f_str(...))`** — Control statistic display formats
- **`f_str(template, stat1, stat2, ...)`** — Format spec: template + named statistics
- **`set_distinct_by(USUBJID)`** — Count each subject once per category
- **`add_total_group()`** — Add an "Overall" / "Total" column
- **`add_total_row()`** — Add a total row within a count layer
- **`build(table)`** — Execute all layers and produce the final tibble
- **`round_half_up`** — SAS-compatible rounding (round half away from zero)
- **UAT** — User Acceptance Testing (Tplyr's formal validation documentation)
- **Layered table** — Tplyr's mental model: each analysis is a layer, layers stack to form the table
- **Atorus ecosystem** — Tplyr + xportr + pkglite + logrx
