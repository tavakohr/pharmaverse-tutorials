# Lesson 31 — `{cardinal}` Part 2: FDA Safety Tables and Figures Templates

**Module**: 6 — TLG: the Cardinal-future stack
**Estimated length**: ~18 min spoken
**Prerequisites**: Lesson 30 (cardinal overview)

---

## Learning objectives

By the end of this lesson, you will be able to:

1. Navigate the cardinal catalog to locate canonical FDA Safety templates
2. Recognize the standard FDA safety table layouts: demographics, disposition, exposure, AE overview, AE by SOC/PT, lab shift, serious AEs
3. Trace a cardinal template's code structure to understand its outputs
4. Anticipate the typical customizations a sponsor will apply to a cardinal template
5. Combine multiple cardinal templates into a complete CSR safety section
6. Use cardinal templates as starting points for sponsor-specific custom tables

---

## 1. The FDA Standard Safety Tables and Figures Integrated Guide

Before walking through templates, it's worth understanding what they implement. The FDA Standard Safety Tables and Figures Integrated Guide is a public document (available on FDA.gov) that describes the canonical safety tables FDA reviewers expect to see in submissions.

Key principles from the guide:

- Tables use **subject-level denominators** for incidence calculations
- Severity (e.g., NCI CTCAE grades) is preferred over qualitative descriptors when available
- Treatment-emergent definitions are explicit
- Footnotes document methodology
- Multiple display formats supported (RTF for CSR, JSON for ARS submission)

cardinal implements this guide one table at a time. Each cardinal template corresponds to a specific FDA table number.

## 2. The canonical safety table set

The "must-have" tables for a typical submission:

| FDA Table # | Subject |
|---|---|
| **14.1.x** | Subject disposition (accountability) |
| **14.2.x** | Demographics and baseline characteristics |
| **14.3.x** | Exposure (treatment duration, total dose) |
| **14.4.x** | Treatment-emergent AE overview |
| **14.5.x** | AEs by SOC and PT |
| **14.6.x** | Serious AEs |
| **14.7.x** | AEs leading to discontinuation |
| **14.8.x** | Deaths |
| **14.9.x** | Laboratory abnormality summaries |

A "complete" cardinal-driven safety section uses ~9 templates. Each is roughly 50–100 lines of R; the whole safety section is ~600 lines of code that produces ~15 RTF tables.

We won't reproduce every template. Instead we look at the **patterns** that recur — once you internalize them, every table is recognizable.

## 3. Pattern A: Demographics (FDA Table 14.2.x)

The canonical demographics template (paraphrased from cardinal):

```r
library(cards)
library(cardx)
library(gtsummary)
library(dplyr)
library(pharmaverseadam)

adsl <- pharmaverseadam::adsl |> filter(SAFFL == "Y")

# Build the descriptive ARD
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

# Build a p-value ARD
pvalue_ard <- bind_ard(
  ard_stats_anova_oneway(adsl, by = "TRT01A",
                          variables = c(AGE, BMIBL, WEIGHTBL, HEIGHTBL)),
  ard_stats_chisq_test(adsl, by = "TRT01A",
                        variables = c(AGEGR1, SEX, RACE, ETHNIC))
)

# Combine and render
demog_tbl <- bind_ard(demog_ard, pvalue_ard) |>
  tbl_ard_summary(
    by = "TRT01A",
    type = c(AGE, BMIBL, WEIGHTBL, HEIGHTBL) ~ "continuous2",
    overall = TRUE
  ) |>
  add_p() |>
  bold_labels() |>
  modify_caption("**Table 14.2.1: Demographic and Baseline Characteristics**")

demog_tbl |>
  as_flex_table() |>
  flextable::save_as_rtf("outputs/t_14_2_1.rtf")
```

Pattern recognition:

- ADSL filtered to safety pop
- ARD built with `ard_stack()` combining continuous and categorical
- p-values from `cardx::ard_stats_*()` functions
- Display via `tbl_ard_summary()` with `continuous2` type
- Export to RTF

Every demographics-style template in cardinal follows this exact pattern. Differences across templates: which variables to include, which statistical tests, how to format the footnotes.

## 4. Pattern B: AE Overview (FDA Table 14.4.x)

