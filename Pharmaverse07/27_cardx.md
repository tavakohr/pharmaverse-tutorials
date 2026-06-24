# Lesson 27 — `{cardx}` and `{siera}`: Inferential ARDs and ARS Automation

**Module**: 6 — TLG: the Cardinal-future stack
**Estimated length**: ~35 min spoken
**Prerequisites**: Lessons 25–26 (cards)

> **Companion animation**: [ars_builder_animation.html](../animations/ars_builder_animation.html)
> (standalone — open in a browser) — animates a mock shell being authored
> block-by-block into CDISC ARS JSON.

---

## Learning objectives

By the end of this lesson, you will be able to:

1. Explain what `{cardx}` adds to `{cards}` — inferential statistics with the same ARD structure
2. Use `ard_stats_t_test()`, `ard_stats_chisq_test()`, `ard_stats_fisher_test()` for univariate tests
3. Use `ard_regression()` for linear, logistic, and Cox model output as ARDs
4. Use `ard_survival_survfit()` for Kaplan-Meier estimates (x-year survival and median)
5. Use `ard_survival_survdiff()` for log-rank tests
6. Use `ard_proportion_ci()` for proportion confidence intervals with multiple CI methods
7. Combine descriptive (cards) + inferential (cardx) ARDs into one display-ready dataset
8. Explain the `{siera}` package: what it does, its main function `readARS()`, and how to use it
9. Walk through a `{siera}` workflow from ARS metadata to auto-generated R scripts to ARD

---

## 1. What `{cardx}` adds

`{cards}` covers descriptive statistics: counts, means, medians. But clinical reporting also needs **inferential** statistics:

- p-values from t-tests on demographics differences between arms
- Confidence intervals for proportions (Wilson, Clopper-Pearson, etc.)
- Regression coefficients with SEs and CIs
- Hazard ratios from Cox models
- Kaplan-Meier median survival and x-year survival rates
- Mixed-model treatment estimates (MMRM)

`{cardx}` wraps all of these into the same ARD structure. Same column layout (`group1`, `variable`, `stat_name`, `stat_label`, `stat`). Same list-column for `stat`. Same error/warning capture. The only difference is the `context` column value changes to reflect the inferential function used.

```r
install.packages("cardx")
library(cards)
library(cardx)
library(survival)
library(pharmaverseadam)
library(dplyr)
```

---

## 2. Packages cardx wraps

cardx imports statistical computation from a wide range of R packages:

| Package | What cardx wraps |
|---|---|
| `{stats}` (base R) | `t.test()`, `chisq.test()`, `fisher.test()`, `wilcox.test()`, `lm()`, `glm()` |
| `{survival}` | `survfit()`, `coxph()`, `survdiff()` |
| `{lme4}` | `lmer()`, `glmer()` (mixed models) |
| `{mmrm}` | `mmrm()` (MMRM for clinical trials) |
| `{geepack}` | `geeglm()` (GEE models) |
| `{emmeans}` | Estimated marginal means and contrasts |
| `{effectsize}` | Cohen's d and other effect sizes |
| `{smd}` | Standardized mean differences |
| `{survey}` | Survey-weighted analyses |
| `{car}` | Analysis-of-variance |
| `{broom.helpers}` | Tidy model extraction backbone |

The pattern: `ard_<package>_<model_type>()` wraps the relevant function and returns an ARD.

---

## 3. Univariate comparison tests

### t-test: comparing continuous variables between arms

The most common use: add a p-value column to a demographics table.

```r
adsl_2arm <- pharmaverseadam::adsl |>
  filter(SAFFL == "Y" &
         ARM %in% c("Xanomeline High Dose", "Xanomeline Low Dose"))

# Two-sample t-test on AGE
age_ttest <- ard_stats_t_test(
  adsl_2arm,
  by        = ARM,
  variables = AGE
)

age_ttest |>
  select(variable, stat_name, stat_label, stat) |>
  mutate(value = map(stat, 1))
```

```
   variable  stat_name   stat_label      value
1  AGE       estimate    Mean Diff       -1.286
2  AGE       estimate1   Group 1 Mean    74.381
3  AGE       estimate2   Group 2 Mean    75.667
4  AGE       statistic   t Statistic     -1.043
5  AGE       p.value     p-value         0.299
6  AGE       parameter   Degrees of F    165.4
7  AGE       conf.low    CI Lower        -3.722
8  AGE       conf.high   CI Upper         1.151
9  AGE       method      Method          Welch Two Sample t-test
10 AGE       alternative Alternative     two.sided
```

