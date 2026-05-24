# Lesson 27 — `{cardx}`: Regression, Survival, and Statistical Test ARDs

**Module**: 6 — TLG: the Cardinal-future stack
**Estimated length**: ~20 min spoken
**Prerequisites**: Lessons 25–26 (cards)

---

## Learning objectives

By the end of this lesson, you will be able to:

1. Explain what `{cardx}` extends `{cards}` with — inferential statistics
2. Use `ard_stats_t_test()`, `ard_stats_chisq_test()` and similar for univariate tests
3. Use `ard_regression()` for regression model output as an ARD
4. Use `ard_survival_survfit()` to derive Kaplan-Meier estimates and median survival ARDs
5. Combine cards descriptive ARDs with cardx inferential ARDs into one display-ready dataset
6. Recognize the broad coverage of statistical model types cardx supports

---

## 1. What cardx is for

`{cards}` covers descriptive statistics — N, mean, counts, percentages, hierarchical tabulations. These are the bread-and-butter of demographics, AE summaries, exposure tables. But clinical reporting also needs **inferential** outputs:

- t-tests and chi-squared tests on demographics tables (testing for arm differences)
- Regression coefficients with CIs and p-values
- Kaplan-Meier median survival, x-year survival rates
- Hazard ratios from Cox models
- Mixed-model estimates (MMRM, mixed-effects)

`{cardx}` extends `{cards}` to cover these. Same ARD structure (one row per statistic), but the statistics come from model objects rather than simple summaries.

```r
install.packages("cardx")
library(cards)
library(cardx)
```

cardx imports cards and depends on it. Loading cardx gives you both vocabularies.

## 2. The packages cardx wraps

cardx imports and wraps statistical computation from several R packages, producing ARDs from each:

| Package | What cardx wraps |
|---|---|
| `{stats}` (base R) | t.test, chisq.test, wilcox.test, aov, lm, glm |
| `{survival}` | survfit, coxph |
| `{lme4}` | lmer, glmer mixed-effects models |
| `{geepack}` | GEE models |
| `{emmeans}` | estimated marginal means |
| `{effectsize}` | effect-size estimates |
| `{parameters}` | tidy parameter extraction |
| `{smd}` | standardized mean differences |
| `{survey}` | survey-weighted analyses |
| `{car}` | analysis-of-variance helpers |
| `{broom.helpers}` | tidy model extraction |

The pattern: cardx provides an `ard_<pkg>_<thing>()` function that wraps the relevant statistical function and returns an ARD.

## 3. Univariate tests: comparing arms on AGE

The classic demographics-table augmentation: report a t-test p-value for AGE between two arms.

```r
library(pharmaverseadam)
library(dplyr)

adsl <- pharmaverseadam::adsl |>
  filter(SAFFL == "Y" & ARM %in% c("Xanomeline High Dose", "Xanomeline Low Dose"))

age_ttest_ard <- ard_stats_t_test(
  adsl,
  by = ARM,
  variables = AGE
)

age_ttest_ard
```

The output:

```
group1  variable  context        stat_name   stat_label     stat
ARM     AGE       stats_t_test   estimate    Mean Diff      -1.286
ARM     AGE       stats_t_test   estimate1   Group 1 Mean   74.381
ARM     AGE       stats_t_test   estimate2   Group 2 Mean   75.667
ARM     AGE       stats_t_test   statistic   t-stat         -1.043
ARM     AGE       stats_t_test   p.value     p-value        0.299
ARM     AGE       stats_t_test   conf.low    CI Low         -3.722
ARM     AGE       stats_t_test   conf.high   CI High        1.151
ARM     AGE       stats_t_test   method      Method         Welch ...
...
```

Each row is one piece of the t-test output: the mean difference, both group means, t-statistic, p-value, CIs, and metadata (method = "Welch Two Sample t-test" — captures whether equal-variance assumption was made). This is the standard "all the information needed" output for clinical reporting.

For categorical variables, the equivalent is `ard_stats_chisq_test()` or `ard_stats_fisher_test()`:

```r
ard_stats_chisq_test(
  adsl,
  by = ARM,
  variables = c(SEX, AGEGR1)
)
```

p-values and other test stats for each categorical variable's distribution across arms.

## 4. Mean differences with confidence intervals

For "mean change from baseline" comparisons:

```r
# Suppose we have ADVS with CHG already derived
advs <- pharmaverseadam::advs |>
  filter(PARAMCD == "WEIGHT" & AVISIT == "Week 24" & ANL01FL == "Y")

chg_ttest <- ard_stats_t_test(
  advs,
  by = TRTA,
  variables = CHG
)
```

