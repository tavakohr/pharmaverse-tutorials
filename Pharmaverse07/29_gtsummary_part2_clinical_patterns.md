# Lesson 29 — `{gtsummary}` Part 2: Clinical Reporting Patterns

**Module**: 6 — TLG: the Cardinal-future stack
**Estimated length**: ~22 min spoken
**Prerequisites**: Lesson 28 (gtsummary Part 1)

---

## Learning objectives

By the end of this lesson, you will be able to:

1. Build the canonical demographics table with arms, overall column, and footnotes
2. Build the AE incidence table with SOC × PT hierarchy and proper denominators
3. Build a lab change-from-baseline table with by-visit summaries
4. Build a survival summary table with HR, median, x-year rates from cardx ARDs
5. Apply `{crane}` extensions for Roche-style clinical conventions
6. Output complete TLG batches to RTF for CSR delivery

---

## 1. The CSR table inventory

A typical CSR (Clinical Study Report) has dozens of tables. The core "Table 14" series (FDA convention):

- **14.1.x** — Disposition: subject accountability, randomization, completion
- **14.2.x** — Demographics and baseline characteristics
- **14.3.x** — Efficacy: primary, secondary, sensitivity analyses
- **14.4.x** — Safety: AE summaries (incidence, severity, relatedness, SAEs, discontinuations)
- **14.5.x** — Lab: liver function tests, renal, hematology, urinalysis
- **14.6.x** — Vital signs, ECG, physical exam
- **14.7.x** — Exposure and compliance

We can't cover all of these in detail. Instead, this lesson presents the **four canonical patterns** that 90% of CSR tables follow. Mastering them gives you the building blocks for the rest.

## 2. Setup

```r
library(cards)
library(cardx)
library(gtsummary)
library(survival)
library(dplyr)
library(pharmaverseadam)
library(flextable)

theme_gtsummary_compact()      # compact theme common for CSR

adsl  <- pharmaverseadam::adsl  |> filter(SAFFL == "Y")
adae  <- pharmaverseadam::adae
adlb  <- pharmaverseadam::adlb  |> filter(SAFFL == "Y" & ANL01FL == "Y")
adtte <- pharmaverseadam::adtte
```

## 3. Pattern 1: Demographics table

The most common CSR table. We covered the basic version in Lesson 28; now we add CSR-grade details.

```r
# Build the ARD
demog_ard <- ard_stack(
  adsl,
  ard_continuous(
    variables = c(AGE, BMIBL, WEIGHTBL, HEIGHTBL),
    statistic = ~ continuous_summary_fns(
      c("N", "mean", "sd", "median", "p25", "p75", "min", "max")
    )
  ),
  ard_categorical(variables = c(AGEGR1, SEX, RACE, ETHNIC)),
  .by = TRT01A,
  .overall = TRUE,
  .total_n = TRUE,
  .attributes = TRUE
)

# Build a p-value ARD with cardx
pvalue_ard <- bind_ard(
  ard_stats_anova_oneway(adsl, by = "TRT01A", variables = c(AGE, BMIBL, WEIGHTBL, HEIGHTBL)),
  ard_stats_chisq_test(adsl, by = "TRT01A", variables = c(AGEGR1, SEX, RACE, ETHNIC))
)

# Render
demog_table <- bind_ard(demog_ard, pvalue_ard) |>
  tbl_ard_summary(
    by = TRT01A,
    type = list(
      c(AGE, BMIBL, WEIGHTBL, HEIGHTBL) ~ "continuous2"
    ),
    statistic = list(
      c(AGE, BMIBL, WEIGHTBL, HEIGHTBL) ~ c("{mean} ({sd})",
                                            "{median} ({p25}, {p75})",
                                            "{min}, {max}")
    ),
    overall = TRUE
  ) |>
  add_p() |>
  add_stat_label() |>
  modify_header(label ~ "**Characteristic**",
                stat_0 ~ "**Overall**  \nN={N}",
                stat_1 ~ "**Placebo**  \nN={n}",
                stat_2 ~ "**Xanomeline Low**  \nN={n}",
                stat_3 ~ "**Xanomeline High**  \nN={n}") |>
  modify_caption("**Table 14.2.1: Demographic and Baseline Characteristics — Safety Population**") |>
  modify_footnote(
    all_stat_cols() ~
      "Continuous: Mean (SD); Median (Q1, Q3); Min, Max.  
       Categorical: n (%).  
       p-values from one-way ANOVA (continuous) or chi-squared test (categorical)."
  ) |>
  bold_labels()

# Render
demog_table

# Export to RTF
demog_table |>
  as_flex_table() |>
  flextable::save_as_rtf(path = "outputs/t_14_2_1_demographics.rtf")
```

