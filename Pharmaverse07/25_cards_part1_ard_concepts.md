# Lesson 25 — `{cards}` Part 1: ARD Structure, Column Anatomy, and Core Constructors

**Module**: 6 — TLG: the Cardinal-future stack
**Estimated length**: ~40 min spoken
**Prerequisites**: Lesson 01 (ARS/ARD paradigm); Lessons 14–19 (admiral)

---

## Learning objectives

By the end of this lesson, you will be able to:

1. Explain the full ARD tibble structure — every column, its type, and what it contains
2. Understand why `stat` is a list column and know multiple ways to extract values from it
3. Use `ard_continuous()`, `ard_categorical()`, `ard_hierarchical()`, `ard_complex()` to build ARDs
4. Stack multiple ARDs with `ard_stack()` and `bind_ard()`
5. Capture warnings and errors gracefully without crashing your pipeline
6. Validate ARD structure with `check_ard_structure()` and inspect conditions with `print_ard_conditions()`
7. Extract specific statistics programmatically with `get_ard_statistics()`
8. Explain the SAS equivalent for each cards constructor
9. Translate common SAS patterns to their `{cards}` equivalents, including custom statistics

---

## 1. Why ARDs, why now — the two-minute recap

Back in Lesson 01 we established the ARS/ARD paradigm. Recap in two lines:

- **Old way**: `ADaM → PROC MEANS → formatted RTF` (analysis + display tangled)
- **New way**: `ADaM → ARD (just numbers) → display layer (just layout)`

The ARD is the durable artifact. Displays derive from it. Multiple displays can share one ARD. Regulators can receive the ARD alongside the TLGs for machine-readable review.

`{cards}` is the R implementation that makes this practical.

---

## 2. Installing and loading cards

```r
# From CRAN (stable):
install.packages("cards")

# Development version:
remotes::install_github("insightsengineering/cards")

library(cards)
library(dplyr)
library(pharmaverseadam)

# Sample data — we'll use these throughout
adsl <- pharmaverseadam::adsl |> filter(SAFFL == "Y")
```

Check your version — the API has been stabilizing through 0.x releases:

```r
packageVersion("cards")  # Should be >= 0.3.0 for all features shown here
```

---

## 3. The ARD column anatomy — a deep dive

Understanding the ARD structure completely is essential before writing any `{cards}` code. Let's build the simplest possible ARD and dissect every column.

```r
# The simplest ARD: one continuous variable, no grouping
simple_ard <- ard_continuous(adsl, variables = "AGE")
simple_ard
```

```
{cards} data frame: 8 x 10
   variable  stat_name  stat_label    stat       fmt_fn    context     warning  error
1  AGE       N          N            <int [1]>  <fn>      continuous  <NULL>   <NULL>
2  AGE       mean       Mean         <dbl [1]>  <fn>      continuous  <NULL>   <NULL>
3  AGE       sd         SD           <dbl [1]>  <fn>      continuous  <NULL>   <NULL>
4  AGE       median     Median       <dbl [1]>  <fn>      continuous  <NULL>   <NULL>
5  AGE       p25        Q1           <dbl [1]>  <fn>      continuous  <NULL>   <NULL>
6  AGE       p75        Q3           <dbl [1]>  <fn>      continuous  <NULL>   <NULL>
7  AGE       min        Min          <int [1]>  <fn>      continuous  <NULL>   <NULL>
8  AGE       max        Max          <int [1]>  <fn>      continuous  <NULL>   <NULL>
```

That's 8 rows: one per default statistic computed on AGE (N, mean, sd, median, Q1, Q3, min, max).

Now add a grouping:

```r
grouped_ard <- ard_continuous(adsl, by = "TRT01A", variables = "AGE")
grouped_ard
```

```
{cards} data frame: 24 x 10
# (8 stats × 3 treatment arms = 24 rows)
   group1  group1_level           variable  stat_name  stat_label  stat       context
1  TRT01A  Placebo                AGE       N          N           <int [1]>  continuous
2  TRT01A  Placebo                AGE       mean       Mean        <dbl [1]>  continuous
3  TRT01A  Placebo                AGE       sd         SD          <dbl [1]>  continuous
...
9  TRT01A  Xanomeline Low Dose    AGE       N          N           <int [1]>  continuous
...
17 TRT01A  Xanomeline High Dose   AGE       N          N           <int [1]>  continuous
...
```

### Column-by-column breakdown

#### `group1` and `group1_level`

`group1` stores the **variable name** used for grouping ("TRT01A"). `group1_level` stores the **value** of that variable for each row ("Placebo", "Xanomeline Low Dose", etc.).

