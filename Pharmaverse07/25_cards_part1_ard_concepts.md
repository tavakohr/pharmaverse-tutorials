# Lesson 25 — `{cards}` Part 1: ARD Concepts in Code

**Module**: 6 — TLG: the Cardinal-future stack
**Estimated length**: ~22 min spoken
**Prerequisites**: Lesson 01 (ARS/ARD paradigm); Lessons 14–19 (admiral)

---

## Learning objectives

By the end of this lesson, you will be able to:

1. Explain why ARDs (Analysis Results Datasets) matter and how `{cards}` makes them
2. Recognize the ARD tibble structure: the standard columns and what they mean
3. Use `ard_continuous()`, `ard_categorical()`, `ard_hierarchical()`, `ard_complex()` to build basic ARDs
4. Stack multiple ARDs into one with `ard_stack()` and `bind_ard()`
5. Capture warnings and errors gracefully via the ARD structure rather than crashing your pipeline
6. Understand where cards sits in the Cardinal-future TLG stack

---

## 1. Why ARDs, why now

Back in Lesson 01 we discussed ARS (Analysis Results Standard) and the emergence of ARDs (Analysis Results Datasets). Recap: instead of producing a finished table directly from ADaM data, you produce an **intermediate** tidy dataset of analysis *results* — the numbers — separately from any formatting. Then you reshape and format that dataset into the desired table.

The shift in mindset:

```
Old:  ADaM   →    Table (with formulas, formats, layout fused)
New:  ADaM   →    ARD (just numbers)   →    Table (just display)
```

The ARD is the durable artifact. Tables are derived from it. Multiple tables (a CSR table, a slide deck table, a Shiny app table) can all share the same ARD.

The CDISC ARS standard formalizes this for regulatory submission; companies are also adopting ARDs internally to streamline TLG production. `{cards}` is the R implementation of this idea.

## 2. What `{cards}` produces

A `cards` ARD is a tibble with a specific shape — one row per statistic, with standard columns that identify what the statistic is. Let's see the simplest example:

```r
library(cards)
library(pharmaverseadam)

adsl <- pharmaverseadam::adsl |> dplyr::filter(SAFFL == "Y")

ard_continuous(adsl, by = "ARM", variables = "AGE")
```

The output:

```
{cards} data frame: 24 x 10
   group1  group1_level  variable  stat_name  stat_label  stat
1  ARM     Placebo       AGE       N          N           86
2  ARM     Placebo       AGE       mean       Mean        75.209
3  ARM     Placebo       AGE       sd         SD          8.59
4  ARM     Placebo       AGE       median     Median      76
5  ARM     Placebo       AGE       p25        Q1          69
6  ARM     Placebo       AGE       p75        Q3          82
7  ARM     Placebo       AGE       min        Min         52
8  ARM     Placebo       AGE       max        Max         89
9  ARM     Xanomeline    AGE       N          N           84
10 ARM     Xanomeline    AGE       mean       Mean        74.381
...
```

Each row is one *statistic* for one (group × variable) combination. The columns:

- **`group1`**: the grouping variable name ("ARM")
- **`group1_level`**: the value of that variable for this row ("Placebo")
- **`variable`**: the variable being summarized ("AGE")
- **`stat_name`**: machine-friendly statistic identifier ("mean", "sd", "p25")
- **`stat_label`**: human-readable label ("Mean", "SD", "Q1")
- **`stat`**: the actual numeric value
- **`context`**: the function family that produced this stat ("continuous", "categorical", etc.)
- **`fmt_fn`**: a function for formatting this stat (e.g., 1 decimal place)
- **`warning`**: any warning from the calculation
- **`error`**: any error from the calculation

For categorical variables, additional `variable_level` columns identify the level of the variable being counted.

This is **the** structure. Every cards ARD has these columns (sometimes more, depending on grouping levels). Once you internalize it, every cards output looks the same.

## 3. The four constructor functions

`{cards}` has four main constructors for different statistic types:

| Function | What it produces |
|---|---|
| `ard_continuous()` | Summary statistics (N, mean, sd, quartiles, min, max) of continuous variables |
| `ard_categorical()` | Counts and proportions (n, N, p) of categorical levels |
| `ard_hierarchical()` | Nested categorical tabulations (e.g., AE terms within SOC) |
| `ard_complex()` | Custom summaries with access to full and subsetted data |

### `ard_continuous()` — for numeric summaries

```r
ard_continuous(adsl, by = "ARM", variables = c("AGE", "BMIBL"))
```

