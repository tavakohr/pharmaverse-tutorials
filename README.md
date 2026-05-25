# Pharmaverse learnr Tutorial Series

> Interactive R tutorials for clinical programmers transitioning from SAS to the
> [pharmaverse](https://pharmaverse.org/) ecosystem.

Each lesson ships as a self-contained **learnr** `.Rmd` file: learners run live R
code in the browser via Posit Connect, or locally in RStudio by clicking
**Run Document**. Every tutorial uses real clinical trial data from the
**CDISCPILOT01** Alzheimer's / Xanomeline study (`pharmaverseadam`,
`pharmaversesdtm`) — no synthetic toy data.

| | |
|---|---|
| **Author** | Hamid Tavakoli |
| **License** | MIT |
| **learnr tutorials** | 46 `.Rmd` files · ~63,400 lines of R |
| **Coding exercises** | 712 live exercises (with hints & solutions) |
| **Quiz questions** | 168 multiple-choice questions |
| **Lesson plan docs** | 137 narrative `.md` files |
| **Dataset** | CDISCPILOT01 — `pharmaverseadam` + `pharmaversesdtm` |

---

## How to Run

```r
# 1 — install learnr once
install.packages("learnr")

# 2a — open any .Rmd in RStudio and click "Run Document"

# 2b — or run from the console
rmarkdown::run("pharmaverse_tutorials/04_datastep_to_dplyr.Rmd")
```

> **Posit Connect:** publish any `.Rmd` with `rsconnect::deployApp()` for a
> hosted, shareable version.

---

## Design Principles

- **Real data only** — all exercises use `pharmaverseadam::adsl/adae/adlb/advs`
  and `pharmaversesdtm` domain tables. Fabricated tibbles appear only when a
  concept has no real-data equivalent.
- **Mocked package infrastructure** — every lesson contains an API-compatible
  mock of the featured package in the `setup` chunk, so exercises run in any
  environment without installing the package under study.
- **Progressive disclosure** — `progressive: true` keeps sections hidden until
  the learner is ready; `allow_skip: true` lets advanced users jump ahead.
- **Exercise scaffolding** — blanks shown as `___`; every exercise has at least
  one hint chunk and a fully-worked solution chunk.
- **SAS↔R mapping** — each lesson opens with an explicit SAS→R translation
  table or side-by-side comparison where relevant.

---

## Repository Structure

```
pharmaverse-tutorials/
│
├── README.md                        ← this file
├── CLAUDE.md                        ← AI-assisted development context
├── LICENSE.txt                      ← MIT License
│
├── pharmaverse_tutorials/           ← PRIMARY DELIVERABLE: 46 learnr .Rmd files
│
├── pharmaverse01/                   ← Lesson plans 00–03  (4 .md + README)
├── pharmaverse02/                   ← Lesson plans 04–06  (3 .md + README)
├── Pharmaverse03/                   ← Lesson plans 07–11  (5 .md + README)
├── Pharmaverse04/                   ← Lesson plans 12–15  (4 .md + README)
├── Pharmaverse05/                   ← Lesson plans 16–19  (4 .md + README)
├── Pharmaverse06/                   ← Lesson plans 20–24  (5 .md + README)
├── Pharmaverse07/                   ← Lesson plans 25–32  (8 .md)
├── Pharmaverse08/                   ← Lesson plans 33–37  (5 .md + README)
├── Pharmaverse09/                   ← Lesson plans 38–42  (5 .md + README)
├── Pharmaverse10/                   ← Lesson plans 43–48  (6 .md + README)
│
└── renv/                            ← renv lockfile for reproducible packages
```

Each `pharmaverseXX/` folder contains human-readable **narrative lesson plans**
(`.md`) used for curriculum planning and review. The `.Rmd` files in
`pharmaverse_tutorials/` are the deployed interactive tutorials.

---

## Module 1 — Environment & R Foundations
> Lessons 00–03 · `pharmaverse01/`

**Lesson plans**

