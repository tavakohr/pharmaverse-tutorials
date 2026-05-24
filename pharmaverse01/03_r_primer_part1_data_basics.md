# Lesson 03 — R Primer for SAS Programmers, Part 1: Data Basics

**Module**: 1 — R foundations for SAS programmers
**Estimated length**: ~25 min spoken
**Prerequisites**: Lesson 02 (Environment setup)

---

## Learning objectives

By the end of this lesson, you will be able to:

1. Translate your mental model of SAS datasets and variables into R data frames and columns
2. Use R's assignment operator and understand why it's `<-` and not `=`
3. Work with R's atomic types (numeric, integer, character, logical) and their SAS equivalents
4. Handle missing values (`NA`) — the equivalent of SAS's `.` for numeric and `' '` for character
5. Subset data frames using base R indexing (we'll cover dplyr in Part 2)
6. Read CSV, SAS XPT, and SAS7BDAT files using `haven`
7. Inspect a dataset using `head()`, `str()`, `glimpse()`, and `summary()`

---

## 1. The big mental shift: everything in R is a vector

In SAS, the fundamental unit is a **dataset** — a rectangular collection of observations and variables. You manipulate datasets row by row using the DATA step, or set by set using PROC steps.

In R, the fundamental unit is a **vector** — a sequence of values, all of the same type. A "variable" is a vector. A "column" in a dataset is a vector. Even a single value, like the number 5, is a vector of length 1.

A **data frame** in R is a list of equal-length vectors — columns of potentially different types, aligned by row. This is the closest thing to a SAS dataset, and you'll spend 90% of your time working with data frames.

The key shift: in SAS, you think "row by row." In R, you think "whole vector at once." This is called **vectorization**, and once it clicks, it makes code much shorter.

SAS:
```sas
data result;
  set adsl;
  age_years = age;          /* one row at a time */
  age_group = "Older";
  if age < 65 then age_group = "Younger";
run;
```

R (the vectorized way):
```r
result <- adsl
result$age_years <- result$age
result$age_group <- ifelse(result$age < 65, "Younger", "Older")
```

The R code operates on the *entire* `age` column at once, rather than row by row. Internally, it's much faster because R loops in C, not in R.

In Part 2 we'll see the dplyr way of doing this, which is even cleaner. For now, get used to the idea that you're rarely "looping over rows" in R — you're transforming whole columns.

## 2. The assignment operator: `<-` (not `=`)

In SAS, you use `=` for assignment. In R, the idiomatic operator is `<-`:

```r
x <- 5             # idiomatic R
y = 5              # works, but discouraged
x = 5              # also works, also discouraged
```

You can technically use `=` for assignment, and it works. The R community strongly prefers `<-` because `=` is also used for naming function arguments, and the visual distinction helps. RStudio has a keyboard shortcut: **Alt + - (Alt-minus)** inserts ` <- ` with surrounding spaces.

There's also a right-pointing version, `->`, which assigns the value on the left to the name on the right. It's legal but unusual:

```r
5 -> x   # legal, weird
```

Don't use it. Stick with `<-`.

## 3. R's atomic types and their SAS equivalents

R has four atomic types you'll deal with regularly:

| R type | SAS equivalent | Example | Notes |
|---|---|---|---|
| `numeric` (also called `double`) | SAS numeric | `45.3`, `3`, `0.001` | Default for any number |
| `integer` | SAS numeric (typically) | `45L`, `100L` | Use `L` suffix to force integer |
| `character` | SAS character | `"Treatment A"`, `"M"` | Always use double quotes |
| `logical` | none directly | `TRUE`, `FALSE`, `NA` | Equivalent to SAS 1/0 flags but with a third state |

A few important nuances:

**R's "numeric" is always double-precision floating point.** SAS does the same by default. You rarely need to think about it.

**The `L` suffix makes a value an integer.** `45` is a double; `45L` is an integer. For most analysis work the distinction doesn't matter, but it affects memory and some package behavior.

**Logical values exist as a distinct type.** SAS uses 1/0 for boolean flags. R has TRUE/FALSE as a real type. They auto-convert when you do arithmetic: `sum(c(TRUE, FALSE, TRUE))` returns 2. This is incredibly useful for counting.

**Factors are categorical variables with ordered levels.** They're not an atomic type — they're built on top of integers, with a labels lookup. They're R's answer to SAS formats. We'll cover them in detail when we get to dplyr.

To check what type a value is:

```r
x <- 45.3
class(x)        # "numeric"
typeof(x)       # "double"

y <- 45L
class(y)        # "integer"

z <- "Treatment A"
class(z)        # "character"

w <- TRUE
class(w)        # "logical"
```

## 4. Missing values: `NA`

SAS uses `.` for missing numerics and `' '` for missing character. R uses `NA` for both.

But there's a subtlety: `NA` has multiple "flavors" tied to the type it lives in:

- `NA` — logical NA (the default)
- `NA_integer_` — integer NA
- `NA_real_` — numeric (double) NA
- `NA_character_` — character NA

Most of the time you don't need to specify; R picks the right one. But occasionally — especially when initializing empty vectors — you need to be explicit:

```r
empty_numeric <- rep(NA_real_, 10)        # vector of 10 missing numbers
empty_character <- rep(NA_character_, 10)  # vector of 10 missing strings
```

**Critical: comparisons with `NA` return `NA`, not `FALSE`.**

```r
x <- NA
x == 5      # returns NA, not FALSE!
is.na(x)    # returns TRUE — this is how you test for missing
```

This is the most common R bug for SAS programmers. In SAS, `if age = . then ...` works because SAS treats missing as a comparable value. In R, you must use `is.na()`:

```r
# Wrong (SAS-like, doesn't work)
if (age == NA) { ... }

# Right
if (is.na(age)) { ... }
```

For logical operations on vectors with NA:
- `NA & FALSE` → `FALSE` (because anything AND FALSE is FALSE)
- `NA & TRUE` → `NA` (we don't know)
- `NA | TRUE` → `TRUE`
- `NA | FALSE` → `NA`

This logic-aware NA handling is actually more correct than SAS's behavior, once you internalize it.

## 5. Creating vectors

Use `c()` (combine) to create a vector:

```r
ages <- c(45, 52, 38, 67, 41)
treatments <- c("A", "A", "B", "B", "A")
flags <- c(TRUE, FALSE, FALSE, TRUE, TRUE)
```

You cannot mix types in a single vector — R will coerce to the most flexible type:

```r
mixed <- c(1, 2, "three")
mixed                    # all coerced to character: "1" "2" "three"
class(mixed)             # "character"
```

This is one of R's gotchas. If you accidentally include a character value in what you thought was a numeric vector, everything silently becomes character. Check with `class()` if math suddenly fails.

For sequences:

```r
1:10                     # 1, 2, 3, ..., 10
seq(0, 100, by = 10)     # 0, 10, 20, ..., 100
seq_len(5)               # 1, 2, 3, 4, 5
seq_along(ages)          # 1, 2, 3, 4, 5 (same length as ages)
rep("Yes", 5)            # "Yes" five times
```

## 6. Data frames: the R equivalent of a SAS dataset

A data frame holds rectangular data. In modern R, you'll typically work with a **tibble**, which is a friendlier data frame from the tidyverse. The differences are minor; tibbles print more nicely and don't do some confusing automatic conversions.

Create a data frame manually:

```r
library(tibble)

study_data <- tibble(
  USUBJID = c("01-001", "01-002", "01-003"),
  AGE = c(45, 52, 38),
  SEX = c("M", "F", "F"),
  TRTA = c("Treatment A", "Treatment B", "Treatment A")
)

study_data
```

In R, by convention, column names use UPPERCASE for CDISC-standard variables (USUBJID, AGE, TRTA, etc.) to match the standard. For internal working variables, lowercase or `snake_case` is preferred (e.g. `age_group`, `is_responder`).

Compare to SAS:

```sas
data study_data;
  length USUBJID $ 8 SEX $ 1 TRTA $ 20;
  input USUBJID $ AGE SEX $ TRTA $;
  datalines;
01-001 45 M Treatment A
01-002 52 F Treatment B
01-003 38 F Treatment A
;
run;
```

Both produce a 3-row, 4-column dataset with the same content.

## 7. Inspecting a data frame

Once you have data, the first thing you do is look at it. R gives you several ways:

```r
# Use the ADSL bundled in pharmaverseadam
library(pharmaverseadam)
data("adsl")

# The whole data frame
adsl

# First 6 rows
head(adsl)

# Last 6 rows
tail(adsl)

# First 10 rows
head(adsl, 10)

# Just structure: types and first values
str(adsl)

# A friendlier version of str()
library(dplyr)
glimpse(adsl)

# Summary statistics for every column
summary(adsl)

# Dimensions: rows × columns
dim(adsl)
nrow(adsl)
ncol(adsl)

# Column names
names(adsl)
colnames(adsl)

# RStudio's interactive viewer (like SAS Viewtable)
View(adsl)
```

`glimpse()` is what most R programmers reach for first — it shows column types and the first several values of each. The SAS equivalent is `PROC CONTENTS DATA=adsl;` plus a peek at the data itself.

## 8. Subsetting a data frame (base R way)

You'll learn the much-nicer dplyr way in Part 2, but you need to know the base R way because you'll see it everywhere — including inside pharmaverse package source code.

### Selecting columns

```r
# By name, single column
adsl$AGE                   # returns a vector

# By name, multiple columns
adsl[, c("USUBJID", "AGE", "SEX")]

# By position
adsl[, 1]                  # first column
adsl[, 1:3]                # first three columns
```

The `$` operator is your shortcut for one column at a time. It returns a vector, not a data frame.

### Filtering rows

```r
# Rows where AGE > 50
adsl[adsl$AGE > 50, ]

# Rows where SAFFL is "Y"
adsl[adsl$SAFFL == "Y", ]

# Rows where AGE > 50 AND SEX is "F"
adsl[adsl$AGE > 50 & adsl$SEX == "F", ]
```

The pattern is `data[rows, columns]`. Leave one side blank to mean "all":

- `adsl[, c("AGE")]` — all rows, AGE column
- `adsl[adsl$AGE > 50, ]` — rows where AGE > 50, all columns

**Critical**: the empty second position with the comma — `adsl[adsl$AGE > 50, ]` — is required. Without the comma, you'd be subsetting the data frame as a list, which behaves differently.

This base R syntax gets verbose for complex operations. Compare:

```r
# Base R
result <- adsl[adsl$SAFFL == "Y" & adsl$AGE > 50, c("USUBJID", "AGE", "TRT01A")]

# dplyr (covered in Part 2)
result <- adsl |>
  filter(SAFFL == "Y", AGE > 50) |>
  select(USUBJID, AGE, TRT01A)
```

The dplyr version reads top-to-bottom like a recipe. Once you learn it, you'll rarely use base R subsetting for analysis code, but you must be able to read it because it's everywhere.

## 9. Adding and modifying columns (base R)

```r
# Add a new column
adsl$AGE_MONTHS <- adsl$AGE * 12

# Modify an existing column
adsl$AGE <- adsl$AGE + 1   # everyone ages a year

# Conditional column
adsl$AGE_GROUP <- ifelse(adsl$AGE < 65, "Younger", "Older")

# Multi-condition (nested ifelse — gets ugly)
adsl$AGE_CAT <- ifelse(adsl$AGE < 18, "Pediatric",
                ifelse(adsl$AGE < 65, "Adult", "Elderly"))

# Cleaner: dplyr::case_when() — see Part 2
```

`ifelse(condition, value_if_true, value_if_false)` is the R analog of SAS's:

```sas
if condition then var = value_if_true;
else var = value_if_false;
```

It's vectorized: pass a logical vector as the condition, and it returns a vector of the same length.

## 10. Reading data files

You'll rarely create data manually. More commonly, you read from CSV, SAS XPT, SAS7BDAT, or RDS files.

### CSV files

```r
library(readr)

dm <- read_csv("data/dm.csv")
```

`readr::read_csv()` is the modern choice. It's fast, returns a tibble, and handles types intelligently. The base R `read.csv()` works but has quirks; avoid it.

### SAS XPT files (CDISC transport format)

```r
library(haven)

ae <- read_xpt("data/ae.xpt")
```

`haven::read_xpt()` reads SAS v5 XPT files — the format used for CDISC submissions. It preserves SAS variable labels and formats as attributes, which is critical for round-tripping back to XPT later via `xportr` (see Module 9).

### SAS7BDAT files

```r
library(haven)

dm <- read_sas("data/dm.sas7bdat")
```

This works for most SAS datasets. Caveat: SAS7BDAT is a proprietary format; haven's reader is reverse-engineered. Most datasets work fine, but rare encoding issues exist.

### RDS files (R's native binary format)

```r
saveRDS(my_data, "data/my_data.rds")
my_data <- readRDS("data/my_data.rds")
```

RDS files are R-only, but they preserve every R-specific attribute perfectly (factor levels, S3 classes, etc.). Use for intermediate working data within an R project.

### Excel files

```r
library(readxl)
data <- read_excel("data/file.xlsx", sheet = "Sheet1")
```

`readxl` is the standard. For writing Excel, use `openxlsx` or `writexl`.

## 11. The pipe operator: `%>%` and `|>`

You'll see this everywhere in pharmaverse code:

```r
adsl |>
  filter(SAFFL == "Y") |>
  select(USUBJID, AGE, TRT01A) |>
  head(10)
```

The pipe (`|>`, called the "native pipe" since R 4.1) takes the value on the left and passes it as the first argument of the function on the right. The above reads as:

> Take adsl, then filter for safety population, then select three columns, then take the first 10 rows.

There's also `%>%` (the magrittr pipe) which predates `|>` and is functionally equivalent for most uses. You'll see both in the wild. Pharmaverse documentation increasingly uses `|>`. Either is fine, but for new code, **prefer `|>`** because it's part of base R and doesn't require loading `magrittr`.

Why pipes matter: they let you write left-to-right, top-to-bottom code that reads like a recipe. Compare:

```r
# Nested function calls — read inside-out, painful
head(select(filter(adsl, SAFFL == "Y"), USUBJID, AGE, TRT01A), 10)

# Piped — reads top-to-bottom, clear
adsl |>
  filter(SAFFL == "Y") |>
  select(USUBJID, AGE, TRT01A) |>
  head(10)
```

Once you internalize pipes, you won't go back. Almost every line of pharmaverse code you'll write or read uses them.

## 12. The SAS WORK library equivalent: the global environment

In SAS, datasets live in libraries (WORK, USER, library names you assign). In R, objects live in **environments**, with the **global environment** as the main one.

```r
x <- 5
y <- c(1, 2, 3)
df <- adsl

ls()                # list objects in global environment
                    # equivalent to PROC DATASETS LIBRARY=WORK in SAS
```

Three important differences from SAS WORK:

1. **R objects are typed by what they hold.** You can put a number, a vector, a data frame, a function, a model fit — anything — in the same global environment.
2. **Objects persist for the R session.** When you quit R, they're gone (unless you turned on .RData restoration — which we said to turn off in Lesson 02).
3. **Names collide.** If you do `adsl <- something_else`, you've overwritten the original `adsl` without warning. SAS at least warns when overwriting; R just does it silently. Be careful with reusing names.

To remove an object:

```r
rm(x)               # remove x
rm(list = ls())     # remove everything — like PROC DATASETS KILL
```

## 13. Putting it together: a mini workflow

Let's do a small task end-to-end using only what we've learned.

> Read the ADSL data, find subjects in the safety population who are female and older than 50, show their USUBJID, age, and treatment.

```r
library(pharmaverseadam)
library(haven)

# Load (it's already in the package)
data("adsl")

# Check what we have
glimpse(adsl)

# Subset
elderly_women <- adsl[
  adsl$SAFFL == "Y" &
  adsl$SEX == "F" &
  adsl$AGE > 50,
  c("USUBJID", "AGE", "TRT01A")
]

# Inspect
head(elderly_women)
nrow(elderly_women)
```

In Part 2, the same task in dplyr:

```r
library(dplyr)

elderly_women <- adsl |>
  filter(SAFFL == "Y", SEX == "F", AGE > 50) |>
  select(USUBJID, AGE, TRT01A)
```

You can see why dplyr won the hearts of R users.

## 14. Common SAS-to-R gotchas (quick reference)

| SAS | R | Note |
|---|---|---|
| `=` | `<-` (or `=`) | `<-` is idiomatic |
| `.` (numeric missing) | `NA` (or `NA_real_`) | Always test with `is.na()` |
| `' '` (character missing) | `NA` (or `NA_character_`) | Same |
| `if age = . then ...` | `if (is.na(age))` | `==` with NA gives NA, not TRUE |
| `&` and `|` | `&` and `|` | Same syntax, also vectorized |
| `and` and `or` | `&&` and `||` | Scalar versions, only for control flow |
| `;` (statement end) | newline | Optional `;` exists, rarely used |
| `*` comment | `#` comment | `#` to end of line |
| `/* */` block comment | no built-in equivalent | Most editors comment selected block |
| `%let x = 5;` | `x <- 5` | No macro/data scope distinction |
| `proc print` | `print()` or just type the name | `adsl` alone prints it |
| `proc contents` | `str(adsl)` or `glimpse(adsl)` | |
| `where age > 50` | `filter(age > 50)` (dplyr) | Or `adsl[adsl$age > 50, ]` |
| `keep var1 var2` | `select(var1, var2)` (dplyr) | Or `adsl[, c("var1", "var2")]` |

## 15. Key takeaways

- R's fundamental unit is the vector. Data frames are lists of vectors.
- Assign with `<-` (idiomatic); not `=`.
- Missing values are `NA` — test with `is.na()`, not `== NA`.
- R is vectorized — operate on whole columns, not row by row.
- Base R subsetting uses `data[rows, columns]` with logical or name-based indexing.
- The pipe (`|>`) lets you chain operations readably; you'll use it constantly.
- Read data with `readr::read_csv()` for CSV, `haven::read_xpt()` for CDISC XPT, `haven::read_sas()` for SAS7BDAT.
- Inspect data with `glimpse()`, `head()`, `str()`, `summary()`.

## 16. What's next

Part 2 of the R primer covers **the dplyr verbs** — the elegant successor to SAS DATA step manipulations. We'll translate every common SAS DATA-step pattern into its dplyr equivalent, including BY-group processing, FIRST./LAST. logic, RETAIN/LAG, and conditional column creation with `case_when()`.

Once you have dplyr fluency, you can read pharmaverse source code, and you're 80% of the way to productive R.

---

## Self-check questions

1. Why is `if (age == NA) { ... }` wrong, and what should it be instead?
2. What does the empty position before the comma mean in `adsl[adsl$AGE > 50, ]`?
3. Convert this SAS code to R (base R is fine): `data result; set adsl; where saffl = "Y" and age >= 18; keep usubjid age trta; run;`
4. What's the difference between `<-` and `=` for assignment?
5. Why does `c(1, 2, "three")` produce a character vector instead of erroring?

## Glossary

- **Vector** — A sequence of values of a single type
- **Data frame / tibble** — A list of equal-length vectors; the R equivalent of a SAS dataset
- **Atomic type** — `numeric`, `integer`, `character`, `logical`
- **NA** — R's missing value, type-specific (`NA_real_`, `NA_character_`, etc.)
- **Vectorization** — Operating on whole vectors instead of element-by-element
- **Pipe** (`|>` or `%>%`) — Operator that passes a value as the first argument of the next function
- **Global environment** — Where top-level objects live during an R session
- **`{haven}`** — Tidyverse package for reading SAS, SPSS, Stata files
- **`{readr}`** — Tidyverse package for reading delimited text files (CSV, TSV)
- **`{tibble}`** — Modern friendlier replacement for `data.frame`
