# Lesson 48 — Capstone Part 2: Building the Deliverables

**Module**: 11 — Capstone end-to-end study
**Estimated length**: ~28 min spoken
**Prerequisites**: Lesson 47 (data pipeline); all prior lessons

---

## Learning objectives

By the end of this lesson, you will be able to:

1. Take the ADaMs from Lesson 47 forward into all standard deliverables
2. Build ARDs for demographics, AE incidence, OS survival, and lab summaries
3. Render CSR-grade RTF tables via gtsummary and tern
4. Build a complete CSR-companion teal app
5. Export XPT v5 and Dataset-JSON submission packages
6. Apply the full traceability stack (logrx, diffdf, riskmetric) to deliverables

---

## 1. Where we are

Lesson 47 produced ADaMs for the synthetic Phase III oncology study:

- **ADSL** — Subject-Level
- **ADAE** — Adverse Events
- **ADLB** — Laboratory
- **ADVS** — Vital Signs
- **ADRS** — Response Analysis
- **ADTTE** — Time-to-Event (OS, PFS, DOR)

Now we turn these into deliverables: **CSR tables, an interactive app, and the FDA submission package**. Every concept from Modules 6-9 appears here in code form.

This lesson uses the pre-built `pharmaverseadam` objects (`adsl`, `adae`, etc.) so the code is runnable.

## 2. Setup

```r
library(dplyr)
library(haven)

# Data layer
library(pharmaverseadam)

# ARD layer
library(cards)
library(cardx)

# Display layer
library(gtsummary)
library(rtables)
library(tern)
library(flextable)

# Interactive layer
library(teal)
library(teal.modules.general)
library(teal.modules.clinical)

# Submission layer
library(xportr)
library(datasetjson)
library(metacore)
library(metatools)

# Traceability
library(logrx)
library(diffdf)
library(survival)

# Load ADaMs from Lesson 47
adsl  <- pharmaverseadam::adsl  |> filter(SAFFL == "Y")
adae  <- pharmaverseadam::adae  |> filter(SAFFL == "Y")
adlb  <- pharmaverseadam::adlb  |> filter(SAFFL == "Y" & ANL01FL == "Y")
advs  <- pharmaverseadam::advs  |> filter(SAFFL == "Y")
adtte <- pharmaverseadam::adtte
```

Working directory should be the capstone project from Lesson 47. We'll add `outputs/`, `app/`, and `submission/` subdirectories as we go.

## 3. Deliverable 1: Demographics ARD + Table

The signature demographics table — a complete pipeline from ADSL to RTF:

```r
# Step A: Build descriptive ARD with cards
demog_ard <- ard_stack(
  adsl,
  ard_continuous(
    variables = c(AGE, BMIBL, WEIGHTBL, HEIGHTBL),
    statistic = ~ continuous_summary_fns(
      c("N", "mean", "sd", "median", "p25", "p75", "min", "max")
    )
  ),
  ard_categorical(variables = c(AGEGR1, SEX, RACE)),
  .by = TRT01A,
  .overall = TRUE,
  .total_n = TRUE,
  .attributes = TRUE
)

# Step B: Add p-value ARD with cardx
pvalue_ard <- bind_ard(
  ard_stats_anova_oneway(
    adsl, by = "TRT01A",
    variables = c(AGE, BMIBL, WEIGHTBL, HEIGHTBL)
  ),
  ard_stats_chisq_test(
    adsl, by = "TRT01A",
    variables = c(AGEGR1, SEX, RACE)
  )
)

# Step C: Save ARDs for archival
saveRDS(demog_ard, "outputs/ards/demographics_ard.rds")
saveRDS(pvalue_ard, "outputs/ards/demographics_pvalue_ard.rds")

# Step D: Render gtsummary table
theme_gtsummary_compact()

demog_table <- bind_ard(demog_ard, pvalue_ard) |>
  tbl_ard_summary(
    by = TRT01A,
    type = c(AGE, BMIBL, WEIGHTBL, HEIGHTBL) ~ "continuous2",
    overall = TRUE
  ) |>
  add_p() |>
  add_stat_label() |>
  modify_caption("**Table 14.2.1: Demographics — Safety Population**") |>
  modify_footnote(
    all_stat_cols() ~
      "Continuous: Mean (SD); Median (Q1, Q3). Categorical: n (%).  
       p-values from one-way ANOVA (continuous) or chi-squared (categorical)."
  ) |>
  bold_labels()

# Step E: Export to RTF
demog_table |>
  as_flex_table() |>
  flextable::save_as_rtf(path = "outputs/tables/t_14_2_1_demographics.rtf")
```

