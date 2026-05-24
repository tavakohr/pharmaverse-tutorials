# Lesson 30 — `{cardinal}` Part 1: The Harmonized TLG Catalog

**Module**: 6 — TLG: the Cardinal-future stack
**Estimated length**: ~18 min spoken
**Prerequisites**: Lessons 25–29

---

## Learning objectives

By the end of this lesson, you will be able to:

1. Recognize Cardinal as an industry-wide TLG harmonization initiative under pharmaverse
2. Understand the catalog-of-templates model: not an R package, but a repository of reproducible TLG examples
3. Browse and select templates from the cardinal catalog for your study
4. Understand which packages cardinal templates use (cards, cardx, gtsummary, tfrmt, crane)
5. Adapt a cardinal template to your sponsor's specifications
6. Contribute new templates back to the catalog

---

## 1. What Cardinal is (and isn't)

`{cardinal}` — formerly called `{falcon}` — is an **industry initiative** rather than a typical R package. The headline goal: build and open-source a harmonized catalog of tables, listings, and graphs (TLGs) for clinical reporting.

The motivating problem: every pharma company independently builds essentially the same tables. The demographic table at Roche looks like the demographic table at GSK looks like the demographic table at Pfizer. Each company maintains its own templates. Each ages slightly differently. Each requires re-validation. Reviewers see slightly different output formats across submissions.

Cardinal proposes a different model: **one industry catalog** of TLG templates, openly maintained, validated against FDA Standard Safety Tables and Figures guidelines, that any sponsor can copy and adapt.

Origin: founded 2023 with Roche, Boehringer Ingelheim, Moderna, and Sanofi. Renamed from {falcon} to {cardinal} in 2024 with broader pharmaverse alignment. Current participating companies include the original four plus expanding contributions.

## 2. The catalog model

Cardinal is **not** a function library you install and call. It's a **Quarto-based catalog** of TLG templates, browsable as a website:

[https://pharmaverse.github.io/cardinal/](https://pharmaverse.github.io/cardinal/)

Each entry is a Quarto document showing:

- The target TLG (the FDA Standard Safety Tables and Figures table being implemented)
- The full R code to produce it
- A rendered preview of the output
- The packages used (typically cards, gtsummary, dplyr, sometimes specific TA packages)
- Notes on customization

You **read** the catalog and **copy** the templates into your study. You don't `library(cardinal)`.

(There is a small `{cardinal}` R package that hosts the catalog infrastructure, but it's not the primary interaction model.)

## 3. The FDA Standard Safety Tables and Figures Integrated Guide

Cardinal's primary source is the FDA Standard Safety Tables and Figures Integrated Guide — a publication describing the canonical safety tables FDA reviewers expect, with table mockups and methodology. The guide covers:

- Demographic and baseline characteristics
- Subject disposition
- Exposure summary
- Adverse events (overall, by SOC/PT, SAEs, by severity)
- Laboratory abnormalities
- Vital signs and ECG
- Special populations (pediatric, hepatic-impaired, renal-impaired)

For each, the guide specifies the layout (columns, rows, footnotes), the methodology (denominators, statistical tests), and the population definition. Cardinal implements these in R, providing reproducible templates that match the guide.

If your CSR's tables are aligned to the FDA guide (most are, increasingly), Cardinal templates are a drop-in starting point.

## 4. How to use the catalog

Browse the website. Find the table you need. Copy its code to your project. Adapt to your data.

```
1. Navigate to https://pharmaverse.github.io/cardinal/
2. Browse the "Catalog" section
3. Open a relevant template (e.g., "FDA Table 9.1: Demographics")
4. Read the methodology notes
5. Copy the .qmd file to your project
6. Replace test data references with your study data
7. Customize per your SAP
```

Templates are stored under `pharmaverse/cardinal/quarto/catalog/` in the GitHub repository, organized by FDA table number and category. Each template is a self-contained Quarto document — you can render it independently before integrating into your study.

## 5. A representative template structure

A typical cardinal template `index.qmd` looks like:

````markdown
---
title: "FDA Table 9.1: Demographics and Baseline Characteristics"
---

## Description

This template implements FDA Standard Safety Tables and Figures Table 9.1...

## Required Packages

```r
library(cards)
library(gtsummary)
library(dplyr)
library(pharmaverseadam)
```

## ADaM Inputs

- `adsl`: Subject-Level Analysis Dataset filtered to safety population

## Code

```r
adsl <- pharmaverseadam::adsl |> filter(SAFFL == "Y")

ard <- ard_stack(adsl, ...)

table <- ard |> tbl_ard_summary(...) |> add_p() |> bold_labels()

table
```

## Output

[Rendered table preview]

## Customization Notes

- For studies with crossover, replace TRT01A with TRT01P or TRTSEQA
- Adjust footnote for sponsor terminology...
````

The structure is documentation-heavy: the *why* is as important as the *what*. A reviewer reading the template can understand both the methodology and the implementation.

## 6. What packages cardinal templates use

The Cardinal-future TLG stack underpins cardinal templates:

| Layer | Packages |
|---|---|
| ARD | `{cards}`, `{cardx}` |
| Display | `{gtsummary}`, sometimes `{tfrmt}` |
| Pharma helpers | `{crane}` (Roche conventions) |
| Test data | `{pharmaverseadam}`, `{pharmaversesdtm}` |
| Quarto rendering | `{quarto}`, `{rmarkdown}` |

Every cardinal template uses cards for ARD construction; most use gtsummary for display; some use tfrmt for complex layouts.

For graphs (the G in TLG), templates additionally use `{ggplot2}` (often with `{tern}`-style themes), `{survminer}` for K-M plots, and `{ggsurvfit}` for newer KM plots.

## 7. Categories in the catalog

The cardinal catalog organizes templates by TLG category:

- **fda-table_xx** — FDA Standard Safety Tables (the canonical baseline)
- **demographics** — Demographics-focused tables
- **adverse-events** — AE summary tables
- **exposure** — Exposure summary tables
- **laboratory** — Lab tables
- **vital-signs** — VS summaries
- **survival** — Survival analyses
- **subgroup** — Subgroup forest plots and similar
- **listings** — Subject-level listings

Each category has multiple entries; the catalog is still growing. Check the website for current coverage.

## 8. Contributing a template

The cardinal initiative explicitly invites contributions. To add a template:

1. Fork the `pharmaverse/cardinal` GitHub repo
2. Create a new folder in `quarto/catalog/` with a unique name (e.g., `lab-creatinine-shift_01`)
3. Add `index.qmd` following the template structure (description, packages, code, output, notes)
4. Add a `result.png` snapshot of the rendered output
5. Open a pull request

The cardinal team reviews and merges. Reviewer feedback typically focuses on:

- Methodology correctness (does it match the FDA guide or a referenced standard?)
- Code quality (uses Cardinal-future stack? readable? error-free?)
- Documentation completeness (can a new programmer understand and adapt it?)

The contribution model encourages broad participation. If your sponsor has a useful TLG template that aligns with the FDA guide, contributing it benefits the industry. Your name appears as the contributor.

## 9. Customization patterns

Cardinal templates are starting points. They need adaptation for your study. Common customizations:

### Replace test data with study data

```r
# Cardinal template (test data)
adsl <- pharmaverseadam::adsl

# Your version (study data)
adsl <- haven::read_xpt("path/to/adsl.xpt")
```

### Adjust filtering for sponsor populations

```r
# Cardinal default
adsl <- adsl |> filter(SAFFL == "Y")

# Sponsor with custom population flag
adsl <- adsl |> filter(SAFFFL == "Y" & ANL01FL == "Y")
```

### Apply sponsor styling

```r
theme_gtsummary_compact()    # cardinal default

# Sponsor custom theme
my_sponsor_theme()           # sponsor-internal theme function
```

### Adjust footnotes for sponsor terminology

Replace cardinal's generic footnotes with your sponsor's SOP-required text. This is purely cosmetic but important for SOP compliance.

## 10. Cardinal vs. NEST: TLG strategy comparison

A natural question: how does cardinal relate to Roche's NEST initiative (rtables/tern/chevron — Module 7)?

**NEST** (legacy stack):
- Mature, production-proven
- All-in-one packages for table generation
- Tightly coupled — rtables → tern → chevron, with optional r2rtf
- Best for highly customized, exotic table layouts

**Cardinal** (future stack):
- New, growing
- Templates rather than monolithic packages
- Built on cards + gtsummary + tfrmt + ggplot
- Best for standard FDA-aligned tables; easier to adapt and validate
- Aligned with CDISC ARS — the regulatory direction

Both stacks coexist. Many sponsors use rtables/tern for complex tables (especially oncology) and gtsummary for everything else. Cardinal accelerates the latter by providing template starting points.

Strategically, Cardinal is positioned to absorb the role of NEST for new development, especially as CDISC ARS becomes more central. Existing rtables-based pipelines won't be rewritten overnight, but new starts will likely prefer Cardinal-future.

## 11. The website as a learning resource

Beyond providing templates, cardinal's website serves as a **learning catalog**. Reading the templates teaches:

- How to structure an ARD for a specific table
- Which cards/cardx/gtsummary functions apply to each table type
- How to handle pharma-specific edge cases (missing data, special populations)
- Methodology (denominator choices, statistical tests, missing-data conventions)

For a new programmer, browsing the cardinal catalog is a faster education than reading individual package vignettes.

## 12. Maintainers and team

Cardinal is governed under pharmaverse with active maintainers from the founding companies (Roche, Boehringer Ingelheim, Moderna, Sanofi). The maintainer pool is growing — by mid-2026, contributors from a dozen pharma companies plus several CROs.

Strategic direction (per the cardinal docs):

- **Continue expanding the catalog** of FDA Safety Tables coverage
- **Add efficacy templates** beyond the safety guide
- **Integrate with `{tfrmt}`** for complex layouts
- **CDISC ARS alignment**: templates that produce both an ARD (for ARS submission) and a display

The roadmap is public on GitHub. If you have a perspective on what should be prioritized, the cardinal Slack and GitHub issues are responsive.

## 13. A worked example: copying a cardinal template

Suppose you need an AE incidence table. Steps:

```
1. Browse https://pharmaverse.github.io/cardinal/
2. Find "FDA Table 14.x: Adverse Events..."
3. Open the template
4. Save the index.qmd content as my_ae_table.qmd in your project
5. Open my_ae_table.qmd
6. Replace test data path with your study's ADAE and ADSL
7. Adjust filtering (e.g., SAFFL = "Y" already matches your needs)
8. Re-render: quarto render my_ae_table.qmd
9. Inspect output; iterate on customization
```

The first iteration produces a working AE table. Subsequent customization adapts to sponsor SOPs.

## 14. Cardinal's relationship to CDISC ARS

CDISC's Analysis Results Standard (ARS) is emerging as the regulatory direction. ARS expects:

- A machine-readable ARD as part of every submission
- The ARD links to the metadata describing how each statistic was computed
- The ARD links to the rendered table for verification

Cardinal templates produce both an ARD (via cards) and a display (via gtsummary). If you save the intermediate ARD object, you have the ARS-ready artifact. Display becomes a derived rendering.

When ARS becomes a formal submission requirement (anticipated 2026–2027), Cardinal-built tables are positioned to be ARS-compliant out of the box. Legacy stack tables would need additional work to generate the corresponding ARDs.

## 15. Key takeaways

- `{cardinal}` (formerly `{falcon}`) is an industry initiative under pharmaverse providing a harmonized catalog of TLG templates
- It's **not** an R package you install — it's a Quarto-based template repository on a website
- Templates implement FDA Standard Safety Tables and Figures Integrated Guide
- Built on the Cardinal-future stack: cards + cardx + gtsummary + tfrmt + crane
- Use pattern: browse → copy template → adapt to your study
- Contribution is open: fork, add template, PR
- Coexists with NEST (legacy rtables stack); both serve different niches
- Aligned with the emerging CDISC ARS standard for regulatory submission

## 16. What's next

Lesson 31 — **`{cardinal}` Part 2** — dives into the FDA Standard Safety Tables and Figures specifically. We'll walk through the most heavily-used cardinal templates (Demographics, AE Overview, AE by SOC/PT, Lab Shift Tables) showing the patterns you'll see repeated across the catalog. After Part 2 we move to `{tfrmt}` (Lesson 32) — the display metadata layer for complex tables.

---

## Self-check questions

1. Why is `{cardinal}` described as a catalog rather than an R package?
2. Which industry guide is the primary source for cardinal's safety table templates?
3. Name three packages that cardinal templates typically use.
4. What's the difference between cardinal and Roche's NEST stack in TLG strategy?
5. How would you contribute a new template to the cardinal catalog?
6. Why is cardinal's approach aligned with the future CDISC ARS standard?

## Glossary

- **`{cardinal}`** — Industry harmonized catalog of TLG templates (formerly `{falcon}`)
- **TLG** — Tables, Listings, and Graphs
- **FDA Standard Safety Tables and Figures** — FDA guide documenting canonical safety table layouts
- **NEST** — Roche-led TLG initiative (rtables, tern, chevron — Module 7)
- **Quarto** — Documentation/publishing framework; cardinal templates are Quarto documents
- **CDISC ARS** — Analysis Results Standard; emerging CDISC framework for ARD-based reporting
- **`{crane}`** — Roche extension for pharma-specific gtsummary patterns
- **Catalog** — The browsable collection of templates on the cardinal website
- **Template** — A single .qmd file implementing one TLG; copyable to your study
- **Contribution** — Open process for adding new templates to the catalog via GitHub PR
