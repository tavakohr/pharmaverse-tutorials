# Lesson 01 — The ARS/ARD Paradigm: Architecture, Structure, and the SAS Programmer's Path Forward

**Module**: 0 — Introduction
**Estimated length**: ~45 min spoken
**Prerequisites**: Lesson 00 (Pharmaverse overview)

---

## Learning objectives

By the end of this lesson, you will be able to:

1. Explain why traditional layout-coupled TLG generation creates long-term technical debt
2. Define ARS (Analysis Results Standard), ARD (Analysis Results Dataset), and ARM — and distinguish them precisely
3. Describe the full CDISC ARS logical model: what it contains and why each component exists
4. Read and interpret a CDISC ARS JSON structure at a conceptual level
5. Name every column in a `{cards}` ARD and explain what each stores, with real example values
6. Map ARS concepts (analysisSets, analysisGroupings, methods) to ARD columns
7. Translate common SAS procedures (PROC FREQ, PROC MEANS, PROC LIFETEST) into their ARD-first R equivalents
8. Articulate where `{siera}` fits in the ARS → ARD automation pipeline
9. Identify the pharmaverse packages aligned with ARD-first TLG generation

---

## 1. The problem with how we've always done TLGs

Let me describe the traditional TLG workflow. You've lived it.

You receive shells for a demographics table. You write SAS code — maybe `PROC FREQ`, maybe `PROC MEANS`, maybe a `DATA` step calculating percentages by hand. The code produces output. You feed the output to a reporting macro that adds titles, footnotes, page breaks, decimals — and out comes an RTF file.

Now your medical writer wants a different breakdown: by age group instead of treatment. You modify the code. The calculations are re-done. A new RTF file comes out.

Now QA wants to verify a single number. They can read it off the RTF, but the number is the *output* of a calculation. To verify it, they need to re-run code, re-derive populations, re-summarize. Often, dual programming means writing the same logic twice and comparing *RTF outputs*, hoping the dual programmer made the same data preparation choices.

Now Health Authority A wants the table in one format and Health Authority B wants it in another. You don't have the option of "just reformatting" — your code mixes the *analysis logic* with the *display logic*, and unwinding them means rewriting.

**The core problem: analysis and presentation are tangled together.**

Every traditional clinical TLG codebase suffers from this. The calculation of "mean age in the safety population" and the *display* of `45.3 (12.1)` formatted in a cell are inseparable in the code. Change one, you risk breaking the other.

## 2. The CDISC vision: separate the analysis from the display

CDISC saw this problem. The **Analysis Results Standard (ARS)** is their answer.

The core idea: **what if every statistic in a clinical study could be stored in a structured, machine-readable dataset — completely independent of how it's eventually displayed?**

Instead of an RTF with `45.3 (12.1)` in a cell, you'd have structured rows:

| variable | statistic | value | population | group |
|---|---|---|---|---|
| AGE | N | 124 | Safety | Xanomeline High Dose |
| AGE | mean | 45.3 | Safety | Xanomeline High Dose |
| AGE | sd | 12.1 | Safety | Xanomeline High Dose |
| AGE | median | 46.0 | Safety | Xanomeline High Dose |

That dataset is an **Analysis Results Dataset (ARD)**. Once you have an ARD:

- **Multiple displays from one source.** RTF, HTML, PowerPoint, a Shiny app — all driven from the same canonical numbers.
- **QA by row lookup.** Verifying mean age = 45.3 means checking one cell in a dataset, not parsing a PDF.
- **Regulatory reuse.** A reviewer can pull your ARD into their own analysis system — they don't need to re-derive anything.
- **Meta-analysis support.** Combine ARDs across studies; you have structured statistics ready to pool.
- **Submission as data.** The ARD becomes a submission artifact alongside the display.

---

## 3. ARS, ARM, ARD — precise definitions

Three related terms are used imprecisely in industry conversation. Here are the exact meanings:

**ARS — Analysis Results Standard**
The overarching CDISC standard. It's a *specification* (a model), not a file or dataset. ARS defines:
- What an analysis is (a named set of operations on defined data)
- How analyses should be organized (grouped, ordered, linked to outputs)
- What the results should look like in machine-readable form (the ARD)
- How this information should be serialized (as JSON or XLSX)

Version 1.0 was published by CDISC in April 2024. This is the official standard you'll reference for submissions.

**ARM — Analysis Results Metadata**
The older precursor concept (pre-ARS). ARM focused narrowly on encoding analysis *specifications* — what variable, what population, what statistic. ARS is the broader successor that folds ARM in and adds the results data model. You'll still see "ARM" used loosely in older documents, but conceptually it's now part of ARS.

