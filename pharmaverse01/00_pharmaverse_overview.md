# Lesson 00 — Pharmaverse: What It Is and Why It Matters

**Module**: 0 — Introduction
**Estimated length**: ~20 min spoken
**Prerequisites**: None

---

## Learning objectives

By the end of this lesson, you will be able to:

1. Explain what pharmaverse is and what it is **not**
2. Describe the historical problem pharmaverse was created to solve
3. Identify the governance structure and how packages enter the curated list
4. Distinguish pharmaverse from related ecosystems (tidyverse, Bioconductor, CRAN)
5. Articulate why open source matters in a regulated clinical-trials context
6. Navigate the pharmaverse website and find the right package for a given task

---

## 1. Setting the scene: where we are in clinical programming

If you've worked in pharma for any length of time, you know the rhythm. Raw data comes off the EDC. It gets mapped to SDTM. SDTM gets transformed into ADaM. ADaM feeds the tables, listings, and figures that go into the Clinical Study Report and ultimately the regulatory submission. For thirty-plus years, this entire pipeline has been built in SAS, and that's not changing overnight.

But something has shifted. Around 2019, the FDA quietly stopped requiring SAS for submissions. Roche, GSK, Novartis, J&J, Novo Nordisk, Merck, and many others started exploring R for production clinical reporting. The R Consortium spun up an "R Validation Hub" to address the regulatory concerns. By 2021, multiple major sponsors were running studies — or significant parts of studies — in R.

And immediately, a problem became visible: **every company was building the same things in parallel, behind closed doors.** Roche had its own internal ADaM library. GSK had another. Merck had a third. Each was solving the same problem — derive `TRTSDT`, build occurrence flags, summarize adverse events — in slightly different ways, all of it proprietary, none of it shared, none of it reviewable by regulators in a way that allowed cross-comparison.

Pharmaverse was created to fix exactly this.

## 2. What pharmaverse actually is

In one sentence: **pharmaverse is a curated network of open-source R packages, plus the community that maintains them, designed to cover the entire clinical reporting pipeline from CRF to eSubmission.**

A few important nuances:

**Pharmaverse is not a single package.** You don't `install.packages("pharmaverse")` and get everything. You install individual packages — `admiral`, `xportr`, `gtsummary`, `teal`, and so on — based on what you need. Pharmaverse the *organization* curates and recommends which packages to use; pharmaverse the *codebase* is many separate codebases.

**Pharmaverse is not a single company's project.** It is a multi-company collaboration. The original founders came from GSK, Roche, Atorus, and Janssen. Today, the Council and Working Groups include Roche, GSK, Atorus, J&J, Novo Nordisk, Merck, Appsilon, Posit, Novartis, and several others.

**Pharmaverse is not a SAS replacement.** It is a complement and an alternative. Many companies run hybrid workflows — SAS for some studies, R for others, or SAS for SDTM and R for analysis. Pharmaverse doesn't take a position on which is "better"; it just makes the R path viable.

**Pharmaverse is governed under PHUSE.** Since 2023, the pharmaverse Working Group operates under the PHUSE (Pharmaceutical Users Software Exchange) umbrella, which provides project management, infrastructure, and a connection to the broader pharma standards community.

## 3. The "tidyverse for pharma" analogy

When introducing pharmaverse to someone unfamiliar with R, the easiest comparison is the **tidyverse**. The tidyverse is a collection of R packages (`dplyr`, `tidyr`, `ggplot2`, `purrr`, etc.) that share a common design philosophy: data should flow through a pipeline of small, composable functions, each doing one job well.

Pharmaverse borrowed this idea explicitly. Its packages share a similar philosophy:

- Functions are **small, composable, and named for what they do** (`derive_vars_dt()`, `ard_continuous()`, `xpt_format()`)
- Pipelines flow through `%>%` or `|>` operators
- Data structures are tidy (one row per observation, one column per variable)
- Documentation is rich, with runnable vignettes for every package

And critically, pharmaverse packages are **built on top of the tidyverse**, not in opposition to it. You'll routinely see `dplyr::filter()` and `dplyr::mutate()` mixed in with admiral and cards functions in the same script. They're designed to coexist.

The difference: tidyverse is general-purpose data science. Pharmaverse is **opinionated for clinical trial reporting** — it knows about SDTM, ADaM, CDISC standards, and regulatory submission. That domain knowledge is what makes it valuable.

## 4. How pharmaverse is different from CRAN, Bioconductor, and other ecosystems

CRAN is R's main package repository. It hosts about 20,000 packages. Anyone meeting the technical criteria can publish there. CRAN is **not curated for clinical use** — package quality, maintenance, and regulatory suitability vary wildly.

Bioconductor is a curated repository focused on bioinformatics and genomics. It has rigorous standards but its scope is computational biology, not clinical trial reporting.

The R Validation Hub (a separate R Consortium working group) focuses on **how to validate any R package for regulated use**. It produces guidance, frameworks, and tools (like `riskmetric`) but doesn't itself curate a package list.