The "overview" AE table summarizes counts and rates of various AE categories per arm: any TEAE, serious TEAE, related TEAE, severe TEAE, leading-to-discontinuation, leading-to-death.

```r
adae_te <- adae |> filter(TRTEMFL == "Y")

# Add subject-level flags to ADSL
adsl_with_flags <- adsl |>
  mutate(
    ANY_TEAE         = if_else(USUBJID %in% adae_te$USUBJID, "Y", "N"),
    SERIOUS_TEAE     = if_else(
      USUBJID %in% (adae_te |> filter(AESER == "Y") |> pull(USUBJID)),
      "Y", "N"
    ),
    SEVERE_TEAE      = if_else(
      USUBJID %in% (adae_te |> filter(ASEV == "SEVERE") |> pull(USUBJID)),
      "Y", "N"
    ),
    DISC_TEAE        = if_else(
      USUBJID %in% (adae_te |> filter(AEACN == "DRUG WITHDRAWN") |> pull(USUBJID)),
      "Y", "N"
    ),
    DEATH_TEAE       = if_else(
      USUBJID %in% (adae_te |> filter(AEOUT == "FATAL") |> pull(USUBJID)),
      "Y", "N"
    )
  )

# Build ARD
ae_overview_ard <- ard_categorical(
  adsl_with_flags,
  by = "TRT01A",
  variables = c(ANY_TEAE, SERIOUS_TEAE, SEVERE_TEAE, DISC_TEAE, DEATH_TEAE),
  denominator = adsl
)

# Render
ae_overview_tbl <- ae_overview_ard |>
  tbl_ard_summary(
    by = "TRT01A",
    type = everything() ~ "dichotomous",
    overall = TRUE
  ) |>
  modify_caption("**Table 14.4.1: Adverse Event Overview**") |>
  modify_footnote(all_stat_cols() ~
    "TEAE = Treatment-Emergent Adverse Event. Subjects counted once per category.")

ae_overview_tbl |>
  as_flex_table() |>
  flextable::save_as_rtf("outputs/t_14_4_1.rtf")
```

Pattern recognition:

- Subject-level flags computed via `mutate()` (one per AE category)
- Single `ard_categorical()` call with `dichotomous` type (one row per category showing "Y" counts)
- Explicit `denominator = adsl` to anchor to safety pop subject count

The template adapts to any "AE overview" variation. Different sponsors include different categories (some skip DEATH_TEAE if very few; some add "moderate-or-worse"). The pattern stays the same.

## 5. Pattern C: AE by SOC and PT (FDA Table 14.5.x)

The detailed AE table with SOC × PT hierarchy.

```r
ae_ard <- adae |>
  filter(TRTEMFL == "Y") |>
  ard_hierarchical(
    by = "ARM",
    variables = c("AEBODSYS", "AEDECOD"),
    denominator = adsl
  )

ae_tbl <- ae_ard |>
  tbl_ard_summary(by = "TRT01A", overall = FALSE) |>
  modify_header(label ~ "**System Organ Class<br>&nbsp;&nbsp;Preferred Term**") |>
  modify_caption("**Table 14.5.1: Adverse Events by System Organ Class and Preferred Term**") |>
  modify_footnote(all_stat_cols() ~
    "n = subjects with event; % = n / (safety population N) × 100. Subjects with multiple events of the same term counted once.")

ae_tbl |>
  as_flex_table() |>
  flextable::save_as_rtf("outputs/t_14_5_1.rtf")
```

This is the classic AE table. The `ard_hierarchical()` does the heavy lifting; gtsummary renders the indentation automatically.

Common customizations:

- **Incidence threshold**: only show PTs occurring in ≥ 5% of any arm. Apply at the ARD level via `filter_fun` or post-hoc.
- **Sort order**: alphabetical (default) vs. by total incidence
- **Severity breakdown**: a multi-column version split by Mild/Moderate/Severe — use `ard_hierarchical()` with grade as an additional grouping

## 6. Pattern D: Lab Shift Table (FDA Table 14.9.x)

Lab shifts: "how many subjects shifted from NORMAL at baseline to HIGH at any visit?" The display: a 2D table — baseline category × on-treatment maximum category, with cell counts.