For multiple grouping variables (e.g., `by = c("PARAMCD", "AVISIT")`), cards adds `group2`/`group2_level`, `group3`/`group3_level`, up to as many levels as needed. The column names follow this pattern automatically.

When there is no grouping (single-column ARD), `group1` and `group1_level` do not appear.

#### `variable`

The name of the ADaM variable being summarized. For `ard_continuous(variables = "AGE")`, every row has `variable = "AGE"`. When you pass multiple variables, each gets its own set of rows.

#### `variable_level`

**Only present for categorical analyses.** For `ard_categorical(variables = "SEX")`, `variable_level` will be `"F"` for rows about female subjects and `"M"` for rows about male subjects. For continuous analyses, this column doesn't appear (there are no levels to enumerate).

#### `stat_name` and `stat_label`

The statistic identifier pair. `stat_name` is the machine-readable key (used for filtering, programmatic extraction). `stat_label` is the human-readable display label (used by gtsummary and tfrmt for table headers).

Standard `stat_name` values for `ard_continuous()`:

| `stat_name` | `stat_label` | What it computes |
|---|---|---|
| `N` | `"N"` | Count of non-missing values |
| `N_obs` | `"N Obs."` | Total observations (including missing) |
| `N_miss` | `"N Missing"` | Count of missing values |
| `p_miss` | `"% Missing"` | Proportion missing |
| `mean` | `"Mean"` | Arithmetic mean |
| `sd` | `"SD"` | Standard deviation |
| `var` | `"Var."` | Variance |
| `median` | `"Median"` | Median |
| `p25` | `"Q1"` | 25th percentile |
| `p75` | `"Q3"` | 75th percentile |
| `min` | `"Min"` | Minimum |
| `max` | `"Max"` | Maximum |
| `iqr` | `"IQR"` | Interquartile range |
| `sum` | `"Sum"` | Sum |

Standard `stat_name` values for `ard_categorical()`:

| `stat_name` | `stat_label` | What it computes |
|---|---|---|
| `n` | `"n"` | Count of subjects in this level |
| `N` | `"N"` | Total count (denominator) |
| `p` | `"%"` | Proportion = n/N |
| `n_cum` | `"Cumulative n"` | Cumulative count |
| `p_cum` | `"Cumulative %"` | Cumulative proportion |

#### `stat` — the list column (critical!)

`stat` is a **list column**. This is the most commonly misunderstood aspect of cards ARDs.

Every cell in `stat` holds a list of length 1 containing the computed value. This is intentional: by using a list column, `stat` can hold *any R object* — a scalar, a vector, a matrix, a named list from a model. This makes the ARD format extensible to complex statistical outputs (like a t-test returning multiple values) without changing the column structure.

```r
# When you print the ARD, stat shows:
# stat = <dbl [1]>    ← a list holding one double
# stat = <int [1]>    ← a list holding one integer
# stat = <fn>         ← for fmt_fn column

# To extract the actual value:
ard <- ard_continuous(adsl, by = "TRT01A", variables = "AGE")

# Method 1: index directly
ard$stat[[1]]        # first row's value → 86 (the N for Placebo)
ard$stat[[2]]        # second row's value → 75.209 (mean for Placebo)

# Method 2: filter + pull + getElement
ard |>
  filter(group1_level == "Placebo" & stat_name == "mean") |>
  pull(stat) |>
  getElement(1)
# [1] 75.209

# Method 3: get_ard_statistics() — the proper helper
get_ard_statistics(ard,
  filter = group1_level == "Placebo" & stat_name == "mean"
)
# Returns: list(mean = 75.209)

# Method 4: unnesting for tabular inspection
ard |>
  filter(stat_name == "mean") |>
  mutate(stat_value = map_dbl(stat, 1)) |>
  select(group1_level, variable, stat_name, stat_value)
#   group1_level          variable  stat_name  stat_value
# 1 Placebo               AGE       mean       75.209
# 2 Xanomeline Low Dose   AGE       mean       74.381
# 3 Xanomeline High Dose  AGE       mean       75.667
```

> **SAS programmer note**: In SAS, `PROC MEANS` writes `MEAN = 75.209` as a regular numeric variable in an output dataset. In R/cards, that same value lives inside a list cell. The list-column design allows the ARD to hold statistics that are not scalars — for example, `ard_survival_survfit()` returns confidence interval vectors. Always use `[[1]]`, `getElement()`, or `get_ard_statistics()` to unwrap values.

#### `fmt_fn` — the formatting function list column

`fmt_fn` is also a list column. Each cell holds a function (or `NULL`) that specifies how the statistic *should be displayed* in a table. This is advisory information that `{gtsummary}` uses to format numbers.