Every piece of the t-test output is a separate row. This matters because you can filter to just `p.value` for a demographics table's p-value column, or include the CI bounds for a more detailed comparison table.

The `method` row tells you which variant of the t-test was used ("Welch Two Sample t-test" vs "Two Sample t-test"). This is traceability you don't get with SAS `PROC TTEST` output by default.

**SAS equivalent**: `PROC TTEST DATA=adsl_2arm; CLASS arm; VAR age; RUN;` — but the SAS output goes to a report, not a structured dataset you can filter.

```r
# Paired t-test (within-subject change from baseline against 0):
ard_stats_t_test(
  advs |> filter(TRTA == "Xanomeline High Dose" & PARAMCD == "WEIGHT"),
  variables = CHG,
  mu        = 0    # test: mean(CHG) = 0
)

# One-sided test:
ard_stats_t_test(adsl_2arm, by = ARM, variables = AGE,
                 alternative = "less")

# Equal variance (Student's t-test, not Welch's):
ard_stats_t_test(adsl_2arm, by = ARM, variables = AGE,
                 var.equal = TRUE)
```

### Wilcoxon rank-sum test

For non-normally distributed variables:

```r
ard_stats_wilcox_test(
  adsl_2arm,
  by        = ARM,
  variables = AGE
)
```

Returns `statistic` (W), `p.value`, `method` ("Wilcoxon rank sum test"), `alternative`.

### Chi-squared and Fisher's exact tests

For categorical variables in a demographics table:

```r
# Chi-squared
sex_chisq <- ard_stats_chisq_test(
  adsl_2arm,
  by        = ARM,
  variables = c(SEX, AGEGR1)
)

# Fisher's exact (better for small cell counts)
sex_fisher <- ard_stats_fisher_test(
  adsl_2arm,
  by        = ARM,
  variables = SEX
)

sex_fisher |>
  filter(stat_name == "p.value") |>
  mutate(p = map_dbl(stat, 1))
# p = 0.847  (no significant sex difference between arms)
```

**SAS equivalent**: `PROC FREQ DATA=adsl_2arm; TABLES arm * sex / CHISQ EXACT; RUN;`

---

## 4. Proportion confidence intervals — `ard_proportion_ci()`

One of the most practically important cardx functions for pharma reporting: confidence intervals for proportions, with multiple CI methods.

```r
# Response rate in the efficacy population
adsl_eff <- adsl |> filter(EFFFL == "Y") |>
  mutate(RESPONDER = factor(if_else(MMRMS_RESPONSE == "Y", "Y", "N"),
                            levels = c("Y", "N")))

# Wilson CI (preferred for clinical reporting — handles small n and proportions near 0/1)
resp_ci_ard <- ard_proportion_ci(
  adsl_eff,
  by        = TRT01A,
  variables = RESPONDER,
  value     = "Y",        # which level is the "success"
  method    = "wilson"    # Wilson score interval
)

resp_ci_ard |>
  mutate(value = map(stat, 1)) |>
  select(group1_level, stat_name, value)
```

```
   group1_level           stat_name  value
1  Placebo                estimate   0.481   (proportion responding)
2  Placebo                conf.low   0.376   (Wilson CI lower)
3  Placebo                conf.high  0.589   (Wilson CI upper)
4  Placebo                n          41
5  Placebo                N          86
...
```

**Available CI methods**:

| `method` argument | Method name | Notes |
|---|---|---|
| `"wilson"` | Wilson score interval | Recommended for proportions; handles extremes well |
| `"wilson_correct"` | Wilson with continuity correction | More conservative |
| `"clopper_pearson"` | Clopper-Pearson "exact" | Exact CI; common in regulatory submissions |
| `"wald"` | Wald interval | Simplest but poor at extremes |
| `"agresti_coull"` | Agresti-Coull | Good for small N |
| `"jeffreys"` | Jeffreys Bayesian | Symmetric; good properties |

**SAS equivalent**: SAS base does not provide Wilson or Clopper-Pearson CIs natively. You'd need `PROC FREQ` with `BINOMIAL(CL=WILSON)` or macro workarounds. This is an area where R is strictly superior.

### Combining response rate with CI in one ARD