| File | Topic |
|------|-------|
| [00_pharmaverse_overview.md](pharmaverse01/00_pharmaverse_overview.md) | What is pharmaverse? Ecosystem map, CDISC context |
| [01_ars_ard_paradigm.md](pharmaverse01/01_ars_ard_paradigm.md) | ARS / ARD paradigm — from SAS macros to structured results |
| [02_environment_setup.md](pharmaverse01/02_environment_setup.md) | renv, RStudio, Posit Connect, package management |
| [03_r_primer_part1_data_basics.md](pharmaverse01/03_r_primer_part1_data_basics.md) | R data types, vectors, data frames, tibbles |

**Interactive tutorial**

| # | File | Exercises | Quizzes | Topic |
|---|------|:---------:|:-------:|-------|
| 00 | [00_setup_and_orientation.Rmd](pharmaverse_tutorials/00_setup_and_orientation.Rmd) | 3 | 1 | R environment, renv, RStudio orientation |

---

## Module 2 — R for SAS Programmers
> Lessons 04–06 · `pharmaverse02/`

**Lesson plans**

| File | Topic |
|------|-------|
| [04_r_primer_part2_datastep_to_dplyr.md](pharmaverse02/04_r_primer_part2_datastep_to_dplyr.md) | DATA step → dplyr narrative curriculum |
| [05_r_primer_part3_joins_sql_functions.md](pharmaverse02/05_r_primer_part3_joins_sql_functions.md) | PROC SQL → dplyr joins and window functions |
| [06_r_primer_part4_tidyverse.md](pharmaverse02/06_r_primer_part4_tidyverse.md) | tidyr, stringr, lubridate, purrr narrative |

**Interactive tutorials**

| # | File | Exercises | Quizzes | Topic |
|---|------|:---------:|:-------:|-------|
| 04 | [04_datastep_to_dplyr.Rmd](pharmaverse_tutorials/04_datastep_to_dplyr.Rmd) | 56 | 3 | filter, select, mutate, summarise, group_by, lag/lead, across, cumulative functions, 2 capstones |
| 05 | [05_joins_sql_functions.Rmd](pharmaverse_tutorials/05_joins_sql_functions.Rmd) | 20 | 4 | inner/left/anti/cross joins, SQL-style window functions |
| 06 | [06_tidyverse.Rmd](pharmaverse_tutorials/06_tidyverse.Rmd) | 29 | 7 | tidyr pivoting, stringr, lubridate, purrr |

---

## Module 3 — SDTM & Raw Data
> Lessons 07–11 · `Pharmaverse03/`

**Lesson plans**

| File | Topic |
|------|-------|
| [07_pharmaverseraw.md](Pharmaverse03/07_pharmaverseraw.md) | pharmaversesdtm / pharmaverseadam raw dataset exploration |
| [08_sdtm_oak_part1_concepts.md](Pharmaverse03/08_sdtm_oak_part1_concepts.md) | sdtm.oak concepts — hardcode, assign, condition |
| [09_sdtm_oak_part2_mapping.md](Pharmaverse03/09_sdtm_oak_part2_mapping.md) | sdtm.oak conditional mapping, SUPP domains |
| [10_sdtm_oak_part3_supp_relrec.md](Pharmaverse03/10_sdtm_oak_part3_supp_relrec.md) | sdtm.oak RELREC, define-XML with xportr |
| [11_sdtmchecks.md](Pharmaverse03/11_sdtmchecks.md) | sdtmchecks, Pinnacle 21 rule categories |

**Interactive tutorials**

| # | File | Exercises | Quizzes | Topic |
|---|------|:---------:|:-------:|-------|
| 07 | [07_pharmaverseraw.Rmd](pharmaverse_tutorials/07_pharmaverseraw.Rmd) | 20 | 6 | Domain inventory, variable metadata, CDISC structure exploration |
| 08 | [08_sdtm_oak_part1.Rmd](pharmaverse_tutorials/08_sdtm_oak_part1.Rmd) | 21 | 9 | sdtm.oak — hardcode\_ct(), assign\_ct(), assign\_no\_ct() |
| 09 | [09_sdtm_oak_part2.Rmd](pharmaverse_tutorials/09_sdtm_oak_part2.Rmd) | 16 | 4 | Conditional mapping, SUPP domain construction |
| 10 | [10_sdtm_oak_part3.Rmd](pharmaverse_tutorials/10_sdtm_oak_part3.Rmd) | 12 | 7 | RELREC, define-XML generation |
| 11 | [11_sdtmchecks.Rmd](pharmaverse_tutorials/11_sdtmchecks.Rmd) | 15 | 5 | sdtmchecks validation functions, Pinnacle 21 rule mapping |

