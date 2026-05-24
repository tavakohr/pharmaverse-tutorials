# Pharmaverse: A Comprehensive Tutorial for SAS-to-R Clinical Programmers

A complete, video-ready curriculum covering the entire pharmaverse ecosystem — every curated open-source R package for clinical trial reporting, from raw data through eSubmission.

---

## Who this is for

You are (or work alongside) a **clinical statistical programmer** with strong SAS skills, asked to deliver studies in R using pharmaverse packages. You know SDTM and ADaM standards, you know what an ADSL looks like and why it matters, but R may be new territory.

This curriculum assumes:

- Solid CDISC knowledge (SDTM/ADaM/CDASH/Define-XML)
- Working SAS proficiency
- **No prior R experience required** — we build R skills from scratch, with SAS comparisons throughout

If you already know R well, skip Module 1 entirely.

---

## How to use these files with NotebookLM

Each lesson is a standalone `.md` file. Upload them as sources to a NotebookLM notebook:

1. Create a new notebook in NotebookLM
2. Add sources → upload the `.md` files for the lessons you want
3. NotebookLM will index them; you can then generate the Audio Overview ("podcast") feature, ask questions across them, or generate a study guide

**Tip**: For a focused video on one package, upload only that lesson's `.md`. For an end-to-end overview, upload the README + the intro module + the capstone.

Each lesson is sized for **15–25 minutes of spoken video** (≈ 2,500–4,000 words). Big packages (`admiral`, `teal`, `gtsummary`, `cards`) are split into multiple parts.

---

## Curriculum overview

The curriculum follows the **clinical reporting pipeline**: Raw → SDTM → ADaM → TLG → Submission, with cross-cutting modules for metadata, Shiny, and traceability.

### Module 0 — Introduction (`00_intro/`)

| # | Lesson | What you'll learn |
|---|---|---|
| 00 | Pharmaverse overview | What pharmaverse is, why it exists, governance, philosophy |
| 01 | The ARS/ARD paradigm shift | Why Cardinal and ARD-first approaches are the future of TLG generation |
| 02 | Environment setup | R, RStudio, Posit Cloud, pharmaverse packages, `renv` reproducibility |

### Module 1 — R foundations for SAS programmers (`01_foundations_r_for_sas/`)

| # | Lesson | What you'll learn |
|---|---|---|
| 03 | R primer Part 1: data basics | Vectors, data frames, types, NA, assignment — with SAS comparisons |
| 04 | R primer Part 2: DATA step → dplyr | `filter`, `select`, `mutate`, `summarise`, `group_by` vs SAS DATA step |
| 05 | R primer Part 3: PROC SQL & macros | `dplyr` joins, SQL via `dbplyr`, functions vs macros |
| 06 | Tidyverse primer | `tidyr` reshaping, `purrr` for iteration, the `%>%` and `|>` pipes |

### Module 2 — Raw data and SDTM (`02_raw_and_sdtm/`)

| # | Lesson | Package(s) |
|---|---|---|
| 07 | `{pharmaverseraw}` — test EDC data | `pharmaverseraw` |
| 08 | SDTM building Part 1: concepts and architecture | `sdtm.oak` |
| 09 | SDTM building Part 2: mapping algorithms | `sdtm.oak` |
| 10 | SDTM building Part 3: SUPP-- and RELREC | `sdtm.oak` |
| 11 | SDTM conformance checks | `sdtmchecks` |

### Module 3 — Metadata-driven programming (`03_metadata/`)

| # | Lesson | Package(s) |
|---|---|---|
| 12 | `{metacore}` — the spec object | `metacore` |
| 13 | `{metatools}` — using specs to build and check datasets | `metatools` |

### Module 4 — ADaM core (`04_adam_core/`)

| # | Lesson | Package(s) |
|---|---|---|
| 14 | `{admiral}` Part 1: foundations and philosophy | `admiral` |
| 15 | `{admiral}` Part 2: building ADSL | `admiral` |
| 16 | `{admiral}` Part 3: BDS datasets (ADLB, ADVS, ADEG) | `admiral` |
| 17 | `{admiral}` Part 4: OCCDS datasets (ADAE, ADCM) | `admiral` |
| 18 | `{admiral}` Part 5: time-to-event (ADTTE) | `admiral` |
| 19 | `{admiral}` Part 6: derivation patterns deep-dive | `admiral` |

### Module 5 — ADaM therapeutic area extensions (`05_adam_ta_extensions/`)

| # | Lesson | Package(s) |
|---|---|---|
| 20 | `{admiralonco}` — oncology endpoints (RECIST, PFS, ORR) | `admiralonco` |
| 21 | `{admiralvaccine}` — immunogenicity and reactogenicity | `admiralvaccine` |
| 22 | `{admiralophtha}` — ophthalmology BCVA, IOP | `admiralophtha` |
| 23 | `{admiralpeds}` — pediatric growth charts, age units | `admiralpeds` |
| 24 | `{admiralmetabolic}` — diabetes and metabolic endpoints | `admiralmetabolic` |

### Module 6 — TLG: the Cardinal future stack (`06_tlg_future_cardinal/`)