```r
# Proportion (count) from cards
response_count_ard <- ard_categorical(
  adsl_eff,
  by        = TRT01A,
  variables = RESPONDER
)

# CI from cardx
response_ci_ard <- ard_proportion_ci(
  adsl_eff,
  by = TRT01A, variables = RESPONDER, value = "Y", method = "wilson"
)

# Combined: both in one ARD for display
response_full_ard <- bind_ard(response_count_ard, response_ci_ard)
```

---

## 5. Mean confidence intervals — `ard_continuous_ci()`

For continuous variable confidence intervals (independent of the `ard_continuous()` default SEM-based CI):

```r
# 95% CI for mean CHG at Week 24
ard_continuous_ci(
  advs |> filter(PARAMCD == "WEIGHT" & AVISIT == "Week 24" & ANL01FL == "Y"),
  by       = TRTA,
  variables = CHG,
  conf.level = 0.95,
  method   = "t.test"    # t-distribution CI
)
```

Available methods: `"t.test"`, `"wilcox.test"`, `"boot"` (bootstrap).

---

## 6. Regression: `ard_regression()`

`ard_regression()` is a universal converter: give it any fitted model object, get back an ARD.

### Linear regression

```r
advs_wk24 <- pharmaverseadam::advs |>
  filter(PARAMCD == "WEIGHT" & AVISIT == "Week 24" & ANL01FL == "Y" & SAFFL == "Y")

model_lm <- lm(CHG ~ BASE + TRTA + AGE + SEX, data = advs_wk24)

reg_ard <- ard_regression(model_lm)

reg_ard |>
  filter(stat_name %in% c("estimate", "conf.low", "conf.high", "p.value")) |>
  mutate(value = map_dbl(stat, 1)) |>
  select(variable, variable_level, stat_name, value)
```

```
   variable  variable_level           stat_name  value
1  BASE      <NA>                     estimate   0.847
2  BASE      <NA>                     conf.low   0.712
3  BASE      <NA>                     conf.high  0.982
4  BASE      <NA>                     p.value    0.000
5  TRTA      Placebo                  estimate   0.000    (reference)
6  TRTA      Xanomeline High Dose     estimate  -1.823
7  TRTA      Xanomeline High Dose     conf.low  -3.241
8  TRTA      Xanomeline High Dose     conf.high -0.405
9  TRTA      Xanomeline High Dose     p.value    0.012
...
```

The reference level for factor variables appears with `estimate = 0` (and other stats as NA). Non-reference levels show estimates relative to the reference. This is identical to what SAS `PROC REG` with `CLASS TRTA(REF=...)` would produce, but now in a structured dataset.

### Logistic regression

```r
adsl_resp <- adsl |>
  filter(EFFFL == "Y") |>
  mutate(RESP_NUM = if_else(MMRMS_RESPONSE == "Y", 1L, 0L))

model_glm <- glm(
  RESP_NUM ~ TRTA + AGE + SEX,
  data   = adsl_resp,
  family = binomial(link = "logit")
)

logit_ard <- ard_regression(model_glm)

# To show odds ratios (exp of log-odds):
logit_ard |>
  filter(stat_name == "estimate") |>
  mutate(OR = exp(map_dbl(stat, 1))) |>
  select(variable, variable_level, OR)
```

**SAS equivalent**: `PROC LOGISTIC DATA=adsl_resp; CLASS trta sex; MODEL resp_num(EVENT='1') = trta age sex; ODDSRATIO trta; RUN;`

The key difference: `ard_regression()` returns log-odds by default (like SAS coefficients). Exponentiation to odds ratios happens downstream — either manually with `exp()`, or automatically by `{gtsummary}` when building an `add_difference()` table.

### Cox proportional hazards

```r
adtte_os <- pharmaverseadam::adtte |>
  filter(PARAMCD == "OS" & SAFFL == "Y")

cox_fit <- coxph(
  Surv(AVAL, 1 - CNSR) ~ TRTA + AGE + SEX,
  data = adtte_os
)

cox_ard <- ard_regression(cox_fit)

# Hazard ratios: exp(log-HR)
cox_ard |>
  filter(stat_name == "estimate") |>
  mutate(HR = exp(map_dbl(stat, 1))) |>
  select(variable, variable_level, HR)
```

**SAS equivalent**: `PROC PHREG DATA=adtte_os; CLASS trta sex; MODEL aval * cnsr(1) = trta age sex; HAZARDRATIO trta; RUN;`

