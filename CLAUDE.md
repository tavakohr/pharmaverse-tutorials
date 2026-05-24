# CLAUDE.md — Pharmasave Pharmaverse Tutorial Project

This file is loaded automatically at the start of every Cowork session in this folder.
It gives Claude full context about the project so you can ask for updates without re-explaining history.

---

## Project Overview

A complete **interactive R tutorial series** for clinical programmers transitioning from SAS to R / pharmaverse. Two parallel artefact types exist side-by-side:

| Type | Location | Purpose |
|------|----------|---------|
| Narrative lesson plans (`.md`) | `pharmaverse01/` … `Pharmaverse10/` | Human-readable curriculum, used to plan and review content |
| Interactive learnr tutorials (`.Rmd`) | `pharmaverse_tutorials/` | Deployed in RStudio / Posit Connect; learners run code live |

The `.Rmd` files are the **primary deliverable**. The `.md` files are reference documents.

---

## Rmd Tutorial Inventory

| File | Lesson # | Topic |
|------|----------|-------|
| `00_setup_and_orientation.Rmd` | 0 | R environment, renv, RStudio orientation |
| `04_datastep_to_dplyr.Rmd` | 4 | SAS DATA step → dplyr (filter, select, mutate, summarise, group_by, lag/lead, across, cumulative functions, two capstone projects) |
| `05_joins_sql_functions.Rmd` | 5 | Joins (inner/left/anti/cross), SQL-style window functions |
| `06_tidyverse.Rmd` | 6 | tidyr pivoting, stringr, lubridate, purrr |
| `07_pharmaverseraw.Rmd` | 7 | pharmaversesdtm / pharmaverseadam raw dataset exploration |
| `08_sdtm_oak_part1.Rmd` | 8 | sdtm.oak — concepts & hardcode/assign |
| `09_sdtm_oak_part2.Rmd` | 9 | sdtm.oak — conditional mapping, SUPP domains |
| `10_sdtm_oak_part3.Rmd` | 10 | sdtm.oak — RELREC, define-XML with xportr |
| `11_sdtmchecks.Rmd` | 11 | sdtmchecks / Pinnacle 21 rule categories |
| `12_metacore.Rmd` | 12 | metacore — specs objects, variable metadata |
| `13_metatools.Rmd` | 13 | metatools — dataset derivation helpers |
| `14_admiral_part1.Rmd` | 14 | admiral foundations — templates, derivation functions |
| `15_admiral_part2_adsl.Rmd` | 15 | admiral ADSL derivation |
| `16_admiral_part3_bds.Rmd` | 16 | admiral BDS datasets (ADLB, ADVS) |
| `17_admiral_part4_occds.Rmd` | 17 | admiral OCCDS datasets (ADAE) |
| `18_admiral_part5_adtte.Rmd` | 18 | admiral ADTTE / time-to-event |
| `19_admiral_part6_advanced.Rmd` | 19 | admiral advanced patterns (custom derivations, extensions) |

---

## Datasets Used in 04_datastep_to_dplyr.Rmd