For example, `mean` has a formatting function that displays to 1 decimal place; `N` has a formatting function that formats as an integer. You rarely interact with `fmt_fn` directly — gtsummary picks it up automatically.

To inspect:
```r
ard$fmt_fn[[2]]       # The formatting function for the mean row
# function(x) format(x, digits = 1, nsmall = 1)  (approximately)
```

To override (if you need different decimal places):
```r
ard_continuous(
  adsl,
  by = "TRT01A",
  variables = "AGE",
  fmt_fn = list(AGE = list(mean = function(x) formatC(x, digits = 2, format = "f")))
)
```

#### `context`

A character string identifying which `ard_*()` family produced this row. Standard values:

| `context` value | Produced by |
|---|---|
| `"continuous"` | `ard_continuous()` |
| `"categorical"` | `ard_categorical()` |
| `"hierarchical"` | `ard_hierarchical()` |
| `"complex"` | `ard_complex()` |
| `"total_n"` | `.total_n = TRUE` in `ard_stack()` |
| `"stats_t_test"` | `cardx::ard_stats_t_test()` |
| `"survival_survfit"` | `cardx::ard_survival_survfit()` |

When you bind multiple ARDs together with `bind_ard()`, the `context` column tells you where each row came from. This is essential for downstream display code that needs to filter on type.

#### `warning` and `error`

Both are list columns. Each cell holds `NULL` (no issue) or the captured condition text.

```r
# A statistic that will fail:
bad_fn <- function(x) stop("calculation failed deliberately")

ard_with_error <- ard_continuous(
  adsl,
  variables = "AGE",
  statistic = list(AGE = list(bad_stat = bad_fn))
)

ard_with_error$error[[1]]
# [1] "calculation failed deliberately"

ard_with_error$stat[[1]]
# NULL  ← value is NULL when computation failed
```

This is fundamental to production robustness: **a single failing statistic does not abort the pipeline.** Other statistics in the same call still succeed. The downstream table renders with `NA` or `"NE"` in problematic cells. You investigate errors at your leisure without losing an entire run.

---

## 4. The four constructor functions — in depth

### `ard_continuous()` — for numeric summaries

The workhorse for continuous variable summaries.

**Default statistics**: N, N_obs, N_miss, p_miss, mean, sd, median, p25, p75, min, max (11 total).

**Limiting statistics** (always do this for production — don't compute stats you don't need):

```r
ard_continuous(
  adsl,
  by = "TRT01A",
  variables = c("AGE", "BMIBL", "WEIGHTBL", "HEIGHTBL"),
  statistic = ~ continuous_summary_fns(c("N", "mean", "sd", "median", "p25", "p75", "min", "max"))
)
```

The `~` (formula notation) applies the same statistic list to all variables. The right-hand side is a list of named functions. `continuous_summary_fns()` is a shortcut that returns pre-built named function lists.

**Custom statistics** (anything you can write as a function):

```r
# Coefficient of variation: sd / mean * 100
cv_fn <- function(x) sd(x, na.rm = TRUE) / mean(x, na.rm = TRUE) * 100

# 95% CI of the mean (normal approximation)
mean_ci_low  <- function(x) mean(x, na.rm = TRUE) - 1.96 * sd(x, na.rm = TRUE) / sqrt(sum(!is.na(x)))
mean_ci_high <- function(x) mean(x, na.rm = TRUE) + 1.96 * sd(x, na.rm = TRUE) / sqrt(sum(!is.na(x)))

ard_continuous(
  adsl,
  by = "TRT01A",
  variables = "AGE",
  statistic = list(AGE = list(
    N        = \(x) length(x[!is.na(x)]),
    mean     = \(x) mean(x, na.rm = TRUE),
    sd       = \(x) sd(x, na.rm = TRUE),
    cv       = cv_fn,
    ci_low   = mean_ci_low,
    ci_high  = mean_ci_high
  ))
)
```

Each function receives a vector of the variable values (already filtered to the current group). Functions must return a single scalar (numeric, integer, or character). Functions that return vectors produce a list-element holding the vector.

**SAS equivalent**: `PROC MEANS DATA=adsl N MEAN STD MEDIAN P25 P75 MIN MAX; CLASS TRT01A; VAR AGE BMIBL WEIGHTBL HEIGHTBL; WHERE SAFFL='Y'; RUN;`

### `ard_categorical()` — for count and proportion summaries

```r
ard_categorical(
  adsl,
  by = "TRT01A",
  variables = c("AGEGR1", "SEX", "RACE", "ETHNIC")
)
```