The signature CSR-grade additions:

- Multiple format strings per `continuous2` variable: 3-row layout with mean/SD, median/IQR, and min/max
- p-values from cardx
- Column headers with arm names and N-counts ("Placebo (N=86)")
- Caption with table number and population
- Detailed footnote explaining methodology
- RTF export for CSR delivery

This pattern adapts to baseline characteristics, baseline disease, prior medications, and similar "subject characteristics" tables by changing the variable list.

## 4. Pattern 2: AE incidence table

The signature safety table: AE by System Organ Class and Preferred Term, with subject-level denominators per arm. CSR-grade includes:

- "Subjects with any TEAE" row
- "Subjects with TEAE leading to discontinuation" row
- SOC × PT hierarchy
- Subject counts and percentages per arm

```r
# Filter to treatment-emergent
adae_te <- adae |> filter(TRTEMFL == "Y")

# Subject-level any-AE flag from ADSL
adsl_with_any_ae <- adsl |>
  mutate(
    ANY_TEAE = if_else(USUBJID %in% adae_te$USUBJID, "Y", "N"),
    SEVERE_TEAE = if_else(
      USUBJID %in% (adae_te |> filter(ASEV == "SEVERE") |> pull(USUBJID)),
      "Y", "N"
    )
  )

# Overall "any AE" rows
overall_ard <- ard_categorical(
  adsl_with_any_ae,
  by = "TRT01A",
  variables = c(ANY_TEAE, SEVERE_TEAE),
  denominator = adsl
)

# Hierarchical SOC × PT
hier_ard <- adae_te |>
  ard_hierarchical(
    by = "ARM",
    variables = c("AEBODSYS", "AEDECOD"),
    denominator = adsl
  )

# Combine
ae_full_ard <- bind_ard(overall_ard, hier_ard)

# Render
ae_table <- ae_full_ard |>
  tbl_ard_summary(
    by = "TRT01A",
    overall = FALSE
  ) |>
  modify_header(label ~ "**System Organ Class<br>Preferred Term**") |>
  modify_caption("**Table 14.4.1: Adverse Events Occurring in ≥5% of Subjects — Safety Population**") |>
  modify_footnote(
    all_stat_cols() ~
      "Counts are number of subjects with at least one event. Percentages use safety population N as denominator."
  ) |>
  bold_labels()

# Export
ae_table |>
  as_flex_table() |>
  flextable::save_as_rtf(path = "outputs/t_14_4_1_ae_incidence.rtf")
```

Considerations specific to AE tables:

- **Subject-level denominators**: every percentage is "subjects with this AE / total subjects in the safety population per arm" — never event-level
- **Hierarchical indentation**: SOC rows appear left-aligned; PT rows appear indented (gtsummary handles this automatically for hierarchical ARDs)
- **Sorting**: typical convention is alphabetical by SOC, alphabetical by PT within SOC. Some sponsors sort by total incidence (most common first).
- **Filtering by incidence threshold**: "AEs occurring in ≥5% of subjects" — apply this filter at the ARD level before rendering, or use a `filter_fun` in gtsummary.

For the "subjects with at least one serious TEAE" subtable, build a separate ARD and `tbl_stack()` it with the main AE table.

## 5. Pattern 3: Lab change-from-baseline table

The canonical lab table: by parameter, by visit, by arm — N/Mean/SD/Median/Min/Max for both AVAL and CHG.

```r
adlb_chg_ard <- adlb |>
  filter(PARAMCD %in% c("HGB", "ALT", "AST", "BILI") & !is.na(AVISIT)) |>
  ard_continuous(
    by = c(PARAMCD, AVISIT, TRTA),
    variables = c(AVAL, CHG),
    statistic = ~ continuous_summary_fns(
      c("N", "mean", "sd", "median", "min", "max")
    )
  )

# For display, reshape: variables (AVAL, CHG) become inner columns; arm at top
# This requires shuffle_ard() + restructure, or use tfrmt (Lesson 32) for full control

# Simpler view: one parameter per table
hgb_table <- adlb_chg_ard |>
  filter(group1_level == "HGB") |>      # filter to HGB rows
  tbl_ard_summary(
    by = TRTA,
    type = c(AVAL, CHG) ~ "continuous2"
  ) |>
  modify_caption("**Table 14.5.1: Hemoglobin and Change from Baseline by Visit — Safety Population**")
```

