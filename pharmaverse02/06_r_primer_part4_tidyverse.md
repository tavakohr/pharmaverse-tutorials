# Lesson 06 — R Primer for SAS Programmers, Part 4: The Broader Tidyverse

**Module**: 1 — R foundations for SAS programmers
**Estimated length**: ~30 min spoken
**Prerequisites**: Lessons 03–05

---

## Learning objectives

By the end of this lesson, you will be able to:

1. Reshape data with `tidyr::pivot_longer()` and `pivot_wider()` — the equivalents of PROC TRANSPOSE
2. Split and combine columns with `separate_*()` and `unite()`
3. Handle dates and times with `lubridate` — including ISO 8601 strings, which are CDISC's standard
4. Manipulate strings with `stringr` — the cleaner alternative to base R string functions
5. Convert categorical variables to factors with controlled ordering
6. Recognize when to use each of the major tidyverse packages in clinical work

---

## 1. The tidyverse, summarized

The tidyverse is a collection of packages that share a design philosophy:

- Data should be **tidy**: one row per observation, one column per variable, one value per cell
- Functions should take a data frame as the first argument and return a data frame
- Function names should be **verbs** that describe what they do
- The pipe `|>` should connect operations

Load the whole tidyverse at once:

```r
library(tidyverse)
```

This loads `dplyr`, `tidyr`, `readr`, `purrr`, `tibble`, `ggplot2`, `stringr`, and `forcats`. Pharmaverse packages depend heavily on this stack, so installing one pharmaverse package usually pulls all of these.

For this lesson, the most relevant tidyverse members beyond dplyr are:

| Package | What it does | SAS equivalent |
|---|---|---|
| `{tidyr}` | Reshape data (wide ↔ long) | PROC TRANSPOSE |
| `{lubridate}` | Date/time handling | DATE9., DATETIME20., date functions |
| `{stringr}` | String manipulation | CATX, SUBSTR, INDEX, etc. |
| `{forcats}` | Factor (categorical) manipulation | PROC FORMAT |
| `{ggplot2}` | Graphics | PROC SGPLOT (we'll cover separately) |

## 2. Wide vs long: the tidy data concept

A **wide** dataset has one row per subject, with each measurement in its own column:

```
USUBJID   AGE   HEIGHT   WEIGHT
01-001    45    175      80
01-002    52    168      75
```

A **long** dataset has one row per measurement, with a column identifying which measurement:

```
USUBJID   PARAMETER   VALUE
01-001    AGE         45
01-001    HEIGHT      175
01-001    WEIGHT      80
01-002    AGE         52
01-002    HEIGHT      168
01-002    WEIGHT      75
```

CDISC's BDS (Basic Data Structure) is **long** — one row per parameter per subject per visit. This is the model behind ADLB, ADVS, ADEG, and BDS-style ADaMs in general.

Some analyses are easier in wide format (e.g., correlations across parameters). Others are easier in long (e.g., creating a faceted plot, or applying the same summary across many parameters). You'll constantly reshape between them.

## 3. `pivot_longer()` — wide to long

```r
library(tidyr)

# Take wide data, pivot to long
wide_data <- tibble(
  USUBJID = c("01-001", "01-002"),
  AGE = c(45, 52),
  HEIGHT = c(175, 168),
  WEIGHT = c(80, 75)
)

long_data <- wide_data |>
  pivot_longer(
    cols = c(AGE, HEIGHT, WEIGHT),
    names_to = "PARAMETER",
    values_to = "VALUE"
  )

long_data
```

You get:

```
USUBJID   PARAMETER   VALUE
01-001    AGE         45
01-001    HEIGHT      175
01-001    WEIGHT      80
01-002    AGE         52
01-002    HEIGHT      168
01-002    WEIGHT      75
```

Key arguments:

- `cols`: which columns to pivot. Supports `c(A, B, C)`, `-USUBJID` (everything except), or tidyselect helpers like `starts_with("LB")`
- `names_to`: name of the new column holding the original column names
- `values_to`: name of the new column holding the original values

For columns with patterns in the names — say `LBORRES_V1`, `LBORRES_V2`, `LBORRES_V3` — `names_pattern` and `names_sep` can split the column name into multiple new columns:

```r
df |>
  pivot_longer(
    cols = starts_with("LBORRES_"),
    names_to = c(".value", "VISIT"),    # .value means "use as variable name"
    names_pattern = "(LBORRES)_V(\\d+)"
  )
```

The SAS equivalent of `pivot_longer` is `PROC TRANSPOSE` with various options. dplyr/tidyr is cleaner once you internalize the syntax.

## 4. `pivot_wider()` — long to wide

```r
wide_again <- long_data |>
  pivot_wider(
    names_from = PARAMETER,
    values_from = VALUE
  )
```

You're back to the original wide table.

Common clinical use: turning a long ADLB with rows for HGB, HCT, RBC into a wide view with one row per visit and columns HGB, HCT, RBC:

```r
adlb |>
  filter(PARAMCD %in% c("HGB", "HCT", "RBC")) |>
  select(USUBJID, AVISITN, PARAMCD, AVAL) |>
  pivot_wider(
    names_from = PARAMCD,
    values_from = AVAL
  )
```

If the same `(USUBJID, AVISITN, PARAMCD)` combination has multiple rows, `pivot_wider` will warn and create list-columns. That's usually a sign you should aggregate first (group_by + summarise).

## 5. `separate_*()` and `unite()` — splitting and combining columns

Splitting a column on a delimiter:

```r
df <- tibble(LBTESTCD_LBCAT = c("HGB_HEMATOLOGY", "ALT_CHEMISTRY"))

df |>
  separate_wider_delim(
    LBTESTCD_LBCAT,
    delim = "_",
    names = c("LBTESTCD", "LBCAT")
  )
```

(Older `separate()` still works but is being deprecated; use `separate_wider_*` going forward.)

For regex-based splits:

```r
df |>
  separate_wider_regex(
    LBTESTCD_LBCAT,
    patterns = c(LBTESTCD = "\\w+", "_", LBCAT = "\\w+")
  )
```

Combining columns:

```r
df |>
  unite("FULL_DATE", c(YEAR, MONTH, DAY), sep = "-")
```

This becomes especially relevant in SDTM derivation, where ISO 8601 dates are often built from separate year/month/day components in the raw data.

## 6. Working with dates: `lubridate`

CDISC standard date format is **ISO 8601**: `YYYY-MM-DD` for dates, `YYYY-MM-DDTHH:MM:SS` for datetimes. SDTM character variables like `AESTDTC` store ISO 8601 strings.

In R, you typically convert these to proper Date or POSIXct (datetime) objects for arithmetic.

`{lubridate}` provides parsers that handle the common formats:

```r
library(lubridate)

ymd("2024-03-15")                # Date
ymd_hms("2024-03-15 14:30:00")   # POSIXct (datetime)
dmy("15/03/2024")                # European format
mdy("3/15/2024")                 # American format

ymd("20240315")                  # ISO basic format
ymd("2024-03-15")                # ISO extended format
```

For partial ISO 8601 dates (common in SDTM where data is sometimes incomplete):

```r
# "2024-03" — missing day
ymd("2024-03-15", truncated = 2)    # filled with 15
ymd("2024", truncated = 2)          # 2024-01-01
```

Pharmaverse provides admiral functions specifically for partial-date imputation following CDISC conventions — we'll cover those in Module 4.

### Extracting parts

```r
d <- ymd("2024-03-15")

year(d)        # 2024
month(d)       # 3
day(d)         # 15
yday(d)        # 75 (day of year)
wday(d)        # day of week
quarter(d)     # 1
```

### Arithmetic

```r
d2 <- ymd("2024-09-01")
d2 - d                        # Time difference of 170 days

# Add intervals
d + days(7)                   # 2024-03-22
d + months(1)                 # 2024-04-15
d + years(1)                  # 2025-03-15

# Difftime in specific units
as.numeric(d2 - d, units = "days")     # 170
as.numeric(d2 - d, units = "weeks")    # 24.28...
```

For age calculation (a common clinical task):

```r
birth <- ymd("1980-05-12")
study_start <- ymd("2024-06-01")

# Age in completed years
floor(as.numeric(study_start - birth) / 365.25)
# or
trunc(interval(birth, study_start) / years(1))
```

### Datetimes and time zones

ISO 8601 supports time zones (`2024-03-15T14:30:00+00:00`). For clinical data, time zones are usually either not present or UTC. `lubridate`'s `ymd_hms()` defaults to UTC unless told otherwise:

```r
dt <- ymd_hms("2024-03-15 14:30:00", tz = "America/New_York")
with_tz(dt, tz = "UTC")
```

For most ADaM derivations, you won't need time zone gymnastics — but be aware that if your raw data has them, you must handle them consistently.

## 7. Strings: `stringr`

Base R has string functions (`substr`, `grepl`, `paste`, `nchar`) but they're inconsistent in argument order and behavior. `{stringr}` wraps them with a consistent `str_*` prefix:

| Task | base R | `stringr` |
|---|---|---|
| Length | `nchar()` | `str_length()` |
| Substring | `substr()` | `str_sub()` |
| Detect pattern | `grepl()` | `str_detect()` |
| Extract pattern | `regmatches()`/`regexpr()` | `str_extract()` |
| Replace pattern | `gsub()`/`sub()` | `str_replace()` / `str_replace_all()` |
| Split | `strsplit()` | `str_split()` |
| Lower/upper | `tolower()` / `toupper()` | `str_to_lower()` / `str_to_upper()` |
| Trim whitespace | `trimws()` | `str_trim()` / `str_squish()` |
| Pad | `formatC()` | `str_pad()` |
| Concatenate | `paste()` / `paste0()` | `str_c()` |

Examples:

```r
library(stringr)

# Detect AEs starting with "HEAD" (case insensitive)
adae |>
  filter(str_detect(AETERM, regex("HEAD", ignore_case = TRUE)))

# Extract first 4 characters of a date string
str_sub("2024-03-15", 1, 4)         # "2024"

# Replace pattern
str_replace_all("Subject 01-001", "-", "_")   # "Subject 01_001"

# Pad with leading zeros (common for ID formatting)
str_pad("5", width = 3, pad = "0")            # "005"

# Concatenate
str_c("Subject ", c("01", "02"), sep = "")    # "Subject 01" "Subject 02"
```

`stringr` is consistent: every function takes the string as its first argument, which makes piping natural:

```r
adae |>
  mutate(AETERM_CLEAN = AETERM |>
                         str_to_upper() |>
                         str_squish() |>
                         str_replace_all("HEADACE", "HEADACHE"))
```

Regular expressions follow the standard POSIX/PCRE-like syntax; you can wrap a pattern in `regex(..., ignore_case = TRUE)` to make it case-insensitive. The free [regex101.com](https://regex101.com) site is invaluable for testing patterns.

## 8. Factors: `forcats`

A **factor** is R's categorical type. It stores values as integers internally with a labels lookup — basically a permanent SAS format applied to the variable.

Factors matter for clinical work for two reasons:

1. **Ordering of categories in tables and plots.** A character variable with values "Placebo", "Low Dose", "High Dose" sorts alphabetically. As a factor with explicit levels, you control the order.
2. **Statistical models** treat factors specially — the first level is the reference category in regression.

```r
library(forcats)

# Create a factor with explicit levels
adsl <- adsl |>
  mutate(TRT01A = fct(TRT01A, levels = c("Placebo",
                                          "Xanomeline Low Dose",
                                          "Xanomeline High Dose")))

# Inspect
levels(adsl$TRT01A)
```

Useful `forcats` functions:

```r
fct_relevel(x, "Placebo")          # move "Placebo" to be the first level
fct_recode(x, "Low" = "Low Dose")  # rename a level
fct_collapse(x,                    # combine levels
             "Active" = c("Low Dose", "High Dose"))
fct_lump_n(x, n = 5)               # keep top 5, lump rest into "Other"
fct_drop(x)                        # drop unused levels
```

In summary tables, the **factor level order determines column order**. Always set factors with intentional level ordering before producing a TLG, or you'll spend hours wondering why your demographics table has columns in the wrong sequence.

### Factor vs character — when to use which

- **In raw data and most derivations**: use character. It's simpler, more flexible.
- **At the moment of building a TLG or fitting a model**: convert key categorical variables to factors with explicit levels.
- **In SDTM/ADaM datasets you'll export**: keep as character. CDISC doesn't have a "factor" concept; XPT files store everything as character or numeric.

A common pattern in pharmaverse code:

```r
adsl_for_tlg <- adsl |>
  mutate(
    TRT01A = factor(TRT01A, levels = c("Placebo", "Low Dose", "High Dose")),
    SEX = factor(SEX, levels = c("M", "F"), labels = c("Male", "Female"))
  )
```

## 9. Putting it together: a real reshaping task

Goal: take ADLB and produce a wide summary of baseline lab values per subject — one row per subject, columns for HGB, ALT, AST.

```r
library(dplyr)
library(tidyr)

baseline_labs <- adlb |>
  filter(PARAMCD %in% c("HGB", "ALT", "AST"),
         ABLFL == "Y") |>
  select(USUBJID, PARAMCD, AVAL) |>
  pivot_wider(
    names_from = PARAMCD,
    values_from = AVAL,
    names_prefix = "BASE_"
  )

baseline_labs
```

Output:

```
USUBJID   BASE_HGB  BASE_ALT  BASE_AST
01-001       14.2      25        22
01-002       12.8      18        20
...
```

Now we can join this to ADSL for downstream analysis:

```r
adsl_enriched <- adsl |>
  left_join(baseline_labs, by = "USUBJID")
```

Three packages cooperating naturally: dplyr for filter/select, tidyr for pivot_wider, then dplyr again for the join. This is the tidyverse pattern.

## 10. Strings + dates: a CDISC-flavored example

You receive AE data where `AESTDTC` is an ISO 8601 string. You need to compute the day of treatment when the AE started (relative to first dose), and flag AEs that occurred within 30 days of first dose.

```r
ae_processed <- adae |>
  left_join(adsl |> select(USUBJID, TRTSDT), by = "USUBJID") |>
  mutate(
    AESTDT = ymd(AESTDTC),                          # parse string → Date
    DAYS_FROM_FIRST_DOSE = as.numeric(AESTDT - TRTSDT),
    AE_WITHIN_30D = if_else(DAYS_FROM_FIRST_DOSE <= 30 &
                              DAYS_FROM_FIRST_DOSE >= 0,
                            "Y", "N",
                            missing = "N")
  )
```

A few patterns to notice:

- ISO 8601 strings are parsed with `lubridate::ymd()`
- `as.numeric()` on a difftime returns numeric days
- `if_else()` (with underscore) handles `NA` cleanly via the `missing` argument

This pattern shows up constantly in admiral derivations — though admiral provides specialized functions like `derive_vars_dt()` that wrap the ISO 8601 + imputation logic. We'll cover those in Module 4.

## 11. The other tidyverse members worth knowing

- **`{readr}`** — fast CSV/TSV reading; we covered it in Lesson 03
- **`{tibble}`** — friendlier replacement for `data.frame`; loaded automatically with dplyr
- **`{ggplot2}`** — graphics. Vast topic, will come up in TLG modules and `{teal}`
- **`{purrr}`** — functional programming; covered briefly in Lesson 05

There are several more "tidyverse-adjacent" packages worth knowing for clinical work:

- **`{glue}`** — string interpolation, like SAS `&macro` references but in a non-macro way
- **`{janitor}`** — data cleaning helpers (clean column names, cross-tabs)
- **`{haven}`** — read SAS/SPSS/Stata files (we used it in Lesson 03)

## 12. SAS → tidyverse cheat sheet

| SAS pattern | tidyverse equivalent |
|---|---|
| `proc transpose` | `pivot_longer()` / `pivot_wider()` |
| `cats(...)` / `catx(...)` | `str_c()` or `paste0()` |
| `input(var, yymmdd10.)` | `ymd(var)` |
| `put(date, date9.)` | `format(date, "%d%b%Y")` |
| `intck("day", date1, date2)` | `as.numeric(date2 - date1)` |
| `intnx("month", date, 3)` | `date %m+% months(3)` |
| `substr(s, 1, 3)` | `str_sub(s, 1, 3)` |
| `index(s, "x")` | `str_locate(s, "x")` |
| `tranwrd(s, "old", "new")` | `str_replace_all(s, "old", "new")` |
| `upcase(s)` | `str_to_upper(s)` |
| `compbl(s)` | `str_squish(s)` |
| PROC FORMAT user format | `factor(x, levels = ..., labels = ...)` |

## 13. Key takeaways

- **Tidy data**: one row per observation, one column per variable. The BDS structure in CDISC is tidy.
- `pivot_longer()` and `pivot_wider()` replace PROC TRANSPOSE more clearly
- Dates: parse ISO 8601 strings with `lubridate::ymd()` / `ymd_hms()`; arithmetic with `days()`, `months()`, `years()`
- Strings: use `stringr` (consistent `str_*` API), not base R string functions
- Factors: use when controlling level order matters (TLG column ordering, model reference categories)
- Convert character → factor at the TLG-building step, not in your stored ADaM datasets

## 14. What's next

That's it for R foundations. From here on, every lesson covers a specific pharmaverse package. We start Module 2 with **`{pharmaverseraw}`** — the test data that simulates raw EDC output — followed by **`{sdtm.oak}`** for SDTM creation in three parts, and **`{sdtmchecks}`** for conformance QC.

If anything from Lessons 03–06 feels shaky, the easiest way to solidify it is to write small data manipulation tasks against the `pharmaverseadam::adsl` dataset and ask yourself "how would I have done this in SAS?" — then translate. The patterns will become automatic after a week or two of consistent practice.

---

## Self-check questions

1. Convert wide → long: a dataset has columns `LBTEST1, LBTEST2, LBTEST3`. Show the `pivot_longer` call.
2. What's the difference between `ymd()` and `mdy()`?
3. Why do you typically NOT store factors in your ADaM datasets?
4. Translate to R: "compute the number of days between TRTSDT and AESTDT".
5. What does `str_squish()` do that `str_trim()` doesn't?
6. When would you use `factor()` vs leaving a column as character?

## Glossary

- **Tidy data** — One row per observation, one column per variable, one value per cell
- **`pivot_longer` / `pivot_wider`** — Reshape between long and wide formats
- **ISO 8601** — International date/time string standard (`YYYY-MM-DD`), CDISC's default
- **`lubridate`** — Tidyverse date/time package
- **`stringr`** — Tidyverse string manipulation package
- **`forcats`** — Tidyverse factor manipulation package
- **Factor** — R's categorical type; integer codes with a labels lookup
- **Factor level** — The distinct values a factor can take, in their defined order
- **BDS** — Basic Data Structure; CDISC's long-format ADaM standard for analysis data
