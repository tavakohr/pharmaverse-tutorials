# Lesson 05 — R Primer for SAS Programmers, Part 3: Joins, SQL, and Functions

**Module**: 1 — R foundations for SAS programmers
**Estimated length**: ~30 min spoken
**Prerequisites**: Lessons 03–04

---

## Learning objectives

By the end of this lesson, you will be able to:

1. Use all dplyr join verbs — `left_join`, `inner_join`, `right_join`, `full_join`, `semi_join`, `anti_join` — to translate any PROC SQL or DATA-step MERGE
2. Diagnose and handle the most common join problems (many-to-many fanout, missing key, type mismatch)
3. Use `dbplyr` to write dplyr code that translates to SQL against a real database
4. Write your own R functions, including default arguments and dot-dot-dot (`...`)
5. Understand the difference between SAS macros and R functions — and why R functions are strictly better
6. Apply functional programming patterns with `purrr::map()` for iteration

---

## 1. Joins: the bread and butter of clinical data work

Almost every ADaM dataset is built by joining SDTM domains: AE ← DM, LB ← DM, EX ← DM. Almost every TLG starts by joining the analysis dataset to ADSL for population flags. Joins are everywhere.

In SAS, you have two main tools:
- **DATA step MERGE** with BY: classic, fast, but with quirks (especially when key variables don't match exactly)
- **PROC SQL** joins: SQL syntax, more flexible, slightly slower

dplyr replaces both with a unified set of join verbs that are clearer than either.

The basic syntax for all dplyr joins:

```r
left_join(x, y, by = "key_column")
left_join(x, y, by = c("key1", "key2"))
left_join(x, y, by = join_by(key1 == key2))   # for joins on differently-named columns
```

You can also pipe:

```r
x |>
  left_join(y, by = "USUBJID")
```

## 2. The six join verbs

### `left_join()` — most common; keep everything from the left

```r
# adae has AE rows; we want to attach treatment from adsl
adae_with_trt <- adae |>
  left_join(
    adsl |> select(USUBJID, TRT01A, SAFFL),
    by = "USUBJID"
  )
```

Every row of `adae` is preserved. If a USUBJID exists in `adae` but not in `adsl`, the new columns are NA for that row. If a USUBJID exists in `adsl` but not in `adae`, that row from adsl is *not* included.

This is the equivalent of:

```sas
proc sql;
  create table adae_with_trt as
  select a.*, b.trt01a, b.saffl
  from adae a
  left join (select usubjid, trt01a, saffl from adsl) b
  on a.usubjid = b.usubjid;
quit;
```

`left_join` is what you reach for 80% of the time in clinical work, because you almost always want to preserve the "main" dataset on the left.

### `inner_join()` — keep only matches

```r
# Only AE records for subjects in the safety population
adae_safety <- adae |>
  inner_join(
    adsl |> filter(SAFFL == "Y") |> select(USUBJID, TRT01A),
    by = "USUBJID"
  )
```

Rows where USUBJID doesn't exist in *both* datasets are dropped. Useful when you want to restrict by population, though `semi_join` (below) is often cleaner.

### `right_join()` — like left_join but mirror-imaged

Rarely used. If you find yourself reaching for it, swap the order of arguments and use `left_join`. It's a more readable equivalent.

### `full_join()` — keep everything from both sides

```r
adsl |>
  full_join(adae, by = "USUBJID")
```

Every USUBJID from both datasets appears in the output. Rows that don't have a match in the other side get NA for those columns. Useful for reconciliation tasks ("which subjects in DM don't have any AEs, and which AE records lack a corresponding DM row?").

### `semi_join()` — filter by existence in another table

```r
# AE records for subjects in the safety population — but don't add any columns
adae_safety <- adae |>
  semi_join(
    adsl |> filter(SAFFL == "Y"),
    by = "USUBJID"
  )
```

`semi_join` does the same filtering as `inner_join` but **doesn't add any columns from the right side**. It's the cleanest way to say "keep rows of X where the key exists in Y."

The SAS equivalent — there isn't a clean one; you'd typically do a PROC SQL subquery or a hash lookup.

### `anti_join()` — the opposite of semi_join

```r
# AE records whose subjects are NOT in the safety population
adae_not_safety <- adae |>
  anti_join(
    adsl |> filter(SAFFL == "Y"),
    by = "USUBJID"
  )
```

`anti_join` is excellent for QC ("which AE records are orphans without a DM row?"). It's far cleaner than the SAS pattern of merging, then keeping rows where the right side's variables are missing.

## 3. Visual mental model

```
  left      right
  ┌──┐      ┌──┐
  │A │      │A │
  │B │      │C │
  └──┘      └──┘

left_join:    A (matched), B (unmatched, NA filled)
inner_join:   A only
full_join:    A (matched), B (unmatched, NA filled), C (unmatched, NA filled)
semi_join:    A from left
anti_join:    B from left
```

For clinical work, ~80% of joins are `left_join`, ~10% are `semi_join` or `anti_join`, the rest divide among `inner_join` and `full_join`.

## 4. Joining on differently-named columns

Sometimes the key column has a different name in each dataset:

```r
# adsl has USUBJID; adae also has USUBJID — same name, easy
left_join(adsl, adae, by = "USUBJID")

# If they were differently named:
left_join(adsl, adae, by = c("USUBJID" = "SUBJECT_ID"))

# Modern syntax with join_by():
left_join(adsl, adae, by = join_by(USUBJID == SUBJECT_ID))
```

`join_by()` (from dplyr 1.1+) is the modern syntax and supports inequality joins:

```r
# Join AE records with concomitant medication where AE started during med exposure
adae |>
  left_join(
    adcm,
    by = join_by(USUBJID, ASTDT >= CMSTDT, ASTDT <= CMENDT)
  )
```

This is a feature SAS PROC SQL has but DATA-step MERGE does not. dplyr makes it readable.

## 5. The most common join problem: many-to-many fanout

You're joining DM (1 row per subject) to AE (many rows per subject). The result has many rows per subject — that's expected and fine.

But suppose you join two many-to-many datasets:

```r
df_a   # 3 rows per subject (visit-level)
df_b   # 5 rows per subject (lab-level)

left_join(df_a, df_b, by = "USUBJID")
# Result: 15 rows per subject — the Cartesian product per key
```

This explosive growth is called **fanout** or **many-to-many fanout**. It's almost always a bug — either you forgot to include another key (like VISITNUM), or one dataset has duplicates you didn't expect.

dplyr 1.1+ explicitly warns when a join produces many-to-many results:

```
Warning: Detected an unexpected many-to-many relationship between `x` and `y`.
```

To silence the warning when many-to-many is intentional, use `relationship = "many-to-many"`. To raise an error on unexpected fanout, use `relationship = "one-to-one"`, `"one-to-many"`, or `"many-to-one"`:

```r
# Will error if fanout is not strictly one ADAE row to one ADSL row
adae |>
  left_join(adsl, by = "USUBJID", relationship = "many-to-one")
```

Use this aggressively in production code. Catching unexpected fanout at the join is far cheaper than discovering it three derivations later.

## 6. Diagnosing key mismatches

If a left_join produces unexpectedly NA columns, the key isn't matching. Common causes:

- **Whitespace** in one but not the other: `"01-001"` vs `"01-001 "`
- **Type mismatch**: `STUDYID` is character in one, factor in another
- **Case sensitivity**: `"a"` vs `"A"`
- **Missing leading zeros**: `"01-1"` vs `"01-001"`

Quick diagnostics:

```r
# Which keys are missing from the right side?
adae |>
  anti_join(adsl, by = "USUBJID") |>
  distinct(USUBJID)

# Check types
class(adae$USUBJID)
class(adsl$USUBJID)

# Whitespace check
adae$USUBJID |> trimws() |> head()
```

In SAS, missing key matches are diagnosed by reading the log. In R, `anti_join` is the tool — make it part of your QC habit.

## 7. dbplyr: dplyr against a database

Many clinical organizations store SDTM in databases (Oracle, SQL Server, PostgreSQL). `{dbplyr}` lets you write the *same dplyr code* against a database table, and it translates to SQL behind the scenes.

```r
library(DBI)
library(dbplyr)
library(dplyr)

# Connect to a database
con <- dbConnect(odbc::odbc(), "ClinicalDB")

# Reference a table (no data pulled yet)
ae_db <- tbl(con, "AE_SDTM")

# Write dplyr — it generates SQL, runs server-side
result <- ae_db |>
  filter(AESER == "Y") |>
  group_by(USUBJID) |>
  summarise(n_serious_ae = n()) |>
  collect()           # only now does data come into R
```

The advantage: you can prototype dplyr against a small in-memory tibble, then point the same code at a 100-million-row database table and have the heavy lifting happen on the database. SAS programmers will recognize this pattern from PROC SQL pass-through.

You don't *need* dbplyr for pharmaverse work — most clinical R workflows operate on extracted XPT files in memory — but it's worth knowing it exists for large-scale pre-processing.

## 8. Writing your own functions

R's `function` keyword is the analog of SAS's `%macro`. The basic shape:

```r
my_function <- function(x, y) {
  result <- x + y
  return(result)
}

my_function(3, 4)    # 7
```

A few things to notice:

- **No explicit `length`/`format` for arguments.** Types are dynamic.
- **No `OUTPUT` statement equivalent.** The last evaluated expression is the return value. You can write `return(result)` explicitly, but `result` on the last line works too.
- **No `%let` / `&var.` interpolation needed.** Arguments are just regular R objects.

```r
# Cleaner version of the above
my_function <- function(x, y) {
  x + y
}
```

The function returns whatever its last expression evaluates to. This is idiomatic R.

### Functions are first-class objects

Unlike SAS macros, R functions are **values** — you can pass them to other functions, store them in lists, return them from functions, etc.

```r
# Apply a function to many columns
adsl |>
  summarise(across(c(AGE, HEIGHTBL, WEIGHTBL), mean, na.rm = TRUE))

# Pass a function as an argument
adsl |>
  summarise(across(c(AGE, HEIGHTBL, WEIGHTBL), my_function))
```

This is what enables `purrr::map`, `lapply`, and the entire functional-programming style — possible because functions are values, not text-substitution macros.

### Default arguments

```r
summarise_age <- function(data, treatment_col = "TRT01A", round_to = 1) {
  data |>
    group_by(.data[[treatment_col]]) |>
    summarise(
      n = n(),
      mean_age = round(mean(AGE, na.rm = TRUE), round_to),
      sd_age = round(sd(AGE, na.rm = TRUE), round_to)
    )
}

summarise_age(adsl)                       # uses defaults
summarise_age(adsl, round_to = 2)         # override one
summarise_age(adsl, "TRT02A", 0)          # override both
```

The `.data[[col]]` syntax handles passing column names as strings — a common pattern in clinical helper functions.

### The `...` (dot-dot-dot) argument

`...` captures arbitrary extra arguments and passes them to inner functions. Pharmaverse uses this everywhere:

```r
my_summary <- function(data, group, ...) {
  data |>
    group_by({{ group }}) |>
    summarise(n = n(), ...)            # ... passes through to summarise
}

my_summary(adsl,
           group = TRT01A,
           mean_age = mean(AGE, na.rm = TRUE),
           median_age = median(AGE, na.rm = TRUE))
```

The `{{ }}` ("curly-curly") syntax handles passing column names without quotes — this is the modern way to write dplyr-aware functions. We'll see it constantly in pharmaverse source code.

## 9. R functions vs SAS macros — why R wins

SAS macros are essentially **text substitution.** You write `%macro foo(var); ...; %mend;`, call `%foo(age)`, and SAS pastes the text in. This is powerful but has well-known pitfalls:

- Macro variables and data variables are in different namespaces — easy to confuse
- Quoting and escaping (`%STR`, `%NRSTR`) is famously tricky
- Debugging "what did the macro actually expand to?" requires `MPRINT` and careful log reading
- Macros don't return values cleanly — you use `&` references or output datasets

R functions are **proper functions**:

- Arguments are real R objects, evaluated in the function's environment
- You can return any R object — number, dataset, list, plot, function
- Debugging is the same as for any other code — set breakpoints, step through
- Composition is natural: `g(f(x))`, or `x |> f() |> g()`
- They participate in functional programming (map, reduce, etc.)

The mental shift from SAS macros to R functions is one of the most freeing parts of moving to R. Once you internalize it, you'll write more functions, write them sooner, and your code will be far more reusable.

## 10. Anonymous functions

Sometimes you need a function for exactly one use. R 4.1+ gives you a short syntax:

```r
# Long form
add_one <- function(x) x + 1

# Anonymous, full form
function(x) x + 1

# Anonymous, short form (R 4.1+)
\(x) x + 1
```

The backslash `\` is the keyword. These are everywhere in modern R:

```r
adsl |>
  summarise(across(where(is.numeric),
                   \(x) mean(x, na.rm = TRUE)))
```

The older `~` formula syntax does the same with purrr:

```r
adsl |>
  summarise(across(where(is.numeric), ~ mean(.x, na.rm = TRUE)))
```

Both are common. The `\(x)` form is the modern preference because it's pure base R and reads more clearly.

## 11. `purrr::map()` — iteration without loops

In SAS, you'd write a macro loop:

```sas
%macro loop_visits;
  %do i = 1 %to 10;
    proc means data=adlb(where=(avisitn=&i.)); ... ; run;
  %end;
%mend;
```

In R, you don't loop — you map a function over a vector:

```r
library(purrr)

visits <- 1:10
results <- map(visits, function(v) {
  adlb |>
    filter(AVISITN == v) |>
    summarise(mean_aval = mean(AVAL, na.rm = TRUE))
})
```

`map()` applies a function to each element and returns a list. Variations return specific types:

- `map_dbl()` returns a numeric vector
- `map_chr()` returns a character vector
- `map_lgl()` returns a logical vector
- `map_dfr()` returns a data frame (row-bound)

For the visit-by-visit means returning a single data frame:

```r
results <- map_dfr(1:10, \(v) {
  adlb |>
    filter(AVISITN == v) |>
    summarise(visit = v, mean_aval = mean(AVAL, na.rm = TRUE))
})
```

This produces a 10-row tibble with visit and mean_aval.

Most of the time, you don't need `map()` for clinical work — `group_by()` handles the most common "for each X, do Y" pattern. But for cross-cutting iteration (multiple datasets, multiple files, multiple model fits), `map()` is invaluable.

## 12. Putting it together: a derivation function

Let's write a function that derives a "subject summary" combining info from multiple datasets:

```r
derive_subject_summary <- function(adsl, adae, adlb) {
  # Count AEs per subject
  ae_counts <- adae |>
    group_by(USUBJID) |>
    summarise(
      n_ae = n(),
      n_ser_ae = sum(AESER == "Y", na.rm = TRUE),
      .groups = "drop"
    )

  # Worst hemoglobin per subject
  hgb_worst <- adlb |>
    filter(PARAMCD == "HGB") |>
    group_by(USUBJID) |>
    summarise(
      hgb_min = min(AVAL, na.rm = TRUE),
      .groups = "drop"
    )

  # Combine
  adsl |>
    filter(SAFFL == "Y") |>
    left_join(ae_counts, by = "USUBJID") |>
    left_join(hgb_worst, by = "USUBJID") |>
    mutate(
      n_ae = replace_na(n_ae, 0),
      n_ser_ae = replace_na(n_ser_ae, 0)
    ) |>
    select(USUBJID, TRT01A, AGE, SEX, n_ae, n_ser_ae, hgb_min)
}

# Use it
summary_df <- derive_subject_summary(adsl, adae, adlb)
```

Note three things:

1. The function takes its inputs as arguments — no global-variable dependence
2. It composes smaller operations (count AEs, find worst HGB, join, fill NAs)
3. It's testable — you can call it with controlled inputs and check the output

This is the R-function style you'll see throughout pharmaverse source code.

## 13. SAS macros → R functions cheat sheet

| SAS macro pattern | R function equivalent |
|---|---|
| `%macro foo(var)` | `foo <- function(var)` |
| `&var.` (substitution) | Just `var` (it's a variable) |
| `%let x = 5;` | `x <- 5` |
| `%if cond %then ... %else ...;` | `if (cond) ... else ...` |
| `%do i = 1 %to 10;` | `for (i in 1:10)` or `map(1:10, \(i) ...)` |
| `%sysfunc(mean(x))` | `mean(x)` (just call it) |
| Multiple datasets in/out | Return a list, or take multiple args |
| `%global / %local` | Function arguments + return values; no need |
| Debug with `MPRINT` | Just step through with the debugger |

## 14. Key takeaways

- Dplyr joins (`left_join`, `inner_join`, `anti_join`, etc.) cover every PROC SQL pattern more readably
- `anti_join` is your QC friend — find rows with missing matches
- Many-to-many fanout is the most common join bug; use `relationship = "..."` to assert expectations
- `dbplyr` lets dplyr write SQL for you when working against a real database
- R functions replace SAS macros and are strictly better — first-class, type-flexible, composable
- The `{{ }}` ("curly-curly") syntax handles dplyr-aware function arguments
- `purrr::map()` replaces SAS macro loops with cleaner, type-safe iteration

## 15. What's next

Lesson 06 wraps the R foundations module with the **broader tidyverse**: reshaping data with `tidyr` (pivot_longer, pivot_wider — the equivalents of PROC TRANSPOSE), separating and uniting columns, and the date/time handling in `lubridate`. After Lesson 06, you have everything you need to start working with pharmaverse packages — beginning with `pharmaverseraw` and SDTM building in Module 2.

---

## Self-check questions

1. Translate this PROC SQL to dplyr: `select a.*, b.trt01a from adae a left join adsl b on a.usubjid = b.usubjid where b.saffl = "Y";`
2. What does `anti_join` do, and what's it good for?
3. Why are R functions "strictly better" than SAS macros?
4. What does the `\(x) x + 1` syntax mean?
5. Translate to dplyr: "find subjects in DM who have no AE record."
6. What's the difference between `purrr::map()` and `purrr::map_dfr()`?

## Glossary

- **Join key** — The column(s) used to match rows between two datasets
- **Many-to-many fanout** — When joining two datasets each with duplicate keys, producing an explosion of rows
- **`semi_join`** — Filtering join: keep rows of X where key exists in Y, without adding columns
- **`anti_join`** — Filtering join: keep rows of X where key does NOT exist in Y
- **`dbplyr`** — dplyr backend that translates to SQL for database queries
- **First-class object** — A value that can be passed, returned, and stored like any other (functions in R)
- **`{{ }}` (curly-curly)** — Tidy-evaluation syntax for passing column names to dplyr-aware functions
- **`purrr`** — Tidyverse package for functional programming and iteration