Lab tables are inherently complex: the typical CSR design has nested column groups (Visit > Arm) and nested row groups (Parameter > Statistic). For full layout control, `{tfrmt}` (Lesson 32) is often the better tool. gtsummary works well for simpler layouts (one parameter per table) but its column structure is limited.

For full multi-parameter, multi-visit lab summaries, the legacy stack's `{rtables}` (Module 7) excels — and pharma teams often use rtables for lab tables and gtsummary for everything else.

## 6. Pattern 4: Survival summary table

For OS or PFS with K-M median, x-year rates, and HR:

```r
# K-M median and x-year survival
os_xyear_ard <- adtte |>
  filter(PARAMCD == "OS") |>
  ard_survival_survfit(
    y = Surv(AVAL, 1 - CNSR),
    variables = "TRTA",
    times = c(180, 365)
  )

os_median_ard <- adtte |>
  filter(PARAMCD == "OS") |>
  ard_survival_survfit(
    y = Surv(AVAL, 1 - CNSR),
    variables = "TRTA",
    probs = c(0.5)
  )

# Cox HR
cox_fit <- coxph(
  Surv(AVAL, 1 - CNSR) ~ TRTA + AGE + SEX,
  data = adtte |> filter(PARAMCD == "OS")
)
hr_ard <- ard_regression(cox_fit)

# Log-rank test
logrank_ard <- survdiff(
  Surv(AVAL, 1 - CNSR) ~ TRTA,
  data = adtte |> filter(PARAMCD == "OS")
) |>
  ard_survival_survdiff()

# Combine
os_full_ard <- bind_ard(os_xyear_ard, os_median_ard, hr_ard, logrank_ard)

# Render — survival tables typically use custom layout
# gtsummary's tbl_ard_summary() can handle this; for full control, tfrmt is better
os_table <- os_full_ard |>
  tbl_ard_summary(
    by = TRTA,
    overall = FALSE
  ) |>
  modify_caption("**Table 14.3.1: Overall Survival — Efficacy Population**") |>
  modify_footnote(
    all_stat_cols() ~
      "Median survival from Kaplan-Meier with 95% CI.  
       Hazard ratio from Cox model adjusting for age and sex.  
       p-value from log-rank test."
  )
```

Survival tables have a different aesthetic from demographics — fewer rows (median, 6-month rate, 1-year rate, HR), more emphasis on the HR row. The display is typically a few rows tall, two arms wide, with HR/CI/p-value in a third "comparison" column.

For CSR-grade survival tables, layout templates often live in `{cardinal}` (Lesson 30); start from there rather than building from scratch.

## 7. The `{crane}` extension

`{crane}` is an extension package by Roche that adds clinical-reporting-specific gtsummary functions. It started as Roche-internal and is being externalized:

```r
# install.packages("crane")    # check current availability
library(crane)

# crane provides functions like:
# tbl_demog_summary()  - drop-in demographics with Roche conventions
# tbl_ae_summary()     - AE table with Roche-style formatting
# tbl_efficacy_*()     - efficacy table templates
```

If your team uses Roche or has adopted Roche conventions, crane provides shortcuts that encode the conventions in code. For other organizations, you build the equivalents yourself (or rely on cardinal).

## 8. Missing data conventions

Pharma tables have specific conventions for displaying missing data:

- For continuous variables: "N=84" in the denominator captures non-missing count; missing values shown as "Missing: 2" row or footnoted
- For categorical: "Unknown" or "Not Reported" as an explicit level (with its own n%)
- For counts: zero counts displayed as "0 (0.0%)" or "0", never blank

gtsummary handles most of these via `missing = "ifany"` (default), `missing = "no"`, or `missing = "always"`. For "always" display of missing rows:

```r
adsl |>
  tbl_summary(
    by = TRT01A,
    include = c(AGE, RACE),
    missing = "always",                # always show a Missing row
    missing_text = "Missing"
  )
```

