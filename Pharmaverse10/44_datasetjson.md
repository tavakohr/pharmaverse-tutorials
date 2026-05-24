# Lesson 44 — `{datasetjson}`: CDISC Dataset-JSON, the XPT Successor

**Module**: 9 — Submission and transport
**Estimated length**: ~20 min spoken
**Prerequisites**: Lesson 43 (xportr)

---

## Learning objectives

By the end of this lesson, you will be able to:

1. Explain the limitations of XPT v5 that motivate Dataset-JSON
2. Recognize Dataset-JSON's structure: top-level metadata + columns array + rows array
3. Use `dataset_json()` to construct a Dataset-JSON object from a data frame
4. Use `write_dataset_json()` and `read_dataset_json()` for I/O
5. Apply the CDISC ARS / Define-XML linkage metadata appropriate for submissions
6. Track the FDA's pilot status and prepare for the XPT-to-JSON transition

---

## 1. Why XPT needs replacing

XPT v5 (Lesson 43) is from the late 1980s. It has hard constraints rooted in 1980s assumptions:

- **8-character variable names**: limits CDISC's ability to use modern descriptive names
- **40-character labels**: harder to add metadata in non-English languages or detailed descriptions
- **200-character string max**: text fields (e.g., verbatim AE terms, comments) get truncated
- **Binary format**: requires SAS or specialized tooling to read; not human-inspectable
- **No native type for dates, times, booleans**: everything is character or numeric
- **File size bloat for sparse data**: every numeric field is 8 bytes regardless of value

These were reasonable trade-offs in 1988. They are dated in 2026. Modern data exchange standards (JSON, parquet, arrow) handle these elegantly.

CDISC has tried to replace XPT before:

- **Dataset XML pilot (2015)**: XML-based; failed due to file size bloat (XML's verbosity made files 3-5x larger than XPT)
- **Dataset JSON hackathon (2022)**: experimental; led to Dataset-JSON v1.0
- **Dataset JSON v1.1 (2024)**: stable specification
- **FDA pilots (2024-2026)**: R-Submissions Working Group has submitted Dataset-JSON to FDA successfully

The trajectory: Dataset-JSON will eventually replace XPT v5 for new submissions. Whether that's 2027, 2029, or later depends on FDA timing — but the standard is in place, the tooling exists, and the transition is happening.

## 2. What Dataset-JSON v1.1 is

Dataset-JSON is a **CDISC standard for sharing tabular data using JSON**. From the v1.1 specification:

> Dataset-JSON is a data exchange standard for sharing tabular data using JSON. It is designed to meet a wide range of data exchange scenarios, including regulatory submissions and API-based data exchange. Each Dataset-JSON dataset can optionally reference a Define-XML document containing more detailed metadata.

Key properties:

- **JSON-based**: human-readable, modern, well-supported in every programming language
- **Self-describing**: each file contains schema + data; no separate metadata required (though Define-XML linkage is supported)
- **No 1988-era constraints**: variable names up to 32 chars, no character length limits, native typed columns
- **API-friendly**: easily streamed over HTTPS; integrates with modern data pipelines
- **Smaller than XML**: 30-50% smaller than equivalent Dataset-XML
- **Comparable to XPT in size for typical clinical data**: sometimes slightly larger uncompressed, smaller compressed

For a complete spec, see [https://cdisc-org.github.io/DataExchange-DatasetJson/](https://cdisc-org.github.io/DataExchange-DatasetJson/).

## 3. The `{datasetjson}` R package

`{datasetjson}` is an Atorus-developed R package for reading and writing CDISC Dataset-JSON files. Released to CRAN in 2023; current version 0.x as of mid-2026. Built with input from GSK (Ben Straub, Eric Simms) during the original CDISC hackathon.

Maintained at [github.com/atorus-research/datasetjson](https://github.com/atorus-research/datasetjson).

```r
install.packages("datasetjson")
library(datasetjson)
```

The package is intentionally focused: read JSON, write JSON, validate against the schema. It doesn't try to do everything xportr does for XPT — Dataset-JSON's native type support means less coercion logic is needed.

## 4. Dataset-JSON file structure

A Dataset-JSON file looks like:

```json
{
  "datasetJSONCreationDateTime": "2026-05-22T16:45:36",
  "datasetJSONVersion": "1.1.0",
  "fileOID": "/some/path",
  "dbLastModifiedDateTime": "2026-05-21T13:34:50",
  "originator": "Sponsor Inc.",
  "sourceSystem": {
    "name": "R 4.4.0 with datasetjson 0.4.0",
    "version": "0.4.0"
  },
  "studyOID": "STUDY001",
  "metaDataVersionOID": "MDV.MSGv2.0.SDTMIG.3.3.SDTM.1.7",
  "metaDataRef": "define.xml",
  "itemGroupOID": "IG.ADSL",
  "records": 254,
  "name": "ADSL",
  "label": "Subject-Level Analysis Dataset",
  "columns": [
    {
      "itemOID": "IT.ADSL.STUDYID",
      "name": "STUDYID",
      "label": "Study Identifier",
      "dataType": "string",
      "length": 12
    },
    {
      "itemOID": "IT.ADSL.USUBJID",
      "name": "USUBJID",
      "label": "Unique Subject Identifier",
      "dataType": "string",
      "length": 20,
      "keySequence": 1
    },
    {
      "itemOID": "IT.ADSL.AGE",
      "name": "AGE",
      "label": "Age",
      "dataType": "integer"
    }
  ],
  "rows": [
    ["STUDY001", "STUDY001/CENTER01/SUBJ-001", 67],
    ["STUDY001", "STUDY001/CENTER01/SUBJ-002", 54],
    ...
  ]
}
```

The top-level metadata identifies the dataset, study, and Define-XML linkage. The `columns` array describes each variable. The `rows` array holds the actual data — arrays-of-arrays for efficiency.

Compare to XPT: same information, vastly more readable, no 8-char variable name limit, no 40-char label limit, no 200-char string limit, native typed columns including integer/float/string/boolean/datetime.

## 5. The minimum viable pipeline

Reading and writing Dataset-JSON:

```r
library(datasetjson)
library(dplyr)

# Start with a data frame
my_data <- pharmaverseadam::adsl |>
  select(STUDYID, USUBJID, AGE, SEX, RACE)

# Construct a Dataset-JSON object
ds_json <- dataset_json(
  .df = my_data,
  itemGroupOID = "IG.ADSL",
  name = "ADSL",
  label = "Subject-Level Analysis Dataset"
)

# Write to disk
write_dataset_json(ds_json, "adsl.json")

# Read back
restored <- read_dataset_json("adsl.json")
```

Three lines. `dataset_json()` constructs the object; `write_dataset_json()` serializes; `read_dataset_json()` deserializes.

For ad-hoc use, this is enough. For submission-grade use, you'll want to add more metadata.

## 6. Adding submission metadata

For Dataset-JSON files going to the FDA, you need additional top-level metadata identifying the study, source system, and Define-XML linkage:

```r
ds_json <- dataset_json(
  .df = my_data,
  itemGroupOID = "IG.ADSL",
  name = "ADSL",
  label = "Subject-Level Analysis Dataset"
)

ds_json <- ds_json |>
  set_study_oid("STUDY001") |>
  set_metadata_version_oid("MDV.STUDY001.ADaM-1.0") |>
  set_metadata_ref("define.xml") |>
  set_originator("Sponsor Inc.") |>
  set_source_system(
    name = "R with datasetjson package",
    version = packageVersion("datasetjson")
  ) |>
  set_file_oid("/study001/adam/adsl") |>
  set_db_last_modified("2026-05-22T13:34:50")
```

The `set_*()` family is fluent: each sets one piece of metadata. The metadata fields mirror the JSON structure (Section 4).

For submission, the **`metaDataRef`** field is the key linkage — it points to the Define-XML document that describes the dataset in more detail. Define-XML is a separate CDISC standard for dataset metadata; both XPT and JSON submissions ship with a Define-XML.

## 7. Column metadata via `set_column_metadata()`

For variable-level metadata (labels, types, controlled terminology references), use `set_column_metadata()`:

```r
column_meta <- list(
  list(
    itemOID = "IT.ADSL.STUDYID",
    name = "STUDYID",
    label = "Study Identifier",
    dataType = "string",
    length = 12
  ),
  list(
    itemOID = "IT.ADSL.USUBJID",
    name = "USUBJID",
    label = "Unique Subject Identifier",
    dataType = "string",
    length = 20,
    keySequence = 1
  ),
  list(
    itemOID = "IT.ADSL.AGE",
    name = "AGE",
    label = "Age",
    dataType = "integer"
  )
  # ... more columns
)

ds_json <- ds_json |> set_column_metadata(column_meta)
```

A list-of-lists where each inner list describes one column. Required fields: `itemOID`, `name`, `label`, `dataType`. Optional: `length`, `displayFormat`, `keySequence`, `targetDataType`, plus various Define-XML-aligned attributes.

Many Define-XML attributes are supported (codeListOID for controlled terminology references, originVariables, derivations). The package mirrors the spec; check `?set_column_metadata` for the current full list.

## 8. Data types in Dataset-JSON

Dataset-JSON supports more native types than XPT:

| Dataset-JSON type | R equivalent | Use case |
|---|---|---|
| `string` | `character` | Text |
| `integer` | `integer` | Whole numbers |
| `float`, `double`, `decimal` | `numeric` | Decimals |
| `boolean` | `logical` | True/false |
| `date` | `Date` (ISO format) | Date only |
| `datetime` | ISO 8601 string | Date + time |
| `time` | ISO time string | Time of day |

When you call `dataset_json(my_data)`, the package introspects R types and sets appropriate JSON types in the `columns` array. For overrides, set them explicitly via `set_column_metadata()`.

This native-typing is a major XPT improvement: no more numeric date encoding (days-since-1960), no more character-vs-numeric coercion games. Dates are dates, booleans are booleans.

## 9. The complete submission-grade pipeline

A full script producing a submission-grade Dataset-JSON:

```r
library(datasetjson)
library(metacore)
library(metatools)
library(dplyr)

# Load spec
mc <- metacore::spec_to_metacore("specs/adam_spec.xlsx")

# Source ADSL (already built via admiral)
adsl <- haven::read_rds("data/adsl.rds")

# Apply variable labels from spec
adsl <- adsl |>
  apply_variable_labels(metacore = mc, dataset = "ADSL")

# Construct Dataset-JSON object with submission metadata
ds_json <- dataset_json(
  .df = adsl,
  itemGroupOID = "IG.ADSL",
  name = "ADSL",
  label = "Subject-Level Analysis Dataset"
) |>
  set_study_oid("STUDY001") |>
  set_metadata_version_oid("MDV.STUDY001.ADaM-1.0") |>
  set_metadata_ref("define.xml") |>
  set_originator("Sponsor Inc.") |>
  set_source_system(
    name = "R 4.4.0 / datasetjson / admiral",
    version = paste(packageVersion("datasetjson"), collapse = ".")
  ) |>
  set_file_oid("/study001/adam/adsl") |>
  set_db_last_modified(format(Sys.time(), "%Y-%m-%dT%H:%M:%S"))

# Write
write_dataset_json(ds_json, "submission/datasets/adsl.json")
```

The result: a single .json file containing both data and metadata, validated against the CDISC schema. Compare to the equivalent XPT workflow which produces only the data with attributes; Define-XML must be produced separately.

## 10. Converting XPT to Dataset-JSON

The Dataset-JSON v1.1 pilot scenario: a sponsor with existing XPT files wants to test JSON submission. The package supports straight conversion:

```r
library(haven)
library(datasetjson)

# Read existing XPT
xpt_data <- haven::read_xpt("adsl.xpt")

# Convert to Dataset-JSON
ds_json <- dataset_json(
  .df = xpt_data,
  itemGroupOID = "IG.ADSL",
  name = "ADSL",
  label = attr(xpt_data, "label") %||% "Subject-Level Analysis Dataset"
)

# Add submission metadata
ds_json <- ds_json |>
  set_study_oid("STUDY001") |>
  # ... etc.

write_dataset_json(ds_json, "adsl.json")
```

`haven::read_xpt()` preserves variable labels and (some) lengths in R attributes, which the package picks up. The result is a Dataset-JSON file representing the same data as the original XPT.

This conversion is what the R-Submissions Working Group used for their Pilot 5 submission to the FDA in late 2025 — converting their existing XPT-based SDTM/ADaM to Dataset-JSON.

## 11. Reading Dataset-JSON

```r
ds <- read_dataset_json("adsl.json")
```

The result is a data frame with Dataset-JSON metadata attached as attributes. Access:

```r
# Get the data as a plain tibble
tibble_view <- as.data.frame(ds)

# Get metadata
attr(ds, "studyOID")
attr(ds, "label")
attr(ds, "metaDataRef")
```

In RStudio's data viewer, variable labels show automatically (since the labels are stored as R attributes on each column). The integration with R's labelled-data tooling is clean.

## 12. Schema validation

Dataset-JSON files must conform to the official CDISC JSON schema. The package validates on read and write:

```r
# Read with validation
ds <- read_dataset_json("adsl.json", validate = TRUE)

# Write with validation
write_dataset_json(ds_json, "adsl.json", validate = TRUE)
```

Validation against the schema catches:

- Missing required top-level fields
- Type mismatches between column definition and row values
- Invalid keySequence values
- Malformed metadata OIDs

For pre-submission QC, always validate. The schema is the source of truth; tools downstream (Pinnacle 21, FDA validation) will use the same schema.

## 13. The FDA pilot trajectory

Status as of mid-2026:

- **Pilot 5 submission (late 2025)**: R-Submissions Working Group submitted Pilot 5 to FDA using Dataset-JSON (instead of XPT) for ADaMs. SDTMs were converted from XPT.
- **FDA feedback (early 2026)**: minor rework requested on intermediate datasets; re-submitted in early 2026.
- **Re-submission completion (Spring 2026)**: expected; will inform FDA's broader Dataset-JSON acceptance roadmap.
- **Pinnacle 21 integration**: as of late 2025, Pinnacle 21 doesn't yet fully validate Dataset-JSON v1.1; expected in 2026.
- **CDISC ARS alignment**: Dataset-JSON is the data format aligned with the emerging CDISC Analysis Results Standard (ARS) — they were designed together.

Practical implication: **for current submissions, ship XPT.** Track Dataset-JSON progress; pilot internally now so you're ready when FDA opens broader acceptance. The transition will likely happen formally in 2027-2029.

For sponsors with sophisticated R/clinical infrastructure (Roche, Novartis, Atorus-aligned, GSK), it's worth running parallel Dataset-JSON exports alongside XPT for several studies to build expertise.

## 14. Comparison: XPT vs Dataset-JSON

| Aspect | XPT v5 | Dataset-JSON v1.1 |
|---|---|---|
| Year defined | 1988 | 2023-2024 |
| Format | Binary | JSON (text) |
| Variable name max | 8 chars | 32 chars |
| Label max | 40 chars | No hard limit (best practice ≤200) |
| String value max | 200 chars | No hard limit |
| Native types | Character, numeric | string, integer, float, boolean, date, datetime, time |
| Self-describing | Partial (limited metadata) | Yes (full top-level metadata) |
| Define-XML linkage | External reference | Built-in field |
| Human-readable | No | Yes |
| File size (typical) | Baseline | Slightly larger uncompressed, similar/smaller compressed |
| FDA acceptance | Yes (default) | Pilot status (full acceptance pending) |
| R package | `{xportr}` | `{datasetjson}` |
| Validation tool | Pinnacle 21 | Pinnacle 21 (in progress) + schema |

For now: XPT is mandatory. For the future: Dataset-JSON is positioned to replace it.

## 15. Reading from a string vs file

The package supports both file-based and string-based I/O:

```r
# Read from string
json_string <- '{"datasetJSONVersion": "1.1.0", ...}'
ds <- read_dataset_json(json_string, source = "string")

# Write to string (no file)
json_text <- write_dataset_json(ds_json, file = NULL)
```

For API-based data exchange — passing Dataset-JSON over HTTPS — string-based I/O is the natural pattern. Pharma teams building data APIs (e.g., for cross-system integration) can use Dataset-JSON as the wire format.

## 16. Multi-dataset packaging

A submission package contains many ADaMs (and SDTMs). For Dataset-JSON, each is its own file:

```
submission/
├── adam/
│   ├── adsl.json
│   ├── adae.json
│   ├── adlb.json
│   ├── adtte.json
│   ├── advs.json
│   ├── adcm.json
│   └── adex.json
├── sdtm/
│   ├── dm.json
│   ├── ae.json
│   ├── lb.json
│   ├── vs.json
│   ├── ex.json
│   ├── cm.json
│   └── ds.json
├── define-adam.xml
└── define-sdtm.xml
```

Same structure as the XPT submission, but with `.json` files. The Define-XML documents (one per type — SDTM, ADaM) provide higher-level metadata; each dataset file references its Define-XML.

For batch conversion of an entire submission package, loop through datasets:

```r
adam_files <- list.files("legacy_submission/adam/", pattern = "\\.xpt$", full.names = TRUE)

for (xpt_file in adam_files) {
  dataset_name <- toupper(tools::file_path_sans_ext(basename(xpt_file)))
  
  xpt_data <- haven::read_xpt(xpt_file)
  
  ds_json <- dataset_json(
    .df = xpt_data,
    itemGroupOID = paste0("IG.", dataset_name),
    name = dataset_name,
    label = attr(xpt_data, "label") %||% dataset_name
  ) |>
    set_study_oid("STUDY001") |>
    set_metadata_ref("define-adam.xml")
  
  write_dataset_json(
    ds_json,
    file.path("submission/adam/", paste0(tolower(dataset_name), ".json"))
  )
}
```

About 20 lines converts an entire 10-dataset ADaM submission from XPT to JSON.

## 17. Dataset-JSON vs Apache Parquet

Worth noting: parquet is another modern columnar format used widely in data science. Why didn't CDISC pick parquet?

- **Parquet is binary**: not human-readable; can't be inspected with a text editor
- **Parquet's schema integration is via Arrow**: well-engineered but more complex than JSON
- **JSON has broader universal support**: every programming language has built-in JSON; not all have parquet
- **Define-XML linkage**: easier to embed in JSON-based exchange formats

Parquet is excellent for data science pipelines (faster, more compact for large data). For regulatory submission, JSON's transparency and universal support won out. Different tools for different jobs.

## 18. Practical recommendations

For your team in 2026:

- **Continue producing XPT v5 via `{xportr}`** for current submissions — it's mandatory
- **Pilot Dataset-JSON internally** for one or two studies — use `{datasetjson}` alongside xportr
- **Monitor FDA guidance** for Dataset-JSON acceptance milestones — pharmaverse blog, R-Submissions Working Group updates
- **Build the muscle now** so when the transition happens, you have working examples
- **Don't rewrite production for Dataset-JSON yet** — wait for formal acceptance

For sponsors new to R adoption: don't worry about Dataset-JSON until you're producing XPT comfortably. The transition will happen, but it's not the priority unless you're R-Submissions WG involved.

## 19. Related: CDISC ARS and ARDs (Lesson 25 callback)

Dataset-JSON was designed in parallel with CDISC ARS (Analysis Results Standard). ARS expects Analysis Results Datasets (ARDs — Lesson 25) to be serialized in a JSON-friendly format. Dataset-JSON is positioned to be that format.

Imagine this future submission package:

```
submission/
├── adam/
│   └── (Dataset-JSON files for ADaMs)
├── ards/
│   ├── demographics_ard.json
│   ├── ae_incidence_ard.json
│   └── (ARDs as Dataset-JSON files)
├── outputs/
│   └── (Cardinal-style HTML/RTF tables)
└── define-ars.xml
```

The submission becomes machine-readable end to end: data, analysis results, displays all serialized in standardized JSON formats. Reviewers can query the ARDs programmatically rather than parsing PDFs.

This is the **5-10 year vision**: full ARS adoption, Dataset-JSON throughout, machine-readable submissions. The infrastructure (cards, datasetjson, cardinal) is being built today.

## 20. Key takeaways

- Dataset-JSON v1.1 is CDISC's modern data exchange standard, positioned as the successor to XPT v5
- Resolves XPT limitations: variable name length, label length, string length, native types
- JSON-based, human-readable, self-describing with optional Define-XML linkage
- `{datasetjson}` is the R package: `dataset_json()` (construct) → `write_dataset_json()` (serialize) → `read_dataset_json()` (read)
- Metadata fluent setters: `set_study_oid()`, `set_metadata_ref()`, `set_originator()`, etc.
- Validates against the CDISC JSON schema on read/write
- FDA pilot status as of 2026; full acceptance pending; transition expected 2027-2029
- Maintained by Atorus with GSK contribution; integrates with the broader pharmaverse stack
- CDISC ARS / ARD format aligned — Dataset-JSON is the serialization format for the future ARS world

## 21. What's next

**Module 9 is complete.** Both submission formats are covered — current (XPT) and future (Dataset-JSON).

**Module 10** covers traceability and validation tooling: `{logrx}` for script execution logging (Lesson 45), `{diffdf}` for dataset comparison in dual-programming workflows (Lesson 46), and `{riskmetric}` for assessing R package risk for regulated use (Lesson 47). These complete the "production-ready R for pharma" toolkit.

After Module 10, the capstone (Lessons 48-49) ties everything together with a runnable end-to-end synthetic oncology study.

---

## Self-check questions

1. List three XPT v5 limitations that Dataset-JSON resolves.
2. What's the practical recommendation for current submissions vs Dataset-JSON pilot work?
3. Translate to `{datasetjson}`: construct a Dataset-JSON object from a data frame with `itemGroupOID = "IG.ADSL"`, name "ADSL", and standard submission metadata.
4. How does Dataset-JSON link to Define-XML?
5. What is the `metaDataRef` field, and why does it matter for submissions?
6. Why does Dataset-JSON support both file-based and string-based I/O?

## Glossary

- **Dataset-JSON v1.1** — CDISC's modern data exchange standard for tabular data using JSON
- **`{datasetjson}`** — Atorus R package for reading/writing Dataset-JSON files
- **`dataset_json()`** — Construct a Dataset-JSON object from a data frame
- **`write_dataset_json()` / `read_dataset_json()`** — Serialize / deserialize
- **`set_study_oid()` / `set_metadata_ref()` / `set_originator()`** — Fluent metadata setters
- **`itemGroupOID`** — Unique identifier for the dataset (e.g., "IG.ADSL")
- **`itemOID`** — Unique identifier per variable (e.g., "IT.ADSL.AGE")
- **`metaDataRef`** — Link to the Define-XML document
- **`keySequence`** — Indicates a variable's position in the natural sort order
- **Define-XML** — CDISC standard for dataset metadata documents
- **CDISC ARS** — Analysis Results Standard; aligned with Dataset-JSON
- **`{xportr}`** — XPT v5 production package; complementary to datasetjson
- **R-Submissions Working Group** — R Consortium effort piloting R-based submissions to FDA
- **Pilot 5** — Late-2025 submission using Dataset-JSON for ADaMs
- **Pinnacle 21** — Validation tool; Dataset-JSON v1.1 support in progress
- **JSON schema** — Formal schema datasetjson validates against
- **Apache Parquet** — Alternative columnar format used in data science; not CDISC-chosen for submissions