By default returns N, mean, sd, median, Q1, Q3, min, max for each variable per group. The `by` argument splits by treatment; `variables` specifies which numeric columns to summarize.

### `ard_categorical()` — for category counts

```r
ard_categorical(adsl, by = "ARM", variables = c("AGEGR1", "SEX", "RACE"))
```

By default returns "n" (count per level), "N" (total non-missing in group), and "p" (proportion = n/N). For variables with multiple levels (RACE has many), one row per level per stat.

### `ard_hierarchical()` — for nested tabulations

For AE analyses we typically want a hierarchical table: rows for system organ class, sub-rows for preferred terms within. `ard_hierarchical()` handles this:

```r
adae <- pharmaverseadam::adae

adae |>
  dplyr::filter(SAFFL == "Y" & TRTEMFL == "Y") |>
  ard_hierarchical(
    by = "ARM",
    variables = c("AESOC", "AEDECOD")
  )
```

Returns counts at each level of the hierarchy — counts per SOC, counts per (SOC × PT), with N for each level. The basis for the standard "AE incidence by SOC and preferred term" table.

### `ard_complex()` — for everything else

When standard summaries aren't enough — e.g., you need an aggregate-level statistic that's a function of the full data, or a baseline-stratified comparison — `ard_complex()` accepts arbitrary summary functions:

```r
# Mode of AGEGR1 per ARM
get_mode <- function(x) {
  table(x) |> sort(decreasing = TRUE) |> names() |> getElement(1L)
}

ard_complex(
  adsl,
  by = "ARM",
  variables = "AGEGR1",
  statistic = list(AGEGR1 = list(mode = get_mode))
)
```

The `statistic` argument is a deeply nested list specifying which function to apply to which variable. Verbose, but maximally flexible. `ard_continuous()` is essentially a friendlier wrapper around `ard_complex()` with pre-defined statistic functions.

## 4. Stacking ARDs together: `ard_stack()`

A real demographics table needs continuous *and* categorical summaries on the same display. `ard_stack()` runs multiple `ard_*()` constructors and combines their output:

```r
adsl_demog_ard <- ard_stack(
  adsl,
  ard_continuous(variables = AGE),
  ard_categorical(variables = c(AGEGR1, SEX, RACE)),
  .by = ARM,
  .overall = TRUE,         # include "Overall" column across all subjects
  .total_n = TRUE          # add a Big-N row per arm
)
```

The result is a single ARD with continuous AGE rows and categorical AGEGR1/SEX/RACE rows stacked. `.overall = TRUE` adds an "Overall" column-level that's the same statistics computed without the `.by` grouping — useful for the "all subjects" column of a demographics table. `.total_n = TRUE` adds the per-arm Big-N row used in column headers like "Placebo (N=86)".

For programmatic combination of pre-built ARDs, use `bind_ard()`:

```r
ard_age   <- ard_continuous(adsl, by = "ARM", variables = "AGE")
ard_sex   <- ard_categorical(adsl, by = "ARM", variables = "SEX")

combined <- bind_ard(ard_age, ard_sex)
```

Both functions enforce ARD structure: if a column you'd expect isn't present in one input, it's added as NA.

## 5. Customizing the statistics

Sometimes the default stats aren't what you want. To compute only specific statistics:

```r
ard_continuous(
  adsl,
  by = "ARM",
  variables = "AGE",
  statistic = ~ continuous_summary_fns(c("N", "mean", "sd", "min", "max"))
)
```

`continuous_summary_fns()` is a helper that returns a named list of summary functions. You pass character names; only those stats get computed. Available names include: "N", "N_obs", "N_miss", "mean", "sd", "median", "p25", "p75", "min", "max", "var", "iqr", and others.

For a *custom* summary function (e.g., 95% CI of the mean):

```r
mean_ci <- function(x, conf = 0.95) {
  s <- sd(x, na.rm = TRUE) / sqrt(sum(!is.na(x)))
  m <- mean(x, na.rm = TRUE)
  z <- qnorm(1 - (1 - conf) / 2)
  c(lower = m - z * s, upper = m + z * s)
}

ard_continuous(
  adsl,
  by = "ARM",
  variables = "AGE",
  statistic = list(AGE = list(mean_ci = mean_ci))
)
```

The result includes rows with `stat_name = "mean_ci"` and the lower/upper values. This pattern works for any statistic you can write as an R function.

## 6. Custom denominators

By default, `ard_categorical()` uses N = number of non-missing rows per (by-group × variable) as the denominator for proportions. Sometimes that's wrong — e.g., for AE rates, the denominator should be "subjects in the safety population," even if many have no AE at all.