```r
adlb <- pharmaverseadam::adlb |>
  filter(SAFFL == "Y" & ANL01FL == "Y" & PARAMCD == "HGB")

# Get baseline reference range categories and worst-on-treatment per subject
shift_data <- adlb |>
  filter(!is.na(BNRIND) & ONTRTFL == "Y") |>
  group_by(USUBJID, BNRIND) |>
  summarise(
    WORST_TRT_IND = case_when(
      any(ANRIND == "HIGH")   ~ "HIGH",
      any(ANRIND == "LOW")    ~ "LOW",
      any(ANRIND == "NORMAL") ~ "NORMAL",
      TRUE                    ~ NA_character_
    ),
    .groups = "drop"
  )

# Merge in treatment arm
shift_data <- shift_data |>
  left_join(adsl |> select(USUBJID, TRT01A), by = "USUBJID")

# Build the cross-tabulation
shift_ard <- ard_categorical(
  shift_data,
  by = c(TRT01A, BNRIND),
  variables = WORST_TRT_IND,
  denominator = adsl |> count(TRT01A, name = "N")
)

shift_tbl <- shift_ard |>
  tbl_ard_summary(by = c("TRT01A", "BNRIND")) |>
  modify_caption("**Table 14.9.1: Hemoglobin Reference Range Shift: Baseline to Worst On-Treatment**")

shift_tbl |>
  as_flex_table() |>
  flextable::save_as_rtf("outputs/t_14_9_1.rtf")
```

Shift tables get visually complex — they have row groups (baseline categories) and column groups (treatment × on-treatment categories). For very complex layouts, switch to `{tfrmt}` (Lesson 32) which handles multi-dimensional displays better than gtsummary.

## 7. Pattern E: Serious AE Listing

Listings (the "L" in TLG) are different from summary tables — one row per AE event, with subject identifiers and details. cardinal includes listing templates too.

```r
sae_listing <- adae |>
  filter(SAFFL == "Y" & TRTEMFL == "Y" & AESER == "Y") |>
  select(USUBJID, AGE, SEX, ARM, AESTDT, AEENDT, AEDECOD, AEBODSYS,
         AESEV, AESER, AEACN, AEOUT) |>
  arrange(USUBJID, AESTDT)

# Render as a simple table
library(flextable)

flex_listing <- sae_listing |>
  flextable() |>
  set_caption("Listing 14.6.1: Serious Adverse Events") |>
  theme_box()

flex_listing |>
  save_as_rtf("outputs/l_14_6_1.rtf")
```

Listings don't need ARDs — they're raw event-level data with formatting. `{flextable}` directly handles them. gtsummary isn't the right tool here.

For longer / more complex listings (multi-page with continuation headers), `{r2rtf}` (Module 7) is often preferred — it has more pagination control. Cardinal includes both flextable and r2rtf-based listing templates.

## 8. Pattern F: Subgroup Forest Plot (FDA Figure)

Cardinal includes graph (G) templates too. The signature: a subgroup forest plot showing the treatment effect (e.g., hazard ratio) across multiple subgroups.

```r
library(ggplot2)
library(survival)

# Build subgroup-level HR ARDs
subgroups <- c("Overall", "Sex: M", "Sex: F", "Age: <65", "Age: ≥65")

subgroup_hrs <- adsl |>
  filter(EFFFL == "Y") |>
  group_split(...) |>           # split by subgroup definitions
  purrr::map_dfr(\(subgroup_data) {
    cox_fit <- coxph(
      Surv(AVAL, 1 - CNSR) ~ TRTA,
      data = subgroup_data
    )
    ard_regression(cox_fit) |>
      mutate(SUBGROUP = unique(subgroup_data$SUBGROUP_LABEL))
  })

# Extract HR estimates and CIs
forest_data <- subgroup_hrs |>
  filter(stat_name %in% c("estimate", "conf.low", "conf.high")) |>
  tidyr::pivot_wider(names_from = stat_name, values_from = stat)

# Forest plot
ggplot(forest_data, aes(x = exp(estimate), y = SUBGROUP)) +
  geom_point(size = 3) +
  geom_errorbarh(aes(xmin = exp(conf.low), xmax = exp(conf.high)), height = 0.2) +
  geom_vline(xintercept = 1, linetype = "dashed") +
  scale_x_log10() +
  labs(x = "Hazard Ratio (95% CI)", y = "Subgroup",
       title = "Figure 14.3.2: Overall Survival Hazard Ratio by Subgroup")

ggsave("outputs/f_14_3_2.png", width = 8, height = 5, dpi = 300)
```