**Always remember**: `CNSR = 1` in ADTTE means *censored*. `Surv()` second argument means *event occurred*. Convert: `Surv(AVAL, 1 - CNSR)`.

---

## 7. Kaplan-Meier survival ARDs

### x-year survival rates

```r
km_fit <- survfit(Surv(AVAL, 1 - CNSR) ~ TRTA, data = adtte_os)

# x-day survival rates (e.g., 180-day and 365-day)
km_xyear_ard <- ard_survival_survfit(km_fit, times = c(180, 365))

km_xyear_ard |>
  mutate(value = map_dbl(stat, 1)) |>
  select(group1_level, stat_name, value)
```

```
   group1_level           stat_name   value
1  Placebo                estimate    0.721   (72.1% survival at day 180)
2  Placebo                conf.low    0.632
3  Placebo                conf.high   0.821
4  Placebo                n.risk      52
5  Placebo                n.event     24
6  Xanomeline High Dose   estimate    0.788   (78.8% survival at day 180)
...
```

### Median survival with CI

```r
km_median_ard <- ard_survival_survfit(km_fit, probs = 0.5)

km_median_ard |>
  filter(stat_name %in% c("estimate", "conf.low", "conf.high")) |>
  mutate(days = map_dbl(stat, 1)) |>
  select(group1_level, stat_name, days)
# Shows: median survival time in days per arm, with CI
```

### Both together

```r
km_full_ard <- bind_ard(km_xyear_ard, km_median_ard)
```

**Confidence interval methods**: The default is Greenwood's formula on the log scale. To use other methods:

```r
km_fit_plain <- survfit(
  Surv(AVAL, 1 - CNSR) ~ TRTA, data = adtte_os,
  conf.type = "plain"    # linear CI
)
ard_survival_survfit(km_fit_plain, times = c(180, 365))
```

**Pattern B** (without pre-building survfit):

```r
km_ard_alt <- adtte_os |>
  ard_survival_survfit(
    y         = Surv(AVAL, 1 - CNSR),
    variables = "TRTA",
    times     = c(180, 365)
  )
```

**SAS equivalent**: `PROC LIFETEST DATA=adtte_os METHOD=KM PLOTS=SURVIVAL; TIME aval * cnsr(1); STRATA trta; ODS OUTPUT QUARTILES=km_medians SURVIVALPLOT=km_data; RUN;`

---

## 8. Log-rank test: `ard_survival_survdiff()`

```r
logrank_ard <- survdiff(
  Surv(AVAL, 1 - CNSR) ~ TRTA,
  data = adtte_os
) |>
  ard_survival_survdiff()

logrank_ard |>
  filter(stat_name == "p.value") |>
  mutate(p = map_dbl(stat, 1))
# p = 0.043
```

**SAS equivalent**: `PROC LIFETEST; ... STRATA trta / LOGRANK; RUN;` with `ODS OUTPUT HomTests=logrank;`

---

## 9. Mixed models: MMRM for repeated measures

For the primary efficacy endpoint in many trials — Mixed Model with Repeated Measures:

```r
library(mmrm)

advs_mmrm <- pharmaverseadam::advs |>
  filter(SAFFL == "Y" & PARAMCD == "WEIGHT" & ANL01FL == "Y") |>
  filter(!is.na(CHG) & !is.na(BASE) & !is.na(AVISIT))

# Fit MMRM with unstructured covariance
mmrm_fit <- mmrm(
  formula = CHG ~ BASE + TRTA + AVISIT + TRTA:AVISIT + us(AVISIT | USUBJID),
  data    = advs_mmrm
)

mmrm_ard <- ard_regression(mmrm_fit)

# Extract treatment effect at last visit:
mmrm_ard |>
  filter(grepl("TRTA", variable) & stat_name == "estimate") |>
  mutate(effect = map_dbl(stat, 1)) |>
  select(variable, variable_level, effect)
```

For estimated marginal means (LS means) with contrasts:

```r
library(emmeans)

emm_ard <- ard_emmeans(
  object      = mmrm_fit,
  spec        = ~ TRTA | AVISIT,
  at          = list(AVISIT = "Week 24")
)

# Contains: estimate (LS mean per arm), SE, CI
```

**SAS equivalent**: `PROC MIXED DATA=advs_mmrm; CLASS trta avisit usubjid; MODEL chg = base trta avisit trta*avisit / SOLUTION DDFM=KR; REPEATED avisit / SUBJECT=usubjid TYPE=UN; LSMEANS trta / DIFF CL; RUN;`