The `denominator` argument supports several inputs:

```r
# Use a data frame as the denominator: count rows in this data
ard_categorical(
  adae |> filter(TRTEMFL == "Y"),
  by = "ARM",
  variables = "AESOC",
  denominator = adsl |> filter(SAFFL == "Y")
)
```

Now N per ARM is the safety-pop count from ADSL, not the row count of TRTEMFL = "Y" events in ADAE. This is critical for correct AE incidence calculations.

A numeric vector also works as denominator. Or a function. The flexibility lets you encode your study's exact denominator definitions.

## 7. Error and warning handling

A signature feature of cards: it never crashes on a per-statistic basis. If a function fails (e.g., dividing by zero, or insufficient data for a t-test), the failure is captured in the `warning` or `error` column of that row:

```r
mean_with_error <- function(x) {
  stop("There was an error calculating the mean.")
}

ard_with_error <- ard_continuous(
  adsl,
  variables = "AGE",
  statistic = ~list(mean = mean_with_error)
)
```

The output: a row with `stat = NULL` and `error` populated with the error message. Other statistics in the same call (e.g., SD, median) still compute correctly.

To inspect errors and warnings:

```r
print_ard_conditions(ard_with_error)
# Prints any errors and warnings to the console as messages
```

This means a single statistic failure doesn't kill your TLG pipeline. The downstream table renders normally; problematic cells appear as "NE" or similar. You investigate the errors at your leisure.

This is a substantial improvement over running everything inside one large `summarise()` call where any single failure stops the whole pipeline.

## 8. Putting it together: a demographics ARD

A complete demographics ARD with continuous (AGE) and categorical (AGEGR1, SEX, RACE) variables:

```r
library(cards)
library(pharmaverseadam)
library(dplyr)

adsl <- pharmaverseadam::adsl |>
  filter(SAFFL == "Y")

demog_ard <- ard_stack(
  adsl,
  ard_continuous(
    variables = AGE,
    statistic = ~ continuous_summary_fns(c("N", "mean", "sd", "median", "p25", "p75", "min", "max"))
  ),
  ard_categorical(variables = c(AGEGR1, SEX, RACE)),
  .by = TRT01A,
  .overall = TRUE,
  .total_n = TRUE
)

demog_ard
```

This produces a tidy ARD ready to be transformed into a demographics table by `gtsummary::tbl_ard_summary()` (Lesson 28) or `tfrmt` (Lesson 32). The numbers are computed; formatting comes later.

## 9. The conceptual shift for SAS programmers

If you've spent years writing `proc freq` and `proc means` outputs directly into final tables, the ARD approach feels indirect at first. You're computing numbers into a tibble that doesn't look like a table.

Embrace the indirection. Here's why:

- **Reusability**: one ARD feeds multiple displays. The CSR demographics table and the slide-deck demographics summary can both come from the same ARD.
- **Auditability**: every number has a row with `stat_name`, `stat_label`, and source info. You can answer "where did that 75.2 come from?" by looking at the relevant ARD row.
- **Mechanization**: ARDs are machine-readable. A reviewer's R script can pull values from your ARD by name; they don't have to OCR your PDF table.
- **CDISC ARS alignment**: when CDISC ARS becomes a submission requirement (likely 2026–2027), your ARDs become standardized submission artifacts.

SAS programmers reach this insight with experience. Stick with it through the first 2-3 ARDs you build.

## 10. The Cardinal-future stack: where cards fits

Recall the strategic positioning we discussed in Lesson 01:

```
ADaM data
   │
   ▼
ARD (ANALYSIS RESULTS — numeric, tidy)         ← {cards}, {cardx}
   │
   ▼
DISPLAY METADATA + ARD                          ← {tfrmt}, {gtsummary}
   │
   ▼
PUBLISHED TABLE (.docx, .rtf, .html)            ← {gt}, {flextable}, {gtsummary}
```

`{cards}` makes the ARD. `{cardx}` (Lesson 27) extends cards with regression and survival functions. `{gtsummary}` (Lessons 28–29) consumes ARDs to produce publication-quality tables. `{tfrmt}` (Lesson 32) provides display metadata for ARDs.

`{cardinal}` (Lessons 30–31) is the meta-project — a harmonized catalog of TLG templates built from this stack.

Together they replace much of the "old way" (Tplyr → rtables → r2rtf or chevron → tern → rtables) with a cleaner, ARD-first architecture. Module 7 covers the legacy stack, which is still dominant in many sponsor environments; both stacks coexist.

## 11. Package maintenance and team