---

## Module 4 — Metadata & admiral Foundations
> Lessons 12–15 · `Pharmaverse04/`

**Lesson plans**

| File | Topic |
|------|-------|
| [12_metacore.md](Pharmaverse04/12_metacore.md) | metacore — specs objects, variable metadata |
| [13_metatools.md](Pharmaverse04/13_metatools.md) | metatools — dataset derivation helpers |
| [14_admiral_part1_foundations.md](Pharmaverse04/14_admiral_part1_foundations.md) | admiral foundations — templates, derivation functions |
| [15_admiral_part2_adsl.md](Pharmaverse04/15_admiral_part2_adsl.md) | admiral ADSL derivation walkthrough |

**Interactive tutorials**

| # | File | Exercises | Quizzes | Topic |
|---|------|:---------:|:-------:|-------|
| 12 | [12_metacore.Rmd](pharmaverse_tutorials/12_metacore.Rmd) | 12 | 5 | metacore specs, variable/value metadata, validation |
| 13 | [13_metatools.Rmd](pharmaverse_tutorials/13_metatools.Rmd) | 12 | 3 | metatools — check\_ct\_data(), combine\_supp(), build datasets |
| 14 | [14_admiral_part1.Rmd](pharmaverse_tutorials/14_admiral_part1.Rmd) | 9 | 5 | admiral templates, derive\_vars\_\*(), date imputation |
| 15 | [15_admiral_part2_adsl.Rmd](pharmaverse_tutorials/15_admiral_part2_adsl.Rmd) | 11 | 5 | ADSL: treatment dates, population flags, disposition |

---

## Module 5 — admiral BDS, OCCDS & Time-to-Event
> Lessons 16–19 · `Pharmaverse05/`

**Lesson plans**

| File | Topic |
|------|-------|
| [16_admiral_part3_bds.md](Pharmaverse05/16_admiral_part3_bds.md) | BDS datasets (ADLB, ADVS) |
| [17_admiral_part4_occds.md](Pharmaverse05/17_admiral_part4_occds.md) | OCCDS datasets (ADAE) |
| [18_admiral_part5_adtte.md](Pharmaverse05/18_admiral_part5_adtte.md) | ADTTE / time-to-event |
| [19_admiral_part6_advanced.md](Pharmaverse05/19_admiral_part6_advanced.md) | Advanced patterns, custom derivations, extensions |

**Interactive tutorials**

| # | File | Exercises | Quizzes | Topic |
|---|------|:---------:|:-------:|-------|
| 16 | [16_admiral_part3_bds.Rmd](pharmaverse_tutorials/16_admiral_part3_bds.Rmd) | 13 | 7 | ADLB/ADVS: analysis records, baseline, toxicity grades |
| 17 | [17_admiral_part4_occds.Rmd](pharmaverse_tutorials/17_admiral_part4_occds.Rmd) | 9 | 8 | ADAE: treatment-emergent flags, severity, seriousness |
| 18 | [18_admiral_part5_adtte.Rmd](pharmaverse_tutorials/18_admiral_part5_adtte.Rmd) | 7 | 7 | ADTTE: derive\_param\_tte(), Kaplan-Meier inputs |
| 19 | [19_admiral_part6_advanced.Rmd](pharmaverse_tutorials/19_admiral_part6_advanced.Rmd) | 8 | 8 | Custom derivation functions, admiral extensions pattern |

---

## Module 6 — admiral Extensions
> Lessons 20–24 · `Pharmaverse06/`

**Lesson plans**

| File | Topic |
|------|-------|
| [20_admiralonco.md](Pharmaverse06/20_admiralonco.md) | admiralonco — oncology ADaM (ADRS, ADTR, ADTTE) |
| [21_admiralvaccine.md](Pharmaverse06/21_admiralvaccine.md) | admiralvaccine — immunogenicity, reactogenicity |
| [22_admiralophtha.md](Pharmaverse06/22_admiralophtha.md) | admiralophtha — ophthalmology endpoints (VA, IOP) |
| [23_admiralpeds.md](Pharmaverse06/23_admiralpeds.md) | admiralpeds — paediatric growth metrics, z-scores |
| [24_admiralmetabolic.md](Pharmaverse06/24_admiralmetabolic.md) | Metabolic syndrome composite endpoints |