**Default statistics**: `n` (count per level), `N` (total per group), `p` (proportion = n/N).

Optional statistics: `n_cum`, `p_cum` (cumulative counts/proportions).

**Controlling what statistics appear**:

```r
ard_categorical(
  adsl,
  by = "TRT01A",
  variables = "AGEGR1",
  statistic = ~ list(
    n = \(x, data, ...) sum(x, na.rm = TRUE),
    p = \(x, data, ...) mean(x, na.rm = TRUE)
  )
)
```

**Missing levels**: If a variable has levels with zero subjects in a group, those levels will be *absent* from the ARD by default. This causes inconsistent table rows. The fix: factor-type the variable with all expected levels declared.

```r
adsl_factored <- adsl |>
  mutate(AGEGR1 = factor(AGEGR1, levels = c("<65", "65-80", ">80")))

ard_categorical(adsl_factored, by = "TRT01A", variables = "AGEGR1")
# Now every arm has rows for all three levels, even if n = 0
```

**SAS equivalent**: `PROC FREQ DATA=adsl; TABLES TRT01A * (AGEGR1 SEX RACE ETHNIC) / NOCUM NOPERCENT; WHERE SAFFL='Y'; RUN;`

#### The denominator argument — critical for AE analyses

By default, `N` (the denominator) is the count of non-missing observations in the source data for each group. This is wrong when the source data has multiple rows per subject (e.g., ADAE has one row per event).

```r
# WRONG: denominator = rows in ADAE (will over-count)
ard_categorical(
  adae |> filter(TRTEMFL == "Y"),
  by = "ARM",
  variables = "AEDECOD"
)

# CORRECT: denominator = subjects in safety population
ard_categorical(
  adae |> filter(SAFFL == "Y" & TRTEMFL == "Y"),
  by = "ARM",
  variables = "AEDECOD",
  denominator = adsl |> filter(SAFFL == "Y")    # ← N per arm from ADSL
)
```

When `denominator` is a data frame, cards counts its rows per group to determine N. The `N` rows in the resulting ARD will reflect the ADSL subject counts, not the ADAE event counts.

**Other denominator forms**:
```r
# Numeric vector: one N per group
ard_categorical(..., denominator = c("Placebo" = 86, "Xanomeline Low Dose" = 84))

# "row": N = total rows in the grouped data (default)
ard_categorical(..., denominator = "row")

# "col": N = total rows across all groups (rare)
ard_categorical(..., denominator = "col")
```

**SAS equivalent**: The denominator pattern replaces the SAS technique of computing Big-N per arm in a separate `PROC FREQ` or `PROC SQL`, outputting it to a dataset, then merging it back onto the AE frequency dataset to compute percentages.

### `ard_hierarchical()` — for nested categorical tabulations

For AE tables where you need both SOC-level and PT-level counts, `ard_hierarchical()` handles the nesting:

```r
adae |>
  filter(SAFFL == "Y" & TRTEMFL == "Y") |>
  ard_hierarchical(
    by = "ARM",
    variables = c("AEBODSYS", "AEDECOD"),   # outermost first
    denominator = adsl |> filter(SAFFL == "Y")
  )
```

What you get:
- Rows where `variable = "AEBODSYS"`: distinct-subject counts per (ARM × SOC)
- Rows where `variable = "AEDECOD"` with the SOC group context: distinct-subject counts per (ARM × SOC × PT)

The counts are *subject-level* (distinct USUBJID), not event-level. This is the correct metric for "incidence by preferred term."

`ard_hierarchical()` vs `ard_categorical()`:
- `ard_categorical()`: flat counts — one level of hierarchy only
- `ard_hierarchical()`: nested counts — SOC and PT both computed correctly, with PT counts shown within their SOC context

**SAS equivalent**: You cannot do this cleanly in one `PROC FREQ` call. The SAS equivalent requires a PROC FREQ for SOC-level, a separate PROC FREQ for PT-level (with a `TABLES ARM * SOC * PT`), then a `DATA` step to stack and handle the hierarchy. `ard_hierarchical()` does all of this correctly in one call.

```r
# Real-world example: getting ready for the AE incidence table
ae_hier_ard <- adae |>
  filter(SAFFL == "Y" & TRTEMFL == "Y") |>
  ard_hierarchical(
    by = "ARM",
    variables = c("AEBODSYS", "AEDECOD"),
    denominator = adsl |> filter(SAFFL == "Y"),
    id = "USUBJID"      # ensures distinct-subject counting
  )

# Inspect SOC-level counts:
ae_hier_ard |>
  filter(variable == "AEBODSYS" & stat_name == "n") |>
  mutate(n = map_dbl(stat, 1)) |>
  select(group1_level, variable_level, n) |>
  arrange(desc(n))
```