**ARD — Analysis Results Dataset**
The actual *data file* containing computed results. An ARD is what you get when you take ADaM data and apply the analysis specifications from an ARS document. It's a tidy dataset — one row per statistic — structured according to the ARS model.

The relationship:

```
ARS (Standard / Spec)
  ├── defines: what an analysis is, how it's organized
  ├── serializes to: JSON (official) or XLSX (readable)
  └── when executed against ADaM data → produces: ARD (Dataset)

ARS JSON  ──[siera readARS()]──→  R scripts
R scripts  ──[run against ADaM]──→  ARD (tidy tibble)
```

In practice, when people say "ARD-first programming," they mean: **compute everything into an ARD first, then transform the ARD into displays as a separate, independent step.**

---

## 4. The CDISC ARS logical model — what's in an ARS specification

Understanding ARS properly requires knowing what the specification actually contains. An ARS file (JSON or XLSX) for a Reporting Event describes six major components:

### 4.1 reportingEvent

The top-level container. One ARS file = one Reporting Event (e.g., an integrated summary of safety, a CSR, a specific submission package).

```json
{
  "id": "RE_APX-DRM-301-CSR",
  "version": "1.0",
  "name": "APX-DRM-301 Phase 3 Clinical Study Report",
  "listOfContents": {...},
  "analysisSets": [...],
  "analysisGroupings": [...],
  "dataSubsets": [...],
  "analyses": [...],
  "methods": [...],
  "outputs": [...]
}
```

### 4.2 analysisSets — population definitions

An Analysis Set is a population filter: a rule that selects which subjects are included in an analysis. In SAS terms, think of a `WHERE` clause on ADSL.

```json
"analysisSets": [
  {
    "id": "AS_SAFETY",
    "label": "Safety Population",
    "condition": {
      "dataset": "ADSL",
      "variable": "SAFFL",
      "comparator": "EQ",
      "value": ["Y"]
    }
  },
  {
    "id": "AS_ITT",
    "label": "Intent-to-Treat Population",
    "condition": {
      "dataset": "ADSL",
      "variable": "ITTFL",
      "comparator": "EQ",
      "value": ["Y"]
    }
  }
]
```

**SAS translation**: `WHERE SAFFL = "Y"` in your DATA step or PROC step.
**ARD impact**: The analysis set determines which rows go into the `{cards}` call. In your R pipeline you `filter(SAFFL == "Y")` before calling `ard_continuous()`.

### 4.3 analysisGroupings — treatment column definitions

An Analysis Grouping defines how results are split across groups — most commonly, treatment arms. This determines what becomes the `by` variable in `{cards}`.

```json
"analysisGroupings": [
  {
    "id": "AG_TREATMENT",
    "label": "Treatment Group",
    "groups": [
      {"id": "AG_TRT_PBO",   "label": "Placebo",             "condition": {"variable": "ARM", "comparator": "EQ", "value": ["Placebo"]}},
      {"id": "AG_TRT_LOW",   "label": "UPADALIMIB 15 mg",    "condition": {"variable": "ARM", "comparator": "EQ", "value": ["UPADALIMIB 15 mg"]}},
      {"id": "AG_TRT_HIGH",  "label": "UPADALIMIB 30 mg",    "condition": {"variable": "ARM", "comparator": "EQ", "value": ["UPADALIMIB 30 mg"]}}
    ]
  }
]
```

**SAS translation**: `CLASS TRT01A` in PROC MEANS, or `BY TRT01A` in PROC FREQ.
**ARD impact**: This becomes the `by = "TRT01A"` argument in `ard_continuous()` / `ard_categorical()`. Each group gets its own set of rows in the ARD, identified by `group1` and `group1_level`.

### 4.4 dataSubsets — row-level filters within a dataset

A Data Subset is an additional filter applied to the analysis dataset *after* the population has been applied. Think: filtering ADAE to treatment-emergent events, or restricting ADLB to a specific parameter.

```json
"dataSubsets": [
  {
    "id": "DS_TEAE",
    "label": "Treatment-Emergent Adverse Events",
    "condition": {
      "dataset": "ADAE",
      "variable": "TRTEMFL",
      "comparator": "EQ",
      "value": ["Y"]
    }
  },
  {
    "id": "DS_SERIOUS_TEAE",
    "label": "Serious TEAEs",
    "compoundExpression": {
      "logicalOperator": "AND",
      "whereClauses": [
        {"variable": "TRTEMFL", "comparator": "EQ", "value": ["Y"]},
        {"variable": "AESER",   "comparator": "EQ", "value": ["Y"]}
      ]
    }
  }
]
```

