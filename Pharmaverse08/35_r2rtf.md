# Lesson 35 — `{r2rtf}`: Merck's RTF Generation Package

**Module**: 7 — TLG: the legacy/Roche stack
**Estimated length**: ~20 min spoken
**Prerequisites**: Lessons 33-34 (rtables, tern)

---

## Learning objectives

By the end of this lesson, you will be able to:

1. Explain r2rtf's role as a focused RTF-output package — separate from table computation
2. Use the three-step pipeline: `rtf_body()` → `rtf_encode()` → `write_rtf()`
3. Apply `rtf_title()`, `rtf_colheader()`, `rtf_footnote()`, `rtf_source()` for complete table chrome
4. Configure pagination with `rtf_page()` and section grouping with `page_by` arguments
5. Combine r2rtf with rtables/tern, Tplyr, or any tibble for end-to-end production
6. Recognize r2rtf's positioning — light-weight, focused, validation-friendly

---

## 1. What r2rtf is for

The previous lessons (rtables, tern) covered **computation** — how to compute statistics into a table structure. r2rtf solves a different problem: **how to render a table as Rich Text Format (RTF) for regulatory delivery**.

The split:

```
ADaM → [computation: rtables/tern/Tplyr/gtsummary] → tibble or table
                                                          │
                                                          ▼
                                                       [r2rtf]
                                                          │
                                                          ▼
                                                        RTF file
```

r2rtf accepts essentially any data frame and produces a publication-grade RTF. It's deliberately decoupled from computation, which makes it composable: pair r2rtf with whatever table-computation package you prefer.

Origin: Merck developed r2rtf and open-sourced it around 2020. Authors: Siruo Wang, Simiao Ye, Keaven Anderson, Yilong Zhang. Published in PharmaSUG 2020. It's part of pharmaverse and widely adopted across the industry, particularly at Merck-aligned sponsors and CROs.

## 2. Why RTF specifically

For pharma CSR delivery:

- **RTF is the regulatory standard** for many sponsor SOPs and FDA review tools
- **RTF is Word-compatible**: reviewers and authors work in Microsoft Word, which handles RTF natively
- **RTF preserves layout precisely**: unlike HTML, RTF can hit pixel-exact margins, fonts, page breaks
- **Pagination is essential**: a 200-page AE table needs continuation headers per page

Other formats (HTML, PDF, Word .docx) exist, but RTF remains the default delivery format. r2rtf focuses on RTF and does it well.

For Word docx: `flextable::save_as_docx()` is the typical path. For PDF: usually rendered from RTF via Word, or from LaTeX. RTF is the most production-friendly intermediate.

## 3. Installation

```r
install.packages("r2rtf")
library(r2rtf)
library(dplyr)
```

The package has minimal dependencies (largely `stringr`), which makes it appealing for validation in regulated environments — fewer dependencies, fewer surfaces for version mismatches.

## 4. The three-step pipeline

A minimal r2rtf usage:

```r
library(r2rtf)

head(iris) |>
  rtf_body() |>           # Step 1: define table body
  rtf_encode() |>         # Step 2: convert to RTF code
  write_rtf(file = "ex-tbl.rtf")   # Step 3: write to file
```

Three steps. The first two are "verbs" that add attributes/styling. The third writes the actual file.

For real tables, you add more verbs between Step 1 and Step 2:

```r
data_table |>
  rtf_title("Table 14.2.1", "Demographics — Safety Population") |>
  rtf_colheader(
    colheader = "Characteristic | Placebo (N=86) | Xanomeline Low (N=84) | Xanomeline High (N=84)",
    col_rel_width = c(3, 2, 2, 2)
  ) |>
  rtf_body(
    col_rel_width = c(3, 2, 2, 2),
    text_justification = c("l", "c", "c", "c"),
    border_first = "single",
    border_last = "single"
  ) |>
  rtf_footnote("Continuous: Mean (SD); Median (Q1, Q3). Categorical: n (%).") |>
  rtf_source("Source: ADSL") |>
  rtf_encode() |>
  write_rtf(file = "outputs/t_14_2_1.rtf")
```