Set this consistently across your tables for visual consistency. Sponsor SOPs typically dictate the convention.

## 9. Footnoting test methodology

For p-value footnotes specifically, gtsummary captures the test method per row. To surface it:

```r
demog_table |>
  add_p() |>
  add_q(method = "fdr") |>           # adjust for multiple testing
  # Method footnote appears automatically
  modify_footnote(
    all_stat_cols() ~ "Test method varies; see methodology section of SAP."
  )
```

For tables with mixed test methods (some t-tests, some chi-squared), gtsummary's auto-generated footnote lists each. You can override with a custom footnote if your SAP requires specific phrasing.

## 10. Output to multiple formats from one ARD

The payoff of ARD-first: one ARD → many displays.

```r
# Build once
demog_ard <- ard_stack(adsl, ...)

# CSR (RTF)
demog_ard |>
  tbl_ard_summary(...) |>
  add_p() |>
  bold_labels() |>
  as_flex_table() |>
  flextable::save_as_rtf("csr/t_14_2_1.rtf")

# Investigator brochure (Word)
demog_ard |>
  tbl_ard_summary(...) |>
  modify_caption("**Table 5.1: Subject Demographics**") |>
  as_flex_table() |>
  flextable::save_as_docx(path = "ib/demographics.docx")

# Conference poster (HTML)
demog_ard |>
  tbl_ard_summary(...) |>
  modify_caption("**Demographics**") |>
  as_kable() |>
  kableExtra::save_kable("poster/demog.html")

# Slide deck via Quarto/RMarkdown — render inline as HTML widget
demog_ard |>
  tbl_ard_summary(...)
```

Each downstream display uses the same numbers (the ARD), but the layout and chrome are adapted to context. SAP changes? Update the ARD definition once; all displays update.

## 11. Validation strategy for gtsummary tables

The split:

- **ARD validation** (Lesson 26): dual programming + `diffdf`. The numbers must be correct.
- **Display validation**: visual review of rendered RTF/HTML against the SAP shell. Layout, column order, footnotes, indentation.

For a typical CSR, ARD validation is 80% of the effort. Display validation is 20% — and is largely a one-time investment per table template, since later studies reuse the same template.

## 12. Performance considerations

For large studies (thousands of subjects, hundreds of AEs):

- ARD construction is generally fast; gtsummary rendering is fast
- The slowdown often comes from RTF export via `flextable::save_as_rtf()` — large tables can take seconds. Pre-render and cache.
- For complex multi-table CSR runs, parallelize at the table level with `{future}` and `{furrr}`

Most pharmacovigilance pipelines I've seen render an entire CSR in 1–3 minutes total. Not real-time, but fine for batch processing.

## 13. Putting it together: a TLG batch script

```r
library(cards)
library(cardx)
library(gtsummary)
library(survival)
library(dplyr)
library(pharmaverseadam)
library(flextable)

theme_gtsummary_compact()

# Data
adsl  <- pharmaverseadam::adsl  |> filter(SAFFL == "Y")
adae  <- pharmaverseadam::adae
adtte <- pharmaverseadam::adtte

# Table 14.2.1: Demographics
demog_ard <- ard_stack(
  adsl,
  ard_continuous(variables = c(AGE, BMIBL),
                 statistic = ~ continuous_summary_fns(c("N", "mean", "sd", "median", "min", "max"))),
  ard_categorical(variables = c(AGEGR1, SEX, RACE)),
  .by = TRT01A, .overall = TRUE, .total_n = TRUE
)

demog_ard |>
  tbl_ard_summary(by = TRT01A, overall = TRUE) |>
  add_p() |>
  bold_labels() |>
  modify_caption("**Table 14.2.1: Demographics**") |>
  as_flex_table() |>
  save_as_rtf("outputs/t_14_2_1.rtf")

# Table 14.4.1: AE Incidence
ae_ard <- adae |>
  filter(TRTEMFL == "Y") |>
  ard_hierarchical(by = "ARM",
                   variables = c("AEBODSYS", "AEDECOD"),
                   denominator = adsl)

ae_ard |>
  tbl_ard_summary(by = "TRT01A") |>
  bold_labels() |>
  modify_caption("**Table 14.4.1: AE Incidence**") |>
  as_flex_table() |>
  save_as_rtf("outputs/t_14_4_1.rtf")

# Table 14.3.1: OS Survival
os_ard <- bind_ard(
  adtte |> filter(PARAMCD == "OS") |>
    ard_survival_survfit(y = Surv(AVAL, 1 - CNSR),
                         variables = "TRTA",
                         times = c(180, 365)),
  adtte |> filter(PARAMCD == "OS") |>
    ard_survival_survfit(y = Surv(AVAL, 1 - CNSR),
                         variables = "TRTA",
                         probs = c(0.5)),
  coxph(Surv(AVAL, 1 - CNSR) ~ TRTA + AGE + SEX,
        data = adtte |> filter(PARAMCD == "OS")) |>
    ard_regression()
)

os_ard |>
  tbl_ard_summary(by = TRTA) |>
  modify_caption("**Table 14.3.1: Overall Survival**") |>
  as_flex_table() |>
  save_as_rtf("outputs/t_14_3_1.rtf")

cat("All tables rendered.\n")
```