---

## 10. Standardized mean differences: `ard_smd()`

For assessing covariate balance (e.g., comparing randomized arms or propensity-matched groups):

```r
library(smd)

ard_smd(
  adsl_saf,
  by        = TRT01A,
  variables = c(AGE, BMIBL, SEX, RACE)
)
```

Returns Cohen's d (for continuous) or standardized difference (for categorical) per variable per treatment comparison. Useful for "Table 1" in observational studies or to assess randomization balance.

---

## 11. Combining cards + cardx into one display-ready ARD

The typical demographics table with p-values: descriptive stats from cards, p-values from cardx, combined in one ARD:

```r
adsl_2arm <- adsl_saf |>
  filter(ARM %in% c("Xanomeline High Dose", "Xanomeline Low Dose"))

# Descriptive: cards
desc_ard <- ard_stack(
  adsl_2arm,
  ard_continuous(variables = AGE),
  ard_categorical(variables = c(SEX, AGEGR1, RACE)),
  .by      = ARM,
  .total_n = TRUE
)

# Inferential: cardx
pval_ard <- bind_ard(
  ard_stats_t_test(adsl_2arm,    by = ARM, variables = AGE),
  ard_stats_chisq_test(adsl_2arm, by = ARM, variables = c(SEX, AGEGR1, RACE))
)

# Combined
demog_with_pvalues_ard <- bind_ard(desc_ard, pval_ard)

# The context column distinguishes them:
demog_with_pvalues_ard |>
  distinct(context)
# "continuous", "categorical", "total_n", "stats_t_test", "stats_chisq_test"
```

`{gtsummary}` can consume this combined ARD and automatically place p-values in the correct column. We cover this in Lessons 28–29.

---

## 12. Complete inferential ARD pipeline: primary efficacy

```r
library(cards); library(cardx); library(survival); library(mmrm)
library(dplyr); library(pharmaverseadam)

adsl_eff  <- pharmaverseadam::adsl  |> filter(EFFFL == "Y")
adtte_os  <- pharmaverseadam::adtte |> filter(PARAMCD == "OS"  & SAFFL == "Y")
adtte_pfs <- pharmaverseadam::adtte |> filter(PARAMCD == "PFS" & SAFFL == "Y")

# ─── K-M: Overall Survival ────────────────────────────────────────────────────
km_os <- survfit(Surv(AVAL, 1 - CNSR) ~ TRTA, data = adtte_os)
os_xyr   <- ard_survival_survfit(km_os, times = c(180, 365))
os_med   <- ard_survival_survfit(km_os, probs = 0.5)
os_lr    <- survdiff(Surv(AVAL, 1 - CNSR) ~ TRTA, data = adtte_os) |>
              ard_survival_survdiff()
cox_os   <- coxph(Surv(AVAL, 1 - CNSR) ~ TRTA + AGE + SEX, data = adtte_os) |>
              ard_regression()

os_ard <- bind_ard(os_xyr, os_med, os_lr, cox_os)

# ─── K-M: PFS ────────────────────────────────────────────────────────────────
km_pfs <- survfit(Surv(AVAL, 1 - CNSR) ~ TRTA, data = adtte_pfs)
pfs_xyr  <- ard_survival_survfit(km_pfs, times = c(90, 180))
pfs_med  <- ard_survival_survfit(km_pfs, probs = 0.5)
pfs_lr   <- survdiff(Surv(AVAL, 1 - CNSR) ~ TRTA, data = adtte_pfs) |>
              ard_survival_survdiff()

pfs_ard <- bind_ard(pfs_xyr, pfs_med, pfs_lr)

# ─── Response rate (proportion CI) ───────────────────────────────────────────
adsl_resp <- adsl_eff |>
  mutate(RESP = factor(if_else(EFFFL == "Y", "Y", "N"), c("Y", "N")))

resp_count  <- ard_categorical(adsl_resp, by = TRT01A, variables = RESP)
resp_ci     <- ard_proportion_ci(adsl_resp, by = TRT01A, variables = RESP,
                                 value = "Y", method = "wilson")
resp_ard    <- bind_ard(resp_count, resp_ci)

# ─── Validate ────────────────────────────────────────────────────────────────
walk(
  list(os_ard = os_ard, pfs_ard = pfs_ard, resp_ard = resp_ard),
  ~ { check_ard_structure(.x); print_ard_conditions(.x) }
)

# ─── Save ────────────────────────────────────────────────────────────────────
saveRDS(os_ard,   "ards/os_ard.rds")
saveRDS(pfs_ard,  "ards/pfs_ard.rds")
saveRDS(resp_ard, "ards/resp_ard.rds")
```