Pharmaverse sits in a unique niche:

- **Scope**: clinical trial reporting (CRF → submission), narrower than CRAN, complementary to Bioconductor
- **Curation**: vetted by a multi-company Council; not every clinical R package gets in
- **Standards alignment**: explicitly designed to work with CDISC SDTM, ADaM, Define-XML, ARS
- **Validation-aware**: packages typically follow good development practices, but pharmaverse itself doesn't validate them — that's still each sponsor's responsibility

A useful mental hierarchy:

```
CRAN (everything)
└── R Validation Hub (validation guidance for any R package)
    └── Pharmaverse (curated clinical-reporting subset)
        ├── pharmaverse "core" packages (admiral, xportr, cards, ...)
        └── pharmaverse-affiliated packages (gtsummary, tern, ...)
```

## 5. The governance: how packages get in (and out)

Pharmaverse has a tiered structure:

**The Council** is the executive body. It sets strategic direction and approves new packages for the curated list. Members are representatives from major contributing companies. As of 2024, Appsilon joined the Council, alongside companies like Atorus, GSK, Roche, J&J, and Novo Nordisk.

**Working Groups** focus on specific pipeline areas — SDTM, ADaM, TLG, eSub, and so on. They coordinate package development, examples, and documentation within their domain.

**Maintainer teams** own individual packages. For example, the `admiral` maintainer team includes developers from Roche, GSK, J&J, Pfizer, and others. They make day-to-day decisions about API changes, releases, and contributions.

**To get a package included in pharmaverse**, the maintainers submit a request that's reviewed by the relevant Working Group and Council. Criteria include:

- Solves a real problem in the clinical reporting pipeline
- Open source license (typically Apache 2.0 or MIT)
- Active maintenance with a clear governance model
- Adequate documentation, including vignettes
- Test coverage and CI/CD
- Doesn't duplicate an existing pharmaverse package without good reason
- Aligned with industry standards (CDISC, FDA, EMA)

Packages can also be **deprecated or removed** if they become unmaintained or superseded. This is an important feature — pharmaverse is a *living* recommendation list, not a museum.

## 6. The pharmaverse website: your starting point

Everything pharmaverse is anchored to **<https://pharmaverse.org>**. The most important pages to bookmark:

| Page | URL | What you'll find |
|---|---|---|
| Home | `/` | Overview, news, announcements |
| End-to-end packages | `/e2eclinical/` | The curated package list, organized by pipeline stage |
| Charter | `/charter/` | Governance, contribution levels, decision-making |
| Examples site | <https://pharmaverse.github.io/examples/> | Runnable Quarto notebooks for ADaM, TLG, end-to-end |
| Blog | <https://pharmaverse.github.io/blog/> | Tutorials, case studies, release notes |
| Slack | invitation on homepage | The community — ~1,000+ members, very active |

A practical tip: when you're new, **start with the Examples site, not the package documentation.** Examples show you how packages combine to solve real problems. Package vignettes show individual features in isolation, which is harder to map to your study workflow.

## 7. The CRAN Task View

In addition to the website, pharmaverse maintains a **CRAN Task View** — a standard R mechanism for grouping packages by domain. You can install all pharmaverse-affiliated packages at once with:

```r
install.packages("ctv")
ctv::install.views("Pharmaverse")
```

This will pull in dozens of packages. For most production work, you don't need everything — you install what your study needs. But the Task View is useful as a discovery tool and for setting up training environments.

## 8. Why open source matters for regulated submissions

This is worth addressing head-on because it's the question every QA group asks.

**The traditional argument against open source in pharma** was: "Open source means uncontrolled. Anyone can change it. How can we trust it for an FDA submission?"

**The modern reality** is the opposite:

- **Source-available means auditable.** A regulator can read the exact algorithm that produced a result. With proprietary tools, the algorithm is a black box.
- **Multi-company maintenance is more robust** than a single internal team. If your internal SAS macro author leaves, you have a knowledge gap. If an admiral function changes, dozens of contributors review the change.
- **Versioning is explicit.** You record `admiral 1.2.1` in your study report; anyone can install exactly that version and reproduce your results.
- **Validation is your responsibility, not the package's.** This was always true with SAS too — you validated your `%macro` libraries. Now you validate your R packages. The risk model is the same; only the tools differ.

The FDA's position has shifted accordingly. The agency has accepted submissions using R for years. Internal FDA reviewers themselves use R extensively. The Standard Safety Tables and Figures Integrated Guide — published by the FDA — is the explicit inspiration for the pharmaverse `cardinal` project.

That said: **using open source for a submission still requires due diligence.** You need a validation strategy, version control, and traceability. Pharmaverse provides the tools (`riskmetric` for risk assessment, `logrx` for execution logs, `diffdf` for dataset comparison), but it doesn't do validation for you.

## 9. Common misconceptions to clear up