What this produced:

- `outputs/ards/demographics_ard.rds` — durable analysis results dataset
- `outputs/ards/demographics_pvalue_ard.rds` — inferential ARD
- `outputs/tables/t_14_2_1_demographics.rtf` — submission-grade RTF

The ARDs are **reusable**: the same numbers can feed the CSR table, slide deck, poster, and teal app. The RTF is what goes in the submission.

## 4. Deliverable 2: AE Incidence ARD + Table

The signature safety table:

```r
# Step A: Build hierarchical AE ARD with subject-level denominator
ae_ard <- adae |>
  filter(TRTEMFL == "Y") |>
  ard_hierarchical(
    by = "TRT01A",
    variables = c("AEBODSYS", "AEDECOD"),
    denominator = adsl   # subject-level denominator
  )

saveRDS(ae_ard, "outputs/ards/ae_incidence_ard.rds")

# Step B: "Any TEAE" overall row
overall_ae_ard <- adsl |>
  mutate(
    ANY_TEAE = if_else(USUBJID %in% (adae |> filter(TRTEMFL == "Y") |> pull(USUBJID)),
                       "Y", "N"),
    SERIOUS_TEAE = if_else(USUBJID %in% (adae |> filter(TRTEMFL == "Y" & AESER == "Y") |> pull(USUBJID)),
                          "Y", "N")
  ) |>
  ard_categorical(
    by = "TRT01A",
    variables = c(ANY_TEAE, SERIOUS_TEAE),
    denominator = adsl
  )

# Step C: Render combined AE table
ae_full <- bind_ard(overall_ae_ard, ae_ard)

ae_table <- ae_full |>
  tbl_ard_summary(by = "TRT01A", overall = FALSE) |>
  modify_header(label ~ "**System Organ Class<br>Preferred Term**") |>
  modify_caption("**Table 14.4.1: Adverse Events — Safety Population**") |>
  bold_labels()

ae_table |>
  as_flex_table() |>
  flextable::save_as_rtf(path = "outputs/tables/t_14_4_1_ae.rtf")
```

The result: a complete AE incidence table with overall row, SOC headers, and PT detail rows. Subject-aware counting via `ard_hierarchical()` with `denominator = adsl`.

## 5. Deliverable 3: Overall Survival K-M Plot and Summary

For the primary efficacy endpoint:

```r
# Filter to OS
adtte_os <- adtte |>
  filter(PARAMCD == "OS") |>
  mutate(is_event = 1 - CNSR)

# Step A: K-M survival at x-year timepoints + median
km_xyear <- adtte_os |>
  ard_survival_survfit(
    y = Surv(AVAL, is_event),
    variables = "TRTA",
    times = c(180, 365)
  )

km_median <- adtte_os |>
  ard_survival_survfit(
    y = Surv(AVAL, is_event),
    variables = "TRTA",
    probs = c(0.5)
  )

# Cox HR
cox_fit <- coxph(Surv(AVAL, is_event) ~ TRTA + AGE + SEX, data = adtte_os)
hr_ard <- ard_regression(cox_fit)

# Log-rank
logrank_ard <- survdiff(Surv(AVAL, is_event) ~ TRTA, data = adtte_os) |>
  ard_survival_survdiff()

# Combine
os_ard <- bind_ard(km_xyear, km_median, hr_ard, logrank_ard)
saveRDS(os_ard, "outputs/ards/os_survival_ard.rds")

# Step B: Render the OS summary table via tern + rtables (legacy stack)
library(rtables)

os_layout <- basic_table(show_colcounts = TRUE,
                          title = "Table 14.3.1: Overall Survival",
                          subtitles = "Efficacy Population") |>
  split_cols_by("TRTA", ref_group = "Placebo") |>
  add_colcounts() |>
  surv_time(
    vars = "AVAL",
    var_labels = "Survival Time (Days)",
    is_event = "is_event"
  ) |>
  surv_timepoint(
    vars = "AVAL",
    is_event = "is_event",
    time_point = c(180, 365)
  ) |>
  summarize_coxreg(
    variables = list(
      time = "AVAL",
      event = "is_event",
      arm = "TRTA",
      covariates = c("AGE", "SEX")
    )
  )

os_table <- build_table(os_layout, adtte_os)

# Export
os_table |>
  tt_to_flextable() |>
  flextable::save_as_rtf("outputs/tables/t_14_3_1_os.rtf")

# Step C: K-M plot via tern's K-M
library(tern)
library(ggplot2)

km_plot_data <- survfit(Surv(AVAL, is_event) ~ TRTA, data = adtte_os)

# tern provides g_km for full K-M plot with at-risk table
km_plot <- tern::g_km(
  df = adtte_os,
  variables = list(tte = "AVAL", is_event = "is_event", arm = "TRTA"),
  control_annot_surv_med = control_surv_med_annot(),
  control_annot_coxph = control_coxph_annot()
)

ggsave("outputs/figures/f_14_3_1_km_os.png",
       plot = km_plot, width = 10, height = 7, dpi = 300)
```

OS deliverables:

- `outputs/ards/os_survival_ard.rds` — survival ARD with median, 6-mo / 1-yr rates, HR, log-rank p-value
- `outputs/tables/t_14_3_1_os.rtf` — submission-grade OS summary table
- `outputs/figures/f_14_3_1_km_os.png` — K-M plot

Note we used **both stacks**: `cards`/`cardx` for the ARD (durable), `tern`/`rtables` for the table (production-proven for complex survival layouts). This dual-stack approach is realistic — different tools for different aspects, all aligned to the same underlying statistics.

## 6. Deliverable 4: Lab Summary

For ALT (a key liver function lab):

```r
# Build lab CFB ARD
lab_alt_ard <- adlb |>
  filter(PARAMCD == "ALT" & !is.na(AVISIT)) |>
  ard_continuous(
    by = c(AVISIT, TRTA),
    variables = c(AVAL, CHG),
    statistic = ~ continuous_summary_fns(c("N", "mean", "sd", "median", "min", "max"))
  )

saveRDS(lab_alt_ard, "outputs/ards/lab_alt_ard.rds")

# Render via gtsummary
lab_alt_table <- lab_alt_ard |>
  tbl_ard_summary(
    by = TRTA,
    type = c(AVAL, CHG) ~ "continuous2"
  ) |>
  modify_caption("**Table 14.5.1: ALT and Change from Baseline by Visit — Safety Population**")

lab_alt_table |>
  as_flex_table() |>
  flextable::save_as_rtf("outputs/tables/t_14_5_1_alt.rtf")
```

For more complex lab tables (multi-parameter, with shifts), `{tfrmt}` (Lesson 32) provides cleaner layout. For the capstone we keep it simple.

## 7. Deliverable 5: Cardinal-style FDA Safety Tables

If we wanted to align with FDA Standard Safety Tables and Figures (Lesson 31), we'd use cardinal templates as starting points. For the capstone, this means copying templates from [pharmaverse.github.io/cardinal](https://pharmaverse.github.io/cardinal/) and adapting:

```r
# Copy template (conceptual)
# 1. Browse https://pharmaverse.github.io/cardinal/ to find FDA Table 14.2.1
# 2. Save the Quarto template locally
# 3. Adapt:
#    - Replace pharmaverseadam test data with our study's data
#    - Adjust caption to our table number
#    - Apply sponsor styling
# 4. Render
```

For brevity, we'll skip the full cardinal template chain in this lesson, but the workflow:

- Browse cardinal catalog → copy template → adapt for study data → render

This pattern produces 60-70% of CSR tables without writing them from scratch.

## 8. Deliverable 6: The CSR-Companion teal App

Now the interactive layer. A full CSR-companion app combining the ADaMs:

```r
# app/app.R — the deployable teal app

library(teal)
library(teal.modules.general)
library(teal.modules.clinical)
library(pharmaverseadam)
library(survival)

# Data — using cdisc_data for auto-join-keys
data <- cdisc_data(
  ADSL  = pharmaverseadam::adsl,
  ADAE  = pharmaverseadam::adae,
  ADLB  = pharmaverseadam::adlb,
  ADVS  = pharmaverseadam::advs,
  ADTTE = pharmaverseadam::adtte,
  ADCM  = pharmaverseadam::adcm,
  ADEX  = pharmaverseadam::adex
)

# Modules — comprehensive
mods <- modules(

  # ===== Overview =====
  modules(
    label = "Overview",
    tm_front_page(
      label = "Study Front Page",
      header_text = c(
        "Title" = "Phase III Oncology Study",
        "Drug" = "Investigational Drug X",
        "Population" = "Advanced NSCLC, prior platinum-based therapy"
      )
    ),
    tm_data_table("Data Browser"),
    tm_variable_browser("Variable Browser")
  ),

  # ===== Demographics =====
  modules(
    label = "Demographics",
    tm_t_summary(
      label = "Demographics Summary",
      dataname = "ADSL",
      arm_var = choices_selected(c("ARM", "ACTARM", "TRT01A"), "TRT01A"),
      summarize_vars = choices_selected(
        c("AGE", "AGEGR1", "SEX", "RACE", "ETHNIC", "BMIBL"),
        c("AGE", "AGEGR1", "SEX", "RACE")
      )
    ),
    tm_g_distribution(
      label = "Age Distribution",
      dist_var = data_extract_spec(
        dataname = "ADSL",
        select = select_spec(
          choices = variable_choices(adsl, c("AGE", "BMIBL", "WEIGHTBL")),
          selected = "AGE"
        )
      ),
      strata_var = data_extract_spec(
        dataname = "ADSL",
        select = select_spec(
          choices = variable_choices(adsl, c("ARM", "SEX")),
          selected = "ARM"
        )
      )
    )
  ),

  # ===== Safety =====
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
      grade = choices_selected(c("AETOXGR"), "AETOXGR")
    )
  ),

  # ===== Efficacy =====
  modules(
    label = "Efficacy",
    tm_g_km(
      label = "K-M Plot",
      dataname = "ADTTE",
      arm_var = choices_selected("TRTA", "TRTA"),
      arm_ref_comp = list(
        TRTA = list(ref = "Placebo", comp = c("Xanomeline High Dose", "Xanomeline Low Dose"))
      ),
      paramcd = choices_selected(value_choices("ADTTE", "PARAMCD"), "OS"),
      time_unit_var = choices_selected("AVALU", "AVALU", fixed = TRUE),
      aval_var = choices_selected("AVAL", "AVAL", fixed = TRUE),
      cnsr_var = choices_selected("CNSR", "CNSR", fixed = TRUE)
    ),
    tm_t_tte(
      label = "TTE Summary",
      dataname = "ADTTE",
      arm_var = choices_selected("TRTA", "TRTA"),
      arm_ref_comp = list(
        TRTA = list(ref = "Placebo", comp = c("Xanomeline High Dose"))
      ),
      paramcd = choices_selected(value_choices("ADTTE", "PARAMCD"), "OS")
    ),
    tm_t_coxreg(
      label = "Cox Regression",
      dataname = "ADTTE",
      arm_var = choices_selected("TRTA", "TRTA"),
      arm_ref_comp = list(
        TRTA = list(ref = "Placebo", comp = c("Xanomeline High Dose"))
      ),
      paramcd = choices_selected(value_choices("ADTTE", "PARAMCD"), "OS"),
      cov_var = choices_selected(c("AGE", "SEX"), c("AGE", "SEX"))
    )
  ),

  # ===== Labs =====
  modules(
    label = "Labs",
    tm_t_summary_by(
      label = "Lab Values by Visit",
      dataname = "ADLB",
      arm_var = choices_selected("ARM", "ARM"),
      by_vars = choices_selected("AVISIT", "AVISIT"),
      summarize_vars = choices_selected(c("AVAL", "CHG"), c("AVAL", "CHG")),
      paramcd = choices_selected(value_choices("ADLB", "PARAMCD"), "ALT")
    )
  ),

  # ===== Patient Profile =====
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

# Build the app
app <- init(
  data = data,
  modules = mods,
  filter = teal_slices(
    teal_slice(dataname = "ADSL", varname = "SAFFL", selected = "Y", fixed = TRUE)
  ),
  title = "Phase III Oncology Study X — CSR Companion"
)

# Run
shinyApp(app$ui, app$server)
```

