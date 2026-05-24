# Lesson 07 — `{pharmaverseraw}`: Test EDC Data for Pharmaverse Examples

**Module**: 2 — Raw data and SDTM
**Estimated length**: ~15 min spoken
**Prerequisites**: Module 1 (R foundations)

---

## Learning objectives

By the end of this lesson, you will be able to:

1. Explain where `pharmaverseraw` sits in the pharmaverse data continuum (raw → SDTM → ADaM)
2. List the SDTM domains that have raw equivalents in the package
3. Load and inspect a raw dataset from the package
4. Understand the design philosophy: **EDC-agnostic** and **standards-agnostic**
5. Locate the annotated CRFs (aCRFs) bundled with the package
6. Recognize what raw data does and doesn't have, and why that matters for SDTM building

---

## 1. Where this package fits

Pharmaverse maintains three test-data packages, designed to flow into each other:

```
{pharmaverseraw}      → simulated raw EDC data
   │
   │  via {sdtm.oak}
   ▼
{pharmaversesdtm}     → SDTM datasets
   │
   │  via {admiral}
   ▼
{pharmaverseadam}     → ADaM datasets
```

`pharmaverseraw` is the youngest of the three. It was released to CRAN in mid-2025 specifically because, without it, the end-to-end pipeline story had a missing first step. Before `pharmaverseraw`, you could demonstrate SDTM → ADaM using `pharmaversesdtm` → `pharmaverseadam`, but the raw → SDTM step had no canonical test data. This release fills a long-standing gap in the SDTM and ADaM workflow examples.

The package itself does almost no computation. It's a **data package** — it bundles raw datasets, documentation, and annotated CRFs. Its purpose is to feed `{sdtm.oak}` examples and tutorials, and to give you something concrete to practice on before you point a real EDC extract at sdtm.oak.

## 2. Installation

```r
install.packages("pharmaverseraw")
```

That's it. The package has minimal dependencies — just enough to make the data accessible.

## 3. The design philosophy: agnostic by construction

Two things are baked into how `pharmaverseraw` was built:

**EDC-agnostic.** The raw dataset does not align with any EDC (Electronic Data Capture) systems, meaning that are EDC agnostic. Real raw data comes from Veeva, Medidata Rave, Castor, OpenClinica, REDCap, and a dozen others — each with its own column naming, dataset structure, and quirks. `pharmaverseraw` deliberately picks naming conventions that don't favor any specific EDC. The point: when you learn `sdtm.oak` against `pharmaverseraw`, you're learning *generic* SDTM mapping logic, not how to use one specific EDC.

**Standards-agnostic.** Some variables follow CDASH (Clinical Data Acquisition Standards Harmonization), while others do not. This reflects real-world data standards variability across companies. Real-world raw data is messy — your sponsor might have CDASH-conformant CRFs for some pages and bespoke variants for others. `pharmaverseraw` mirrors that reality intentionally.

So the test data is *deliberately* a bit inconsistent — it's not a clean reference, it's a realistic playground. This matters for learning, because the patterns you'll encounter are the patterns you'll see in real studies.

## 4. What's in the package — domains covered

The initial CRAN release v0.1.0 includes raw data for the following SDTM domains:

| Raw dataset | Maps to SDTM | Description |
|---|---|---|
| `dm_raw` | DM | Demographics — one row per subject |
| `ae_raw` | AE | Adverse Events |
| `ec_raw`, `ex_raw` | EC, EX | Exposure (planned and actual) |
| `ds_raw` | DS | Disposition events |

More domains (LB, VS, CM, MH, etc.) are added with subsequent releases. Check `library(help = "pharmaverseraw")` against the version installed for the current list:

```r
library(help = "pharmaverseraw")
# Or:
data(package = "pharmaverseraw")
```

The naming convention is consistent: each raw dataset is named for the SDTM domain it maps to, with `_raw` appended. So `ds_raw` corresponds to the DS domain, `ae_raw` to AE, etc.

## 5. Loading and inspecting a raw dataset

```r
library(pharmaverseraw)
library(dplyr)

# Load AE raw data
data("ae_raw")

# Inspect
glimpse(ae_raw)
```

You'll see something like (column names vary by version):