**"Pharmaverse will tell me which package to use."** Sometimes yes, often no. Pharmaverse intentionally hosts overlapping packages — for example, `gtsummary`, `tern`, `Tplyr`, and `tidytlg` all produce summary tables. You choose based on your team's preferences, your existing infrastructure, and the strategic direction you're betting on (which is what makes the Cardinal-future direction relevant — more on that next lesson).

**"If a package isn't in pharmaverse, I shouldn't use it."** Not true. Pharmaverse is a curated subset. Many excellent clinical-relevant packages live on CRAN — `mmrm` for mixed models, `survival` for time-to-event, `lme4` for mixed models. Pharmaverse focuses on packages designed for the *pipeline*; the analytical packages they depend on are CRAN-native.

**"Pharmaverse packages are FDA-approved."** No. FDA does not approve packages — they review submissions. Pharmaverse packages are open-source tools that *make it easier* to produce compliant submissions, but the responsibility for validation and submission quality remains with the sponsor.

**"Pharmaverse is a Roche project."** Roche contributes heavily, especially to `admiral`, `rtables`, `tern`, and `teal`. But GSK, Atorus, J&J, Merck, Novo Nordisk, Novartis, and Pfizer are all major contributors. Calling it a "Roche project" understates the cross-industry nature.

**"R is too risky for submissions."** The R Validation Hub white paper directly addresses this. Most major sponsors have submitted studies using R. The risk is real but manageable through standard validation practices.

## 10. The roadmap of this curriculum

Now that you know what pharmaverse is, here's where we're going:

1. **Module 0 (this module)**: Foundational concepts — pharmaverse, the ARS/ARD shift, environment setup
2. **Module 1**: R and tidyverse skills, taught with SAS comparisons
3. **Module 2**: Raw data and SDTM — `pharmaverseraw`, `sdtm.oak`, `sdtmchecks`
4. **Module 3**: Metadata — `metacore`, `metatools`
5. **Module 4**: ADaM core — the full `admiral` workflow
6. **Module 5**: ADaM TA extensions — `admiralonco`, `admiralvaccine`, etc.
7. **Module 6**: TLG with the Cardinal-future stack — `cards`, `cardx`, `gtsummary`, `cardinal`, `tfrmt`
8. **Module 7**: TLG with the legacy stack — `rtables`, `tern`, `r2rtf`, `Tplyr`, `tidytlg`
9. **Module 8**: Shiny for clinical exploration — `teal`
10. **Module 9**: Submission and transport — `xportr`, `datasetjson`
11. **Module 10**: Traceability and validation — `logrx`, `diffdf`, `riskmetric`
12. **Capstone**: End-to-end synthetic oncology study

A useful way to think about the structure: each module mirrors a stage of work a clinical programmer actually does. Once you complete the curriculum, you should be able to deliver a study from CRF to eSubmission entirely in R, using pharmaverse packages, with confidence in your validation approach.

## 11. Key takeaways

- Pharmaverse is a curated network of open-source R packages plus the community that maintains them, covering the entire clinical reporting pipeline.
- It was created to stop pharma companies from duplicating proprietary tooling and to make cross-industry collaboration possible.
- It is governed under PHUSE, by a multi-company Council and Working Groups, with package-specific maintainer teams.
- It is **not** a single package, a single company's project, or a SAS replacement — it's a complementary ecosystem.
- The website (`pharmaverse.org`), Examples site, and Slack community are your primary entry points.
- Open source is not a regulatory liability; it's an auditability advantage when paired with proper validation.

## 12. What's next

In the next lesson, we'll cover **the most important conceptual shift happening in pharmaverse right now**: the move from layout-coupled to layout-independent analysis via the CDISC Analysis Results Standard (ARS) and Analysis Results Datasets (ARDs). This is the foundation for understanding why packages like `cards`, `cardx`, `gtsummary`, and `cardinal` are positioned to dominate the next several years of clinical R programming.

If you're going to invest your time learning one new mental model from this entire curriculum, ARS/ARD is the one. Lesson 01 is next.

---

## Self-check questions

1. What is the difference between pharmaverse the organization and pharmaverse the codebase?
2. Why did pharmaverse choose PHUSE as its umbrella organization?
3. Name three companies that contribute to pharmaverse.
4. If a clinical R package is *not* in pharmaverse, does that mean you shouldn't use it? Why or why not?
5. What's the difference between "pharmaverse-approved" and "FDA-approved"?

## Glossary

- **CDISC** — Clinical Data Interchange Standards Consortium; sets data standards for clinical trials (SDTM, ADaM, ARS, etc.)
- **PHUSE** — Pharmaceutical Users Software Exchange; a non-profit that hosts working groups for clinical software
- **TLG / TFL** — Tables, Listings, and Graphs / Tables, Figures, and Listings; the displays included in a Clinical Study Report
- **eSubmission** — Electronic submission to a regulatory agency (FDA, EMA, PMDA); typically structured per the eCTD (electronic Common Technical Document) standard
- **CSR** — Clinical Study Report; the structured document describing the conduct and results of a clinical trial