Each verb is one component of a complete table. The verbs are chainable; the pipe makes the whole table definition read top-to-bottom like the rendered output.

## 5. The column-header DSL

`rtf_colheader()` uses a string DSL where `|` separates columns:

```r
rtf_colheader(
  colheader = "Characteristic | Placebo | Xanomeline Low | Xanomeline High",
  col_rel_width = c(3, 2, 2, 2),
  text_justification = c("l", "c", "c", "c")
)
```

For multi-line / multi-row headers (e.g., a spanner above arm columns):

```r
rtf_colheader(
  colheader = " | Active Treatment",
  col_rel_width = c(3, 6),
  border_top = "single",
  border_bottom = "single",
  text_justification = "c"
) |>
rtf_colheader(
  colheader = "Characteristic | Placebo | Low | High",
  col_rel_width = c(3, 2, 2, 2),
  text_justification = c("l", "c", "c", "c")
)
```

Two `rtf_colheader()` calls stack to produce a two-row header. The first row spans columns 2-4 with "Active Treatment"; the second row labels each individual column.

## 6. Pagination

For long tables, pagination is essential. `rtf_page()` controls the page setup:

```r
data_table |>
  rtf_page(
    orientation = "landscape",
    width = 11,
    height = 8.5,
    margin = c(1.25, 1.0, 1.0, 1.0, 0.5, 0.5),     # left/right/top/bottom/header/footer
    nrow = 35                                       # max rows per page
  ) |>
  rtf_title("Table 14.5.1", "Adverse Events") |>
  rtf_colheader(...) |>
  rtf_body(...) |>
  rtf_footnote(...) |>
  rtf_encode() |>
  write_rtf("outputs/long_ae_table.rtf")
```

`nrow` controls maximum rows per page. r2rtf inserts page breaks automatically, repeating the column headers on each new page.

For group-based pagination (e.g., one page per SOC):

```r
rtf_body(
  data,
  ...,
  page_by = c("AEBODSYS")     # break pages between SOCs
)
```

The `page_by` argument inserts a page break whenever the value of the named column changes. Useful for SOC-level pagination in long AE tables.

## 7. Group headers within a table

For SOC × PT tables, group headers appear within each page:

```r
rtf_body(
  data,
  col_rel_width = c(...),
  border_first = "single",
  border_last = "single",
  group_by = c("AEBODSYS"),       # SOC as group header
  pageby_header = TRUE,
  subline_by = "AEBODSYS"          # underline below each SOC group
)
```

The `group_by` argument makes the SOC variable appear as a header above each group of PT rows. Pairs naturally with rtables/tern output where the SOC is a split.

## 8. Cell-level customization

For specific cells needing distinct formatting:

```r
rtf_body(
  data,
  col_rel_width = c(3, 2, 2, 2),
  text_justification = matrix(c(
    "l", "c", "c", "c",      # row 1
    "l", "c", "c", "c",      # row 2
    ...
  ), ncol = 4, byrow = TRUE),
  text_color = matrix(c(
    "black", "black", "black", "black",
    "black", "red", "black", "black",       # highlight a cell red
    ...
  ), ncol = 4, byrow = TRUE)
)
```

Matrix arguments allow per-cell control. Common uses: highlight cells with safety signals (e.g., abnormal liver enzymes), apply different alignment for specific rows.

## 9. Producing figures (the F in TLF)

Despite the name "rtf", r2rtf also handles **figures** — converting PNG/JPG to RTF for inclusion in submission packages:

```r
# Generate a plot
png(file = "fig.png", width = 600, height = 400)
plot(1:10, main = "Title")
dev.off()

# Convert PNG to RTF
rtf_read_figure("fig.png") |>
  rtf_figure() |>
  rtf_title("Figure 14.3.1", "Overall Survival") |>
  rtf_footnote("Source: ADTTE") |>
  rtf_encode(doc_type = "figure") |>
  write_rtf("outputs/f_14_3_1.rtf")
```

The `rtf_read_figure()` reads a PNG/JPG; `rtf_figure()` adds RTF-specific attributes. The resulting RTF embeds the image with title/footnote chrome — submission-ready.

For pharma submissions, RTF-wrapped figures are common because they can be paginated and chrome'd consistently with tables, all in the same delivery format.