---

## 13. Introducing `{siera}`: ARS metadata → ARD programs

So far in this module we've been writing `{cards}` and `{cardx}` calls manually. The ARS standard envisions a higher automation level: **start from a structured specification, auto-generate the calculation code, never write boilerplate from scratch.**

`{siera}` is the R implementation of this vision.

### What siera does

`{siera}` takes an ARS file (JSON or XLSX) describing your reporting event — what analyses to run, on what populations, with what statistical methods — and generates one R script per output. Each script, when run against ADaM datasets, produces an ARD for that output.

**Key insight**: The specification-to-code step is automated. The programmer's job shifts from "write `ard_continuous()` calls" to "review and validate generated scripts, then run them."

### Installation

```r
install.packages("siera")   # CRAN
library(siera)
```

### The main function: `readARS()`

```r
readARS(
  ARS_path      = "path/to/ars_metadata.xlsx",  # or .json
  output_folder = "programs/ARDs/",              # where R scripts go
  ADaM_folder   = "data/adam/"                   # where .csv or .xpt ADaMs live
)
```

After running, you'll have one `.R` file per output in `output_folder`. Running any of these scripts produces an `ARD` object.

### Example: using siera's bundled data

```r
library(siera)

# View the bundled example files:
ARS_example()
# [1] "ADAE.csv"                           "ADEXSUM.csv"
# [3] "ADSL.csv"                           "ADVS.csv"
# [5] "Common_Safety_Displays_cards.xlsx"  "exampleARS_1.json"
# ... (several ARS JSON and XLSX examples)

# Use the CDISC Common Safety Displays ARS file (XLSX format):
ARS_path    <- ARS_example("Common_Safety_Displays_cards.xlsx")
output_dir  <- tempdir()
ADaM_dir    <- dirname(ARS_example("ADSL.csv"))

# Generate R scripts:
readARS(ARS_path, output_dir, ADaM_dir)
# Creates: ARD_Out14-1-1.R, ARD_Out14-3-1-1.R, ARD_Out14-3-2-1.R, etc.

list.files(output_dir, pattern = "ARD_.*\\.R")
# [1] "ARD_Out14-1-1.R"    "ARD_Out14-3-1-1.R"  "ARD_Out14-3-2-1.R"
# [4] "ARD_Out14-3-3-1a.R" "ARD_Out14-3-3-1b.R"
```

### Running a generated script

```r
# Run the demographics table script:
example_script <- ARD_script_example("ARD_Out14-1-1.R")
source(example_script)

# The ARD is named "ARD" by convention
head(ARD)
```

```
   group1  group1_level  group2  group2_level  variable  variable_level  stat_name  stat_label  stat
1  <NA>                  <NA>                  TRT01A    Placebo         n          n           86
2  <NA>                  <NA>                  TRT01A    Xanomeline...   n          n           84
3  <NA>                  <NA>                  TRT01A    Xanomeline...   n          n           84
4  TRT01A  Placebo       <NA>                  AGE       <NA>            N          N           86
5  TRT01A  Placebo       <NA>                  AGE       <NA>            mean       Mean        75.209
6  TRT01A  Placebo       <NA>                  AGE       <NA>            sd         SD          8.59
```

This is a standard `{cards}` ARD, generated from the ARS specification — not from manually written R code.

### Anatomy of a siera-generated script

Each generated script follows this structure:

```r
# === Section 1: Program header ===
# Output: Out14-1-1  (Demographics Summary Table)
# Generated by siera 0.5.5 from: Common_Safety_Displays_cards.xlsx
# Date: 2025-06-22

# === Section 2: Libraries ===
library(cards)
library(cardx)
library(dplyr)

# === Section 3: Load ADaM datasets ===
ADSL <- read.csv("data/adam/ADSL.csv")

# === Section 4a: Big-N analysis (by convention, always first) ===
# Analysis: An01_05_SAF_Summ_ByTrt (Safety Population N per arm)
# Apply Analysis Set: SAFFL == "Y"
df_pop <- dplyr::filter(ADSL, SAFFL == "Y")

df3_An01_05 <- cards::ard_categorical(
  data = df_pop |> dplyr::select(TRT01A) |> dplyr::mutate(dummy = "x"),
  by   = "TRT01A",
  variables = "dummy"
) |>
  dplyr::filter(stat_name == "n") |>
  dplyr::mutate(
    AnalysisId = "An01_05_SAF_Summ_ByTrt",
    MethodId   = "Mth01",
    OutputId   = "Out14-1-1"
  )

# === Section 4b: AGE summary analysis ===
# Analysis: An03_01_Age_Summ_ByTrt
df2_An03_01 <- df_pop  # no additional data subset

df3_An03_01 <- cards::ard_continuous(
  data       = df2_An03_01,
  by         = c(TRT01A),
  variables  = AGE
) |>
  dplyr::mutate(
    AnalysisId = "An03_01_Age_Summ_ByTrt",
    MethodId   = "Mth02",
    OutputId   = "Out14-1-1"
  )

# ... (one section per Analysis in the spec)

# === Section 5: Combine analyses ===
ARD <- dplyr::bind_rows(
  df3_An01_05,
  df3_An03_01,
  df3_An03_02_AgeGrp,
  df3_An03_03_Sex,
  df3_An03_04_Ethnic,
  df3_An03_05_Race
)
```

Notice the traceability columns (`AnalysisId`, `MethodId`, `OutputId`) are injected automatically by the generated script — something you'd otherwise have to add manually.

### The `AnalysisMethodCodeTemplate` mechanism

The most powerful siera feature: ARS metadata can contain dynamic R code templates, not just declarative specifications. The template uses placeholder variables that siera substitutes with actual metadata values:

```r
# In the ARS XLSX: AnalysisMethodCodeTemplate column contains:
Analysis_ARD <- ard_continuous(
  data      = filtered_data,
  by        = c(byvariables_here),
  variables = analysisvariable_here
)

# siera substitutes:
# byvariables_here      → TRT01A         (from analysisGroupings)
# analysisvariable_here → AGE            (from analyses[].variable)
# filtered_data         → df2_<analysisId>   (from analysisSets + dataSubsets)
```

This means the same method template is reused for every continuous variable in the demographics table — siera instantiates it once per analysis with the appropriate variable name.

---

---

## 14. The full cardx coverage

Beyond what we've covered in this lesson:

```r
# Complete function list from cardx:
ls("package:cardx") |> grep("^ard_", x = ., value = TRUE)

# Key functions not yet shown:
# ard_aov()              — one-way or multi-way ANOVA table
# ard_emmeans()          — estimated marginal means and contrasts (LSMEANS equivalent)
# ard_geepack_geeglm()   — GEE model output
# ard_survey_*()         — survey-weighted analyses
# ard_dichotomous()      — dichotomous endpoint stats
# ard_categorical_ci()   — proportion CI for any categorical level
# ard_effectsize_*()     — various effect size measures
```

For a complete and always-current listing: browse the cardx reference at `https://insightsengineering.github.io/cardx/`

---

## 15. Censoring convention — the always-misunderstood detail

This is the most common source of bugs in cardx survival analyses. Memorize this table:

| Context | Meaning of `1` | Source |
|---|---|---|
| ADTTE: `CNSR = 1` | Subject was **censored** (event did NOT occur) | CDISC ADaM standard |
| `survival::Surv(time, event)`: `event = 1` | Event **occurred** | R survival package |

They are **opposite**. The conversion is always `Surv(AVAL, 1 - CNSR)`:

```r
# CORRECT:
survfit(Surv(AVAL, 1 - CNSR) ~ TRTA, data = adtte_os)
coxph(Surv(AVAL, 1 - CNSR) ~ TRTA + AGE, data = adtte_os)

# WRONG (will analyze the wrong subjects as having events):
survfit(Surv(AVAL, CNSR) ~ TRTA, data = adtte_os)  # ← BUG
```

This is a frequent QC failure point. Build a project-level wrapper if your team has trouble with it:

```r
# Helper to standardize the survival object construction:
adtte_surv <- function(data, paramcd) {
  data |>
    filter(PARAMCD == paramcd) |>
    mutate(EVENT = 1 - CNSR)  # Convert once; never use CNSR directly in Surv()
}

os_data <- adtte_surv(adtte, "OS")
survfit(Surv(AVAL, EVENT) ~ TRTA, data = os_data)  # EVENT is now 1 = event
```

---

## 16. Key takeaways