**Interactive tutorials**

| # | File | Exercises | Quizzes | Topic |
|---|------|:---------:|:-------:|-------|
| 20 | [20_admiralonco.Rmd](pharmaverse_tutorials/20_admiralonco.Rmd) | 21 | 7 | ADRS (response), ADTR (tumour), BICR vs investigator |
| 21 | [21_admiralvaccine.Rmd](pharmaverse_tutorials/21_admiralvaccine.Rmd) | 20 | 6 | ADIS (immunogenicity), ADCE (reactogenicity), titre analysis |
| 22 | [22_admiralophtha.Rmd](pharmaverse_tutorials/22_admiralophtha.Rmd) | 18 | 6 | Visual acuity letter scores, IOP, BCVA analysis sets |
| 23 | [23_admiralpeds.Rmd](pharmaverse_tutorials/23_admiralpeds.Rmd) | 20 | 5 | WHO growth charts, z-scores, age-adjusted endpoints |
| 24 | [24_admiralmetabolic.Rmd](pharmaverse_tutorials/24_admiralmetabolic.Rmd) | 23 | 4 | Metabolic composite flags, HbA1c, HOMA-IR |

---

## Module 7 — Tables, Listings & Figures (Part 1)
> Lessons 25–32 · `Pharmaverse07/`

**Lesson plans**

| File | Topic |
|------|-------|
| [25_cards_part1_ard_concepts.md](Pharmaverse07/25_cards_part1_ard_concepts.md) | cards — ARD concepts, ard\_continuous(), ard\_categorical() |
| [26_cards_part2_clinical_ards.md](Pharmaverse07/26_cards_part2_clinical_ards.md) | cards clinical ARDs — safety, efficacy summaries |
| [27_cardx.md](Pharmaverse07/27_cardx.md) | cardx — ard\_ttest(), ard\_wilcoxtest(), ard\_chisqtest() |
| [28_gtsummary_part1_basics.md](Pharmaverse07/28_gtsummary_part1_basics.md) | gtsummary basics — tbl\_summary(), add\_p() |
| [29_gtsummary_part2_clinical_patterns.md](Pharmaverse07/29_gtsummary_part2_clinical_patterns.md) | gtsummary clinical patterns — tbl\_merge(), themes |
| [30_cardinal_part1_overview.md](Pharmaverse07/30_cardinal_part1_overview.md) | cardinal overview — freq\_table(), cont\_table() |
| [31_cardinal_part2_fda_safety.md](Pharmaverse07/31_cardinal_part2_fda_safety.md) | cardinal FDA safety tables |
| [32_tfrmt.md](Pharmaverse07/32_tfrmt.md) | tfrmt — formatting templates, frmt\_combine(), body\_plan() |

**Interactive tutorials**

| # | File | Exercises | Quizzes | Topic |
|---|------|:---------:|:-------:|-------|
| 25 | [25_cards_cardx.Rmd](pharmaverse_tutorials/25_cards_cardx.Rmd) | 21 | 3 | ARD construction with cards/cardx, statistical test results |
| 26 | [26_gtsummary_part1.Rmd](pharmaverse_tutorials/26_gtsummary_part1.Rmd) | 11 | 2 | tbl\_summary(), by-arm demographics, add\_n/add\_p |
| 27 | [27_gtsummary_part2.Rmd](pharmaverse_tutorials/27_gtsummary_part2.Rmd) | 9 | 2 | tbl\_regression(), tbl\_merge(), custom themes |
| 28 | [28_cardinal.Rmd](pharmaverse_tutorials/28_cardinal.Rmd) | 14 | 2 | cardinal frequency and continuous summary tables |
| 29 | [29_tfrmt_part1.Rmd](pharmaverse_tutorials/29_tfrmt_part1.Rmd) | 19 | 3 | tfrmt body\_plan, frmt(), frmt\_combine(), frmt\_when() |
| 30 | [30_tfrmt_part2.Rmd](pharmaverse_tutorials/30_tfrmt_part2.Rmd) | 16 | 2 | Spanning headers, row groups, footnotes, col\_plan() |
| 31 | [31_gt.Rmd](pharmaverse_tutorials/31_gt.Rmd) | 20 | 3 | gt table styling, colours, cell annotations |
| 32 | [32_tlf_capstone.Rmd](pharmaverse_tutorials/32_tlf_capstone.Rmd) | 14 | 4 | End-to-end ARD → formatted submission table capstone |