Three core CSR tables, ~80 lines of code, all RTF-ready for delivery. The patterns scale to dozens of tables — each is its own block in the script.

## 14. Limitations of gtsummary for some pharma tables

To be fair: gtsummary doesn't handle every CSR table well. Specifically:

- **Highly nested column groups** (e.g., Visit > Arm > Statistic, three deep) — gtsummary supports two levels of column structure cleanly; deeper requires `tfrmt` or `rtables`
- **Complex listings** — gtsummary is for summaries, not listings (e.g., line-by-line AE detail)
- **Highly custom layouts** — some sponsor templates demand specific row positioning, group labels, indentation that gtsummary's API doesn't expose

For these cases, the Cardinal-future answer is `{tfrmt}` (Lesson 32) which provides full layout control via metadata. The legacy stack's `{rtables}` (Module 7) also excels here. Most teams use multiple tools: gtsummary for ~80% of tables, rtables or tfrmt for the remaining ~20%.

## 15. Key takeaways

- Four canonical CSR table patterns: demographics, AE incidence, lab change-from-baseline, survival summary — each has a recognizable ARD + gtsummary structure
- AE tables require subject-level denominators via `denominator = adsl`
- `bind_ard()` combines descriptive (cards) and inferential (cardx) ARDs before passing to gtsummary
- `tbl_ard_summary()` renders any cards/cardx ARD; many `modify_*()` and `add_*()` helpers compose
- `flextable` provides reliable RTF/Word export; `{crane}` adds Roche conventions
- ARD-first means one ARD feeds many displays (CSR + slides + posters + Shiny)
- For very complex layouts, fall back to `{tfrmt}` or `{rtables}` — most CSRs use multiple tools

## 16. What's next

Lesson 30 covers **`{cardinal}`** — the harmonized TLG catalog initiative. cardinal is the meta-project: a community-maintained library of TLG templates that you can copy into your study. It uses the cards + gtsummary stack we just covered. Lesson 31 dives into cardinal's FDA Safety Tables and Figures templates specifically.

---

## Self-check questions

1. Why are subject-level denominators (`denominator = adsl`) essential for AE incidence tables?
2. Why does `{crane}` exist alongside `{gtsummary}`?
3. What's the role of `bind_ard()` when constructing a demographics table with p-values?
4. Translate to gtsummary: render an AE incidence table with arm columns and SOC × PT hierarchy.
5. Why does the lesson recommend using `{tfrmt}` or `{rtables}` for highly complex lab layouts even on the Cardinal-future stack?
6. How does the ARD-first approach support multi-format delivery (CSR RTF + slides + posters)?

## Glossary

- **TEAE** — Treatment-Emergent Adverse Event
- **SOC / PT** — System Organ Class / Preferred Term (MedDRA hierarchy)
- **CSR** — Clinical Study Report
- **SAP** — Statistical Analysis Plan
- **Table 14.x.x** — FDA-conventional CSR table numbering scheme
- **Subject-level denominator** — Use safety-population subject count for proportions, not row count
- **`tbl_ard_summary()`** — gtsummary function consuming ARDs
- **`tbl_hierarchical()`** — Hierarchical AE table builder
- **`{crane}`** — Roche extension for clinical reporting patterns
- **`as_flex_table()` / `save_as_rtf()`** — Export gtsummary table to RTF
- **K-M / median survival / x-year rate** — Kaplan-Meier outputs typical of survival tables