`{cards}` is jointly maintained by Roche, GSK, and Novartis, with Dan Sjoberg (Roche) as the most visible maintainer. The package is on CRAN; the current release is 0.x — production-ready but the API is still settling in places.

Active development:

- More categorical and complex statistic helpers
- Tighter integration with gtsummary's column-by-column composition
- Coverage of additional CDISC ARS-defined statistic types
- Performance optimizations for very large ARDs

## 12. Inspecting and validating an ARD

`{cards}` provides utility functions for ARD validation:

```r
check_ard_structure(demog_ard)
# Verifies the ARD has the required columns and types; errors if not

print_ard_conditions(demog_ard)
# Prints any captured errors/warnings

get_ard_statistics(demog_ard, filter = variable == "AGE" & stat_name == "mean")
# Extract specific values from the ARD
```

These help when you're building custom ARDs from your own data — they confirm the structure is right.

For a real-world TLG pipeline, you'd typically:

1. Build the ARD
2. Run `check_ard_structure()` as a unit test
3. Print conditions to see any errors
4. Pass to gtsummary or tfrmt for display

The ARD is then the durable artifact stored in your project, version-controlled, used for downstream displays.

## 13. Where cards differs from old-style table generation

Two key differences from `Tplyr` / `tern` / similar:

- **No layout in the data**: cards ARDs don't have row labels, column groupings, or layout headers. Those are display concerns.
- **Long format, not wide**: each statistic is a row, not a column. Reshape happens at the display step.

If you're coming from Tplyr, you'll find that `Tplyr::tplyr_table() |> build()` produces a layout-already-in-place wide data frame. The cards equivalent is two steps: build the ARD long, then reshape for display.

The benefit shows up when:

- Multiple displays consume the same data (no need to recompute)
- You want to support multiple output formats (RTF + PowerPoint + HTML) from one source
- You're integrating with regulatory reviewer tools that expect tidy data

## 14. Key takeaways

- `{cards}` makes Analysis Results Datasets — tidy tables of computed statistics, separated from display
- An ARD has standard columns: `group1/group1_level`, `variable`, `stat_name/stat_label`, `stat`, `context`, `fmt_fn`, plus warning/error capture
- Four constructors: `ard_continuous()`, `ard_categorical()`, `ard_hierarchical()`, `ard_complex()`
- `ard_stack()` and `bind_ard()` combine multiple ARDs into one
- Errors and warnings on individual statistics are captured in the row, not raised — your pipeline doesn't crash
- The `denominator` argument lets you control N for proportion calculations
- cards sits at the ARD layer of the Cardinal-future TLG stack; consumed by gtsummary, tfrmt, and cardinal templates

## 15. What's next

Lesson 26 — **`{cards}` Part 2** — works through clinical ARD examples in detail: demographics, AE incidence, lab change-from-baseline, exposure summary. We'll see the standard patterns used across pharma reporting and how cards handles each.

After Part 2 we move to `{cardx}` (regression/survival ARDs), then gtsummary in two parts, then cardinal, then tfrmt.

---

## Self-check questions

1. What does ARD stand for, and what makes a cards ARD different from a regular tibble?
2. Name the four primary cards constructor functions and what each is for.
3. What's the purpose of the `error` column in an ARD row?
4. When would you use `ard_hierarchical()` instead of `ard_categorical()`?
5. Translate to cards: "Compute N, mean, and SD of AGE per ARM with the safety population as denominator."
6. Why is the ARD-first architecture preferred over generating tables directly?

## Glossary

- **ARD** — Analysis Results Dataset; tidy tibble of computed statistics
- **ARS** — Analysis Results Standard; CDISC framework defining ARD structures
- **`ard_continuous()`** — Summary statistics for numeric variables
- **`ard_categorical()`** — Counts/proportions for categorical variables
- **`ard_hierarchical()`** — Nested tabulations (e.g., AE terms within SOC)
- **`ard_complex()`** — Custom summaries with arbitrary functions
- **`ard_stack()`** — Combine multiple ard_*() outputs in one call
- **`bind_ard()`** — Concatenate pre-built ARDs
- **`stat_name` / `stat_label`** — Machine and human-readable statistic identifiers
- **`fmt_fn`** — Formatting function attached to each statistic
- **`denominator`** — Custom N for proportion calculations
- **Cardinal-future stack** — cards + cardx + gtsummary + tfrmt + cardinal
- **`continuous_summary_fns()`** — Helper returning named list of summary functions
- **`print_ard_conditions()`** — Print captured warnings/errors from an ARD
