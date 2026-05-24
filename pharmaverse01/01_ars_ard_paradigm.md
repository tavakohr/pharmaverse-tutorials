# Lesson 01 — The ARS/ARD Paradigm Shift: Why Cardinal Is the Future

**Module**: 0 — Introduction
**Estimated length**: ~25 min spoken
**Prerequisites**: Lesson 00 (Pharmaverse overview)

---

## Learning objectives

By the end of this lesson, you will be able to:

1. Explain the difference between traditional layout-coupled TLG generation and ARD-first analysis
2. Define ARS (Analysis Results Standard) and ARD (Analysis Results Dataset)
3. Describe why an ARD is "machine-readable" and what that enables
4. Identify the packages aligned with the ARD-first paradigm: `cards`, `cardx`, `gtsummary`, `cardinal`, `tfrmt`
5. Articulate the strategic case for adopting an ARD-first stack now vs. later
6. Recognize the limits and current gaps of the ARS standard

---

## 1. The problem with how we've always done TLGs

Let me describe the traditional TLG workflow. You've lived it.

You receive shells for a demographics table. You write SAS code — maybe `PROC FREQ`, maybe `PROC MEANS`, maybe a `DATA` step calculating percentages by hand. The code produces output. You feed the output to a reporting macro that adds titles, footnotes, page breaks, decimals — and out comes an RTF file.

Now your medical writer wants a different breakdown: by age group instead of treatment. You modify the code. The calculations are re-done. A new RTF file comes out.

Now QA wants to verify a single number. They can read it off the RTF, but the number is the *output* of a calculation. To verify it, they need to re-run code, re-derive populations, re-summarize. Often, dual programming means writing the same logic twice and comparing the *RTF outputs*, hoping the dual programmer made the same data preparation choices.

Now Health Authority A wants the table in one format and Health Authority B wants it in another. You don't have the option of "just reformatting" — your code mixes the *analysis logic* with the *display logic*, and unwinding them means rewriting.

This is the core problem: **analysis and presentation are tangled together.**

Every traditional clinical TLG codebase suffers from this. The calculation of "mean age in the safety population" and the *display* of "Mean (SD) age" formatted as `45.3 (12.1)` in the top-left cell of Table 14.1.1 are inseparable in the code. Change one, you risk breaking the other. Re-use is hard. Traceability is hard.

## 2. The CDISC vision: separate the analysis from the display

CDISC saw this problem early. The **Analysis Results Standard (ARS)** is their answer.

The core idea is simple and powerful: **what if every statistic in a clinical study could be stored in a structured, machine-readable dataset — completely independent of how it's eventually displayed?**

Imagine instead of an RTF file with the value `45.3 (12.1)` in a cell, you had a row in a dataset like this:

| variable | statistic | value | population | group | byvar | byvar_val |
|---|---|---|---|---|---|---|
| AGE | mean | 45.3 | Safety | Treatment A | — | — |
| AGE | sd | 12.1 | Safety | Treatment A | — | — |
| AGE | n | 124 | Safety | Treatment A | — | — |

That row tells you:
- **What was calculated** (mean of AGE)
- **For which population** (Safety)
- **For which group** (Treatment A)
- **The value itself** (45.3)

You can also encode:
- **Who calculated it** (lineage / traceability)
- **How** (the algorithm definition)
- **When** (timestamp)
- **With what formatting intent** (e.g., display to 1 decimal)

That dataset is called an **Analysis Results Dataset**, or **ARD**.

Once you have ARDs:

- **The same ARD can produce many displays.** RTF, HTML, PDF, an interactive Shiny app, a slide for a conference — all driven from one canonical source of truth.
- **QA becomes trivial.** Verifying that the mean age is 45.3 means inspecting one row in a dataset, not parsing a PDF.
- **Meta-analysis is straightforward.** Combine ARDs across studies; you have structured statistics ready to pool.
- **Submissions are richer.** Regulators can receive the underlying numbers and the displays, then do their own analyses without re-deriving anything.

This is what the ARS/ARD paradigm is offering: **decouple "what's calculated" from "how it's displayed."**

## 3. ARS, ARD, ARM — the alphabet soup

Three related terms get used interchangeably and shouldn't be:

- **ARS** — Analysis Results **Standard**. The overarching CDISC framework. Defines concepts, metadata, and structure. It's a *specification*, not a dataset.
- **ARM** — Analysis Results **Metadata**. A subset of ARS focused on how analyses are *specified* (what variable, what population, what statistic). Predates ARD; ARS supersedes the standalone ARM concept.
- **ARD** — Analysis Results **Dataset**. The actual data file containing the results. Structured rows of statistics.

The relationship:

```
ARS (Standard)
 ├── Defines what an ARD should look like
 ├── Defines how analyses should be specified (the old ARM concept, now folded in)
 └── Provides the conceptual framework for traceability and re-use
```

In practice, when people talk about "ARD-first programming," they mean: **calculate everything into an ARD first, then transform the ARD into displays as a separate step.**

## 4. What an ARD looks like in code

Here's a minimal ARD generated by the `cards` package in R. Don't worry about the syntax yet — focus on the *shape* of the output.

```r
library(cards)
library(dplyr)

# ADSL is a sample ADaM Subject-Level dataset bundled with cards
adsl <- pharmaverseadam::adsl

ard <- adsl |>
  filter(SAFFL == "Y") |>
  ard_continuous(
    by = TRT01A,
    variables = AGE,
    statistic = ~ list(N = \(x) length(x),
                       mean = \(x) mean(x, na.rm = TRUE),
                       sd = \(x) sd(x, na.rm = TRUE))
  )

print(ard)
```

What you'd see is a tibble (an R data frame) with rows like:

```
# A tibble: 9 × 7
  group1 group1_level   variable stat_name stat_label  stat   warning  error
  <chr>  <chr>          <chr>    <chr>     <chr>       <list> <list>   <list>
1 TRT01A Placebo        AGE      N         N           <int>  <NULL>   <NULL>
2 TRT01A Placebo        AGE      mean      Mean        <dbl>  <NULL>   <NULL>
3 TRT01A Placebo        AGE      sd        SD          <dbl>  <NULL>   <NULL>
4 TRT01A Xanomeline Low AGE      N         N           <int>  <NULL>   <NULL>
5 TRT01A Xanomeline Low AGE      mean      Mean        <dbl>  <NULL>   <NULL>
...
```

Notice three things:

**First, every cell value lives in its own row.** This is the opposite of a "wide" presentation table. It's tidy data — one observation per row.

**Second, the context for each value is captured in columns.** Which group? Which variable? Which statistic? You can filter, group, or pivot this for any display you need.

**Third, warnings and errors are captured per row.** If the mean calculation hit a problem (say, all-missing input), the error is recorded right next to the value. This is huge for QC: you find out *which specific statistic* failed, not just that "something went wrong somewhere."

This is an ARD. It's the canonical, structured representation of analysis results.

## 5. The pharmaverse stack for ARD-first programming

Several packages work together to make ARD-first programming practical in R. They're tightly integrated:

| Package | Role | Maintainer |
|---|---|---|
| `{cards}` | Build ARDs from data | Pharmaverse (Roche + GSK + Novartis) |
| `{cardx}` | Extensions: regression, survival, comparison statistics | Pharmaverse (same group) |
| `{gtsummary}` | Format ARDs into publication-ready tables | Pharmaverse (community + MSK origin) |
| `{tfrmt}` | Apply display metadata to ARDs (decimals, sorting, footnotes) | GSK |
| `{cardinal}` | Pre-built TLG templates aligned with FDA Safety guidance | Pharmaverse (multi-company) |

A typical ARD-first workflow looks like this:

```
ADaM datasets (ADSL, ADAE, etc.)
        │
        ▼
   {cards} + {cardx}     ← build ARDs (the statistics)
        │
        ▼
        ARD              ← canonical, structured results
       ╱  ╲
      ╱    ╲
     ▼      ▼
{gtsummary} {tfrmt}      ← format into displays (RTF, HTML, PDF)
     │      │
     ▼      ▼
  Final TLGs
```

`{cardinal}` is the **catalog of templates** that gives you starting points for common tables (demographics, AE summaries, lab abnormalities, etc.) using this stack. Think of it as the open-source equivalent of a company's internal "standard TLG library," but built collaboratively across the industry.

