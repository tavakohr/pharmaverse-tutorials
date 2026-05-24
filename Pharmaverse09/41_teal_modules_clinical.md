# Lesson 41 — `{teal.modules.clinical}`: Clinical Module Library

**Module**: 8 — Interactive applications with Shiny and teal
**Estimated length**: ~28 min spoken
**Prerequisites**: Lessons 39-40 (teal architecture, teal.modules.general)

---

## Learning objectives

By the end of this lesson, you will be able to:

1. Navigate the 40+ clinical modules in `{teal.modules.clinical}` organized by analysis type
2. Build an AE-focused app using `tm_t_events_summary`, `tm_t_events`, `tm_t_events_by_grade`, `tm_t_smq`
3. Build a survival-focused app using `tm_g_km`, `tm_t_tte`, `tm_t_coxreg`
4. Build a lab-focused app using `tm_t_abnormality`, `tm_t_shift_by_grade`, `tm_t_summary_by`
5. Use patient profile modules (`tm_g_pp_*`) for medical-reviewer drill-downs
6. Combine modules into a complete CSR-companion teal app

---

## 1. The clinical module library

`{teal.modules.clinical}` provides ~40 pre-built clinical analysis modules. Each implements one specific CSR-style analysis as a Shiny module that fits into the teal framework.

These are not just clinical-flavored versions of general modules — they encode pharma-specific conventions:

- **Subject-level denominators** for AE rates (not event-level)
- **Standard MedDRA hierarchies** for AE displays
- **CDISC-standard variable names** (PARAMCD, AVAL, ARM, AVISIT, etc.)
- **Reference-arm comparisons** for treatment effect estimates
- **Standard survival conventions** (CNSR encoding, K-M with median + CIs)
- **Grade-based abnormality classification** for labs

Maintained by Roche NEST team; current version 0.12.x as of mid-2026. Built on top of `{tern}` and `{rtables}` (Module 7) for the underlying statistical computation — same engine that produces static CSR tables, just wrapped in interactive Shiny modules.

```r
install.packages("teal.modules.clinical")
library(teal.modules.clinical)
```

## 2. Module families

The ~40 modules group naturally:

| Family | Examples | Purpose |
|---|---|---|
| **Summary** | `tm_t_summary`, `tm_t_summary_by` | Demographics, baseline characteristics |
| **Adverse events** | `tm_t_events`, `tm_t_events_summary`, `tm_t_events_by_grade`, `tm_t_events_patyear`, `tm_t_smq` | All AE-related |
| **Survival** | `tm_g_km`, `tm_t_tte`, `tm_t_coxreg` | TTE endpoints |
| **Response** | `tm_t_binary_outcome`, `tm_t_rsp`, `tm_t_logistic` | Binary outcomes, response rates |
| **Lab/VS** | `tm_t_abnormality`, `tm_t_abnormality_by_worst_grade`, `tm_t_shift_by_grade`, `tm_t_shift_by_arm` | Lab shifts, abnormalities |
| **Change** | `tm_t_ancova`, `tm_g_lineplot` | Change-from-baseline analyses |
| **Exposure** | `tm_t_exposure` | Exposure summaries for RMP |
| **MMRM** | `tm_a_mmrm` | Mixed-model repeated measures |
| **Patient profile** | `tm_g_pp_adverse_events`, `tm_g_pp_patient_timeline`, `tm_g_pp_therapy`, `tm_g_pp_vitals` | Subject-level drill-down |
| **Plots** | `tm_g_ci`, `tm_g_barchart_simple`, `tm_g_forest_*` | Common clinical visualizations |

For a typical phase III CSR-companion app, you might use 10-15 of these. We'll cover the most common patterns.

## 3. The AE family in depth

Three modules typically combine for a complete AE story:

### `tm_t_events_summary` — AE overview

The first AE table in any CSR: counts of subjects with any TEAE, serious TEAE, severe TEAE, death from AE, discontinuation due to AE.