```
Rows: 1,191
Columns: ~20
$ STUDYID         <chr> "TEST_STUDY", "TEST_STUDY", ...
$ PATNUM          <int> 1015, 1015, 1023, ...
$ AETERM          <chr> "HEADACHE", "NAUSEA", ...
$ AESTDT          <chr> "2020-07-15", ...
$ AEENDT          <chr> "2020-07-17", ...
$ AESEV           <chr> "MILD", "MODERATE", ...
$ AESER           <chr> "N", "N", "Y", ...
$ AEOUT           <chr> "RECOVERED/RESOLVED", ...
...
```

Notice:

- **Subject identifier is `PATNUM`, not `USUBJID`**. The raw data uses an EDC-internal patient number; SDTM requires `USUBJID` (study + site + subject ID). One job of the SDTM-building step is to compute USUBJID from STUDYID + PATNUM (or similar).
- **Date columns are character strings**. The raw format may be `"2020-07-15"` or `"15JUL2020"` or other variations — parsing and converting to ISO 8601 is part of the SDTM mapping work.
- **There are no SDTM-specific qualifier variables** like AEDECOD, AEBODSYS, AESOC (those come from medical coding) or AESEQ (sequence number, derived). The raw data has only what's collected on the CRF.

This is what real raw data looks like — minimal, EDC-flavored, in need of structure.

## 6. The annotated CRFs (aCRFs)

A subtle but valuable feature: The package also includes annotated case report forms (aCRFs) to demonstrate mapping logic.

aCRFs are PDF files showing each CRF page with annotations indicating which SDTM domain and variable each collected field maps to. They're a regulatory requirement for submissions (FDA expects them as part of eCTD Module 5).

Find them on your system:

```r
acrf_dir <- system.file("acrf", package = "pharmaverseraw")
list.files(acrf_dir)
```

This gives you the paths to the PDFs. Open them with your normal PDF viewer. You'll see CRF pages with annotations like:

```
[Field: "Date of Birth"]   → DM.BRTHDTC
[Field: "Sex"]             → DM.SEX
[Field: "Race"]            → DM.RACE
```

For learning, these are gold. When you write an `sdtm.oak` mapping in Lesson 08, glance at the matching aCRF to remind yourself which raw fields feed which SDTM variables.

## 7. The companion: `{pharmaversesdtm}`

The corresponding SDTM datasets — the *output* of mapping the raw data — live in `{pharmaversesdtm}`. Same loading pattern:

```r
install.packages("pharmaversesdtm")

library(pharmaversesdtm)
data("ae")    # the SDTM AE domain
glimpse(ae)
```

In this version you'll see canonical SDTM:

```
$ STUDYID    <chr> "CDISCPILOT01", ...
$ USUBJID    <chr> "01-701-1023", ...
$ AESEQ      <dbl> 1, 2, 3, ...
$ AETERM     <chr> "HEADACHE", ...
$ AEDECOD    <chr> "Headache", ...
$ AEBODSYS   <chr> "Nervous system disorders", ...
$ AESTDTC    <chr> "2020-07-15", ...
$ AESEV      <chr> "MILD", ...
...
```

This is the *target* shape for SDTM. When you run `sdtm.oak` against `pharmaverseraw`, the goal is to produce something matching the structure (though not necessarily identical content) of the corresponding `pharmaversesdtm` dataset.

A useful exercise: load both side by side and identify which variables had to be derived versus directly mapped from the raw data. It builds your mental model for what SDTM mapping actually does.

## 8. A quick comparison: raw vs SDTM for AE

Let's put them side by side to make the conceptual leap explicit.

| SDTM Variable | Source | Derivation Logic |
|---|---|---|
| `STUDYID` | hardcoded | Same value for all rows |
| `DOMAIN` | hardcoded | `"AE"` |
| `USUBJID` | derived | `paste(STUDYID, SITEID, PATNUM, sep = "-")` or similar |
| `AESEQ` | derived | Sequence number within USUBJID |
| `AETERM` | direct map | From `ae_raw$AETERM` |
| `AEDECOD` | medical coding | Comes from MedDRA coding (external process) |
| `AEBODSYS` | medical coding | Same |
| `AESTDTC` | parsed | Convert `ae_raw$AESTDT` to ISO 8601 |
| `AESEV` | direct map | From `ae_raw$AESEV` (with controlled terminology check) |
| `AESER` | direct map | From `ae_raw$AESER` |