## 6. The Cardinal initiative — why it matters strategically

`{cardinal}` deserves special attention because it represents something new: **multi-company harmonization of TLG templates.**

The project was originally called `{falcon}` and was driven primarily by Roche. In late 2023 / early 2024, it was rebranded to `{cardinal}` and broadened to a true multi-company initiative under pharmaverse. The goal:

- Build a comprehensive catalog of standardized TLG templates
- Anchor the catalog on the FDA Standard Safety Tables and Figures Integrated Guide (which is itself an FDA-published standardization effort)
- Implement everything in ARD-first style using `{cards}` + `{gtsummary}`
- Make it usable across sponsors so that, ideally, regulators see harmonized output formats across submissions

This last point is the strategic bet. **If FDA reviewers see the same demographics table layout from Sponsor A, B, and C, review becomes faster and more accurate.** Sponsors save effort on display engineering. The industry as a whole spends less time arguing about whether AE percentages should be calculated with a numerator of "subjects with AE" or "events" because the cardinal templates encode one agreed answer.

This is why I — and many practitioners in the field — believe `{cardinal}` represents the most likely future of cross-industry TLG generation. It's not a forecast based on hype; it's a strategic observation that:

1. The major sponsors are aligned (Roche, GSK, Novartis, J&J all contributing)
2. The technical stack (cards + gtsummary) is already production-ready
3. The standards body (CDISC) has formally endorsed ARS as the direction
4. The FDA has both endorsed the underlying ARS work and published the safety templates that cardinal implements

## 7. What about the existing tools? Do I throw them out?

No. Critically: **the legacy stack (`rtables`, `tern`, `Tplyr`, `tfrmt`) is not going anywhere in the near or medium term.**

Roche's investment in `rtables` and `tern` is enormous. The Roche-internal TLG catalog has 220+ standardized tables built on rtables. That codebase will continue to grow. `tern` will continue to be the canonical implementation of certain statistical algorithms for clinical reporting.

What's happening is a *gradual rebalancing*:

- New projects, especially at companies without legacy rtables infrastructure, are increasingly starting with `{cards}` + `{gtsummary}`
- Existing rtables/tern users are integrating with ARDs by having tern output ARDs alongside their tables
- `{tfrmt}` straddles both worlds — it's ARD-friendly but also widely used independently

A reasonable forecast for the next 3–5 years:

- **Companies starting fresh in R**: will mostly choose the cards/gtsummary/cardinal path
- **Companies with existing rtables/tern infrastructure**: will continue using it, but new functionality will increasingly be ARD-aware
- **Cross-industry standardization**: will be ARD-mediated, regardless of which formatting layer renders the final RTF

For this curriculum, we cover **both stacks comprehensively**, with extra weight on the Cardinal-future path because that's where the strategic momentum is.

## 8. A concrete example: demographics table, both ways

To make the difference tangible, let's see the same demographics table built both ways at a high level. (We'll get into the actual code in later lessons.)

### The traditional way (rtables + tern)

```r
library(rtables)
library(tern)

adsl <- pharmaverseadam::adsl

# The analysis and the display are intertwined
result <- basic_table() |>
  split_cols_by("TRT01A") |>
  analyze_vars("AGE", var_labels = c(AGE = "Age (years)")) |>
  analyze_vars("SEX", var_labels = c(SEX = "Sex")) |>
  build_table(adsl)

result  # An rtables object — already formatted with structure
```

You get a formatted table object back. To produce a different display, you re-run with different layout code.

### The ARD-first way (cards + gtsummary)

```r
library(cards)
library(gtsummary)
library(dplyr)

adsl <- pharmaverseadam::adsl

# Step 1: Build the ARD (analysis only)
ard <- adsl |>
  ard_stack(
    .by = TRT01A,
    ard_continuous(variables = AGE),
    ard_categorical(variables = SEX),
    .overall = TRUE
  )

# Step 2: Use the ARD to produce a table (display)
tbl <- tbl_ard_summary(
  cards = ard,
  by = TRT01A
)
```

The ARD (`ard` object) is reusable. You can produce a different table from the same ARD, or feed it to `{tfrmt}` for fully metadata-driven formatting, or push it into a `{teal}` app where users interact with it. You can also archive the ARD with your submission — regulators have the structured numbers, not just the formatted output.