Forest plots are conceptually simple but visually demanding. cardinal templates include the standard layout with vertical reference line, CIs as error bars, log-scaled x-axis, subgroup labels left-justified. Sponsor adaptations are mostly aesthetic.

## 9. Combining cardinal templates into a CSR safety section

A complete CSR safety section script using multiple cardinal templates:

```r
# t_14_1_1_disposition.qmd        - Subject disposition
# t_14_2_1_demographics.qmd        - Demographics (Pattern A)
# t_14_3_1_exposure.qmd            - Exposure summary
# t_14_4_1_ae_overview.qmd         - AE overview (Pattern B)
# t_14_5_1_ae_soc_pt.qmd           - AE by SOC × PT (Pattern C)
# t_14_6_1_sae_listing.qmd         - Serious AE listing (Pattern E)
# t_14_7_1_disc_due_to_ae.qmd      - Discontinuation due to AE
# t_14_8_1_deaths.qmd              - Deaths
# t_14_9_1_lab_shift_hgb.qmd       - HGB shift table (Pattern D)
# t_14_9_2_lab_shift_alt.qmd       - ALT shift table
# t_14_9_3_lab_shift_creat.qmd     - Creatinine shift table
# f_14_4_1_ae_forest.qmd           - AE incidence forest plot
```

Run all templates with one command:

```r
quarto::quarto_render(
  c("t_14_1_1_disposition.qmd",
    "t_14_2_1_demographics.qmd",
    # ... etc.
  )
)
# All RTFs and PNGs land in outputs/
```

For a phase III submission, this might be 20–30 templates rendering into ~50–80 RTF tables and figures. cardinal's contribution: each template is ~50 lines of R, validated against the FDA guide, ready to adapt.

## 10. Common adaptations sponsors make

The cardinal templates are starting points. Real CSR work involves:

### Sponsor-specific safety population

```r
# cardinal default
adsl <- pharmaverseadam::adsl |> filter(SAFFL == "Y")

# Sponsor variant
adsl <- haven::read_xpt("data/adsl.xpt") |>
  filter(SAFFL == "Y" & ANLPOP == "Y")    # custom analysis flag
```

### Different MedDRA version

```r
# cardinal uses default MedDRA from test data; your study uses a specific version
adae <- haven::read_xpt("data/adae.xpt") |>
  metadata::set_meddra_version("26.0")
```

### Sponsor table numbering

```r
# cardinal default
modify_caption("**Table 14.4.1: Adverse Event Overview**")

# Sponsor convention
modify_caption("**T-14-04-01: Treatment-Emergent Adverse Events — Safety Population**")
```

### Footnote terminology

```r
modify_footnote(all_stat_cols() ~
  "Per sponsor SOP-12345: subjects categorized by treatment received...")
```

### Custom column labels

```r
modify_header(
  stat_1 ~ "**Treatment A**<br>n = {n}",
  stat_2 ~ "**Treatment B**<br>n = {n}"
)
```

## 11. When to write a template from scratch vs. start from cardinal

**Start from cardinal when:**

- The table is a standard FDA-aligned safety summary
- A cardinal template exists for the table number/type
- Your customizations are cosmetic (footnotes, terminology, styling)

**Start from scratch when:**

- The table is highly study-specific (e.g., biomarker analyses, complex efficacy endpoints not in the standard set)
- No cardinal template exists; you'd be reinventing it anyway
- Sponsor SOPs require a fundamentally different layout than the FDA guide

For most CSRs, ~60-70% of tables can start from cardinal templates. The remaining ~30-40% need custom work but typically borrow patterns from cardinal templates (the ARD structure, the gtsummary configuration).

## 12. Contributing customizations back

A virtuous cycle: as your team adapts cardinal templates for your sponsor, some adaptations are generally useful (sponsor-neutral improvements like better footnotes, more flexible filtering). Contributing these back via PR to cardinal's GitHub:

- Helps other sponsors
- Earns recognition for your contributors
- Reduces your future maintenance burden (the cardinal version stays current)

Sponsors with mature open-source contribution practices (Roche, GSK, etc.) routinely contribute back. The model works.

## 13. Cardinal vs. the SaTH (Standard Safety Tables in `{tern}`)

Roche's NEST stack (Module 7) includes `{tern}` which has its own standard safety table implementations. How do they relate?

- **tern's safety tables**: built on rtables, mature, production-proven; require rtables-style code
- **cardinal's safety templates**: built on cards + gtsummary; newer, growing, easier to start with

Both align to similar standards (FDA guide). The difference is the underlying stack. As discussed in Lesson 30, both coexist; cardinal is positioned to be the future direction for new development.

If you're already invested in tern, you can keep using it. If you're starting fresh, cardinal is the natural choice.

## 14. Beyond safety: efficacy and other domains

Cardinal's initial focus was FDA safety. Subsequent expansion targets:

- **Efficacy templates**: primary and secondary endpoints by therapeutic area
- **Subgroup analyses**: forest plots, interaction tests
- **Sensitivity analyses**: per-protocol, censoring variants, missing-data approaches
- **Specific TAs**: oncology-specific templates (waterfall plots, spider plots, tumor response)

These expand the catalog beyond safety to cover most of a typical CSR. The same Quarto template structure applies.

## 15. Putting it together: a CSR safety section in one shot

```r
library(quarto)

# Render all safety tables for the CSR
templates_dir <- "csr/safety/templates"

templates <- list.files(templates_dir, pattern = "\\.qmd$", full.names = TRUE)

for (template in templates) {
  message("Rendering: ", basename(template))
  quarto_render(template, quiet = TRUE)
}

# All RTFs available in outputs/
```

10 templates → 10 RTFs in a few minutes. The CSR safety section is rendered. You manually integrate the RTFs into the CSR Word/PDF document (or use automated tools for that step too).

## 16. Key takeaways

- The FDA Standard Safety Tables and Figures Integrated Guide is cardinal's primary reference
- Six canonical patterns: demographics, AE overview, AE by SOC/PT, lab shift, listings, forest plots
- Each cardinal template implements one FDA table with cards + gtsummary code
- Common customizations: population filter, MedDRA version, table numbering, footnotes
- Use cardinal when the FDA template fits; write from scratch for study-specific tables
- A complete safety section is ~10 templates rendering ~50 RTFs in a few minutes
- Contributing improvements back via GitHub PR benefits the industry and reduces future maintenance

## 17. What's next

Lesson 32 — the final lesson in Module 6 — covers **`{tfrmt}`**: display metadata for ARDs. For tables that gtsummary can't handle elegantly (multi-dimensional layouts, mock-table workflows, full sponsor-templated displays), tfrmt provides a separate metadata-driven layer. After tfrmt, Module 6 is complete and we move to Module 7 — the legacy TLG stack.

---

## Self-check questions

1. Which FDA reference is cardinal primarily implementing?
2. What's the pattern for an AE overview table — what's the structure of its ARD?
3. Why do lab shift tables sometimes warrant tfrmt instead of gtsummary?
4. What's typically the first customization a sponsor applies to a cardinal template?
5. List three FDA Table 14.x.x subjects and their typical cardinal-template pattern.
6. Why doesn't gtsummary handle listings well?

## Glossary

- **Subject-level denominator** — Use safety-population subject count for AE proportions
- **TEAE** — Treatment-Emergent Adverse Event
- **AE Overview** — Single table summarizing major AE categories (any, serious, severe, etc.)
- **SOC × PT** — System Organ Class (MedDRA top level) and Preferred Term (lower level)
- **Shift table** — Cross-tabulation of baseline category × on-treatment category
- **Forest plot** — Subgroup-level effect-size plot with reference line
- **Listing** — Subject-event-level data display, not aggregated
- **MedDRA** — Medical Dictionary for Regulatory Activities; the coding standard for AEs
- **CSR safety section** — The standard ~10-table set of safety tables in a CSR
- **tern's SaTH** — Standard Safety Tables in `{tern}`; the NEST equivalent of cardinal templates