This is a complete, production-style CSR companion app. ~100 lines covering:

- Study overview + data browser + variable explorer
- Demographics summary + age distribution
- AE overview + SOC/PT detail + grade breakdown
- Survival: K-M plot + summary table + Cox regression
- Lab values by visit
- Patient profile drill-down

Users get an interactive companion to the static CSR. Every output is reproducible via "Show R Code". Outputs can be added to a downloadable report.

For deployment to Posit Connect:

```r
# Deploy via rsconnect
library(rsconnect)
rsconnect::deployApp(
  appDir = "app/",
  appFiles = "app.R",
  server = "internal-connect.sponsor.com",
  appName = "study-x-csr-companion"
)
```

## 9. Deliverable 7: XPT Submission Package

For the FDA submission, every ADaM becomes an XPT v5:

```r
# specs/adam_spec.xlsx contains variable-level metadata
mc <- metacore::spec_to_metacore("specs/adam_spec.xlsx")

# List of ADaMs to export
adam_set <- list(
  ADSL  = adsl,
  ADAE  = adae,
  ADLB  = adlb,
  ADVS  = advs,
  ADTTE = adtte
)

# Export each
for (name in names(adam_set)) {
  message("Exporting: ", name)

  data <- adam_set[[name]]

  data_xpt <- data |>
    xportr_metadata(mc, name, verbose = "warn") |>
    xportr_type() |>
    xportr_length() |>
    xportr_label() |>
    xportr_order() |>
    xportr_format() |>
    xportr_df_label(mc)

  xportr_write(
    data_xpt,
    path = file.path("submission/xpt", paste0(tolower(name), ".xpt"))
  )
}

# Result: submission/xpt/adsl.xpt, adae.xpt, adlb.xpt, advs.xpt, adtte.xpt
```

Plus the Define-XML (produced separately via metacore or commercial tools — typically Pinnacle 21 or Define-XML generators), the analysis data reviewer's guide (ADRG), and the TLF PDF or RTFs.

Submission package structure:

```
submission/
├── xpt/
│   ├── adsl.xpt
│   ├── adae.xpt
│   ├── adlb.xpt
│   ├── advs.xpt
│   └── adtte.xpt
├── define.xml
├── reviewer_guide.pdf
├── tlfs/
│   ├── t_14_2_1_demographics.rtf
│   ├── t_14_3_1_os.rtf
│   ├── t_14_4_1_ae.rtf
│   ├── t_14_5_1_alt.rtf
│   └── f_14_3_1_km_os.png
└── README.txt
```