Same numbers, fundamentally different architecture.

## 9. The state of ARS adoption today

It's important to be honest about where the ARS standard is in its maturity:

**What's solid:**
- CDISC has published ARS draft specifications and is iterating actively
- The core ARD data structure is well-defined and implemented in `{cards}`
- Major sponsors are piloting it for production use (Roche, GSK have presented case studies)
- The FDA has endorsed ARS-aligned approaches

**What's still evolving:**
- Define-XML extensions to describe ARDs are not yet final
- Submission expectations are not yet formalized (do you submit the ARD alongside the TLGs? In what format?)
- Some statistical methods (complex models, missing-data handling) don't yet have agreed ARS conventions
- Tooling for round-tripping (ARD → display → back to ARD) is incomplete

The recommendation for clinical programmers entering the field now: **learn the ARD-first paradigm as your foundation**, while remaining fluent in the legacy stack because (a) you'll see it in production for years and (b) some endpoints still don't have mature ARD implementations.

## 10. Mental model — what to take away

If you internalize one mental shift from this curriculum, make it this:

> **A "table" is two things: the calculation and the layout. The calculation should live in a dataset (the ARD). The layout should be applied as a separate, swappable step. Anything that conflates the two is technical debt.**

This is the principle that drove the tidyverse design. It's the principle behind CDISC's separation of SDTM from ADaM. It's the principle ARS extends into the final mile of TLG generation. Once you see it this way, you can't unsee it.

## 11. How the rest of this curriculum reflects the ARD-first shift

In our module structure:

- **Module 6 (TLG: Cardinal future stack)** is the largest TLG module, covering the full ARD-first toolchain in depth.
- **Module 7 (TLG: legacy stack)** is covered fairly and competently because you'll encounter rtables, tern, and r2rtf in real production for years to come.
- **Module 8 (Shiny / teal)** explicitly shows how ARDs feed into interactive applications.
- **The capstone** uses an ARD-first approach end-to-end to demonstrate the integration story.

## 12. Key takeaways

- The traditional TLG workflow tangles analysis and display together, making re-use, QA, and standardization hard.
- CDISC's ARS standard defines a way to separate the two: calculate everything into a structured **ARD**, then apply display logic as a separate step.
- The pharmaverse ARD-first stack is `{cards}` (build ARDs) → `{gtsummary}`/`{tfrmt}` (format displays), with `{cardinal}` providing a cross-industry catalog of harmonized templates.
- `{cardinal}` represents the strongest current bet on cross-industry TLG harmonization — driven by multi-company collaboration, anchored on FDA standards, technically mature.
- The legacy stack (`rtables`, `tern`) is not going away; both stacks will coexist for years.
- The ARS standard is mature in core concepts but still evolving in submission and define.xml integration.

## 13. What's next

In Lesson 02, we set up the development environment: install R, RStudio (or use Posit Cloud), install pharmaverse packages, and configure `renv` for project reproducibility. Once your environment is working, you'll be ready to start writing R code in Module 1.

If you're a SAS programmer, Module 1 will be where it really starts to click — we translate the SAS concepts you already know into their R equivalents.

---

## Self-check questions

1. What is the fundamental problem the ARS standard is trying to solve?
2. Define ARS, ARM, and ARD in your own words.
3. Which package builds ARDs from data? Which formats ARDs into tables?
4. Why does the Cardinal initiative matter beyond just being "another R package"?
5. Why is the legacy stack (rtables, tern) not being deprecated even though the ARD-first stack is the strategic direction?

## Glossary

- **ARS** — Analysis Results Standard; the CDISC standard for analysis result representation
- **ARD** — Analysis Results Dataset; a structured dataset of statistics conforming to ARS
- **ARM** — Analysis Results Metadata; the older ARS-precursor focused on analysis specifications; now folded into ARS
- **Cardinal** — Pharmaverse initiative for harmonized TLG templates (originally `{falcon}`)
- **FDA STF** — FDA Standard Safety Tables and Figures Integrated Guide; the FDA's published standard safety TLG templates
- **Tidy data** — One row per observation, one column per variable; the underlying ARD structure