```r
tm_t_events_summary(
  label = "AE Overview",
  dataname = "ADAE",
  arm_var = choices_selected(c("ARM", "ACTARM"), "ARM"),
  flag_var_anl = choices_selected(c("TRTEMFL", "AEACN"), "TRTEMFL"),
  flag_var_aesi = choices_selected(c("AESERFL", "AERELFL"), "AESERFL")
)
```

Renders the canonical "Adverse Event Overview" table: arm columns; rows for each AE category with subject counts and percentages.

### `tm_t_events` — AE by SOC and PT

The detailed AE incidence table:

```r
tm_t_events(
  label = "AE Incidence",
  dataname = "ADAE",
  arm_var = choices_selected(c("ARM", "ACTARM"), "ARM"),
  llt = choices_selected(c("AETERM", "AEDECOD"), "AEDECOD"),
  hlt = choices_selected(c("AEBODSYS", "AESOC"), "AEBODSYS"),
  drop_arm_levels = TRUE
)
```

`hlt` = high-level term (SOC); `llt` = low-level term (PT). The module nests PTs within SOCs and shows subject counts/percentages per arm.

Users can change which SOC/PT variables to display — e.g., switch from `AESOC` to a custom SOC variable if your study uses a non-standard hierarchy.

### `tm_t_events_by_grade` — AE by severity grade

For oncology and other graded-toxicity studies:

```r
tm_t_events_by_grade(
  label = "AE by Grade",
  dataname = "ADAE",
  arm_var = choices_selected(c("ARM"), "ARM"),
  llt = choices_selected(c("AEDECOD"), "AEDECOD"),
  hlt = choices_selected(c("AEBODSYS"), "AEBODSYS"),
  grade = choices_selected(c("AETOXGR", "ATOXGR"), "AETOXGR")
)
```

Adds grade as an extra dimension: each cell shows counts at each grade level (1, 2, 3, 4, 5).

### `tm_t_events_patyear` — patient-year-adjusted rates

For long-term safety data where exposure varies:

```r
tm_t_events_patyear(
  label = "AE per 100 Patient-Years",
  dataname = "ADAE",
  arm_var = choices_selected("ARM", "ARM"),
  events_var = choices_selected("AEDECOD", "AEDECOD"),
  duration_var = choices_selected("TRTDURD", "TRTDURD")
)
```

Adjusts incidence rates by exposure time. Standard for chronic-treatment studies (e.g., obesity, diabetes, certain CV trials).

### `tm_t_smq` — Standardized MedDRA Queries

For MedDRA SMQ-based analyses (e.g., "Liver-Related Investigations" SMQ):

```r
tm_t_smq(
  label = "AE by SMQ",
  dataname = "ADAE",
  arm_var = choices_selected("ARM", "ARM"),
  smq_varlabel = "SMQ"
)
```

If ADAE has SMQ flags, the module summarizes subjects flagged for each SMQ.

## 4. Survival modules

The TTE family covers Kaplan-Meier plots, median survival summaries, and Cox regression.

### `tm_g_km` — Kaplan-Meier plot

```r
tm_g_km(
  label = "Kaplan-Meier",
  dataname = "ADTTE",
  arm_var = choices_selected(c("ARM", "ARMCD"), "ARM"),
  arm_ref_comp = list(
    ARM = list(ref = "B: Placebo", comp = c("A: Drug X", "C: Combination"))
  ),
  paramcd = choices_selected(value_choices("ADTTE", "PARAMCD", "PARAM"), "OS"),
  strata_var = choices_selected(c("SEX", "RACE"), NULL),
  facet_var = choices_selected(c("STRATA1"), NULL),
  time_unit_var = choices_selected("AVALU", "AVALU", fixed = TRUE),
  aval_var = choices_selected("AVAL", "AVAL", fixed = TRUE),
  cnsr_var = choices_selected("CNSR", "CNSR", fixed = TRUE),
  conf_level = choices_selected(c(0.95, 0.90), 0.95),
  control_annot_surv_med = control_surv_med_annot(),
  control_annot_coxph = control_coxph_annot()
)
```

Long argument list because K-M is highly configurable: reference arm, parameter (which TTE — OS, PFS, etc.), stratification, faceting, confidence levels, annotation control.

Renders an interactive K-M plot with:

- Median survival annotation
- HR (Cox) annotation
- Number-at-risk table
- Survival probability at user-specified times

User can switch between PARAMCD values (OS, PFS, DOR) without re-launching.

### `tm_t_tte` — TTE summary table

```r
tm_t_tte(
  label = "TTE Summary",
  dataname = "ADTTE",
  arm_var = choices_selected("ARM", "ARM"),
  arm_ref_comp = list(
    ARM = list(ref = "B: Placebo", comp = c("A: Drug X"))
  ),
  paramcd = choices_selected(value_choices("ADTTE", "PARAMCD"), "OS"),
  strata_var = choices_selected(c("SEX"), NULL)
)
```

Renders median survival, HR, log-rank p-value as a table. Companion to `tm_g_km` — same data, table form.

### `tm_t_coxreg` — Cox regression

For multivariable Cox models with treatment plus covariates:

```r
tm_t_coxreg(
  label = "Cox Regression",
  dataname = "ADTTE",
  arm_var = choices_selected("ARM", "ARM"),
  arm_ref_comp = list(
    ARM = list(ref = "B: Placebo", comp = c("A: Drug X"))
  ),
  paramcd = choices_selected(value_choices("ADTTE", "PARAMCD"), "OS"),
  cov_var = choices_selected(c("AGE", "SEX", "RACE"), c("AGE", "SEX"))
)
```

Renders the multivariable Cox HR table — coefficients for treatment plus covariates with CIs and p-values.

## 5. Demographics and summary modules

### `tm_t_summary` — generic summary table

The most-used clinical module:

```r
tm_t_summary(
  label = "Demographics",
  dataname = "ADSL",
  arm_var = choices_selected(c("ARM", "ACTARM"), "ARM"),
  summarize_vars = choices_selected(
    c("AGE", "AGEGR1", "SEX", "RACE", "ETHNIC", "BMIBL"),
    c("AGE", "SEX", "RACE")
  ),
  add_total = TRUE,
  total_label = "Total",
  useNA = "ifany",
  numeric_stats = c("n", "mean_sd", "median", "quantiles", "range"),
  denominator = "N"
)
```

Renders the canonical demographics table: arms as columns, characteristics as rows, with continuous summaries (Mean (SD), Median (Q1, Q3), Min-Max) and categorical summaries (n (%)).

Users can dynamically pick:

- Which variables to summarize (`summarize_vars`)
- Which stats for continuous variables (`numeric_stats`)
- Whether to include the Total column (`add_total`)

This module replaces what would be many study-team Excel queries: "what does demographics look like if we exclude the high-dose arm?" "what's BMIBL by sex within each arm?"

### `tm_t_summary_by` — summary stratified by additional variable

For "Demographics by Visit" or "Lab Summary by Parameter" style tables:

```r
tm_t_summary_by(
  label = "Lab Values by Visit",
  dataname = "ADLB",
  arm_var = choices_selected("ARM", "ARM"),
  by_vars = choices_selected(c("AVISIT", "VISIT"), "AVISIT"),
  summarize_vars = choices_selected(c("AVAL", "CHG"), c("AVAL", "CHG")),
  paramcd = choices_selected(
    value_choices("ADLB", "PARAMCD", "PARAM"),
    "ALT"
  )
)
```

Renders a table with rows per visit, columns per arm, with chosen statistics. Users can switch lab parameter on the fly.

## 6. Lab modules

### `tm_t_abnormality` — abnormality classification

Classifies lab values as LOW/NORMAL/HIGH per reference range, summarizes per arm:

```r
tm_t_abnormality(
  label = "Lab Abnormalities",
  dataname = "ADLB",
  arm_var = choices_selected("ARM", "ARM"),
  paramcd = choices_selected(value_choices("ADLB", "PARAMCD"), "ALT"),
  abnormal = choices_selected(c("BNRIND", "ANRIND"), "ANRIND")
)
```

Output: subjects with any HIGH, any LOW, etc., per arm.

### `tm_t_abnormality_by_worst_grade` — worst-grade abnormality

For toxicity-graded labs:

```r
tm_t_abnormality_by_worst_grade(
  label = "Worst Lab Abnormality",
  dataname = "ADLB",
  arm_var = choices_selected("ARM", "ARM"),
  paramcd = choices_selected(value_choices("ADLB", "PARAMCD"), "ALT"),
  worst_grade_var = choices_selected("ATOXGR", "ATOXGR")
)
```

Counts subjects by their worst on-treatment grade per lab.

### `tm_t_shift_by_grade` — shift tables by grade

The classic "baseline grade × on-treatment worst grade" cross-tab:

```r
tm_t_shift_by_grade(
  label = "Lab Shift Table",
  dataname = "ADLB",
  arm_var = choices_selected("ARM", "ARM"),
  paramcd = choices_selected(value_choices("ADLB", "PARAMCD"), "ALT"),
  baseline_grade_var = choices_selected("BTOXGR", "BTOXGR"),
  worst_grade_var = choices_selected("ATOXGR", "ATOXGR")
)
```

## 7. Change-from-baseline modules

### `tm_t_ancova` — ANCOVA-based change

For Week-N change from baseline with treatment effect adjusted for baseline:

```r
tm_t_ancova(
  label = "ANCOVA",
  dataname = "ADQS",
  arm_var = choices_selected("ARM", "ARM"),
  arm_ref_comp = list(
    ARM = list(ref = "B: Placebo", comp = c("A: Drug X"))
  ),
  paramcd = choices_selected(value_choices("ADQS", "PARAMCD"), "FKSI-FWB"),
  aval_var = choices_selected("CHG", "CHG"),
  cov_var = choices_selected(c("BASE", "AGE"), "BASE"),
  visit_var = choices_selected("AVISIT", "AVISIT")
)
```

Renders LS Mean change per arm, difference vs reference, CI, and p-value.

### `tm_g_lineplot` — change-from-baseline visualization

For line plots showing mean change over time:

```r
tm_g_lineplot(
  label = "Change Over Time",
  dataname = "ADQS",
  strata = choices_selected("ARM", "ARM"),
  x = choices_selected("AVISIT", "AVISIT"),
  y = choices_selected("AVAL", "AVAL"),
  paramcd = choices_selected(value_choices("ADQS", "PARAMCD"), "FKSI-FWB"),
  conf_level = choices_selected(c(0.95, 0.99), 0.95)
)
```

Mean (or median) over visits with CI ribbons per arm.

## 8. MMRM module

For longitudinal continuous data:

```r
tm_a_mmrm(
  label = "MMRM",
  dataname = "ADQS",
  aval_var = choices_selected("CHG", "CHG"),
  id_var = choices_selected("USUBJID", "USUBJID"),
  arm_var = choices_selected("ARM", "ARM"),
  arm_ref = "B: Placebo",
  visit_var = choices_selected("AVISIT", "AVISIT"),
  cov_var = choices_selected(c("BASE", "AGE", "SEX"), "BASE"),
  conf_level = choices_selected(c(0.95, 0.90), 0.95)
)
```

Uses the `{mmrm}` package (also pharmaverse, Roche-led) for fast MMRM fitting. Renders LS means per arm per visit with CIs and treatment-effect differences.

For chronic-disease studies (diabetes, COPD, depression), MMRM is the workhorse efficacy analysis. Having it as an interactive teal module lets reviewers explore "what if we exclude this visit?" or "what if we add a covariate?" without rewriting code.

## 9. Patient profile modules

For drilling into individual subjects — typical for medical reviewers investigating specific cases:

### `tm_g_pp_patient_timeline` — subject event timeline

```r
tm_g_pp_patient_timeline(
  label = "Patient Timeline",
  dataname = "ADCM",
  patient_col = "USUBJID",
  dataname_adsl = "ADSL",
  cm_data_dataname = "ADCM",
  ex_data_dataname = "ADEX",
  ae_data_dataname = "ADAE"
)
```

Renders a horizontal timeline for one subject showing concomitant medications, exposures, and AEs. Click subjects to switch.

### `tm_g_pp_adverse_events` — subject AE detail

```r
tm_g_pp_adverse_events(
  label = "Patient AEs",
  dataname = "ADAE",
  patient_col = "USUBJID"
)
```