| # | Lesson | Package(s) |
|---|---|---|
| 25 | `{cards}` Part 1: the ARD concept in code | `cards` |
| 26 | `{cards}` Part 2: building ARDs for clinical summaries | `cards` |
| 27 | `{cardx}` — extending cards with regression and survival | `cardx` |
| 28 | `{gtsummary}` Part 1: from ARD to publication table | `gtsummary` |
| 29 | `{gtsummary}` Part 2: clinical reporting patterns (demographics, AE) | `gtsummary` |
| 30 | `{cardinal}` Part 1: the harmonized TLG catalog | `cardinal` |
| 31 | `{cardinal}` Part 2: FDA Safety Tables and Figures templates | `cardinal` |
| 32 | `{tfrmt}` — display metadata for ARDs | `tfrmt` |

### Module 7 — TLG: the legacy/Roche stack (`07_tlg_legacy/`)

| # | Lesson | Package(s) |
|---|---|---|
| 33 | `{rtables}` — the table engine behind tern | `rtables` |
| 34 | `{tern}` — Roche's statistical TLG library | `tern` |
| 35 | `{r2rtf}` — submission-ready RTF output | `r2rtf` |
| 36 | `{Tplyr}` — traceability-minded summary grammar | `Tplyr` |
| 37 | `{tidytlg}` — tidyverse-native TLG generation | `tidytlg` |

### Module 8 — Shiny for clinical exploration (`08_shiny_teal/`)

| # | Lesson | Package(s) |
|---|---|---|
| 38 | Shiny foundations for SAS programmers | `shiny` |
| 39 | `{teal}` Part 1: framework architecture | `teal`, `teal.data` |
| 40 | `{teal.modules.general}` — general-purpose modules | `teal.modules.general` |
| 41 | `{teal.modules.clinical}` — clinical module library | `teal.modules.clinical` |
| 42 | Custom modules, deployment, and validation | `teal`, `teal.reporter`, `teal.code` |

### Module 9 — Submission and transport (`09_submission/`)

| # | Lesson | Package(s) |
|---|---|---|
| 43 | `{xportr}` — XPT v5 transport for FDA | `xportr` |
| 44 | `{datasetjson}` — CDISC Dataset-JSON, the XPT successor | `datasetjson` |

### Module 10 — Traceability, validation, and tooling (`10_traceability/`)

| # | Lesson | Package(s) |
|---|---|---|
| 45 | `{logrx}` — execution logging for clinical programming | `logrx` |
| 46 | `{diffdf}` + `{riskmetric}` — dual programming QC and package risk | `diffdf`, `riskmetric` |

### Capstone (`99_capstone/`) — split into 2 lessons

| # | Lesson | What you'll do |
|---|---|---|
| 47 | Part 1: Data Pipeline | Raw EDC → SDTM → ADaM (ADSL, ADAE, ADLB, ADRS, ADTTE) with full spec-driven programming |
| 48 | Part 2: Deliverables | ADaMs → ARDs → CSR tables (demographics, AE, K-M) → teal app → XPT/JSON submission package |

---

## File naming convention

Files are numbered in recommended viewing order:

```
NN_topic_name.md         ← lesson number 00–46
NN_topic_partM.md        ← multi-part lessons (Part 1, Part 2, ...)
```

---

## Assumptions baked into the curriculum

These were defaulted to keep the curriculum coherent. They can be adjusted later if your context differs:

| Assumption | Value | Why |
|---|---|---|
| Primary audience | SAS programmers transitioning to R | Matches the stated audience |
| Therapeutic area default | Oncology | Most common in pharmaverse examples; admiralonco is well-documented |
| Submission target | FDA-primary, with EMA notes | FDA still drives most format requirements (xportr, define.xml) |
| Test data | `pharmaverseraw`/`pharmaversesdtm`/`pharmaverseadam` | Continuity across every lesson; learners build on the same dataset throughout |
| R version | R ≥ 4.3 | Matches admiral 1.x and gtsummary 2.x requirements at time of writing |
| Style | Tutorial / textbook | Prose + diagrams + runnable code, adapt to video later |

---

## Delivery progress

This curriculum is built in iterative batches. The current status:

| Module | Status |
|---|---|
| 0 — Intro | ✅ Complete (Batch 1) |
| 1 — R foundations | ✅ Complete (Batch 2) |
| 2 — Raw and SDTM | ✅ Complete (Batch 3) |
| 3 — Metadata | ✅ Complete (Batch 4) |
| 4 — ADaM core | ✅ Complete (Batches 4–5) |
| 5 — ADaM TA extensions | ✅ Complete (Batch 6) |
| 6 — TLG future (Cardinal) | ✅ Complete (Batch 7) |
| 7 — TLG legacy | ✅ Complete (Batch 8) |
| 8 — Shiny (teal) | ✅ Complete (Batch 9) — expanded to 5 lessons |
| 9 — Submission | ✅ Complete (Batch 10) |
| 10 — Traceability | ✅ Complete (Batch 10) |
| 99 — Capstone | ✅ Complete (Batch 10) — split into 2 lessons |

---

## Reference links (canonical sources)

- Pharmaverse website: <https://pharmaverse.org>
- End-to-end packages list: <https://pharmaverse.org/e2eclinical/>
- Pharmaverse examples: <https://pharmaverse.github.io/examples/>
- Pharmaverse Slack: invitation link on pharmaverse.org
- PHUSE: <https://phuse.global>
- CDISC standards: <https://www.cdisc.org/standards>
- FDA Study Data Technical Conformance Guide (current version): search FDA's website

---

*This tutorial is independent educational material. It is not affiliated with or endorsed by Anthropic, the pharmaverse Council, PHUSE, CDISC, or any individual package maintainer. Package APIs evolve; always validate the version of any package you use in a regulated environment against current documentation.*