For Dataset-JSON submission (parallel pilot):

```r
for (name in names(adam_set)) {
  data <- adam_set[[name]]

  ds_json <- dataset_json(
    .df = data,
    itemGroupOID = paste0("IG.", name),
    name = name,
    label = attr(data, "label") %||% name
  ) |>
    set_study_oid("STUDY001") |>
    set_metadata_ref("define.xml") |>
    set_originator("Sponsor Inc.")

  write_dataset_json(
    ds_json,
    file.path("submission/json", paste0(tolower(name), ".json"))
  )
}
```

Both formats produced. XPT is the current submission; JSON is the parallel pilot for the upcoming transition.

## 10. The full traceability layer

Wrap everything with logrx for the audit trail:

```bash
#!/bin/bash
# run_all.sh

# 1. Build ADaMs (Lesson 47)
for script in programs/data_pipeline/*.R; do
  Rscript -e "logrx::axecute('$script', log_path = 'logs/data_pipeline/')"
done

# 2. Build ARDs and tables (Lesson 48)
for script in programs/deliverables/*.R; do
  Rscript -e "logrx::axecute('$script', log_path = 'logs/deliverables/')"
done

# 3. Export submission
Rscript -e "logrx::axecute('programs/submission/export_xpt.R', log_path = 'logs/submission/')"
Rscript -e "logrx::axecute('programs/submission/export_json.R', log_path = 'logs/submission/')"

# 4. Package risk assessment
Rscript -e "logrx::axecute('programs/qc/risk_assessment.R', log_path = 'logs/qc/')"

echo "Pipeline complete."
ls -la outputs/
ls -la submission/
ls -la logs/
```

Every script produces a log. The complete audit trail lives in `logs/` — searchable, archivable, regulatory-grade.

## 11. The QC layer

For dual programming, every artifact gets a QC comparison:

```r
library(diffdf)

qc_pairs <- list(
  list(prod = "data/adam/adsl.rds", qc = "qc/adam/adsl.rds", keys = "USUBJID"),
  list(prod = "data/adam/adae.rds", qc = "qc/adam/adae.rds", keys = c("USUBJID", "AESEQ")),
  list(prod = "data/adam/adlb.rds", qc = "qc/adam/adlb.rds", keys = c("USUBJID", "PARAMCD", "AVISITN")),
  list(prod = "data/adam/adtte.rds", qc = "qc/adam/adtte.rds", keys = c("USUBJID", "PARAMCD"))
)

for (pair in qc_pairs) {
  prod <- readRDS(pair$prod)
  qc <- readRDS(pair$qc)

  result <- diffdf(prod, qc, keys = pair$keys, tolerance = 1e-6)

  if (length(result$VarsInBaseOnly) > 0 || length(result$ValDiffs) > 0) {
    diffdf(prod, qc, keys = pair$keys, tolerance = 1e-6,
           file = paste0("qc/diff_", basename(pair$prod), ".txt"))
    message("DISCREPANCY in ", basename(pair$prod), " — see qc/diff_*.txt")
  } else {
    message(basename(pair$prod), ": clean")
  }
}
```

For ARDs and tables, similar pattern — compare primary vs QC outputs.

## 12. The package risk assessment

Once per project, document the risk profile of all packages used:

```r
library(riskmetric)
library(dplyr)
library(writexl)

study_packages <- c(
  "admiral", "admiralonco", "metacore", "metatools",
  "pharmaverseadam", "pharmaversesdtm",
  "cards", "cardx", "gtsummary", "rtables", "tern", "xportr",
  "teal", "teal.modules.general", "teal.modules.clinical",
  "datasetjson", "logrx", "diffdf",
  "dplyr", "haven"
)

risk_results <- tibble(package = study_packages) |>
  mutate(
    ref = lapply(package, pkg_ref),
    score_obj = lapply(lapply(ref, pkg_assess), pkg_score)
  ) |>
  tidyr::unnest_wider(score_obj)

write_xlsx(risk_results, "qc/study_package_risk_assessment.xlsx")
```