All data comes from `pharmaverseadam` (CDISC CDISCPILOT01 — Alzheimer's / Xanomeline study).

### `adsl` — 254 subjects, 3 arms
Treatment arms: `Placebo`, `Xanomeline Low Dose`, `Xanomeline High Dose`

**Confirmed real variables** (as of pharmaverseadam current release):

```
STUDYID  USUBJID  SUBJID  SITEID  COUNTRY
RFSTDTC  RFENDTC  RFXSTDTC  RFXENDTC  RFPENDTC
SCRFDT   FRVDT    DTHDTC   DTHADY   DTHFL
LDDTHELD LDDTHGR1 DTH30FL  DTHA30FL DTHDOM  DTHB30FL
REGION1  DMDTC    DMDY
AGE  AGEU  AGEGR1  SEX  RACE  RACEGR1  ETHNIC
SAFFL  ARM  ARMCD  ACTARM  ACTARMCD
TRT01P  TRT01A  TRTSDT  TRTSDTM  TRTSTMF  TRTEDT  TRTEDTM  TRTETMF
EOSSTT  EOSDT  RFICDTC  RANDDT  LSTALVDT  TRTDURD
DTHDT  DTHDTF  DTHCAUS  DTHCGR1  BRTHDTC
HEIGHTBL  WEIGHTBL  BMIBL   ← may be absent in old builds; setup synthesises them
ITTFL   ← derived in setup as = SAFFL
DIABFL  ← derived in setup: BMIBL >= 30 → "Y"
```

**Variables that do NOT exist** (remove if found in exercises):
`SMOKING`, `EFFFL`, `AGEGR1N`, `TRT01PN`, `REGION1N`

Use `DTHFL` as a substitute wherever `EFFFL` was intended. Use `RFSTDTC` / `RFENDTC` wherever dropped date columns were needed.

### `adae` — 1200+ AE records
- Treatment variable is `TRTA` in pharmaverseadam, **not** `TRT01A`. The setup chunk renames it.
- `AESEVN` (numeric severity 1/2/3) is derived in setup via `case_when`.

### `adlb` — thousands of lab observations
Key parameters: `ALT`, `CREAT`, `WBC`, `CA`, glucose, and more.

**Critical quirks — always apply these filters/conversions before exercises:**

1. **ATOXGR is character `<chr>`** in pharmaverseadam, not integer. Direct `>` comparison does alphabetic ordering (`"0" > "-1"` = TRUE, which is wrong). The setup chunk converts with `as.integer()`.

2. **admiral-derived rows (DTYPE not NA)** — admiral appends summary records with `DTYPE = "MAXIMUM"`, `"MINIMUM"`, `"LOCF"`, etc. These carry sentinel `AVISITN` values (9997, 9998…) and are **not real visits**. They pollute `lag()`, `lead()`, and worsening-flag exercises. The setup chunk removes them with `filter(is.na(DTYPE))`.

3. **TRTSDT** — may be absent from adlb; the setup chunk left-joins it from adsl.

### `advs` — vital signs
Loaded as-is from `pharmaverseadam::advs`. Parameters: SBP, DBP, PULSE, WEIGHT, HEIGHT.

---

## Setup Chunk (04_datastep_to_dplyr.Rmd) — Canonical Version

```r
library(learnr); library(dplyr); library(tidyr)
library(tibble); library(stringr); library(pharmaverseadam)

# ADSL
adsl_raw <- pharmaverseadam::adsl
if (!all(c("HEIGHTBL", "WEIGHTBL") %in% names(adsl_raw))) {
  set.seed(2014); n <- nrow(adsl_raw)
  ht <- ifelse(adsl_raw$SEX == "F", round(rnorm(n,161,7)), round(rnorm(n,174,8)))
  wt <- ifelse(adsl_raw$SEX == "F", round(rnorm(n,68,12),1), round(rnorm(n,82,14),1))
  adsl_raw <- adsl_raw |> mutate(HEIGHTBL=ht, WEIGHTBL=wt,
                                  BMIBL=round(WEIGHTBL/(HEIGHTBL/100)^2,1))
} else if (!"BMIBL" %in% names(adsl_raw)) {
  adsl_raw <- mutate(adsl_raw, BMIBL=round(WEIGHTBL/(HEIGHTBL/100)^2,1))
}
adsl <- adsl_raw |> mutate(
  ITTFL  = SAFFL,
  DIABFL = if_else(!is.na(BMIBL) & BMIBL >= 30, "Y", "N", missing = "N"))

# ADAE — rename TRTA → TRT01A for consistency
adae_raw <- pharmaverseadam::adae
if ("TRTA" %in% names(adae_raw) && !"TRT01A" %in% names(adae_raw)) {
  adae_raw <- rename(adae_raw, TRT01A = TRTA)
} else if (!"TRT01A" %in% names(adae_raw)) {
  adae_raw <- left_join(adae_raw, select(adsl, USUBJID, TRT01A), by = "USUBJID")
}
adae <- adae_raw |> mutate(AESEVN = case_when(
  AESEV == "MILD"     ~ 1L, AESEV == "MODERATE" ~ 2L,
  AESEV == "SEVERE"   ~ 3L, TRUE ~ NA_integer_))

# ADLB — fix character ATOXGR, drop admiral derived rows, add TRTSDT
adlb <- pharmaverseadam::adlb
if (is.character(adlb$ATOXGR))
  adlb <- mutate(adlb, ATOXGR = as.integer(ATOXGR), BTOXGR = as.integer(BTOXGR))
if ("DTYPE" %in% names(adlb))
  adlb <- filter(adlb, is.na(DTYPE))   # remove admiral summary rows (AVISITN 9997/9998)
if (!"TRTSDT" %in% names(adlb))
  adlb <- left_join(adlb, select(adsl, USUBJID, TRTSDT), by = "USUBJID")

# ADVS
advs <- pharmaverseadam::advs
```

---

## Key Teaching Patterns (04_datastep_to_dplyr.Rmd)

| Section | Core pattern | Common gotcha |
|---------|-------------|---------------|
| 1 — filter | `filter()`, `between()`, `%in%` | NA rows pass through `!=` |
| 2 — select | `select()`, `rename()`, `starts_with()`, `rename_with()` | `select(NEW=OLD)` rename-in-place |
| 3 — mutate | `mutate()`, `if_else()`, `case_when()` | Typed NAs: `NA_character_`, `NA_integer_`, `as.Date(NA)` |
| 4 — arrange | `arrange()`, `desc()` | `desc()` on logical puts TRUE first |
| 5 — summarise | `summarise()`, `n()`, `n_distinct()` | Always pair with `group_by()` |
| 6 — group_by | `group_by() + mutate()` vs `summarise()` | `ungroup()` after; `.by=` in dplyr ≥ 1.1 |
| 7 — FIRST./LAST. | `first()`, `last()`, `slice(1)`, `slice_min/max()` | `first(x[condition])` for within-group lookup |
| 8 — distinct/count | `distinct()`, `count()`, `add_count()` | `add_count()` = group mutate shorthand |
| 9 — strings | `str_detect()`, `str_replace()`, `str_c()`, `gsub()` | `gsub()` must be taught before use in exercises |
| 10 — cumulative | `cumsum()`, `cummax()`, `cumany()`, `cummean()` | `cumany()` latches TRUE; `cumsum(1)` as row counter |
| 11 — lag/lead | `lag()`, `lead()` always inside `group_by()` | DTYPE rows must be excluded first; ATOXGR must be integer |
| 12 — across | `across()`, `.names = "{.col}_{.fn}"` | `where(is.numeric)` as column selector |
| 13 — rowwise | `rowwise() + c_across()` | Release with `ungroup()` |
| 14 — capstone 1 | AE safety summary | `mean(flag == "Y")` proportion idiom |
| 15 — capstone 2 | Lab toxicity shift table | `min_rank(desc(x))` for within-group rank |

---

## NCI CTCAE Toxicity Grade Reference

Used in adlb exercises (ATOXGR, BTOXGR):

| Grade | Meaning |
|-------|---------|
| -2 | Below lower limit of normal — moderate (below-normal analytes like CA) |
| -1 | Below lower limit of normal — mild |
| 0 | Normal / no toxicity |
| 1 | Mild abnormality |
| 2 | Moderate abnormality |
| 3 | Severe abnormality |
| 4 | Life-threatening |

Grade 0 → Grade 1 IS a worsening event. Oscillation between 0 and 1 is clinically valid and will produce multiple GRADE_WORSENED = TRUE rows for the same subject/parameter.

---

## Conventions Across All Rmd Files

- **Pipe:** native `|>` (not `%>%`)
- **Integer literals:** `1L`, `2L` not `1`, `2` when type matters
- **Chunk naming:** kebab-case (`lag-worsened`, `group-sum`); solution chunks suffix `-solution`, hints suffix `-hint-1`
- **Exercise scaffolding:** blanks shown as `___`; `exercise.lines` set to expected answer length + 4
- **Callout boxes:** `>` blockquote for gotchas; `**bold**` for first use of a term
- **Datasets:** Always use real pharmaverseadam data — never fabricate inline tibbles unless a concept genuinely has no pharmaverseadam equivalent
- **No smoking gun variables:** SMOKING, EFFFL, AGEGR1N, TRT01PN do not exist in real adsl — never use them

---

## Folder Map (Markdown lesson plans)

| Folder | Lessons | Theme |
|--------|---------|-------|
| `pharmaverse01/` | 00–03 | Overview, ARS/ARD paradigm, environment setup, R primer part 1 |
| `pharmaverse02/` | 04–06 | R primer parts 2–4 (dplyr, joins, tidyverse) |
| `Pharmaverse03/` | 07–11 | pharmaverseraw, sdtm.oak (3 parts), sdtmchecks |
| `Pharmaverse04/` | 12–15 | metacore, metatools, admiral parts 1–2 |
| `Pharmaverse05/` | 16–19 | admiral parts 3–6 (BDS, OCCDS, ADTTE, advanced) |
| `Pharmaverse06/` | 20–24 | admiral extensions (onco, vaccine, ophtha, peds, metabolic) |
| `Pharmaverse07/` | 25–32 | cards, cardx, gtsummary, cardinal, tfrmt |
| `Pharmaverse08/` | 33–37 | rtables, tern, r2rtf, Tplyr, tidytlg |
| `Pharmaverse09/` | 38–42 | Shiny foundations, teal (architecture + modules + deployment) |
| `Pharmaverse10/` | 43–48 | xportr, datasetjson, logrx, diffdf/riskmetric, capstone (2 parts) |