**SAS translation**: `WHERE TRTEMFL = "Y"` or `WHERE TRTEMFL = "Y" AND AESER = "Y"`.
**ARD impact**: Your `filter()` calls before passing to `{cards}`. These become the dataset filtering steps in a siera-generated R script.

### 4.5 methods — statistical operations

An Analysis Method defines the statistical operation: what functions to apply, to what variables, to produce what statistics.

```json
"methods": [
  {
    "id": "MTH_SUMMARY_STATISTICS_CONTINUOUS",
    "label": "Summary Statistics for Continuous Variables",
    "operations": [
      {"id": "OP_N",      "label": "n",      "resultPattern": "integer"},
      {"id": "OP_MEAN",   "label": "Mean",   "resultPattern": "decimal(1)"},
      {"id": "OP_SD",     "label": "SD",     "resultPattern": "decimal(2)"},
      {"id": "OP_MEDIAN", "label": "Median", "resultPattern": "decimal(1)"},
      {"id": "OP_MIN",    "label": "Min",    "resultPattern": "integer"},
      {"id": "OP_MAX",    "label": "Max",    "resultPattern": "integer"}
    ]
  },
  {
    "id": "MTH_COUNT_AND_PERCENTAGE",
    "label": "Count and Percentage",
    "operations": [
      {"id": "OP_N",   "label": "n",   "resultPattern": "integer"},
      {"id": "OP_PCT", "label": "%",   "resultPattern": "decimal(1)"}
    ]
  }
]
```

**SAS translation**: The PROC MEANS `VAR` and statistics options, or PROC FREQ `TABLES` with `/ OUT=`. The `resultPattern` encodes the display format (decimal places).
**ARD impact**: Operations map directly to rows in the ARD. Each operation becomes a distinct `stat_name` / `stat_label` pair. `MTH_SUMMARY_STATISTICS_CONTINUOUS` maps to `ard_continuous()`. `MTH_COUNT_AND_PERCENTAGE` maps to `ard_categorical()`.

### 4.6 analyses — the bridge between method, data, and output

An Analysis connects all the pieces: a specific method applied to specific variables in a specific population with specific groupings, producing results for a specific output.

```json
"analyses": [
  {
    "id": "AN_DEMOG_AGE",
    "name": "Summary of Age",
    "dataset": "ADSL",
    "variable": "AGE",
    "analysisSetId": "AS_SAFETY",
    "analysisGroupingId": "AG_TREATMENT",
    "methodId": "MTH_SUMMARY_STATISTICS_CONTINUOUS",
    "outputId": "T_DEMOG"
  },
  {
    "id": "AN_DEMOG_SEX",
    "name": "Frequency of Sex",
    "dataset": "ADSL",
    "variable": "SEX",
    "analysisSetId": "AS_SAFETY",
    "analysisGroupingId": "AG_TREATMENT",
    "methodId": "MTH_COUNT_AND_PERCENTAGE",
    "outputId": "T_DEMOG"
  }
]
```

**Reading this in English**: "For output T_DEMOG, analyze AGE from ADSL, using the Safety Population, split by Treatment, computing N/Mean/SD/Median/Min/Max."

**ARD impact**: One analysis = one `ard_*()` call. The ARD rows from this analysis will carry `AnalysisId = "AN_DEMOG_AGE"` as a traceability column.

---

## 5. The ARD column anatomy — every column explained

A `{cards}` ARD is a tibble with a defined column structure. Here is every column with its meaning, data type, and a real example value.

### The complete ARD column specification

| Column | Type | What it contains | Example value |
|---|---|---|---|
| `group1` | `<chr>` | Name of the first grouping variable | `"TRT01A"` |
| `group1_level` | `<chr>` | Value of the first grouping variable for this row | `"Placebo"` |
| `group2` | `<chr>` | Name of the second grouping variable (if nested) | `"AVISIT"` |
| `group2_level` | `<chr>` | Value of the second grouping variable | `"Week 4"` |
| `variable` | `<chr>` | The variable being summarized | `"AGE"` |
| `variable_level` | `<chr>` | For categorical variables: the level being counted | `"Female"` (for SEX) |
| `stat_name` | `<chr>` | Machine-readable statistic identifier | `"mean"` |
| `stat_label` | `<chr>` | Human-readable label for the statistic | `"Mean"` |
| `stat` | `<list>` | **A list column.** The computed value, stored as a list element | `list(75.2)` → prints as `75.2` |
| `fmt_fn` | `<list>` | A list column holding the formatting function | `list(function(x) formatC(x, digits=1))` |
| `context` | `<chr>` | The `ard_*()` function family that produced this row | `"continuous"` |
| `warning` | `<list>` | Any warning message from the calculation | `list(NULL)` if no warning |
| `error` | `<list>` | Any error message from the calculation | `list(NULL)` if no error |