Or for a paired analysis (within-subject baseline vs post-baseline change):

```r
ard_stats_t_test(
  advs |> filter(TRTA == "Xanomeline High Dose"),
  variables = CHG,
  paired = FALSE                    # one-sample test of CHG against 0
)
```

The arguments mirror `t.test()`'s. The ARD captures everything you need for reporting.

## 5. Regression output: `ard_regression()`

For multi-variable models — linear regression, logistic regression, Poisson — cardx provides `ard_regression()` which converts a fitted model object into an ARD:

```r
library(survival)

# Linear regression: WEIGHT change ~ baseline + treatment + age
model_lm <- lm(
  CHG ~ BASE + TRTA + AGE,
  data = advs
)

reg_ard <- ard_regression(model_lm)
```

The output has one row per (coefficient × statistic):

```
variable       variable_level    stat_name   stat_label    stat
(Intercept)    NA                estimate    Estimate      2.30
(Intercept)    NA                std.error   SE            0.51
(Intercept)    NA                conf.low    CI Low        1.30
(Intercept)    NA                conf.high   CI High       3.30
(Intercept)    NA                p.value     p-value       0.000
BASE           NA                estimate    ...           ...
TRTA           Placebo           estimate    ...           ...   (reference)
TRTA           Xanomeline High   estimate    ...           ...
AGE            NA                estimate    ...           ...
```

Every coefficient gets a complete set of statistics. For factor variables (like TRTA), each non-reference level gets its own row. Under the hood, cardx uses `broom.helpers` to tidy the model.

Logistic regression (binary outcome):

```r
adsl_pop <- adsl |> mutate(RESPONDER = if_else(EFFFL == "Y" & ...some condition..., 1, 0))

model_glm <- glm(
  RESPONDER ~ TRTA + AGE + SEX,
  data = adsl_pop,
  family = binomial
)

ard_regression(model_glm)
```

The ARD includes log-odds estimates and CIs. To produce odds ratios with CIs, cardx provides exponentiation utilities; alternatively, `gtsummary` (Lesson 28) does the exponentiation at the display step.

## 6. Survival: Kaplan-Meier ARDs

The cardx pattern for K-M analyses:

```r
library(survival)

adtte_os <- pharmaverseadam::adtte |>
  filter(PARAMCD == "OS")

# Build a survfit object
km_fit <- survfit(Surv(AVAL, 1 - CNSR) ~ TRTA, data = adtte_os)

# Convert to ARD: x-year survival rates
km_xyear_ard <- ard_survival_survfit(km_fit, times = c(180, 365))
```

The result: for each arm, at each requested time point, you get:

- `n.risk`: number at risk
- `estimate`: survival probability
- `std.error`: standard error
- `conf.low` / `conf.high`: CI bounds

These are the data you need for "% surviving at 6 months / 1 year" annotations on a K-M plot.

For **median survival** with CI:

```r
km_median_ard <- ard_survival_survfit(
  km_fit,
  probs = c(0.5)                # 0.5 = median
)
```

The result has the time at which survival = 0.5 for each arm, with CI. You can request other quantiles by passing different `probs`.

Two patterns for the call:

```r
# Pattern A: pass survfit object
survfit(Surv(AVAL, 1 - CNSR) ~ TRTA, data = adtte_os) |>
  ard_survival_survfit(times = c(180, 365))

# Pattern B: pass data frame with formula
adtte_os |>
  ard_survival_survfit(
    y = Surv(AVAL, 1 - CNSR),
    variables = "TRTA",
    times = c(180, 365)
  )
```

Pattern A is more common; Pattern B is handy when the formula isn't known at survfit-call time.

## 7. Hazard ratios from Cox models

For HR comparing arms:

```r
cox_fit <- coxph(
  Surv(AVAL, 1 - CNSR) ~ TRTA + AGE + SEX,
  data = adtte_os
)

ard_regression(cox_fit)
```

`ard_regression()` works for Cox models the same way as for `lm`/`glm` — coefficient ARDs with estimates, SEs, CIs, p-values. For Cox the coefficients are log-hazard-ratios; downstream display layers typically exponentiate.

For survival-specific helpers like log-rank tests:

```r
survdiff(Surv(AVAL, 1 - CNSR) ~ TRTA, data = adtte_os) |>
  ard_survival_survdiff()
```

Returns the log-rank statistic, p-value, and degrees of freedom.

## 8. Mixed models: lme4 wrapper

For MMRM-style analyses with `{lme4}`:

```r
library(lme4)

# Mixed model: CHG over time
mmrm_data <- advs |> filter(PARAMCD == "WEIGHT")

mixed_fit <- lmer(
  CHG ~ TRTA * AVISITN + BASE + (1 | USUBJID),
  data = mmrm_data
)

ard_regression(mixed_fit)
```

The ARD has rows for fixed effects, similar to `lm` output. Random-effects variance components require additional cardx functions (or the `parameters` package directly).

For dedicated MMRM analyses, the `{mmrm}` package (also pharmaverse-aligned) is increasingly preferred over lme4 for clinical reporting; cardx integration is improving.

## 9. Effect sizes and standardized mean differences

For "did treatment matter clinically, not just statistically":

```r
library(smd)

ard_stats_smd(
  adsl,
  by = "ARM",
  variables = c("AGE", "BMIBL")
)
```

Returns Cohen's d or similar standardized mean differences with CIs. Useful for ITT vs PP comparisons, propensity-score balance checks, etc.

## 10. Combining cards + cardx in one display

For a demographics table with p-values, you'd typically build separate ARDs (cards for descriptive, cardx for inferential) and stack them:

```r
descriptive_ard <- ard_stack(
  adsl,
  ard_continuous(variables = AGE),
  ard_categorical(variables = c(SEX, AGEGR1)),
  .by = ARM,
  .overall = TRUE,
  .total_n = TRUE
)

pvalue_ard <- bind_ard(
  ard_stats_t_test(adsl, by = ARM, variables = AGE),
  ard_stats_chisq_test(adsl, by = ARM, variables = c(SEX, AGEGR1))
)

full_ard <- bind_ard(descriptive_ard, pvalue_ard)
```

The combined ARD has descriptive rows (with `context = "continuous"` or `"categorical"`) and inferential rows (with `context = "stats_t_test"` or `"stats_chisq_test"`). Downstream display filters and arranges them.

`gtsummary::tbl_ard_summary()` with `add_p()` does this automatically — it requests the right tests internally and stacks the results.

## 11. The pre-baked datasets shipped with cards/cardx

For quick experimentation, `cards::ADSL` and `cards::ADTTE` are bundled test datasets:

```r
cards::ADSL    # CDISC pilot demographics
cards::ADTTE   # CDISC pilot time-to-event
```

These match `pharmaverseadam`'s test data structure; use whichever feels natural. The cards docs typically reference `cards::ADSL` for compactness.

## 12. Putting it together: an inferential ARD

A complete script that produces descriptive + inferential ARDs for a CSR's primary efficacy summary:

```r
library(cards)
library(cardx)
library(survival)
library(dplyr)
library(pharmaverseadam)

adsl <- pharmaverseadam::adsl |> filter(EFFFL == "Y")
adtte_os <- pharmaverseadam::adtte |> filter(PARAMCD == "OS")
adtte_pfs <- pharmaverseadam::adtte |> filter(PARAMCD == "PFS")

# K-M analysis: 6-month and 1-year survival per arm
os_xyear <- adtte_os |>
  ard_survival_survfit(
    y = Surv(AVAL, 1 - CNSR),
    variables = "TRTA",
    times = c(180, 365)
  )

# K-M median survival per arm
os_median <- adtte_os |>
  ard_survival_survfit(
    y = Surv(AVAL, 1 - CNSR),
    variables = "TRTA",
    probs = c(0.5)
  )

# Cox HR adjusting for age and sex
cox_fit <- coxph(
  Surv(AVAL, 1 - CNSR) ~ TRTA + AGE + SEX,
  data = adtte_os
)
os_hr <- ard_regression(cox_fit)

# Log-rank test
os_logrank <- survdiff(Surv(AVAL, 1 - CNSR) ~ TRTA, data = adtte_os) |>
  ard_survival_survdiff()

# Combine for the survival results section
survival_ard <- bind_ard(os_xyear, os_median, os_hr, os_logrank)

saveRDS(survival_ard, "ards/survival_ard.rds")
```

This single block produces all the data behind a typical "Overall Survival Analysis" CSR table — median survival, x-year survival rates, HR, log-rank p-value. The display layer (gtsummary or tfrmt) formats this into the canonical layout.

## 13. Validation considerations

For regression-based ARDs:

- **Compare to standard software output**: run the same model in SAS PROC MIXED, PROC PHREG, etc., and confirm cardx values match
- **Spot-check coefficients**: print the model summary, manually verify a few rows in the ARD
- **Check sample size**: ARDs include N statistics; confirm they match the analysis-set count

For survival ARDs:

- **K-M at standard timepoints**: verify median, 6-month, 1-year values against `survminer::ggsurvplot()` annotations on the same data
- **Censoring direction**: cardx convention is `Surv(time, event)` with `event = 1` for event, `0` for censor. ADTTE CDISC convention is the opposite (CNSR = 1 for censor). Always convert: `Surv(AVAL, 1 - CNSR)`

The censoring convention mismatch is a common source of bugs. Always document and test.

## 14. The broad coverage

cardx is large and growing. Beyond what we've covered:

- `ard_aov()` — ANOVA tables
- `ard_emmeans()` — estimated marginal means and contrasts
- `ard_smd()` — standardized mean differences
- `ard_continuous_ci()` — CIs for means with various methods
- `ard_proportion_ci()` — CIs for proportions (Wilson, Clopper-Pearson, etc.)
- `ard_categorical_ci()` — CIs for categorical proportions
- `ard_dichotomous()` — dichotomous endpoint statistics
- `ard_anova()` — ANOVA tables from various model classes
- `ard_geepack_geeglm()` — generalized estimating equations
- `ard_survey_*()` — survey-weighted analyses

For a complete listing: `ls("package:cardx")` or browse the package reference site. Most clinical reporting needs are covered.

## 15. The maintainers and direction

`{cardx}` is maintained alongside `{cards}` — same team across Roche, GSK, Novartis. The package is in active development (0.x); new wrappers appear with each release as users request them.

Strategic direction: cardx + cards together aim to be the comprehensive ARD-producing layer of the Cardinal-future stack. As CDISC ARS becomes formalized, cardx's coverage will align with the ARS-mandated statistic types.

## 16. Where cardx fits in the bigger picture

Recap of the stack:

```
ADaM data
   │
   ▼
{cards}     ← descriptive ARDs
{cardx}     ← inferential ARDs (you are here)
   │
   ▼
{gtsummary} ← display
{tfrmt}     ← display metadata
   │
   ▼
.docx / .rtf / .html
```

By the time you've mastered cards and cardx, you can compute essentially any statistic appearing in a clinical report and produce it as a structured ARD. The display layer becomes a transformation problem — much simpler.

## 17. Key takeaways

- `{cardx}` extends `{cards}` with inferential statistics — tests, regression, survival
- ARD structure stays the same: one row per statistic, with `stat_name`, `stat_label`, `stat`
- `ard_stats_t_test()`, `ard_stats_chisq_test()`, `ard_stats_fisher_test()` for univariate tests
- `ard_regression()` for lm, glm, coxph, and similar model output
- `ard_survival_survfit()` for K-M x-year survival and median survival
- `ard_survival_survdiff()` for log-rank tests
- Censoring convention: `Surv(AVAL, 1 - CNSR)` for ADTTE → cardx
- Combine descriptive (cards) and inferential (cardx) ARDs with `bind_ard()` for full-table data

## 18. What's next

Lessons 28–29 cover **`{gtsummary}`** — the display layer that turns ARDs into publication-quality tables. We'll cover `tbl_ard_summary()` (consumes ARDs from cards/cardx), composable tables, clinical reporting patterns (demographics tables, AE tables), and output to RTF for CSR delivery.

After gtsummary: `{cardinal}` (Lessons 30–31) and `{tfrmt}` (Lesson 32). Then Module 6 is complete.

---

## Self-check questions

1. What's the distinction between cards and cardx in terms of what they compute?
2. Why does the censoring direction in ADTTE differ from the `survival::Surv()` convention?
3. Translate to cardx: "Compute median PFS per arm with 95% CI."
4. Translate to cardx: "Fit a Cox model of OS on TRTA, AGE, SEX; return the coefficients as an ARD."
5. Why are p-values from cardx typically a separate ARD from cards descriptive output?
6. List three packages cardx wraps and one example function from each.

## Glossary

- **`ard_stats_t_test()`** — t-test as an ARD
- **`ard_stats_chisq_test()`** — chi-squared test as an ARD
- **`ard_regression()`** — Convert a fitted regression model to an ARD
- **`ard_survival_survfit()`** — Convert a survfit object to ARD with x-year or quantile survival
- **`ard_survival_survdiff()`** — Log-rank test as an ARD
- **Censoring convention** — ADTTE: CNSR = 1 means censored; `Surv()`: event = 1 means event
- **MMRM** — Mixed Model with Repeated Measures
- **HR** — Hazard Ratio
- **CI** — Confidence Interval
- **SMD** — Standardized Mean Difference
- **`broom.helpers`** — Package providing tidy model extraction; cardx depends on this