---

## Module 8 — Tables, Listings & Figures (Part 2)
> Lessons 33–37 · `Pharmaverse08/`

**Lesson plans**

| File | Topic |
|------|-------|
| [33_rtables.md](Pharmaverse08/33_rtables.md) | rtables — split-based table structure |
| [34_tern.md](Pharmaverse08/34_tern.md) | tern — clinical summary functions on rtables |
| [35_r2rtf.md](Pharmaverse08/35_r2rtf.md) | r2rtf — submission-ready RTF output |
| [36_Tplyr.md](Pharmaverse08/36_Tplyr.md) | Tplyr — count, shift, and descriptive table layers |
| [37_tidytlg.md](Pharmaverse08/37_tidytlg.md) | tidytlg — freq\_table(), cont\_table(), tlg\_output() pipeline |

**Interactive tutorials**

| # | File | Exercises | Quizzes | Topic |
|---|------|:---------:|:-------:|-------|
| 33 | [33_rtables.Rmd](pharmaverse_tutorials/33_rtables.Rmd) | 16 | 1 | rtables split/table structure, row/col splits, pagination |
| 34 | [34_tern.Rmd](pharmaverse_tutorials/34_tern.Rmd) | 14 | 1 | tern clinical functions (count\_occurrences, summarize\_vars) |
| 35 | [35_r2rtf.Rmd](pharmaverse_tutorials/35_r2rtf.Rmd) | 13 | 1 | rtf\_body/title/footnote/page pipeline, multi-page tables |
| 36 | [36_Tplyr.Rmd](pharmaverse_tutorials/36_Tplyr.Rmd) | 18 | 2 | Tplyr layers (count, desc, shift), custom headers |
| 37 | [37_tidytlg.Rmd](pharmaverse_tutorials/37_tidytlg.Rmd) | 27 | 3 | tidytlg pipeline from summary stats to submission RTF |

---

## Module 9 — Shiny & teal
> Lessons 38–42 · `Pharmaverse09/`

**Lesson plans**

| File | Topic |
|------|-------|
| [38_shiny_foundations.md](Pharmaverse09/38_shiny_foundations.md) | Shiny reactivity, modules, clinical app patterns |
| [39_teal_architecture.md](Pharmaverse09/39_teal_architecture.md) | teal architecture — cdisc\_data, teal\_slice, tab\_group |
| [40_teal_modules_general.md](Pharmaverse09/40_teal_modules_general.md) | Custom teal module authoring — UI/server pattern |
| [41_teal_modules_clinical.md](Pharmaverse09/41_teal_modules_clinical.md) | teal data layer — teal\_data(), join\_keys(), connectors |
| [42_teal_custom_deployment_validation.md](Pharmaverse09/42_teal_custom_deployment_validation.md) | teal deployment, validation, testServer() |

**Interactive tutorials**

| # | File | Exercises | Quizzes | Topic |
|---|------|:---------:|:-------:|-------|
| 38 | [38_shiny_foundations.Rmd](pharmaverse_tutorials/38_shiny_foundations.Rmd) | 38 | 0 | reactiveVal, observe, modules, clinical UI patterns |
| 39 | [39_teal_architecture.Rmd](pharmaverse_tutorials/39_teal_architecture.Rmd) | 7 | 4 | cdisc\_dataset/cdisc\_data, teal\_slice filters, modules/tab\_group |
| 40 | [40_teal_modules.Rmd](pharmaverse_tutorials/40_teal_modules.Rmd) | 6 | 2 | teal\_module(), ui\_args/server\_args, qenv, testServer() |
| 41 | [41_teal_data_deployment.Rmd](pharmaverse_tutorials/41_teal_data_deployment.Rmd) | 6 | 1 | teal\_data(), join\_keys(), dataset\_connector(), Posit Connect |
| 42 | [42_teal_capstone.Rmd](pharmaverse_tutorials/42_teal_capstone.Rmd) | 10 | 0 | Full CDISCPILOT01 4-module clinical data review app + debug challenge |