### `ard_complex()` — for everything else

When the standard constructors don't cover your analysis, `ard_complex()` accepts arbitrary functions with access to the full dataset (not just the variable vector):

```r
# Custom: mode of a categorical variable
get_mode <- function(x, ...) {
  tbl <- sort(table(x), decreasing = TRUE)
  names(tbl)[1]
}

ard_complex(
  adsl,
  by = "TRT01A",
  variables = "AGEGR1",
  statistic = list(AGEGR1 = list(mode = get_mode))
)
```

The key difference from `ard_continuous()` custom statistics: `ard_complex()` functions receive the *data frame* subset (not just a vector), giving you access to all variables when your statistic requires more than one column.

```r
# Custom: ratio of counts between two variables (requires data frame access)
risk_ratio <- function(data, ...) {
  events   <- sum(data$AOCCFL == "Y", na.rm = TRUE)
  non_events <- sum(data$AOCCFL != "Y", na.rm = TRUE)
  events / (events + non_events)
}

ard_complex(
  adae,
  by = "ARM",
  variables = "AOCCFL",
  statistic = list(AOCCFL = list(proportion = risk_ratio)),
  .by = "ARM"
)
```

---

## 5. Stacking ARDs: `ard_stack()` and `bind_ard()`

### `ard_stack()` — multiple constructors in one call

For a real demographics table you need continuous and categorical ARDs together. `ard_stack()` runs them in sequence and combines:

```r
demog_ard <- ard_stack(
  adsl,                                    # dataset
  ard_continuous(
    variables = AGE,
    statistic = ~ continuous_summary_fns(c("N", "mean", "sd", "median", "min", "max"))
  ),
  ard_categorical(
    variables = c(AGEGR1, SEX, RACE, ETHNIC)
  ),
  .by = TRT01A,         # grouping variable — applied to ALL constructors
  .overall = TRUE,      # add "Overall" column combining all groups
  .total_n = TRUE,      # add Big-N rows per group (for column headers)
  .missing = FALSE      # don't include missing level by default
)

nrow(demog_ard)  # Will be several hundred rows covering all stats × variables × arms

# Quick validation: see the distinct stat names in the continuous section
demog_ard |>
  filter(context == "continuous") |>
  distinct(stat_name, stat_label)
```

**What `.overall = TRUE` does**: Adds a complete set of rows with `group1_level = "Overall"` — the statistics computed across all groups combined. This corresponds to the "All Subjects" or "Total" column in a demographics table.

**What `.total_n = TRUE` does**: Adds rows with `context = "total_n"` and `stat_name = "N"` — the Big-N per arm that becomes the column header subtitle ("Placebo (N=86)").

**SAS programmer analogy**: `.overall = TRUE` is like adding `PROC MEANS` with no `CLASS` statement after the `CLASS`-stratified run, then combining the outputs. `.total_n = TRUE` is like the Big-N dataset you'd compute separately and merge into column headers.

### `bind_ard()` — combine pre-built ARDs

When ARDs are built in separate scripts or function calls:

```r
ard_age    <- ard_continuous(adsl, by = "TRT01A", variables = "AGE")
ard_sex    <- ard_categorical(adsl, by = "TRT01A", variables = "SEX")
ard_race   <- ard_categorical(adsl, by = "TRT01A", variables = "RACE")

combined <- bind_ard(ard_age, ard_sex, ard_race)
# Single ARD with all rows, structure-enforced
```

`bind_ard()` enforces that all inputs have compatible ARD structures. If a column is present in one but not another, it's added as `NA` in the deficient ARDs before combining. This prevents silent row mis-alignment.

```r
# Contrast with dplyr::bind_rows():
# bind_rows() doesn't validate ARD structure — use bind_ard() instead
```

---

## 6. Validating and inspecting ARDs

### `check_ard_structure()`

Verifies the ARD has the required columns and types. Throws an informative error if not:

```r
check_ard_structure(demog_ard)
# No output = passes
# Error with informative message if fails

# Integrate into your pipeline as a unit test:
tryCatch(
  check_ard_structure(my_ard),
  error = function(e) stop("ARD structure validation failed: ", e$message)
)
```

### `print_ard_conditions()`

Prints all captured warnings and errors from computation:

```r
print_ard_conditions(demog_ard)
# Prints warnings/errors per stat_name, or "No conditions found." if clean
```

Always call this after building a production ARD. Captured conditions are silent — they don't print unless you ask.

### `get_ard_statistics()`