All AEs for a chosen subject, with grades and outcomes.

### `tm_g_pp_therapy` — subject treatment history

```r
tm_g_pp_therapy(
  label = "Patient Therapy",
  dataname = "ADCM"
)
```

All concomitant therapies for the chosen subject.

### `tm_g_pp_vitals` — subject vital signs over time

```r
tm_g_pp_vitals(
  label = "Patient Vitals",
  dataname = "ADVS",
  patient_col = "USUBJID",
  paramcd = "PARAMCD",
  aval_var = "AVAL",
  xaxis = "ADY"
)
```

Subject-level vital signs trajectory.

The patient profile family is essential for medical reviewer use cases — investigating SAEs, deaths, discontinuations. teal apps with patient profile modules become standard tools at major sponsors.

## 10. Response and binary outcome modules

### `tm_t_binary_outcome` — response rate analysis

For "% responders" type outcomes:

```r
tm_t_binary_outcome(
  label = "Response Rate",
  dataname = "ADRS",
  arm_var = choices_selected("ARM", "ARM"),
  arm_ref_comp = list(
    ARM = list(ref = "B: Placebo", comp = c("A: Drug X"))
  ),
  paramcd = choices_selected(value_choices("ADRS", "PARAMCD"), "RSP"),
  aval_var = choices_selected("AVALC", "AVALC"),
  responder_val = c("Y")
)
```

Renders ORR (Objective Response Rate), CI, comparison vs reference. For oncology studies, this is the headline efficacy table.

### `tm_t_logistic` — logistic regression

For multivariable response analyses:

```r
tm_t_logistic(
  label = "Logistic Regression",
  dataname = "ADRS",
  arm_var = choices_selected("ARM", "ARM"),
  arm_ref_comp = list(
    ARM = list(ref = "B: Placebo", comp = c("A: Drug X"))
  ),
  cov_var = choices_selected(c("AGE", "SEX"), c("AGE", "SEX")),
  paramcd = choices_selected(value_choices("ADRS", "PARAMCD"), "BESRSPI"),
  responder_val = "CR"
)
```

OR (odds ratio) per predictor with CIs.

## 11. The complete CSR-companion app

A realistic full teal app combining many modules:

```r
library(teal)
library(teal.modules.general)
library(teal.modules.clinical)
library(pharmaverseadam)

data <- cdisc_data(
  ADSL  = pharmaverseadam::adsl,
  ADAE  = pharmaverseadam::adae,
  ADLB  = pharmaverseadam::adlb,
  ADVS  = pharmaverseadam::advs,
  ADTTE = pharmaverseadam::adtte,
  ADCM  = pharmaverseadam::adcm,
  ADEX  = pharmaverseadam::adex
)

mods <- modules(
  # Orientation
  modules(
    label = "Overview",
    tm_front_page(label = "Front Page", header_text = c(Title = "Study X")),
    tm_data_table("Data Browser"),
    tm_variable_browser("Variables")
  ),
  # Demographics
  modules(
    label = "Demographics",
    tm_t_summary(
      label = "Demographics Summary",
      dataname = "ADSL",
      arm_var = choices_selected(c("ARM", "ACTARM"), "ARM"),
      summarize_vars = choices_selected(
        c("AGE", "AGEGR1", "SEX", "RACE", "ETHNIC", "BMIBL"),
        c("AGE", "SEX", "RACE", "BMIBL")
      )
    )
  ),
  # Safety
  modules(
    label = "Safety",
    tm_t_events_summary(
      label = "AE Overview",
      dataname = "ADAE",
      arm_var = choices_selected("ARM", "ARM"),
      flag_var_anl = choices_selected("TRTEMFL", "TRTEMFL"),
      flag_var_aesi = choices_selected("AESERFL", "AESERFL")
    ),
    tm_t_events(
      label = "AE by SOC/PT",
      dataname = "ADAE",
      arm_var = choices_selected("ARM", "ARM"),
      llt = choices_selected("AEDECOD", "AEDECOD"),
      hlt = choices_selected("AEBODSYS", "AEBODSYS")
    ),
    tm_t_events_by_grade(
      label = "AE by Grade",
      dataname = "ADAE",
      arm_var = choices_selected("ARM", "ARM"),
      llt = choices_selected("AEDECOD", "AEDECOD"),
      hlt = choices_selected("AEBODSYS", "AEBODSYS"),
      grade = choices_selected("AETOXGR", "AETOXGR")
    )
  ),
  # Efficacy
  modules(
    label = "Efficacy",
    tm_g_km(
      label = "K-M Plot",
      dataname = "ADTTE",
      arm_var = choices_selected("ARM", "ARM"),
      arm_ref_comp = list(ARM = list(ref = "B: Placebo", comp = c("A: Drug X"))),
      paramcd = choices_selected(value_choices("ADTTE", "PARAMCD"), "OS")
    ),
    tm_t_tte(
      label = "TTE Summary",
      dataname = "ADTTE",
      arm_var = choices_selected("ARM", "ARM"),
      arm_ref_comp = list(ARM = list(ref = "B: Placebo", comp = c("A: Drug X"))),
      paramcd = choices_selected(value_choices("ADTTE", "PARAMCD"), "OS")
    ),
    tm_t_coxreg(
      label = "Cox Regression",
      dataname = "ADTTE",
      arm_var = choices_selected("ARM", "ARM"),
      arm_ref_comp = list(ARM = list(ref = "B: Placebo", comp = c("A: Drug X"))),
      paramcd = choices_selected(value_choices("ADTTE", "PARAMCD"), "OS"),
      cov_var = choices_selected(c("AGE", "SEX"), c("AGE", "SEX"))
    )
  ),
  # Labs
  modules(
    label = "Labs",
    tm_t_abnormality_by_worst_grade(
      label = "Lab Abnormalities",
      dataname = "ADLB",
      arm_var = choices_selected("ARM", "ARM"),
      paramcd = choices_selected(value_choices("ADLB", "PARAMCD"), "ALT"),
      worst_grade_var = choices_selected("ATOXGR", "ATOXGR")
    ),
    tm_t_shift_by_grade(
      label = "Lab Shift",
      dataname = "ADLB",
      arm_var = choices_selected("ARM", "ARM"),
      paramcd = choices_selected(value_choices("ADLB", "PARAMCD"), "ALT"),
      baseline_grade_var = choices_selected("BTOXGR", "BTOXGR"),
      worst_grade_var = choices_selected("ATOXGR", "ATOXGR")
    )
  ),
  # Patient profiles
  modules(
    label = "Patient Profile",
    tm_g_pp_patient_timeline(
      label = "Patient Timeline",
      dataname = "ADCM",
      patient_col = "USUBJID",
      dataname_adsl = "ADSL"
    ),
    tm_g_pp_adverse_events(
      label = "Patient AEs",
      dataname = "ADAE",
      patient_col = "USUBJID"
    )
  )
)

app <- init(
  data = data,
  modules = mods,
  filter = teal_slices(
    teal_slice(dataname = "ADSL", varname = "SAFFL", selected = "Y", fixed = TRUE)
  ),
  title = "Study X CSR Companion"
)

shinyApp(app$ui, app$server)
```

About 100 lines → a 6-tab-group, ~15-module app covering the full CSR analysis space. The user can:

- Navigate study orientation (front page, data browser)
- See demographics by arm
- Drill into safety (overview → SOC/PT → grade)
- Explore efficacy (K-M + median + Cox)
- Investigate labs (abnormalities + shifts)
- Drill into individual subjects

This becomes the **interactive companion** to the CSR. Reviewers, study teams, biostatisticians all use it for "what if" exploration and case investigation.

## 12. The Show R Code output for clinical modules

Clinical modules produce particularly useful Show R Code output because the underlying `{tern}` / `{rtables}` code is shown. For `tm_t_summary`:

```r
# Data loading
library(teal.data)
library(pharmaverseadam)
ADSL <- pharmaverseadam::adsl

# Filter
ADSL <- ADSL |> dplyr::filter(SAFFL == "Y")

# Table layout via tern + rtables
library(tern)
library(rtables)

lyt <- basic_table(show_colcounts = TRUE) |>
  split_cols_by("ARM") |>
  add_overall_col(label = "Total") |>
  analyze_vars(
    vars = c("AGE", "SEX", "RACE"),
    .stats = c("n", "mean_sd", "median", "quantiles", "range")
  )

result <- build_table(lyt, ADSL)
result
```

This is a complete, runnable script for a CSR-grade demographics table. Saving it gives you a programmatically-validated starting point for the formal CSR programming.

This is teal's regulatory pitch: even when teal is the interactive tool, the output is the same `rtables` code that produces submission-grade tables. There's no methodology divergence between "what teal shows" and "what goes in the CSR."

## 13. arm_ref_comp — the reference comparison pattern

A subtle teal.modules.clinical convention: `arm_ref_comp` specifies which arms compare to which reference:

```r
arm_ref_comp = list(
  ARM = list(
    ref = "B: Placebo",
    comp = c("A: Drug X", "C: Combination")
  )
)
```

This says: when computing treatment effects, Placebo is the reference; Drug X and Combination each get compared to Placebo, producing two effect estimates.

For 2-arm studies, simpler:

```r
arm_ref_comp = list(
  ARM = list(ref = "B: Placebo", comp = c("A: Drug X"))
)
```

Without `arm_ref_comp`, modules don't know how to structure the comparison. Always specify for any module that produces treatment-effect estimates (Cox, ANCOVA, logistic, binary outcome).

## 14. Decorators on clinical modules

Newer feature (~2024-2025): modules accept `decorators` to customize their output. For `tm_g_km`:

```r
sponsor_km_theme <- teal_transform_module(
  label = "Apply sponsor theme",
  ui = function(id) NULL,
  server = function(id, data) {
    moduleServer(id, function(input, output, session) {
      reactive({
        # Modify the plot per sponsor branding
        within(data(), {
          plot <- plot + ggplot2::theme_classic() +
            ggplot2::scale_color_manual(values = c("#005EB8", "#E63946"))
        })
      })
    })
  }
)

tm_g_km(
  ...,
  decorators = list(plot = sponsor_km_theme)
)
```