---

## Module 10 — Submission Package
> Lessons 43–48 · `Pharmaverse10/`

**Lesson plans**

| File | Topic |
|------|-------|
| [43_xportr.md](Pharmaverse10/43_xportr.md) | xportr — XPT pipeline, date handling, metacore integration |
| [44_datasetjson.md](Pharmaverse10/44_datasetjson.md) | Dataset-JSON v1.1 spec, write/read, validation |
| [45_logrx.md](Pharmaverse10/45_logrx.md) | logrx — GxP logging, axecute(), batch execution |
| [46_diffdf_riskmetric.md](Pharmaverse10/46_diffdf_riskmetric.md) | diffdf QC + riskmetric package risk scoring |
| [47_capstone_part1_data_pipeline.md](Pharmaverse10/47_capstone_part1_data_pipeline.md) | Capstone Part 1 — SDTM → ADaM pipeline design |
| [48_capstone_part2_deliverables.md](Pharmaverse10/48_capstone_part2_deliverables.md) | Capstone Part 2 — ADaM → TLF → submission package |

**Interactive tutorials**

| # | File | Exercises | Quizzes | Topic |
|---|------|:---------:|:-------:|-------|
| 43 | [43_xportr.Rmd](pharmaverse_tutorials/43_xportr.Rmd) | 12 | 2 | xportr\_type/label/length/format/order, unified xportr(), date encoding |
| 44 | [44_datasetjson.Rmd](pharmaverse_tutorials/44_datasetjson.Rmd) | 9 | 2 | dataset\_json(), write/read, NA handling, round-trip fidelity |
| 45 | [45_logrx.Rmd](pharmaverse_tutorials/45_logrx.Rmd) | 8 | 2 | axecute(), log structure, warning triage, CI/CD integration |
| 46 | [46_diffdf_riskmetric.Rmd](pharmaverse_tutorials/46_diffdf_riskmetric.Rmd) | 9 | 1 | diffdf() double-programming QC, riskmetric risk tier scoring |
| 47 | [47_capstone_part1.Rmd](pharmaverse_tutorials/47_capstone_part1.Rmd) | 12 | 0 | SDTM→ADaM: ADSL (DM+EX+DS), ADAE derivation, XPT export |
| 48 | [48_capstone_part2.Rmd](pharmaverse_tutorials/48_capstone_part2.Rmd) | 8 | 3 | ADaM→TLF→submission: gtsummary+tfrmt+r2rtf, logrx, diffdf, dual export |

---

## Prerequisites

```r
# Core tidyverse + learnr
install.packages(c(
  "learnr", "dplyr", "tidyr", "tibble", "stringr",
  "purrr", "lubridate", "ggplot2"
))

# CDISC clinical data (open-source, CDISCPILOT01 study)
install.packages(c("pharmaverseadam", "pharmaversesdtm"))

# Packages covered lesson-by-lesson (install as needed)
install.packages(c(
  # SDTM
  "sdtm.oak", "sdtmchecks",
  # Metadata
  "metacore", "metatools",
  # ADaM
  "admiral", "admiralonco", "admiralvaccine",
  "admiralophtha", "admiralpeds",
  # ARD / TLF
  "cards", "cardx", "gtsummary", "cardinal",
  "tfrmt", "gt", "rtables", "tern",
  "r2rtf", "Tplyr", "tidytlg",
  # Shiny / teal
  "shiny", "teal", "teal.data", "teal.modules.clinical",
  # Submission
  "xportr", "datasetjson", "logrx", "diffdf", "riskmetric"
))
```

---

## Totals

| Metric | Count |
|--------|------:|
| learnr `.Rmd` tutorials | 46 |
| Source lines (all `.Rmd`) | ~63,400 |
| Coding exercises | 712 |
| Multiple-choice quiz questions | 168 |
| Narrative lesson plan `.md` files | 137 |
| Pharmaverse packages covered | 30+ |

---

*48 lessons · 10 modules · from raw SDTM domains to a complete eCTD submission package*