The proper way to extract specific values from an ARD by filter condition:

```r
# Get all statistics for AGE in the Placebo arm
age_placebo_stats <- get_ard_statistics(
  demog_ard,
  filter = group1_level == "Placebo" & variable == "AGE"
)
# Returns a named list: list(N = 86, mean = 75.209, sd = 8.59, ...)

# Get a specific value:
age_placebo_stats$mean
# [1] 75.209

# Get mean across all arms:
get_ard_statistics(
  demog_ard,
  filter = variable == "AGE" & stat_name == "mean",
  .by = "group1_level"
)
# Returns a list of named lists, one per arm
```

This pattern is useful when you need to pull specific numbers for inline reporting (e.g., "The mean age was `r get_ard_statistics(ard, filter=...)$mean`").

---

## 7. Custom statistics — deep dive

Cards' custom statistics mechanism is where experienced programmers unlock the full power of the ARD model. Any R function that takes a vector and returns a scalar can be a statistic.

### Pattern 1: Simple custom function

```r
geometric_mean <- function(x) exp(mean(log(x[x > 0 & !is.na(x)])))
harmonic_mean  <- function(x) length(x) / sum(1/x[x > 0 & !is.na(x)])

ard_continuous(
  adsl,
  by = "TRT01A",
  variables = "AGE",
  statistic = list(AGE = list(
    geo_mean = geometric_mean,
    harm_mean = harmonic_mean
  ))
)
```

### Pattern 2: Mixed default + custom statistics

```r
ard_continuous(
  adsl,
  by = "TRT01A",
  variables = "AGE",
  statistic = list(AGE = c(
    continuous_summary_fns(c("N", "mean", "sd")),   # standard stats
    list(cv = \(x) sd(x, na.rm=TRUE) / mean(x, na.rm=TRUE) * 100)  # custom
  ))
)
```

### Pattern 3: Statistics that return named vectors

When your function returns more than one value (e.g., both bounds of a CI), return a *named list*:

```r
mean_with_ci <- function(x) {
  m <- mean(x, na.rm = TRUE)
  se <- sd(x, na.rm = TRUE) / sqrt(sum(!is.na(x)))
  list(
    mean   = m,
    ci_low  = m - 1.96 * se,
    ci_high = m + 1.96 * se
  )
}

ard_continuous(
  adsl,
  by = "TRT01A",
  variables = "AGE",
  statistic = list(AGE = list(mean_ci = mean_with_ci))
)
```

This creates three rows per group: `stat_name = "mean_ci.mean"`, `"mean_ci.ci_low"`, `"mean_ci.ci_high"` — one per named list element.

### Pattern 4: Using `continuous_summary_fns()` helper

```r
# All available stat names:
names(continuous_summary_fns())
# [1] "N"     "N_obs" "N_miss" "p_miss" "mean"  "sd"    "var"   "median"
# [9] "p25"   "p75"   "min"    "max"    "iqr"   "sum"

# Select a subset:
continuous_summary_fns(c("N", "mean", "sd", "median", "p25", "p75"))
# Returns a named list of functions
```

---

## 8. The conceptual shift for SAS programmers

If you've spent years writing `PROC FREQ` and `PROC MEANS` outputs flowing directly into RTF macros, the ARD approach feels indirect. You're computing numbers into a tibble that doesn't look like a table yet. The indirection is the point.

Here's the mental model translation:

| SAS programmer's mental model | ARD-first mental model |
|---|---|
| My PROC MEANS **produces the table** | My `ard_continuous()` produces the **numbers**; the table is built separately |
| I reformat by changing the PROC code | I reformat by changing the display layer; the numbers don't change |
| Dual programming = run twice, compare RTF | Dual programming = build two ARDs, compare with `dplyr::anti_join()` |
| My output dataset has columns like `MEAN`, `STD` | My ARD has rows with `stat_name = "mean"`, `stat_name = "sd"` |
| My Big-N is computed separately and merged | My Big-N is `stat_name = "N"` rows in the ARD, or `.total_n = TRUE` |
| I can't easily re-use calculations | One ARD → infinite displays |

**The practical test**: Can you answer "what is the mean age in the Placebo arm?" from your analysis artifact without re-running code or reading a formatted table? With an ARD: yes — one filter, one `[[1]]` unwrap. With a traditional TLG: you'd need to re-run PROC MEANS or OCR the PDF.

---

## 9. The full ARD-producing function list

Here is a catalog of all `{cards}` constructors and their purposes:

| Function | Input type | Statistic type | SAS equivalent |
|---|---|---|---|
| `ard_continuous()` | Numeric variable | N, mean, sd, median, quartiles, min, max | `PROC MEANS` |
| `ard_categorical()` | Factor/character variable | n, N, p per level | `PROC FREQ` |
| `ard_hierarchical()` | Nested factor variables | Nested n, N, p (SOC × PT) | Nested `PROC FREQ` |
| `ard_complex()` | Any variable + full data | Custom functions | `PROC SQL` custom aggregates |
| `ard_total_n()` | Any dataset | Total N | `PROC FREQ` one-way |
| `ard_missing()` | Any variable | Missingness statistics | `PROC FREQ` with MISSING option |
| `ard_attributes()` | Variable metadata | Labels, types | `PROC CONTENTS` |
| `ard_dichotomous()` | Binary variable | True/False counts/proportions | `PROC FREQ` one-level |

And from `{cardx}` (covered in Lesson 27):

| Function | Statistic type | SAS equivalent |
|---|---|---|
| `ard_stats_t_test()` | t-test | `PROC TTEST` |
| `ard_stats_chisq_test()` | Chi-squared | `PROC FREQ` chi-sq option |
| `ard_stats_fisher_test()` | Fisher's exact | `PROC FREQ` exact option |
| `ard_regression()` | Regression coefficients | `PROC REG`, `PROC LOGISTIC`, `PROC PHREG` |
| `ard_survival_survfit()` | K-M estimates | `PROC LIFETEST` |
| `ard_survival_survdiff()` | Log-rank test | `PROC LIFETEST` log-rank |
| `ard_proportion_ci()` | Proportion CIs (Wilson, etc.) | Not directly available in base SAS |
| `ard_continuous_ci()` | Mean CIs | `PROC MEANS CLM` |
| `ard_aov()` | ANOVA | `PROC GLM` / `PROC MIXED` |
| `ard_emmeans()` | Estimated marginal means | `PROC MIXED LSMEANS` |
| `ard_smd()` | Standardized mean differences | Not in base SAS |

---

## 10. Performance considerations for large ARDs

For studies with many parameters, visits, and arms, ARDs can have thousands of rows. Cards handles this gracefully, but here are production tips:

```r
# 1. Always limit statistics to only what you need:
ard_continuous(
  adlb |> filter(SAFFL == "Y"),
  by = c("PARAMCD", "AVISIT", "TRTA"),
  variables = c("AVAL", "CHG"),
  statistic = ~ continuous_summary_fns(c("N", "mean", "sd"))  # not all 11 defaults!
)

# 2. Filter data before passing — don't compute on the full dataset then subset the ARD:
adlb_filtered <- adlb |> filter(PARAMCD %in% c("ALT", "AST", "HGB") & ANL01FL == "Y")
ard_lab <- ard_continuous(adlb_filtered, ...)

# 3. For very large hierarchical analyses, consider building separate ARDs per PARAMCD
# and bind_ard() at the end:
lab_ardslist <- split(adlb_filtered, adlb_filtered$PARAMCD) |>
  lapply(function(df) {
    ard_continuous(df, by = c("AVISIT", "TRTA"), variables = c("AVAL", "CHG"),
                   statistic = ~ continuous_summary_fns(c("N", "mean", "sd")))
  })
full_lab_ard <- do.call(bind_ard, lab_ardslist)

# 4. Use check_ard_structure() as a CI gate in your pipeline:
stopifnot(is.null(check_ard_structure(full_lab_ard)))
```

---

## 11. Saving, loading, and versioning ARDs

ARDs are just tibbles. Standard R I/O applies:

```r
# RDS (recommended for R-internal use — preserves list columns perfectly):
saveRDS(demog_ard, "ards/demog_ard.rds")
demog_ard <- readRDS("ards/demog_ard.rds")

# CSV/Parquet (for sharing with non-R systems — loses list-column structure):
# Use cards::as.data.frame() or tidyr::unnest() to flatten first
demog_ard_flat <- demog_ard |>
  mutate(stat_value = map(stat, ~ if (!is.null(.x[[1]])) as.numeric(.x[[1]]) else NA_real_)) |>
  tidyr::unnest(stat_value) |>
  select(-stat, -fmt_fn, -warning, -error)
readr::write_csv(demog_ard_flat, "ards/demog_ard_flat.csv")

# For CDISC ARS-aligned JSON submission (emerging standard):
# Tools for converting cards ARDs to ARS JSON are in development (2025-2026)
```

**Why version control your ARDs?** An ARD checked into git provides a historical record of what the numbers were at any point in the project. When a value changes between study snapshots, `git diff` on the ARD flat file shows exactly which statistic changed and by how much. This is a powerful audit trail.