The patterns here — hardcode, direct map, derive, parse — are what `sdtm.oak` provides functions for. We'll see each in Lesson 08.

## 9. When you'd use this package

For a typical clinical R user:

- **In tutorials and training**: it's the canonical input for any `sdtm.oak` example
- **When learning SDTM mapping**: practice deriving SDTM domains against the raw data, then compare to `pharmaversesdtm` to check your work
- **When prototyping**: if you're testing a new SDTM derivation idea, use `pharmaverseraw` to validate the approach before pointing it at sensitive study data
- **For demos and presentations**: shareable, non-proprietary example data

You would **not** use this package:

- For real study work (use your actual EDC extracts)
- For validation (you must validate against real-world cases representative of your study)
- For benchmarking performance (volume is small by design)

## 10. Versioning and extending the package

`pharmaverseraw` is on CRAN and updated periodically. If you want to follow recent additions or contribute:

```r
# Install the dev version from GitHub for the latest domains
if (!requireNamespace("remotes", quietly = TRUE)) {
  install.packages("remotes")
}
remotes::install_github("pharmaverse/pharmaverseraw", ref = "main")
```

Contributions are welcome. Programs that generate raw data are stored in the data-raw/ folder. Each of these programs is written as a standalone R script, which makes it relatively approachable to add new domains. If you want to extend it for a domain that's missing (e.g., LB or VS), the pharmaverse community welcomes pull requests.

## 11. A note on the related `{phuse}` test data

You may encounter older pharmaverse examples that use the **CDISC Pilot** dataset (sometimes called the "PHUSE pilot data"). This is a different, older test dataset that's been in clinical-programming community use for a decade. It's still floating around — for example, the SDTM in `{pharmaversesdtm}` was originally seeded from this pilot data.

For new projects, prefer `pharmaverseraw` + `pharmaversesdtm` + `pharmaverseadam` as the canonical example chain. They were designed to work together and are actively maintained.

## 12. Key takeaways

- `{pharmaverseraw}` is the starting point of the pharmaverse test data chain — raw EDC-shaped data that feeds `sdtm.oak`
- It is intentionally **EDC-agnostic and standards-agnostic** to teach generic mapping patterns
- Datasets are named `<domain>_raw` — `ae_raw`, `dm_raw`, etc.
- Annotated CRFs ship with the package under `inst/acrf/` — open them to see CRF→SDTM mapping intent
- The companion package `{pharmaversesdtm}` contains the SDTM-shaped *outputs*; comparing the two teaches you what SDTM mapping does
- Raw datasets typically include character dates that need ISO 8601 parsing, missing USUBJID (must be derived from PATNUM), and no controlled-terminology coding (that's MedDRA's job)

## 13. What's next

Lesson 08 starts the core SDTM-building work with **`{sdtm.oak}`** Part 1: foundational concepts. We'll cover the OAK algorithm framework, the `oak_id_vars` concept, conditioned data frames, and how the modular function design works. After Part 1 (concepts), Part 2 walks through actual domain creation, and Part 3 covers SUPP-- and RELREC.

If you have time, before Lesson 08: install `pharmaverseraw`, load `ae_raw` and `pharmaversesdtm::ae`, and try to verbally describe how you'd convert the former to the latter. The exercise will make Lesson 08 land far better.

---

## Self-check questions

1. Why is `pharmaverseraw` deliberately not aligned with any specific EDC system?
2. What does `_raw` mean in the dataset naming convention?
3. Where do you find the annotated CRFs that ship with the package?
4. What kinds of variables would you expect to be present in raw data but absent in SDTM (and vice versa)?
5. Why does AEDECOD typically not come from raw data?

## Glossary

- **EDC** — Electronic Data Capture system; the software clinical sites enter data into (Rave, Veeva, Castor, etc.)
- **CDASH** — Clinical Data Acquisition Standards Harmonization; CDISC standard for CRF design and raw variable naming
- **aCRF** — annotated Case Report Form; PDF of CRF pages with SDTM mappings indicated
- **Raw dataset** — Pre-SDTM data structured the way the EDC produces it
- **MedDRA** — Medical Dictionary for Regulatory Activities; the standard terminology for medical coding (used for AEDECOD, AEBODSYS, etc.)
- **PHUSE CDISC Pilot data** — Older shared test dataset historically used in pharmaverse examples; superseded for new examples by the pharmaverseraw/sdtm/adam chain