## 10. Putting it together: rtables → r2rtf

A typical flow combines rtables/tern (for computation) with r2rtf (for output):

```r
library(rtables)
library(tern)
library(r2rtf)
library(dplyr)

# Computation with rtables/tern (Lesson 33-34)
adae <- ex_adae
adsl <- ex_adsl |> filter(SAFFL == "Y")

ae_lyt <- basic_table(show_colcounts = TRUE) |>
  split_cols_by("ARM") |>
  add_colcounts() |>
  split_rows_by("AEBODSYS",
                split_fun = drop_split_levels) |>
  count_occurrences(var = "AEDECOD", drop = FALSE)

ae_tbl <- build_table(ae_lyt,
                       adae |> filter(USUBJID %in% adsl$USUBJID),
                       alt_counts_df = adsl)

# Convert rtables output to a flat data frame for r2rtf
ae_df <- as.data.frame(ae_tbl)

# Render with r2rtf
ae_df |>
  rtf_page(orientation = "landscape", nrow = 30) |>
  rtf_title(
    title = "Table 14.5.1",
    subtitle = c("Adverse Events by System Organ Class and Preferred Term",
                 "Safety Population")
  ) |>
  rtf_colheader(
    colheader = "System Organ Class \n  Preferred Term | Placebo \n (N=86) | Xanomeline Low \n (N=84) | Xanomeline High \n (N=84)",
    col_rel_width = c(4, 2, 2, 2),
    border_top = "single",
    border_bottom = "single",
    text_justification = c("l", "c", "c", "c")
  ) |>
  rtf_body(
    col_rel_width = c(4, 2, 2, 2),
    text_justification = c("l", "c", "c", "c"),
    border_first = "single",
    border_last = "single"
  ) |>
  rtf_footnote(
    "n = subjects with at least one event. % uses safety population N."
  ) |>
  rtf_source("Source: ADAE; ADSL") |>
  rtf_encode() |>
  write_rtf(file = "outputs/t_14_5_1.rtf")
```

The rtables side computes the table. The r2rtf side renders it as RTF with proper pagination, headers, footnotes, and source attribution.

For Tplyr → r2rtf or gtsummary → r2rtf, similar flow with different computation packages.

## 11. r2rtf vs flextable

Two RTF-output packages in the pharma ecosystem:

| Aspect | r2rtf | flextable |
|---|---|---|
| Primary focus | RTF specifically (also figures) | Word, RTF, HTML, PowerPoint |
| Dependencies | Minimal (stringr) | Heavier (officer, gdtools) |
| RTF detail control | Very fine-grained (matrix cell control) | Good but less granular |
| Word docx export | Indirect (via Word converting RTF) | Native |
| Pharma adoption | Strong at Merck-aligned, broad CROs | Strong at gtsummary-aligned, GSK |

Both produce regulatory-grade RTFs. The choice often comes down to existing infrastructure: if you're on the rtables/tern path, both work. If you're on the gtsummary path, flextable integrates more cleanly. If you have a Merck-aligned heritage, r2rtf is the default.

Many teams use both — flextable for gtsummary-rendered tables, r2rtf for tables computed by other means or needing fine RTF control.

## 12. The validation story

A key reason r2rtf is popular: minimal dependencies plus extensive testing make it easier to qualify for regulatory use.