> **Critical detail about `stat`**: The `stat` column is a **list column**, not a simple numeric column. Each cell contains a list with one element: the computed value. This is why you see `<dbl>` printed inside `<list>` tags. To extract the actual numeric value: `ard$stat[[row_number]]` or use `get_ard_statistics()`. This design allows `stat` to hold any R object (a number, a vector, a model object).

> **Critical detail about `fmt_fn`**: This is a list column of functions. It stores the recommended display formatting function for each statistic. For example, the formatting function for `mean` might format to 1 decimal place; for `N` it formats as an integer. These functions are used by `{gtsummary}` to format display values.

For multi-level groupings (e.g., PARAMCD × AVISIT × TRTA), cards adds `group2`, `group2_level`, `group3`, `group3_level` columns automatically. The column count adapts to how many `by` variables you specify.

### What a real ARD looks like — row by row

Here is an annotated real ARD output for a demographics analysis:

```r
library(cards)
library(pharmaverseadam)
library(dplyr)

adsl <- pharmaverseadam::adsl |> filter(SAFFL == "Y")

ard_continuous(adsl, by = "TRT01A", variables = "AGE") |>
  select(group1, group1_level, variable, stat_name, stat_label, stat, context)
```

```
# A tibble: 24 × 7
   group1 group1_level          variable stat_name stat_label stat       context
   <chr>  <chr>                 <chr>    <chr>     <chr>      <list>     <chr>
 1 TRT01A Placebo               AGE      N         N          <int [1]>  continuous
 2 TRT01A Placebo               AGE      mean      Mean       <dbl [1]>  continuous
 3 TRT01A Placebo               AGE      sd        SD         <dbl [1]>  continuous
 4 TRT01A Placebo               AGE      median    Median     <dbl [1]>  continuous
 5 TRT01A Placebo               AGE      p25       Q1         <dbl [1]>  continuous
 6 TRT01A Placebo               AGE      p75       Q3         <dbl [1]>  continuous
 7 TRT01A Placebo               AGE      min       Min        <int [1]>  continuous
 8 TRT01A Placebo               AGE      max       Max        <int [1]>  continuous
 9 TRT01A Xanomeline Low Dose   AGE      N         N          <int [1]>  continuous
10 TRT01A Xanomeline Low Dose   AGE      mean      Mean       <dbl [1]>  continuous
...
```

Each row decodes unambiguously:
- Row 1: `group1 = "TRT01A"`, `group1_level = "Placebo"`, `variable = "AGE"`, `stat_name = "N"` → the count of subjects with non-missing AGE in the Placebo arm, Safety Population.
- Row 2: Same arm, same variable, `stat_name = "mean"` → mean age in the Placebo arm.

To get the actual number out of row 2:

```r
ard <- ard_continuous(adsl, by = "TRT01A", variables = "AGE")

# Pull mean age for Placebo:
ard |>
  filter(group1_level == "Placebo" & stat_name == "mean") |>
  pull(stat) |>
  getElement(1)  # unwrap the list
# [1] 75.209

# Or use the helper function:
get_ard_statistics(ard,
  filter = group1_level == "Placebo" & stat_name == "mean"
)
# Returns: list(mean = 75.209)
```

For a **categorical variable** (e.g., SEX), the ARD adds the `variable_level` column:

```r
ard_categorical(adsl, by = "TRT01A", variables = "SEX") |>
  select(group1, group1_level, variable, variable_level, stat_name, stat)
```

```
   group1  group1_level          variable  variable_level  stat_name  stat
1  TRT01A  Placebo               SEX       F               n          <int>   ← n females, Placebo
2  TRT01A  Placebo               SEX       F               N          <int>   ← total Placebo subjects
3  TRT01A  Placebo               SEX       F               p          <dbl>   ← proportion female, Placebo
4  TRT01A  Placebo               SEX       M               n          <int>
5  TRT01A  Placebo               SEX       M               N          <int>
6  TRT01A  Placebo               SEX       M               p          <dbl>
...
```

---

## 6. The ARS → ARD mapping: from specification to data

Here is the explicit mapping from each ARS component to what it becomes in the ARD:

| ARS Component | ARS JSON Key | Effect on ARD |
|---|---|---|
| Analysis Set | `analysisSets[].condition` | The `filter()` applied to ADaM before the `ard_*()` call. Does **not** appear as a column in the ARD (it's pre-processing). |
| Analysis Grouping | `analysisGroupings[].groups` | Becomes the `by = ` argument in `ard_*()`. Each group value appears in `group1_level` (or `group2_level` etc.) in the ARD. |
| Data Subset | `dataSubsets[].condition` | A secondary `filter()` applied after the population filter. Also pre-processing; not directly a column. |
| Method → Operation | `methods[].operations[].id` | Becomes a row's `stat_name`. E.g., `OP_MEAN` → `stat_name = "mean"`. |
| Method → Operation label | `methods[].operations[].label` | Becomes `stat_label`. E.g., `"Mean"` → `stat_label = "Mean"`. |
| Analysis → variable | `analyses[].variable` | Becomes the `variable` column in the ARD. |
| Analysis → dataset | `analyses[].dataset` | Determines which ADaM to load; not directly in ARD columns. |
| Analysis → id (traceability) | `analyses[].id` | Appears as a traceability column `AnalysisId` added post-hoc (siera adds this; base `{cards}` doesn't). |
| Output → id (traceability) | `outputs[].id` | Appears as `OutputId` traceability column added by siera. |

**The key insight for programmers**: the ARD is the *output* of executing an ARS specification against ADaM data. The ARS spec says *what* to compute; the ARD contains the *results*.

---

## 7. The SAS programmer's translation guide

If you've spent your career with SAS procedures, here is the direct translation to ARD-first R:

### PROC MEANS → `ard_continuous()`

**SAS:**
```sas
proc means data=adsl n mean std median min max;
  class trt01a;
  var age bmibl weightbl;
  where saffl = 'Y';
run;
```

**R (ARD-first):**
```r
adsl |>
  filter(SAFFL == "Y") |>
  ard_continuous(
    by = "TRT01A",
    variables = c("AGE", "BMIBL", "WEIGHTBL"),
    statistic = ~ continuous_summary_fns(c("N", "mean", "sd", "median", "min", "max"))
  )
```

The key difference: PROC MEANS writes a formatted table. `ard_continuous()` writes tidy rows — one per statistic per variable per group. The display is a separate step.

### PROC FREQ → `ard_categorical()`

**SAS:**
```sas
proc freq data=adsl;
  tables trt01a * (sex agegr1 race) / nocum nopercent;
  where saffl = 'Y';
run;
```

**R (ARD-first):**
```r
adsl |>
  filter(SAFFL == "Y") |>
  ard_categorical(
    by = "TRT01A",
    variables = c("SEX", "AGEGR1", "RACE")
  )
```

PROC FREQ produces cross-tabulation cells. `ard_categorical()` produces one row per (arm × variable level × statistic). The `n`, `N`, and `p` stats in the ARD are the equivalent of PROC FREQ's frequency and percentage output.

### PROC FREQ with denominator control → `ard_categorical(denominator = )`

**SAS (AE incidence — using explicit N from ADSL):**
```sas
/* First get N per arm from ADSL */
proc freq data=adsl noprint;
  tables trt01a / out=bign(rename=(count=n_arm));
  where saffl = 'Y';
run;

/* Then compute AE counts and merge on the N */
proc freq data=adae noprint;
  tables trt01a * aedecod / out=ae_freq;
  where saffl = 'Y' and trtemfl = 'Y';
run;

data ae_incidence;
  merge ae_freq bign;
  by trt01a;
  pct = count / n_arm * 100;
run;
```

**R (ARD-first):**
```r
adae |>
  filter(SAFFL == "Y" & TRTEMFL == "Y") |>
  ard_categorical(
    by = "TRT01A",
    variables = "AEDECOD",
    denominator = adsl |> filter(SAFFL == "Y")   # ← N comes from ADSL
  )
```

The `denominator` argument replaces the SAS pattern of computing separate Big-N datasets and merging them back. In the ARD, `stat_name = "N"` will be the safety-population N from ADSL, not the event count from ADAE.

### PROC FREQ with nested hierarchy → `ard_hierarchical()`

**SAS (AE by SOC and PT):**
```sas
proc freq data=adae noprint;
  tables arm * aebodsys * aedecod / out=ae_hier;
  where saffl = 'Y' and trtemfl = 'Y';
run;
```

**R (ARD-first):**
```r
adae |>
  filter(SAFFL == "Y" & TRTEMFL == "Y") |>
  ard_hierarchical(
    by = "ARM",
    variables = c("AEBODSYS", "AEDECOD"),
    denominator = adsl |> filter(SAFFL == "Y")
  )
```

`ard_hierarchical()` handles the nested tabulation correctly: counts at the SOC level are distinct-subject counts within SOC, and counts at the PT level are distinct-subject counts within SOC×PT — the correct behavior for "patients with events" rather than "event occurrences."

### PROC LIFETEST → `ard_survival_survfit()` (from `{cardx}`)

**SAS (K-M median survival):**
```sas
proc lifetest data=adtte method=km plots=(survival);
  time aval * cnsr(1);
  strata trta;
  where paramcd = 'OS';
run;
```

**R (ARD-first, via `{cardx}`):**
```r
library(cardx)
library(survival)

adtte |>
  filter(PARAMCD == "OS") |>
  ard_survival_survfit(
    y = Surv(AVAL, 1 - CNSR),  # Note: ADTTE CNSR=1 means censored; Surv() event=1 means event
    variables = "TRTA",
    probs = 0.5                  # median
  )
```

> **SAS→R censoring warning**: In ADTTE, `CNSR = 1` means *censored* (no event). In `survival::Surv()`, the second argument is the *event indicator* where `1 = event occurred*. Always convert: `Surv(AVAL, 1 - CNSR)`.

### PROC PHREG → `ard_regression()` (from `{cardx}`)

**SAS (Cox proportional hazards):**
```sas
proc phreg data=adtte;
  class trta (ref='Placebo') / param=ref;
  model aval * cnsr(1) = trta age sex;
  where paramcd = 'OS';
run;
```

**R (ARD-first):**
```r
cox_model <- coxph(
  Surv(AVAL, 1 - CNSR) ~ TRTA + AGE + SEX,
  data = adtte |> filter(PARAMCD == "OS")
)
ard_regression(cox_model)
```

### PROC MIXED → `ard_regression()` with `lme4` or `mmrm`

**SAS (MMRM for repeated measures):**
```sas
proc mixed data=advs;
  class trta usubjid avisit;
  model chg = base trta avisit trta*avisit / solution;
  repeated avisit / subject=usubjid type=un;
  where paramcd = 'WEIGHT';
run;
```

**R (ARD-first, via `{cardx}` + `{mmrm}`):**
```r
library(mmrm)
library(cardx)

mmrm_fit <- mmrm(
  formula = CHG ~ BASE + TRTA + AVISIT + TRTA:AVISIT + us(AVISIT | USUBJID),
  data = advs |> filter(PARAMCD == "WEIGHT")
)
ard_regression(mmrm_fit)
```

### Complete SAS → R translation table

| SAS Procedure | R ARD function | Package |
|---|---|---|
| `PROC MEANS` | `ard_continuous()` | `{cards}` |
| `PROC FREQ` | `ard_categorical()` | `{cards}` |
| `PROC FREQ` (nested hierarchy) | `ard_hierarchical()` | `{cards}` |
| `PROC FREQ` + custom denominator merge | `ard_categorical(denominator=)` | `{cards}` |
| `PROC UNIVARIATE` | `ard_continuous()` with extended stats | `{cards}` |
| `PROC TTEST` | `ard_stats_t_test()` | `{cardx}` |
| `PROC FREQ` chi-square | `ard_stats_chisq_test()` | `{cardx}` |
| `PROC FREQ` Fisher's exact | `ard_stats_fisher_test()` | `{cardx}` |
| `PROC LIFETEST` | `ard_survival_survfit()` | `{cardx}` |
| `PROC PHREG` | `ard_regression(coxph())` | `{cardx}` |
| `PROC MIXED` / MMRM | `ard_regression(mmrm())` | `{cardx}` |
| `PROC LOGISTIC` | `ard_regression(glm(family=binomial))` | `{cardx}` |
| `PROC GLM` | `ard_regression(lm())` or `ard_aov()` | `{cardx}` |

---

## 8. The full ARD-first workflow: three levels of abstraction

It's useful to think of ARD-first programming as having three layers:

```
┌─────────────────────────────────────────────────────┐
│ LAYER 1: SPECIFICATION (ARS JSON / XLSX)            │
│  analysisSets, analysisGroupings, methods, analyses │
│  "What to compute, on what data, for what groups"   │
└────────────────────┬────────────────────────────────┘
                     │  siera::readARS() generates scripts
                     │  arsbridge::ars_to_ard() executes directly
                     ▼
┌─────────────────────────────────────────────────────┐
│ LAYER 2: ARD (tidy dataset of results)              │
│  group1/group1_level, variable, stat_name, stat     │
│  "The computed numbers, one row per statistic"      │
└────────────────────┬────────────────────────────────┘
                     │  gtsummary, tfrmt, arsbridge::ars_render_tlf()
                     ▼
┌─────────────────────────────────────────────────────┐
│ LAYER 3: DISPLAY (TLG output)                       │
│  .rtf, .html, .docx, .pdf, Shiny                   │
│  "Formatted presentation of the numbers"            │
└─────────────────────────────────────────────────────┘
```

Each layer is independently testable and swappable. You can validate Layer 2 (the numbers) without worrying about Layer 3 (the display). You can change the display format without re-running Layer 2. This is the architectural payoff.

---

## 9. Introducing `{siera}` and `{arsbridge}`: ARS automation tools

Two R packages automate the ARS → ARD pipeline. Understanding them now will pay dividends in later lessons.

### `{siera}` — ARS metadata → R scripts → ARD

**Author**: Malan Bosman (Clymb Clinical)
**CRAN**: Yes
**Role**: Reads an ARS file (JSON or XLSX), generates one R script per output, and when those scripts are run, they produce ARDs.

The workflow:

```r
library(siera)

# Step 1: Provide paths
ARS_path    <- "path/to/study_ars.xlsx"   # or .json
output_dir  <- "programs/ARDs/"            # where R scripts go
ADaM_dir    <- "data/adam/"                # where .csv or .xpt ADaMs live

# Step 2: Generate R scripts (one per output defined in the ARS file)
readARS(ARS_path, output_dir, ADaM_dir)

# You now have, e.g.:
#   programs/ARDs/ARD_Out14-1-1.R     (demographics table)
#   programs/ARDs/ARD_Out14-3-1-1.R   (overall AE table)
#   ...

# Step 3: Run a script to get an ARD
source("programs/ARDs/ARD_Out14-1-1.R")
head(ARD)     # The ARD object is named "ARD" by convention
```

Each generated R script has a standard structure:
1. Program header (output ID, ARS version, date)
2. Library loads
3. Load ADaM datasets
4. For each analysis: apply population, apply data subset, apply method (via `{cards}`)
5. Append all analysis-level ARDs into one output-level ARD

This means that **as a programmer, you never write boilerplate R code from scratch for analysis derivation** — siera generates it from the spec. You review, validate, and run.

`{siera}` is covered in depth in Module 6 (Lesson 27). The important conceptual point now: **it represents the realization of the ARS vision** — going from a machine-readable specification (an ARS JSON or XLSX file) all the way to a tidy ARD, with the R code auto-generated from the metadata.

---

## 10. The pharmaverse stack for ARD-first programming

| Package | Role | Maintainer |
|---|---|---|
| `{cards}` | Build ARDs from ADaM data (descriptive stats) | Roche + GSK + Novartis (pharmaverse) |
| `{cardx}` | Extensions: regression, survival, statistical tests | Pharmaverse (same group) |
| `{gtsummary}` | Format ARDs into publication-ready tables | Dan Sjoberg (Roche) |
| `{tfrmt}` | Apply display metadata to ARDs (decimals, sorting) | GSK |
| `{cardinal}` | Pre-built TLG templates aligned with FDA Safety guidance | Pharmaverse multi-company |
| `{siera}` | ARS metadata → auto-generated ARD R scripts | Clymb Clinical |

A typical ARD-first workflow:

```
ADaM datasets (ADSL, ADAE, etc.)
        │
        ▼
  {cards} + {cardx}          ← build ARDs
        │
        ▼
       ARD                    ← canonical, structured results
      ╱ │ ╲
     ╱  │  ╲
    ▼   ▼   ▼
{gtsummary} {tfrmt} {arsbridge}   ← format into displays
    │   │   │
    ▼   ▼   ▼
  Final TLGs (.rtf, .html, .docx)
```

For the **ARS-driven path** (specification-first):

```
ARS JSON (spec)
      │
      └──[siera]──→ R scripts ──→ ARD ──→ {gtsummary}/{tfrmt}
```

---

## 11. The strategic picture: why this matters now

It's important to be honest about where the ARS standard is in its maturity:

**What's solid (as of 2024–2026):**
- CDISC ARS v1.0 was published April 2024. This is a finalized standard.
- The core ARD structure is well-defined and implemented in `{cards}`
- Major sponsors are running production pilots (Roche, GSK have published case studies)
- FDA has endorsed ARS-aligned approaches in its own standardization work
- siera (CRAN, v0.5.x) and arsbridge are production-ready tools

**What's still maturing:**
- Submission expectations for ARDs are not yet formalized across FDA/EMA (expected 2025–2027)
- Define-XML extensions describing ARDs are in development
- Some complex statistical methods (adaptive designs, complex multiplicity adjustments) don't yet have agreed ARS representations
- Cross-industry harmonization of analysis method IDs is ongoing

**The recommendation for programmers entering the field in 2025–2026**: Learn the ARD-first paradigm as your foundation. The tools are mature. The standard is finalized. Sponsors who master this now will have a significant advantage when regulatory mandates arrive.

---

## 12. Mental model — the one thing to take away

> **A "table" is two things: the computation and the layout. The computation should live in a dataset (the ARD). The layout should be applied as a separate, swappable step. Code that conflates the two is technical debt.**

This is the same principle that drove CDISC's separation of SDTM from ADaM. SDTM is the observed data, structured. ADaM is the analysis-ready transformation. ARS extends this one more step: ARD is the analysis *results*, structured. The final display is a rendering of the ARD, not the analysis itself.

Once you see it this way, traditional TLG code — where `PROC MEANS` output flows directly into a reporting macro that writes RTF cells — looks like a violation of separation of concerns. And it is.

---

## 13. How the rest of this curriculum reflects the ARD-first shift

- **Module 6 (TLG: Cardinal future stack)** covers the full ARD-first toolchain in depth: `{cards}`, `{cardx}`, `{gtsummary}`, `{tfrmt}`, `{cardinal}`, `{siera}`, `{arsbridge}`.
- **Module 7 (TLG: legacy stack)** covers `{rtables}`, `{tern}`, `{r2rtf}`, `{Tplyr}` — the dominant legacy stack you'll encounter in production environments.
- **Module 8 (Shiny / teal)** shows how ARDs feed into interactive clinical review applications.
- **The capstone** uses an ARD-first approach end-to-end.

---

## 14. Key takeaways

- Traditional TLG workflows tangle analysis and display — ARS/ARD separates them
- **ARS** is the CDISC standard (spec, v1.0 published April 2024); **ARD** is the resulting dataset
- ARS JSON contains: analysisSets (populations), analysisGroupings (treatment splits), dataSubsets (row filters), methods (operations), analyses (connections), outputs (table definitions)
- An ARD is a tidy tibble: one row per statistic, with `group1/group1_level`, `variable`, `stat_name`, `stat_label`, `stat`, `context`, `fmt_fn`, `warning`, `error`
- The `stat` column is a **list column** — each cell holds a list element; use `[[]]` or `get_ard_statistics()` to extract values
- SAS PROC MEANS → `ard_continuous()`; PROC FREQ → `ard_categorical()`; PROC LIFETEST → `ard_survival_survfit()`; PROC PHREG → `ard_regression(coxph())`
- `{siera}` reads ARS JSON/XLSX and generates R scripts that produce ARDs

---

## 15. What's next

In Lesson 02, we set up the development environment: R, RStudio, pharmaverse packages, and `{renv}`. Once your environment is working, you'll be ready to start writing R code. Module 1 then covers R fundamentals with SAS-programmer translations throughout.

Module 6 (starting at Lesson 25) is where we build ARDs hands-on. But you now have the conceptual architecture you need to understand *why* every step in that module is structured the way it is.

---

## Self-check questions

1. What are the six major components of an ARS JSON file? Describe what each contains.
2. What does the `stat` column in a `{cards}` ARD contain, and why is it a list column?
3. A SAS programmer asks: "where do I put my `WHERE SAFFL = 'Y'` filter in the R ARD pipeline?" What do you tell them?
4. What is the `denominator` argument in `ard_categorical()`, and which SAS pattern does it replace?
5. Translate: "PROC LIFETEST with `TIME aval * cnsr(1); STRATA trta;`" to ARD-first R.
6. What does `{siera}` take as input, and what does it produce?
7. Explain the censoring convention difference between ADTTE CNSR and `survival::Surv()`.
8. Name the three layers of the ARD-first architecture and what swapping each layer allows you to do independently.

---

## Glossary

- **ARS** — Analysis Results Standard; CDISC foundational standard v1.0 (April 2024)
- **ARD** — Analysis Results Dataset; tidy tibble of computed statistics, one row per statistic
- **ARM** — Analysis Results Metadata; precursor to ARS, now folded in
- **analysisSet** — ARS term for a population definition (e.g., Safety Population)
- **analysisGrouping** — ARS term for the split variable (e.g., treatment arm column)
- **dataSubset** — ARS term for a row-level filter on the analysis dataset
- **method** — ARS term for the statistical operations to perform (e.g., N/Mean/SD)
- **analysis** — ARS term connecting a method + variable + population + grouping + output
- **`stat`** — List column in ARD holding the computed value
- **`fmt_fn`** — List column in ARD holding the display formatting function
- **`stat_name`** — Machine-readable statistic identifier (e.g., `"mean"`, `"p"`)
- **`stat_label`** — Human-readable label (e.g., `"Mean"`, `"%"`)
- **`context`** — Which `ard_*()` constructor family produced this row
- **`{siera}`** — Package by Clymb Clinical; reads ARS metadata, generates ARD R scripts
- **Cardinal-future stack** — `{cards}` + `{cardx}` + `{gtsummary}` + `{tfrmt}` + `{cardinal}`
- **Big-N** — Total subject count per arm; denominator for proportion calculations
- **TRTEMFL** — Treatment-Emergent Flag; standard ADAE flag for AE incidence analyses
- **CNSR** — Censoring indicator in ADTTE; `1 = censored` (opposite of `survival::Surv()` convention)