---

## 12. Where cards fits in the Cardinal-future stack

```
ADaM data
   │
   ▼
{cards}     ← descriptive ARDs (you are here)
{cardx}     ← inferential ARDs (Lesson 27)
   │
   ▼
{gtsummary} ← display (Lessons 28–29)
{tfrmt}     ← display metadata (Lesson 32)
   │
   ▼
.docx / .rtf / .html
```

`{cards}` makes the ARD. Everything downstream consumes it. Get the ARD right, and the display becomes a thin transformation.

---

## 13. Key takeaways

- A `{cards}` ARD has 10 standard columns: `group1/group1_level`, `variable`, `variable_level` (categorical only), `stat_name`, `stat_label`, `stat`, `fmt_fn`, `context`, `warning`, `error`
- `stat` is a **list column** — unwrap with `[[1]]`, `getElement(1)`, or `get_ard_statistics()`
- `fmt_fn` is also a list column holding display formatting functions
- Four constructors: `ard_continuous()` (numeric), `ard_categorical()` (factor), `ard_hierarchical()` (nested), `ard_complex()` (custom)
- `ard_stack()` combines multiple constructors; `bind_ard()` combines pre-built ARDs
- `denominator` argument is critical for AE incidence — use ADSL safety pop as denominator
- Factor-type categorical variables to ensure zero-count levels appear in the ARD
- Errors are captured per-row, not raised — use `print_ard_conditions()` to inspect
- `check_ard_structure()` validates ARD structure; use it as a pipeline gate
- `continuous_summary_fns()` returns named function lists for common stats; limit to what your SAP requires

---

## 14. What's next

Lesson 26 — **`{cards}` Part 2** — works through a complete clinical ARD pipeline: demographics, AE incidence, lab change-from-baseline, vital signs, exposure, and concomitant medications. We'll build the full set of ARDs for a study and see how they connect into the display layer.

---

## Self-check questions

1. Why is `stat` a list column rather than a simple numeric column? Name two ways to extract the actual value.
2. What does `.overall = TRUE` add to an `ard_stack()` result? What column value identifies those rows?
3. You need "N, mean, SD of AGE by TRT01A with the safety population." Write the complete `{cards}` call.
4. Your AE incidence analysis returns percentages that seem too high. What's the likely cause, and how do you fix it with the `denominator` argument?
5. What is `context` and why is it useful when you've used `bind_ard()` to combine multiple ARDs?
6. Translate SAS: `PROC FREQ DATA=adae; TABLES ARM * AEBODSYS * AEDECOD; WHERE SAFFL='Y' AND TRTEMFL='Y'; RUN;` to cards.
7. A colleague's `ard_continuous()` call throws no error, but the resulting ARD has wrong statistics. What two utility functions should you call to investigate?

---

## Glossary

- **ARD** — Analysis Results Dataset; tidy tibble of computed statistics, one row per statistic
- **`stat`** — List column holding the computed value; must be unwrapped to use as a number
- **`fmt_fn`** — List column holding the display formatting function per statistic
- **`stat_name`** — Machine-readable statistic key (e.g., `"mean"`, `"n"`, `"p"`)
- **`stat_label`** — Human-readable display label (e.g., `"Mean"`, `"n"`, `"%"`)
- **`context`** — Which `ard_*()` family produced each row
- **`group1` / `group1_level`** — Grouping variable name and its value for each row
- **`variable_level`** — For categorical ARDs: the level being counted (e.g., `"Female"`)
- **`ard_continuous()`** — Summary stats for numeric variables (PROC MEANS equivalent)
- **`ard_categorical()`** — Count/proportion stats for categorical variables (PROC FREQ equivalent)
- **`ard_hierarchical()`** — Nested categorical counts (SOC × PT pattern)
- **`ard_complex()`** — Custom summaries with arbitrary functions
- **`ard_stack()`** — Run multiple constructors in one call and combine outputs
- **`bind_ard()`** — Combine pre-built ARDs with structure enforcement
- **`denominator`** — Controls the N for proportion calculations; pass a data frame for population-based N
- **`.overall = TRUE`** — Add an "All subjects" column to `ard_stack()` output
- **`.total_n = TRUE`** — Add Big-N rows per group in `ard_stack()` output
- **`continuous_summary_fns()`** — Helper returning named list of summary functions by name
- **`check_ard_structure()`** — Validate ARD column presence and types
- **`print_ard_conditions()`** — Print any captured warnings and errors
- **`get_ard_statistics()`** — Extract named statistic values from an ARD by filter condition
- **Big-N** — Total subject count per arm; denominator for all proportion calculations