- **Stable API**: r2rtf 1.0 released in 2022; the public API has been stable since
- **Unit testing**: comprehensive test suite covering RTF code generation, pagination, formatting
- **Documentation**: vignettes covering customization, page settings, special characters
- **The R for Clinical Study Reports book** ([https://r4csr.org](https://r4csr.org)) uses r2rtf as the default RTF tool

Sponsors moving to R for CSR delivery often choose r2rtf for its validation-friendly profile.

## 13. The pkglite ecosystem

r2rtf is part of a broader Merck open-source ecosystem also including:

- **`{pkglite}`**: compress an R package into text format for eCTD submission
- **`{simtrial}`**: clinical trial simulation
- **`{gMCPLite}`**: graphical multiple comparison procedures
- **`{metalite}`** and **`{metalite.ae}`**: metadata-driven safety analyses

If your sponsor uses Merck's open-source path, r2rtf integrates naturally with the others. Even outside Merck, these tools are pharmaverse-aligned and broadly usable.

## 14. When to choose r2rtf

Use r2rtf when:

- RTF is your delivery format (it almost certainly is for CSR)
- You need fine control over pagination, group headers, special characters
- Minimal-dependency validation is a priority
- You're using rtables/tern or Tplyr for computation (r2rtf composes well with both)
- Your sponsor has adopted Merck's open-source path

flextable is often the better choice when:

- gtsummary is your computation package (closer integration)
- You need Word, HTML, and PDF in addition to RTF
- You're working in a primarily flextable-based environment

## 15. r2rtf and rtflite (Python)

A footnote: Merck has also developed **`rtflite`** — a Python equivalent of r2rtf with similar API. For data science teams running mixed R/Python pipelines, rtflite covers RTF generation from the Python side using the same conceptual vocabulary as r2rtf. The packages are designed to be interoperable.

This matters for pharma teams adopting Python for AI/ML applications: the RTF delivery pipeline can stay consistent regardless of which language computed the data.

## 16. Maintainers and direction

`{r2rtf}` is maintained primarily by Merck (Keaven Anderson, Yilong Zhang, and others). Active development continues with regular minor releases adding features.

Strategic direction:

- Continued integration with the broader pharmaverse (e.g., better gtsummary → r2rtf workflows)
- Improved figure handling (more chart formats, better embedding)
- rtflite parity for Python-based workflows
- Continued validation-friendly profile maintenance

## 17. Key takeaways

- `{r2rtf}` is a focused RTF-output package, decoupled from table computation
- Three-step pipeline: `rtf_body()` → `rtf_encode()` → `write_rtf()`
- Add chrome with `rtf_title()`, `rtf_colheader()`, `rtf_footnote()`, `rtf_source()`
- Pagination via `rtf_page(nrow = ...)` and `page_by` for group-based breaks
- Group headers via `group_by` + `pageby_header` for SOC-style tables
- Figures via `rtf_read_figure()` and `rtf_figure()`
- Composes with rtables/tern/Tplyr/gtsummary — accepts any data frame
- Minimal dependencies → easier to validate; popular in Merck-aligned environments
- Coexists with flextable; choice often follows the rest of the stack

## 18. What's next

Lesson 36 covers **`{Tplyr}`** — Atorus's table-building package designed for SAS programmers transitioning to R. Tplyr's layered-summary API mirrors SAS proc summary patterns, making it a friendly entry point for sponsors with deep SAS heritage.

After Tplyr: tidytlg (Lesson 37) and Module 7 is complete.

---

## Self-check questions

1. Why is r2rtf described as "focused" — what does it deliberately not do?
2. What's the role of `rtf_page(nrow = 30)`?
3. Why is the `|` in `rtf_colheader(colheader = "A | B | C")` special?
4. Translate to r2rtf: pipe a data frame through title, column header (one row), body, footnote, and write to file.
5. Compare r2rtf and flextable — when would you choose each?
6. How does r2rtf integrate with rtables/tern outputs?

## Glossary

- **`rtf_body()`** — Define the table body
- **`rtf_title()`** — Add title (and optional subtitle)
- **`rtf_colheader()`** — Add column header row(s); `|` separates columns
- **`rtf_footnote()`** — Add footnote text below the table
- **`rtf_source()`** — Add data source attribution line
- **`rtf_page()`** — Configure page setup (orientation, size, margins, rows-per-page)
- **`rtf_encode()`** — Convert all attributes to actual RTF code
- **`write_rtf(file)`** — Write to a file on disk
- **`page_by`** — Argument for page breaks between groups
- **`group_by`** — Argument for in-table group headers
- **`col_rel_width`** — Relative column widths (numeric vector)
- **`text_justification`** — Per-column alignment: "l", "c", "r"
- **`rtf_read_figure()` / `rtf_figure()`** — Convert PNG/JPG to RTF-embedded figure
- **`{rtflite}`** — Python equivalent of r2rtf
- **`{pkglite}`** — Companion package for compressing R packages for eCTD
