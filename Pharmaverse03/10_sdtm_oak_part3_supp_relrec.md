# Lesson 10 — `{sdtm.oak}` Part 3: SUPP-- Domains and RELREC

**Module**: 2 — Raw data and SDTM
**Estimated length**: ~20 min spoken
**Prerequisites**: Lessons 08–09

---

## Learning objectives

By the end of this lesson, you will be able to:

1. Explain what Supplemental Qualifier (SUPP--) datasets are and when you need one
2. Identify which raw variables should go to a parent domain versus a SUPP-- dataset
3. Use `generate_sdtm_supp()` to build a SUPP-- dataset from raw variables
4. Understand the RELREC dataset structure: linking records across domains
5. Recognize the current capabilities and limits of `sdtm.oak` in this area
6. Make principled decisions about non-standard variable handling

---

## 1. The "extra variables" problem

SDTM's strength is standardization — every adverse event has AETERM, AESEV, AESER, AESTDTC, and so on. Every CDISC reviewer knows the meaning of those variables.

But real studies collect more than the SDTM standard variables allow. You might capture:

- An AE that was tracked in a sponsor-specific severity scale (0–5 ordinal grade) — not in the AESEV codelist
- Whether an AE was discussed at a safety review meeting
- The investigator's verbatim narrative
- An internal site flag for AE follow-up status
- A specific surgical procedure detail for an MH (Medical History) record

These variables matter for analysis. They don't fit in the SDTM parent domain because they're not in the SDTMIG variable list. SDTM's solution: a **Supplemental Qualifier dataset**, named `SUPP<domain>` — `SUPPAE`, `SUPPDM`, `SUPPLB`, etc.

## 2. The SUPP-- shape

A SUPP-- dataset is **long** — one row per (subject × parent record × non-standard variable). The shape is fixed by SDTMIG:

```
STUDYID    USUBJID         RDOMAIN  IDVAR   IDVARVAL   QNAM         QLABEL                       QVAL    QORIG  QEVAL
PILOT01    01-701-1015     AE       AESEQ   1          AESPID       Sponsor-specific AE ID       AE001   CRF    INVESTIGATOR
PILOT01    01-701-1015     AE       AESEQ   1          AESCAT       AE Subcategory                G1      CRF    INVESTIGATOR
PILOT01    01-701-1015     AE       AESEQ   2          AESPID       Sponsor-specific AE ID       AE002   CRF    INVESTIGATOR
```

Reading this:

- **RDOMAIN**: which parent domain the supplemental qualifies (AE here)
- **IDVAR + IDVARVAL**: which row in the parent domain (AESEQ = 1, etc.) the qualifier refers to. If the qualifier is at the subject level rather than the record level, IDVAR and IDVARVAL are blank.
- **QNAM**: the qualifier's name (like a column name)
- **QLABEL**: a human-readable label for QNAM
- **QVAL**: the value (always character — there's no QVALN)
- **QORIG**: origin of the value (CRF, DERIVED, ASSIGNED, etc.)
- **QEVAL**: evaluator (INVESTIGATOR, SPONSOR, etc.)

So instead of widening the AE dataset with non-standard columns, you flatten the non-standard data into long-format rows here.

## 3. Subject-level vs record-level SUPP--

There are two ways a SUPP-- row can attach to its parent:

**Record-level**: the qualifier applies to a specific row of the parent (e.g., a comment on AE #2). IDVAR and IDVARVAL identify which row.

**Subject-level**: the qualifier applies to the subject as a whole, not a specific record (e.g., a sponsor's internal subject flag). IDVAR and IDVARVAL are blank.

Subject-level SUPPDM rows are common — you'll often find study-specific subject attributes that don't fit anywhere in DM (e.g., "stratification group" if it isn't already in DM as a standard variable).

## 4. When should something go to SUPP-- vs. the parent domain?

This is a judgment call. CDISC's guidance: if a variable is in the SDTMIG for that domain, it goes in the parent. If it's not, it goes in SUPP--. Don't invent your own parent-domain variables.

Common SUPP-- contents:

- Sponsor-specific severity grades or scales not in CDISC CT
- Investigator comments / narratives
- Sponsor-defined classifications (subcategory codes, internal flags)
- Custom date fields that don't have an SDTM equivalent
- Reason-for-action specifics not covered by the standard codelists

If you're not sure, search the SDTMIG (the published implementation guide PDF) for the domain. If the variable name and meaning aren't there, it's a SUPP-- candidate.

## 5. `sdtm.oak`'s SUPP-- support

The package provides `generate_sdtm_supp()` (added in v0.2.0) to build a SUPP-- dataset from a list of qualifier variables.

The conceptual flow:

1. Build your parent domain as usual (e.g., the AE dataset from Lesson 09)
2. Identify the raw variables that should go to SUPP--
3. Map each as a row in SUPP--, with appropriate QNAM, QLABEL, IDVAR, IDVARVAL, QORIG, QEVAL

The exact API for `generate_sdtm_supp()` is evolving — check the current pkgdown site for the latest signature. In broad strokes:

```r
suppae <- generate_sdtm_supp(
  parent_dataset = ae,
  raw_dat = ae_raw,
  id_var = "AESEQ",                # identifier in the parent
  qnam_definitions = list(
    list(
      qnam = "AESPID",
      qlabel = "Sponsor-specific AE ID",
      raw_var = "SPONSOR_AE_ID",
      qorig = "CRF",
      qeval = "INVESTIGATOR"
    ),
    list(
      qnam = "AESCAT2",
      qlabel = "Investigator AE Category",
      raw_var = "INV_AE_CAT",
      qorig = "CRF",
      qeval = "INVESTIGATOR"
    )
  )
)
```

(API illustrative — refer to the package's vignette `vignette("supp_domain", package = "sdtm.oak")` for the version you're using.)

The function:

- Joins the raw values back to the parent dataset by `oak_id_vars`
- Constructs the SUPP-- row structure with proper IDVAR/IDVARVAL
- Stacks rows for multiple qualifiers
- Sets STUDYID, RDOMAIN, and the QNAM/QLABEL/QVAL/QORIG/QEVAL columns per spec

## 6. Manual SUPP-- construction (the dplyr way)

Sometimes you'll find it easier to build SUPP-- manually with dplyr, especially when the logic is custom. Here's how:

```r
suppae <- ae |>
  select(USUBJID, AESEQ, patient_number) |>
  inner_join(
    ae_raw |>
      generate_oak_id_vars(pat_var = "PATNUM", raw_src = "ae_raw") |>
      select(patient_number, oak_id, SPONSOR_AE_ID, INV_AE_CAT),
    by = c("patient_number")
  ) |>
  pivot_longer(
    cols = c(SPONSOR_AE_ID, INV_AE_CAT),
    names_to = "QNAM",
    values_to = "QVAL"
  ) |>
  filter(!is.na(QVAL) & QVAL != "") |>
  mutate(
    STUDYID = "TEST_STUDY",
    RDOMAIN = "AE",
    IDVAR = "AESEQ",
    IDVARVAL = as.character(AESEQ),
    QLABEL = case_when(
      QNAM == "SPONSOR_AE_ID" ~ "Sponsor-specific AE ID",
      QNAM == "INV_AE_CAT"    ~ "Investigator AE Category"
    ),
    QORIG = "CRF",
    QEVAL = "INVESTIGATOR"
  ) |>
  select(STUDYID, RDOMAIN, USUBJID, IDVAR, IDVARVAL,
         QNAM, QLABEL, QVAL, QORIG, QEVAL)
```

This is what `generate_sdtm_supp()` automates, but writing it explicitly once is a useful exercise to understand the structure.

## 7. The "SDTM 2.0 / Dataset-JSON" future

Looking forward: SDTM 2.0 and the Dataset-JSON format (covered in Module 9) are moving away from the SUPP-- pattern. The eventual replacement is **non-standard variables embedded directly in the parent domain**, possibly with metadata flags marking them as non-standard.

For now, however, SUPP-- is the production reality — every submission still uses it. `sdtm.oak` supports it; future regulatory shifts may reduce its importance.

## 8. RELREC — relating records across domains

RELREC (Related Records) is a SDTM dataset that **links rows across domains**. Common cases:

- An AE linked to the EX dose that may have caused it
- A concomitant medication linked to the AE it was administered to treat
- A lab result linked to the procedure it was performed during

The RELREC structure:

```
STUDYID    USUBJID         RDOMAIN  IDVAR   IDVARVAL   RELID    RELTYPE
PILOT01    01-701-1015     AE       AESEQ   1          REL01    ONE
PILOT01    01-701-1015     EX       EXSEQ   1          REL01    ONE
```

Two rows form a relationship: both share the same `RELID`. The two rows above say "AE row #1 for subject 01-701-1015 is related to EX row #1 for the same subject." `RELTYPE` indicates the cardinality (ONE-ONE, ONE-MANY, MANY-MANY).

## 9. `sdtm.oak`'s RELREC status

As of the v0.1.0 release: RELREC is NOT in scope. RELREC support is planned for subsequent releases.

So today, you build RELREC manually with dplyr. The pattern:

```r
# Suppose AE rows have an AESPID linking to an EX row's EXSPID
ae_to_ex_links <- ae |>
  inner_join(ex |> select(USUBJID, EXSEQ, EXSPID),
             by = c("USUBJID", "AESPID" = "EXSPID")) |>
  mutate(RELID = paste0("REL", row_number()))

# Build the AE side of the relationship
relrec_ae <- ae_to_ex_links |>
  transmute(
    STUDYID = "TEST_STUDY",
    USUBJID,
    RDOMAIN = "AE",
    IDVAR = "AESEQ",
    IDVARVAL = as.character(AESEQ),
    RELID,
    RELTYPE = "ONE"
  )

# Build the EX side
relrec_ex <- ae_to_ex_links |>
  transmute(
    STUDYID = "TEST_STUDY",
    USUBJID,
    RDOMAIN = "EX",
    IDVAR = "EXSEQ",
    IDVARVAL = as.character(EXSEQ),
    RELID,
    RELTYPE = "ONE"
  )

# Stack — the two halves form the dataset
relrec <- bind_rows(relrec_ae, relrec_ex)
```

Until OAK provides a dedicated helper, this dplyr pattern is the practical approach. The key idea: every relationship is **two rows** sharing a `RELID`, one per related domain.

## 10. When RELREC is required vs. optional

RELREC is required when your study's analysis needs cross-domain links. Examples:

- Causality analysis: AE-to-EX links
- Concomitant-treatment-for-AE: CM-to-AE links
- Procedure-during-visit: PR-to-SV links (if you submit PR)

It's optional (or absent) when no cross-domain analytical question requires it. Many phase-I PK studies, for example, never need RELREC.

Check your study's SAP. If the analyses describe AE→drug relationships, AE→co-medication relationships, or similar, you'll need RELREC.

## 11. The CO domain — a SUPP-- cousin

While we're on edge cases: the **CO** (Comments) domain stores free-text comments that aren't tied to a single domain. It looks superficially like SUPP-- but is a parent domain in its own right.

```
STUDYID   USUBJID    COSEQ   IDVAR    IDVARVAL   RDOMAIN   COREF                COMVAL
PILOT01   01-701     1       AESEQ    2          AE        Investigator note    "Patient declined to continue..."
PILOT01   01-701     2                                                          "General study comment"
```

The IDVAR/IDVARVAL/RDOMAIN columns link a comment to a specific record in a domain (similar to SUPP--), or are blank for general subject-level comments. `sdtm.oak` doesn't currently provide a CO-specific helper; you build it with the algorithm functions just like any Events-style domain, then add the cross-domain reference columns manually.

## 12. Trial design domains: TA, TE, TI, TS, TV, TX

Briefly noted: SDTM's trial design domains (TA = Trial Arms, TE = Trial Elements, TI = Trial Inclusion/Exclusion, TS = Trial Summary, TV = Trial Visits, TX = Trial Summary Parameter Values) describe the study itself rather than subject-level data. They typically have very few rows and are often hand-coded or built from study metadata, not from raw EDC.

As of v0.1.0: Trial design domains are NOT in scope for `sdtm.oak`. You build them with hand-coded dplyr or read them from a study spec spreadsheet. They're often the same across studies for a given sponsor (one TI dataset per protocol amendment, etc.), so the SAS legacy of "trial design macros" maps cleanly to "study-specific dataset construction scripts" in R.

## 13. Subject visits (SV) and subject elements (SE)

Another gap: `sdtm.oak` doesn't yet have specific support for SV (Subject Visits — actual visits each subject attended) or SE (Subject Elements — which trial elements each subject experienced). These tie together TV/TA with subject-level data.

You build SV from visit-level raw data (typically from DM-related forms or visit-tracking pages). The pattern is Events-like: one row per (USUBJID × VISIT × VISITNUM × actual visit date).

## 14. A pragmatic recommendation

Given the current state of `sdtm.oak` for non-standard structures:

- **Use OAK for**: AE, DS, CM, EX, LB, VS, EG, MH, FA, QS, PE, PR (the Findings, Events, Interventions classes it supports)
- **Build manually (dplyr) for**: SUPP--, RELREC, CO, trial design domains, SV, SE
- **Watch the changelog**: with each `sdtm.oak` release, more of these gaps fill in. The current release notes are at <https://github.com/pharmaverse/sdtm.oak/releases>

This mixed approach is what most pharma teams using `sdtm.oak` actually do in production.

## 15. Validating SUPP-- and RELREC

Both these dataset types have stricter structural requirements than typical domains:

- SUPP-- column order is fixed by SDTMIG (STUDYID, RDOMAIN, USUBJID, IDVAR, IDVARVAL, QNAM, QLABEL, QVAL, QORIG, QEVAL)
- QNAM follows a naming convention: 8 chars max, uppercase
- IDVAR must match an actual variable in the parent domain
- IDVARVAL must reference an existing row in the parent (no orphan SUPP rows)
- RELREC requires both halves of each relationship — a RELID with only one row is invalid

`{sdtmchecks}` (Lesson 11) catches some of these. Pinnacle 21 catches more — for SUPP-- in particular, run your dataset through P21 before submission.

## 16. Key takeaways

- **SUPP-- datasets** hold non-standard variables for a parent domain, in a fixed long format
- The split: standard variables go in the parent; sponsor-specific extras go to SUPP--
- `sdtm.oak`'s `generate_sdtm_supp()` automates the construction; manual dplyr also works and is sometimes clearer
- **RELREC** links rows across domains using paired rows sharing a RELID
- `sdtm.oak` doesn't yet have direct support for RELREC, CO, trial design, SV, SE — build these manually
- Watch the release notes; coverage is growing each release

## 17. What's next

Lesson 11 — the final lesson of Module 2 — covers **`{sdtmchecks}`**. This is a Roche-originated package with 100+ analysis-focused checks for SDTM datasets. Where Pinnacle 21 catches conformance issues, `sdtmchecks` catches things that would mess up *your downstream analysis* — duplicate AEs, AE-without-EX-record, lab values without units, etc.

After Module 2, we move to Module 3 (metadata-driven programming with `metacore` and `metatools`) and then into the core ADaM work with `admiral`.

---

## Self-check questions

1. When does a variable belong in SUPP-- versus the parent SDTM domain?
2. What two columns make a SUPP-- row "record-level" rather than "subject-level"?
3. What does RELTYPE = "ONE" mean in a RELREC row?
4. Why do RELREC relationships always come in pairs of rows?
5. If `sdtm.oak` doesn't have RELREC support, how do most users build it today?
6. What's the difference between the CO domain and SUPP--?

## Glossary

- **SUPP-- / Supplemental Qualifier dataset** — A long-format dataset holding non-standard variables for a parent domain
- **RDOMAIN** — In SUPP-- and RELREC, the parent domain abbreviation
- **IDVAR / IDVARVAL** — The variable and value identifying which parent row the qualifier or relation applies to
- **QNAM / QLABEL / QVAL** — Qualifier name (column-like), human label, value (always character)
- **QORIG / QEVAL** — Origin of the value (CRF, DERIVED, etc.) and evaluator (INVESTIGATOR, SPONSOR)
- **RELREC** — Related Records dataset; links rows across domains via paired RELID rows
- **RELID** — Identifier shared by the two rows of a single relationship
- **RELTYPE** — Cardinality of the relationship: ONE, MANY, ONE-MANY
- **CO** — Comments domain; holds free-text comments, optionally linked to a domain record
- **Trial design domains** — TA, TE, TI, TS, TV, TX; describe the study design, not subject-level data