**`{cardx}`**:
- Same ARD structure as `{cards}` — one row per statistic, same columns
- Adds inferential statistics: tests, regression coefficients, survival curves, effect sizes
- `ard_stats_t_test()`, `ard_stats_chisq_test()`: univariate comparison tests
- `ard_proportion_ci()`: proportion CIs with Wilson, Clopper-Pearson, and other methods
- `ard_regression()`: any fitted model (lm, glm, coxph, mmrm) → ARD
- `ard_survival_survfit()`: K-M x-year survival and median survival → ARD
- `ard_survival_survdiff()`: log-rank test → ARD
- Combine with cards descriptive ARDs using `bind_ard()`
- Censoring: `CNSR = 1` means censored in ADTTE; `Surv()` needs `1 - CNSR` for event indicator

**`{siera}`**:
- Reads ARS JSON or XLSX; auto-generates R scripts using `{cards}` that produce ARDs
- `readARS(ars_path, output_folder, adam_folder)` — the main function
- Generated scripts: standard structure (header → load ADaMs → analyses → combine ARDs)
- `ARD_script_example()` — access and run bundled example scripts
- `ARS_example()` — access bundled ARS metadata files and ADaM CSVs


---

## 17. What's next

Lessons 28–29 cover **`{gtsummary}`** — the display layer that consumes ARDs and produces publication-quality tables. We'll use `tbl_ard_summary()`, `add_p()`, and the full gtsummary vocabulary to turn the ARDs we've built into CSR-ready output.

---

## Self-check questions

1. What's the key difference between `{cards}` and `{cardx}` in terms of the statistics they produce?
2. Write the complete cardx call for: "Wilson 95% CI for response rate in the efficacy population by treatment arm."
3. Why does `Surv(AVAL, 1 - CNSR)` need the `1 - CNSR` conversion? What happens if you forget it?
4. Translate to cardx: "Log-rank test of OS by treatment arm."
5. What is `AnalysisMethodCodeTemplate` in siera's ARS metadata, and what makes it powerful?
6. What is `AnalysisMethodCodeTemplate` in siera's ARS metadata, and what makes it powerful?
7. After running `readARS()`, you have a script `ARD_Out14-1-1.R`. What does running it produce, and what is the resulting object named by convention?

---

## Glossary

- **`ard_stats_t_test()`** — t-test → ARD; wraps `stats::t.test()`
- **`ard_stats_chisq_test()`** — Chi-squared test → ARD
- **`ard_stats_fisher_test()`** — Fisher's exact test → ARD
- **`ard_stats_wilcox_test()`** — Wilcoxon rank-sum test → ARD
- **`ard_proportion_ci()`** — Proportion CI with multiple methods (Wilson, Clopper-Pearson, etc.)
- **`ard_continuous_ci()`** — CI for a continuous mean
- **`ard_regression()`** — Convert any fitted model to ARD
- **`ard_survival_survfit()`** — K-M x-year survival and median → ARD
- **`ard_survival_survdiff()`** — Log-rank test → ARD
- **`ard_smd()`** — Standardized mean differences → ARD
- **`ard_emmeans()`** — Estimated marginal means (LSMEANS) → ARD
- **`mmrm()`** — Mixed Model with Repeated Measures; preferred over `lme4` for clinical MMRM
- **Censoring convention** — ADTTE: `CNSR = 1` = censored; `Surv()`: second arg `1` = event
- **Wilson interval** — Recommended proportion CI method; handles small N and extreme proportions
- **Clopper-Pearson** — "Exact" proportion CI; conservative but widely accepted in regulatory submissions
- **MMRM** — Mixed Model with Repeated Measures; standard analysis for repeated measures efficacy endpoints
- **HR** — Hazard Ratio; exp of log-HR from Cox model
- **LS mean** — Least Squares Mean; model-adjusted group mean
- **`{siera}`** — R package (Clymb Clinical) that reads ARS metadata and generates ARD R scripts
- **`readARS()`** — Main siera function: ARS file → R scripts
- **`ARS_example()`** — siera helper to access bundled ARS/ADaM example files
- **`ARD_script_example()`** — siera helper to access and run bundled generated ARD scripts
- **AnalysisMethodCodeTemplate** — ARS metadata component: dynamic R code template run by siera per analysis
- **`AnalysisId`** — Traceability column linking ARD rows to their ARS analysis specification
- **`OutputId`** — Traceability column linking ARD rows to their output (table) in the ARS spec