Decorator applied to "plot" output (K-M modules have outputs named like "plot", "table" — see each module's docs).

For sponsor-customized teal apps, decorators are the right extension point. You don't fork or wrap the module; you add a decorator that customizes the output.

## 15. Module configurability — what users can change

Each clinical module exposes a UI panel allowing users to change:

- Population filters (via the main filter panel)
- Variable selections (e.g., switch from `AEDECOD` to a custom PT variable)
- Statistic selections (which stats to display)
- Visualization options (axis labels, colors, sizes)
- Significance levels (e.g., switch from 95% to 90% CI)
- Reference levels for comparisons

This breadth is part of teal's value: instead of static "here's the table I produced", users explore configurations. "What if AGE was categorical instead of continuous?" "What if we used median instead of mean?" Click, re-run, compare.

For QC, this matters too: programmers can rapidly verify alternate analyses without rewriting code.

## 16. Performance for large datasets

For 5,000-subject ADSL with 50,000-row ADAE: teal apps respond fast. For 100,000+ subjects: optimization needed.

- Filter to the active subset early (the global filter panel handles this efficiently)
- Avoid modules that compute over all data when only a subset is needed (e.g., don't load all 5 years of long-term safety data if your analysis is 6 months)
- Use cached data via `bindCache()` for expensive computations (Shiny pattern, applies inside custom modules)
- Use Posit Connect with sufficient memory for production deployments

For most pharma teal apps (single study, hundreds-to-thousands of subjects), performance is fine without optimization.

## 17. Reportability

Most clinical modules support `{teal.reporter}` — the "Add to Report" button. Users can:

1. Configure a module to their preferred view (filters, variables, stats)
2. Click "Add to Report" → snapshot saved
3. Add text commentary
4. Repeat across modules
5. Download a Word/PDF report containing all snapshots + commentary

For sponsor teams generating ad-hoc summary reports (e.g., for an FDA Type C meeting), this is invaluable: build the analyses in teal, snapshot the ones you need, download a coherent document.

## 18. Limitations and edge cases

Clinical modules don't cover everything:

- **Highly custom layouts**: if your sponsor's safety table has specific layout requirements that diverge from FDA/CDISC conventions, you may need to wrap your own module
- **Cross-domain joins beyond CDISC defaults**: complex multi-dataset joins may need manual `join_keys`
- **Real-time data sources**: standard modules assume static loaded data; refresh patterns need `teal_data_module`
- **Non-CDISC data**: modules assume CDISC variable conventions; custom data structures may need adaptation

For these cases, building a custom module (Lesson 42) is the answer.

## 19. Key takeaways

- `{teal.modules.clinical}` provides ~40 pre-built clinical analysis modules
- Families: summary, AE, survival, response, lab, change, exposure, MMRM, patient profile
- Built on `{tern}` and `{rtables}` for computation — same engine as static CSR tables
- AE family: `tm_t_events_summary` (overview) → `tm_t_events` (SOC/PT) → `tm_t_events_by_grade` (severity)
- Survival family: `tm_g_km` (plot) + `tm_t_tte` (summary table) + `tm_t_coxreg` (multivariable)
- Patient profiles for individual-subject drill-down — essential for medical reviewers
- `arm_ref_comp` specifies reference arm for treatment-effect comparisons
- Decorators (newer pattern) allow sponsor-specific customization without forking modules
- Show R Code outputs runnable tern/rtables scripts — methodology aligned with static CSR tables
- Coexists with general modules; typical app uses 3-5 general + 8-12 clinical

## 20. What's next

Lesson 42 — the final Module 8 lesson — covers **custom teal modules + deployment + validation**. You'll learn how to build your own teal module from scratch (essential when pre-built modules don't cover your specific need), deployment patterns to Posit Connect for sponsor use, and validation considerations for GxP-relevant interactive applications.

After Module 8, we move to Module 9 (submission: xportr + datasetjson), Module 10 (traceability), and the capstone study.

---

## Self-check questions

1. What's the difference between `tm_t_events_summary` and `tm_t_events`?
2. Why does `tm_g_km` require `arm_ref_comp`?
3. What's the role of patient profile modules and who typically uses them?
4. Translate to teal.modules.clinical: an app with demographics + AE overview + K-M for OS + patient profile.
5. Why do clinical modules produce more useful "Show R Code" output than general modules?
6. When would you use `tm_t_summary_by` instead of `tm_t_summary`?

## Glossary

- **`tm_t_summary`** — Generic clinical summary (demographics)
- **`tm_t_summary_by`** — Summary stratified by additional variable (visit, parameter)
- **`tm_t_events_summary`** — AE overview table (any TEAE, SAE, etc.)
- **`tm_t_events`** — AE incidence by SOC/PT
- **`tm_t_events_by_grade`** — AE incidence with grade dimension
- **`tm_t_events_patyear`** — Patient-year-adjusted AE rates
- **`tm_t_smq`** — Standardized MedDRA Query AE analysis
- **`tm_g_km`** — Interactive Kaplan-Meier plot
- **`tm_t_tte`** — TTE summary table (median, x-year survival)
- **`tm_t_coxreg`** — Multivariable Cox regression
- **`tm_t_binary_outcome`** — Response rate analysis
- **`tm_t_logistic`** — Multivariable logistic regression
- **`tm_t_ancova`** — ANCOVA-based change analysis
- **`tm_a_mmrm`** — Mixed-model repeated measures
- **`tm_t_abnormality`** — Lab abnormality classification
- **`tm_t_abnormality_by_worst_grade`** — Worst-grade abnormality counts
- **`tm_t_shift_by_grade`** — Lab shift tables (baseline grade × on-treatment grade)
- **`tm_g_pp_patient_timeline`** — Subject event timeline
- **`tm_g_pp_adverse_events`** — Subject AE detail
- **`arm_ref_comp`** — Specifies reference arm for treatment comparisons
- **Decorator** — Module output customization mechanism
- **Patient profile** — Family of subject-level drill-down modules for medical reviewers
- **CSR companion app** — Standard term for a teal app that exists alongside the CSR for interactive exploration