Archive alongside the submission for audit.

## 13. The complete deliverable tree

After running the full pipeline:

```
study_capstone/
├── data/
│   ├── raw/                       # raw EDC (or pharmaverseraw)
│   ├── sdtm/                      # SDTM datasets
│   └── adam/                      # ADaM datasets (.rds and .xpt)
├── outputs/
│   ├── ards/                      # Analysis Results Datasets
│   │   ├── demographics_ard.rds
│   │   ├── ae_incidence_ard.rds
│   │   ├── os_survival_ard.rds
│   │   └── lab_alt_ard.rds
│   ├── tables/                    # Submission-grade RTFs
│   │   ├── t_14_2_1_demographics.rtf
│   │   ├── t_14_3_1_os.rtf
│   │   ├── t_14_4_1_ae.rtf
│   │   └── t_14_5_1_alt.rtf
│   └── figures/
│       └── f_14_3_1_km_os.png
├── app/
│   └── app.R                      # CSR companion teal app
├── submission/
│   ├── xpt/                       # FDA-format XPT v5 files
│   │   ├── adsl.xpt
│   │   ├── adae.xpt
│   │   ├── adlb.xpt
│   │   ├── advs.xpt
│   │   └── adtte.xpt
│   ├── json/                      # Dataset-JSON parallel pilot
│   │   ├── adsl.json
│   │   ├── adae.json
│   │   └── ...
│   ├── define.xml
│   ├── reviewer_guide.pdf
│   ├── tlfs/                      # All RTFs assembled
│   └── README.txt
├── logs/                          # logrx audit trail per script
├── qc/                            # diffdf comparison reports
│   ├── diff_adsl.txt
│   ├── diff_adae.txt
│   ├── study_package_risk_assessment.xlsx
│   └── ...
├── programs/                      # All R scripts
│   ├── data_pipeline/
│   ├── deliverables/
│   ├── submission/
│   └── qc/
├── specs/
│   └── adam_spec.xlsx
├── renv.lock                      # Locked environment
└── README.md
```

This is a complete, audit-ready pharmaverse R-based study deliverable. Everything from raw EDC through submission packaging, with full traceability and validation.

## 14. What you've accomplished

If you've followed the curriculum and completed the capstone, you can now:

- **Build SDTM** from raw EDC data using sdtm.oak's algorithmic framework
- **Build ADaMs** using admiral + TA extensions (admiralonco, admiralvaccine, etc.)
- **Manage specs** with metacore as the single source of truth
- **Validate ADaMs** with metatools, sdtmchecks, diffdf
- **Build ARDs** using cards/cardx — the CDISC ARS-aligned analysis results format
- **Render CSR tables** using both stacks:
  - Cardinal-future: gtsummary + tfrmt + cardinal templates
  - Legacy: rtables + tern + r2rtf
- **Build interactive apps** with teal — both pre-built modules and custom modules
- **Export to FDA formats** via xportr (XPT v5) and datasetjson (Dataset-JSON v1.1)
- **Ensure traceability** with logrx, diffdf, and riskmetric

That's the complete pharmaverse skill set for clinical reporting in R.

## 15. Where to go from here

For continued learning:

- **Pharmaverse Slack**: active community across all packages
- **Pharmaverse examples**: [https://pharmaverse.github.io/examples/](https://pharmaverse.github.io/examples/) — TLG examples across stacks
- **Cardinal catalog**: [https://pharmaverse.github.io/cardinal/](https://pharmaverse.github.io/cardinal/) — TLG templates to copy
- **TLG Catalog**: [https://insightsengineering.github.io/tlg-catalog/](https://insightsengineering.github.io/tlg-catalog/) — cross-stack TLG implementations
- **R Validation Hub**: [https://www.pharmar.org/](https://www.pharmar.org/) — validation framework
- **R-Submissions Working Group**: tracking FDA Dataset-JSON acceptance
- **R/Pharma conference**: annual pharmaverse-focused conference
- **Posit Conference**: pharma track sessions
- **R for Clinical Study Reports book**: [https://r4csr.org/](https://r4csr.org/) — Merck's free book

For real implementation at your sponsor:

- Start with a low-stakes study (e.g., a small Phase I) to build muscle
- Use pharmaverseadam data to prototype before applying to your study
- Partner with QA early — the validation framework needs sponsor buy-in
- Adopt incrementally: ADaM first, then TLG, then teal, then full submission
- Don't rewrite working SAS pipelines just because R is shiny — pick the right tool

The pharmaverse story is one of **community-driven open-source pharma R adoption**. The packages exist because individual programmers and companies decided to share rather than duplicate. Joining the community (Slack, GitHub, conferences) accelerates your team's adoption substantially.

## 16. Key takeaways

- The capstone integrates every concept from Modules 0-10 into a complete deliverable
- ARDs are built once and feed multiple displays (CSR tables, slides, posters, teal app)
- Both TLG stacks (Cardinal-future and legacy) coexist; pick the right tool per table type
- A complete CSR companion teal app is ~100 lines combining ~10 modules
- Submission package includes XPT (mandatory) + Dataset-JSON (parallel pilot)
- Full traceability layer: logrx logs every script; diffdf QCs every output; riskmetric documents package risk
- The pattern scales from one-off studies to organization-wide infrastructure
- This curriculum brings you to the level where you can build production pharma deliverables in R end to end

## 17. Final notes

This is the end of the curriculum. **48 lessons, ~140,000 words, ~16 hours spoken**, covering the full pharmaverse from R foundations through FDA submission.

You're now equipped to:

- Read and contribute to pharmaverse codebases
- Build production R pipelines for clinical reporting
- Choose appropriate tools for each task in your sponsor's workflow
- Train and onboard SAS programmers transitioning to R
- Engage with the broader pharmaverse community

**The transition from SAS to R in pharma is happening now, in real time, across the industry.** You're not late; you're in the middle. The infrastructure (these packages, these patterns) exists because programmers like you decided to build it.

Welcome to pharmaverse. Build well.

---

## Self-check questions

1. Why do we save ARDs as durable artifacts even though we can regenerate them?
2. When would you use rtables + tern (legacy stack) vs gtsummary (Cardinal-future) for a particular table?
3. What's the difference between submitting XPT and submitting Dataset-JSON in 2026?
4. How does the CSR-companion teal app complement the static CSR tables?
5. List the traceability layer's three packages and what each provides.
6. What's the practical pattern for adopting pharmaverse R at a SAS-heritage sponsor?

## Glossary

- **CSR companion app** — Interactive teal app providing exploration alongside the static CSR
- **Cardinal-future stack** — cards + cardx + gtsummary + tfrmt + cardinal templates
- **Legacy stack** — rtables + tern + r2rtf (or chevron orchestrating these)
- **Dual-stack approach** — Using different tools for different tables based on fit (common in practice)
- **Submission package** — Complete bundle: XPT/JSON data + Define-XML + ADRG + TLFs
- **eCTD** — Electronic Common Technical Document; FDA submission format
- **ADRG** — Analysis Data Reviewer's Guide; required submission document
- **Pinnacle 21** — Industry-standard CDISC validation tool
- **Pharmaverse Slack** — Active community for all packages
- **R Validation Hub** — Industry validation framework
- **Pharma R Adoption** — The transition story; community-driven, decade-long, in progress
