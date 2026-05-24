# Lesson 04 — R Primer for SAS Programmers, Part 2: The DATA Step in dplyr

**Module**: 1 — R foundations for SAS programmers
**Estimated length**: ~30 min spoken
**Prerequisites**: Lesson 03 (R primer Part 1)

---

## Learning objectives

By the end of this lesson, you will be able to:

1. Use the five core dplyr verbs — `filter`, `select`, `mutate`, `summarise`, `arrange` — to translate any SAS DATA step
2. Apply `group_by()` for BY-group processing, replacing SAS's `BY` and `BY...PROCESSED` statements
3. Replicate FIRST./LAST. dot logic in dplyr
4. Use `case_when()` for complex conditional assignment (the clean alternative to nested ifelse)
5. Replicate RETAIN and LAG behavior with `lag()`, `lead()`, `cumsum()`, and `cummax()`
6. Recognize and use dplyr's "across" pattern for applying operations to many columns at once

---

## 1. Why dplyr exists

`{dplyr}` is the workhorse of tidyverse data manipulation. It's not officially part of pharmaverse, but it's a hard dependency of nearly every pharmaverse package, and you'll write more dplyr code in a typical clinical R script than any other library — probably more than all pharmaverse packages combined.

The motivation: base R's data manipulation is powerful but verbose. dplyr provides **five small verbs** that, combined, cover almost everything you used to do in the SAS DATA step:

| dplyr verb | SAS equivalent | What it does |
|---|---|---|
| `filter()` | `where` / subsetting `if` | Keep rows that meet a condition |
| `select()` | `keep` / `drop` | Keep, drop, or reorder columns |
| `mutate()` | assignment statements | Add or modify columns |
| `summarise()` | `proc means`, `proc summary` | Reduce data to summary statistics |
| `arrange()` | `proc sort` | Reorder rows |

Combined with `group_by()` (the BY statement) and the pipe `|>`, these five verbs handle 90%+ of clinical data manipulation.

Load dplyr:

```r
library(dplyr)
```

For this lesson, we'll use the `adsl` and `adae` datasets from `{pharmaverseadam}`:

```r
library(pharmaverseadam)
data("adsl")
data("adae")
```

## 2. `filter()` — the WHERE clause

`filter()` keeps rows that match a condition. Multiple conditions can be combined.

SAS:
```sas
data result;
  set adsl;
  where saffl = "Y" and age >= 65;
run;
```

dplyr:
```r
result <- adsl |>
  filter(SAFFL == "Y", AGE >= 65)
```

A few things to notice:

**Commas mean AND.** `filter(A, B)` is equivalent to `filter(A & B)`. Multiple commas chain conditions.

**For OR, use `|`.** Not `or` — `|`.

```r
adsl |>
  filter(SAFFL == "Y" | EFFFL == "Y")
```

**Use `%in%` for "in a list of values".** This is dplyr's equivalent of SAS's `var in ("A", "B", "C")`:

```r
adsl |>
  filter(TRT01A %in% c("Placebo", "Xanomeline Low Dose"))
```

**For "not in", negate the `%in%`:**

```r
adsl |>
  filter(!(TRT01A %in% c("Placebo")))     # everyone NOT on placebo
```

**Filtering on missingness:**

```r
adae |>
  filter(!is.na(AESEV))            # rows where AESEV is not missing
```

**Common gotcha**: filter drops rows where the condition is `NA` (not just `FALSE`). This is usually what you want, but it can surprise you. To explicitly keep NA rows:

```r
adsl |>
  filter(AGE >= 65 | is.na(AGE))
```

## 3. `select()` — KEEP and DROP, and more

`select()` chooses, drops, and reorders columns.

```r
# Keep specific columns (like SAS keep)
adsl |>
  select(USUBJID, AGE, SEX, TRT01A)

# Drop specific columns (like SAS drop) — use minus
adsl |>
  select(-STUDYID, -SITEID)

# Reorder: variables appear in the listed order
adsl |>
  select(USUBJID, TRT01A, everything())   # USUBJID and TRT01A first, then all others

# By range (like SAS var1--var5, but with names)
adsl |>
  select(USUBJID:TRT01A)

# By column type
adsl |>
  select(where(is.numeric))               # all numeric columns

# By naming pattern
adsl |>
  select(starts_with("TRT"))              # all columns starting with TRT
adsl |>
  select(ends_with("FL"))                 # all flag columns
adsl |>
  select(contains("DT"))                  # all date-related columns
adsl |>
  select(matches("^A.*FL$"))              # regex: starts with A, ends with FL
```

The `starts_with()` / `ends_with()` / `contains()` / `matches()` family is called **tidyselect helpers**. They make selecting groups of related variables much cleaner than SAS's variable lists.

Also useful: `rename()` to rename without dropping:

```r
adsl |>
  rename(treatment = TRT01A,
         subject_id = USUBJID)
```

And `relocate()` to move columns:

```r
adsl |>
  relocate(USUBJID, .before = STUDYID)
adsl |>
  relocate(TRT01A, .after = USUBJID)
```

## 4. `mutate()` — assignment statements, vectorized

`mutate()` adds new columns or modifies existing ones.

```r
adsl |>
  mutate(
    AGE_GROUP = ifelse(AGE < 65, "<65", ">=65"),
    AGE_MONTHS = AGE * 12,
    SEX_LOWER = tolower(SEX)
  )
```

You can refer to columns just created in the same `mutate()` call:

```r
adsl |>
  mutate(
    AGE_GROUP = ifelse(AGE < 65, "<65", ">=65"),
    AGE_GROUP_LABEL = paste0("Group: ", AGE_GROUP)
  )
```

Compare to SAS:

```sas
data adsl_with_group;
  set adsl;
  length AGE_GROUP $ 5 AGE_GROUP_LABEL $ 20;
  if age < 65 then AGE_GROUP = "<65";
  else AGE_GROUP = ">=65";
  AGE_GROUP_LABEL = "Group: " || AGE_GROUP;
run;
```

The dplyr version is shorter and doesn't require `length` declarations.

To **modify in place**, just assign to the same name:

```r
adsl |>
  mutate(USUBJID = trimws(USUBJID))      # trim whitespace
```

To **drop**, set to `NULL`:

```r
adsl |>
  mutate(USELESS_COL = NULL)
```

## 5. `case_when()` — the clean alternative to nested ifelse

For multi-condition logic, `case_when()` is far cleaner than nested `ifelse()`:

```r
adsl |>
  mutate(
    AGE_CAT = case_when(
      AGE <  18 ~ "Pediatric",
      AGE <  65 ~ "Adult",
      AGE >= 65 ~ "Elderly",
      TRUE ~ NA_character_       # catch-all (covers NA AGE)
    )
  )
```

Read it as: "When AGE < 18, assign 'Pediatric'; when AGE < 65, assign 'Adult'; etc."

Compare to SAS:

```sas
data adsl_cat;
  set adsl;
  length AGE_CAT $ 10;
  if age < 18 then AGE_CAT = "Pediatric";
  else if age < 65 then AGE_CAT = "Adult";
  else if age >= 65 then AGE_CAT = "Elderly";
  else AGE_CAT = "";
run;
```

Key features of `case_when()`:

- Conditions are evaluated in order; first match wins
- `TRUE ~ value` is the catch-all (like SAS's bare `else`)
- The default — when no condition matches and no catch-all is given — is `NA`
- Always make the RHS values the **same type**. `case_when(... ~ "A", ... ~ 1)` will error or coerce. Use explicit `NA_character_`, `NA_real_`, etc. for missing values

For binary cases, `if_else()` (note: with underscore, not `ifelse`) is the type-strict version:

```r
adsl |>
  mutate(IS_ADULT = if_else(AGE >= 18, "Adult", "Minor"))
```

`if_else()` requires both branches to be the same type. `ifelse()` (no underscore) is base R, more permissive but can silently coerce types — leading to bugs. **Prefer `if_else()` for clinical code.**

## 6. `arrange()` — PROC SORT

```r
adsl |>
  arrange(USUBJID)                       # ascending by USUBJID

adsl |>
  arrange(desc(AGE))                     # descending by AGE

adsl |>
  arrange(USUBJID, desc(AGE))            # USUBJID asc, then AGE desc
```

This is identical to SAS PROC SORT, but inline and with the pipe-able interface.

Important: **dplyr does NOT require pre-sorting for group operations.** In SAS, you must `proc sort by ... ; data ... ; by ...; run;` Sort + DATA step BY combinations are everywhere. In dplyr, `group_by()` handles this internally. You only need `arrange()` if the final *output* needs to be in a specific order, or if a downstream operation (like `lag()` or `first()`) depends on row order.

## 7. `summarise()` — PROC MEANS, PROC SUMMARY, PROC FREQ

`summarise()` collapses many rows down to one (or a few).

```r
# Mean age of safety population
adsl |>
  filter(SAFFL == "Y") |>
  summarise(mean_age = mean(AGE, na.rm = TRUE))
```

Multiple statistics at once:

```r
adsl |>
  filter(SAFFL == "Y") |>
  summarise(
    n = n(),
    mean_age = mean(AGE, na.rm = TRUE),
    sd_age = sd(AGE, na.rm = TRUE),
    median_age = median(AGE, na.rm = TRUE),
    min_age = min(AGE, na.rm = TRUE),
    max_age = max(AGE, na.rm = TRUE)
  )
```

Returns a single-row tibble. Compare to:

```sas
proc means data=adsl(where=(saffl="Y")) n mean std median min max;
  var age;
run;
```

**Critical: `na.rm = TRUE`.** R's default for `mean()`, `sd()`, etc. is to return `NA` if any input is `NA`. This is the safety-net default — it forces you to acknowledge missingness explicitly. In SAS, PROC MEANS silently ignores missing by default.

Always include `na.rm = TRUE` (or handle NA explicitly) when summarizing clinical data.

## 8. `group_by()` — BY-group processing

The real power of dplyr appears when you combine `group_by()` with `summarise()` or `mutate()`:

```r
# Mean age BY treatment
adsl |>
  filter(SAFFL == "Y") |>
  group_by(TRT01A) |>
  summarise(
    n = n(),
    mean_age = mean(AGE, na.rm = TRUE),
    sd_age = sd(AGE, na.rm = TRUE)
  )
```

This produces one row per treatment group with the requested summaries — exactly what you want for a demographics table.

SAS equivalent:

```sas
proc sort data=adsl; by trt01a; run;
proc means data=adsl(where=(saffl="Y")) n mean std;
  by trt01a;
  var age;
  output out=demog_summary n=n mean=mean_age std=sd_age;
run;
```

Notice the dplyr version is shorter, doesn't require pre-sorting, and produces a tidy tibble directly usable in further analyses.

You can group by multiple variables:

```r
adsl |>
  filter(SAFFL == "Y") |>
  group_by(TRT01A, SEX) |>
  summarise(n = n(), mean_age = mean(AGE, na.rm = TRUE))
```

This produces one row per `(TRT01A, SEX)` combination.

**Important**: After `summarise()`, dplyr automatically removes the last grouping level. After multi-level grouping, you'll often want to `ungroup()` explicitly to be safe:

```r
adsl |>
  group_by(TRT01A, SEX) |>
  summarise(n = n(), .groups = "drop")    # drop all grouping after summarise
```

Or globally use `.groups = "drop"` in every summarise call — it's a defensive habit worth adopting.

## 9. `group_by()` + `mutate()` — RETAIN-like behavior

The combination of `group_by()` and `mutate()` doesn't collapse rows — it adds a column computed within each group:

```r
# Mean age within each treatment, kept on every row
adsl |>
  group_by(TRT01A) |>
  mutate(mean_age_by_trt = mean(AGE, na.rm = TRUE)) |>
  ungroup()
```

Each row in the output has `mean_age_by_trt` equal to the mean age of its treatment group. This is the equivalent of SAS's RETAIN + BY pattern.

Example for clinical work: flag the highest dose received per subject from ADCM:

```r
# Pretend adcm has CMTRT and CMDOSE
adcm |>
  group_by(USUBJID) |>
  mutate(MAX_DOSE = max(CMDOSE, na.rm = TRUE)) |>
  ungroup()
```

Every row for a given USUBJID now has the same `MAX_DOSE` value.

## 10. FIRST./LAST. — the dot logic

In SAS, `first.var` and `last.var` are crucial for clinical work — flagging the first or last record per subject, per visit, etc.

In dplyr, you achieve this with `row_number()`, `n()`, or `slice_*()`:

```r
# First record per USUBJID (assumes already in desired order)
adae |>
  arrange(USUBJID, AESTDTC) |>
  group_by(USUBJID) |>
  slice(1) |>                  # the first row in each group
  ungroup()

# Last record per USUBJID
adae |>
  arrange(USUBJID, AESTDTC) |>
  group_by(USUBJID) |>
  slice(n()) |>                # n() returns the group size; slice n = last
  ungroup()
```

Cleaner alternatives:

```r
adae |>
  group_by(USUBJID) |>
  slice_min(AESTDTC, n = 1, with_ties = FALSE) |>    # first by date
  ungroup()

adae |>
  group_by(USUBJID) |>
  slice_max(AESTDTC, n = 1, with_ties = FALSE) |>    # last by date
  ungroup()
```

`slice_min()` and `slice_max()` are cleaner because they don't depend on pre-sorting — they pick the row(s) with the min/max value of the named column.

**To flag (not subset) first/last**, use `row_number()`:

```r
adae |>
  arrange(USUBJID, AESTDTC) |>
  group_by(USUBJID) |>
  mutate(
    AEFIRST = row_number() == 1,
    AELAST = row_number() == n()
  ) |>
  ungroup()
```

This adds two logical columns to every row, like SAS's `first.usubjid` and `last.usubjid` flags.

## 11. `lag()` and `lead()` — looking backward and forward

SAS programmers use the LAG function constantly for visit-to-visit comparisons. In dplyr:

```r
# Compare each visit to the previous visit
adlb |>
  arrange(USUBJID, AVISITN) |>
  group_by(USUBJID) |>
  mutate(
    AVAL_PREV = lag(AVAL),                    # previous AVAL within subject
    CHG_FROM_PREV = AVAL - AVAL_PREV,         # change from previous visit
    AVAL_NEXT = lead(AVAL)                    # next AVAL within subject
  ) |>
  ungroup()
```

Critical differences from SAS LAG:

- **dplyr `lag()` respects groups.** Within each USUBJID, the lag is bounded; you don't accidentally pick up the last value from the previous subject.
- **SAS LAG is positional** — it returns the value from the previous time you *called* it, which is famously confusing. dplyr `lag()` always returns the row above.

This alone makes dplyr's `lag()` worth the switch.

## 12. Cumulative functions — `cumsum`, `cummax`, `cummin`

Useful for derivations like "worst toxicity grade to date" or "cumulative dose":

```r
# Worst lab grade to date per subject
adlb |>
  arrange(USUBJID, ADT) |>
  group_by(USUBJID) |>
  mutate(WORST_GRADE = cummax(ATOXGR)) |>
  ungroup()

# Cumulative dose per subject
adex |>
  arrange(USUBJID, EXSTDTC) |>
  group_by(USUBJID) |>
  mutate(CUM_DOSE = cumsum(EXDOSE)) |>
  ungroup()
```

These are vectorized and respect group_by, so they're far cleaner than the equivalent SAS DATA step with RETAIN and conditional logic.

## 13. `across()` — apply operations to many columns

A common pattern: convert all character columns to factors, or compute the mean of many numeric columns at once. dplyr's `across()` is the tool.

Apply a function to many columns at once:

```r
# Mean of all numeric columns, by treatment
adsl |>
  group_by(TRT01A) |>
  summarise(across(c(AGE, HEIGHTBL, WEIGHTBL),
                   ~ mean(.x, na.rm = TRUE)))

# Same, using a selection helper
adsl |>
  group_by(TRT01A) |>
  summarise(across(where(is.numeric),
                   ~ mean(.x, na.rm = TRUE),
                   .names = "mean_{.col}"))
```

The `~ mean(.x, na.rm = TRUE)` is shorthand for "apply this function." The `.x` is a placeholder for "the column."

`across()` is the dplyr replacement for what would have been verbose SAS code listing each variable separately. For clinical work, it's invaluable when you want to apply the same transformation to a family of variables (e.g., all baseline lab values).

## 14. Pulling it all together: a worked example

Let's build a small derivation. Goal:

> For the safety population, derive each subject's **maximum-severity AE** and its **start date**. Output one row per subject with USUBJID, TRT01A, maximum severity, and the date that severity first occurred.

In SAS, this is roughly:

```sas
proc sort data=adae out=adae_sorted; by usubjid aesevn aestdt; run;

data ae_worst;
  set adae_sorted;
  by usubjid;
  if last.usubjid;             /* keep the highest severity (sorted last) */
  keep usubjid aesev aestdt;
run;

proc sql;
  create table result as
  select a.usubjid, a.trt01a, b.aesev, b.aestdt
  from adsl a left join ae_worst b on a.usubjid = b.usubjid
  where a.saffl = "Y";
quit;
```

In dplyr:

```r
worst_ae <- adae |>
  group_by(USUBJID) |>
  slice_max(AESEVN, n = 1, with_ties = FALSE) |>
  ungroup() |>
  select(USUBJID, AESEV, AESTDT)

result <- adsl |>
  filter(SAFFL == "Y") |>
  left_join(worst_ae, by = "USUBJID") |>
  select(USUBJID, TRT01A, AESEV, AESTDT)
```

(We'll cover `left_join` properly in Lesson 05.) The dplyr version reads like the requirement statement, top to bottom.

## 15. The hidden gotcha: variable masking

A subtle bug worth knowing: inside dplyr verbs, column names are looked up *first* in the data frame, then in the surrounding R environment. If you have a variable in your R session with the same name as a column, dplyr uses the column.

```r
AGE <- 50
adsl |>
  filter(AGE > 60)        # filters by the column AGE, not the R variable
```

This is *usually* what you want, but if you genuinely meant to filter using an R variable, use `!!` (bang-bang) to unquote:

```r
threshold <- 60
adsl |>
  filter(AGE > !!threshold)    # explicit: use the R variable threshold
```

Or just use a different name. For the most part, this isn't a frequent issue in clinical code as long as you keep your R working-variable names distinct from CDISC column names (lowercase vs uppercase helps).

## 16. SAS → dplyr cheat sheet

| SAS pattern | dplyr equivalent |
|---|---|
| `where age > 50` | `filter(AGE > 50)` |
| `where var in ("A", "B")` | `filter(var %in% c("A", "B"))` |
| `keep var1 var2` | `select(var1, var2)` |
| `drop var1` | `select(-var1)` |
| `rename old=new` | `rename(new = old)` |
| `proc sort by var` | `arrange(var)` |
| `proc sort by descending var` | `arrange(desc(var))` |
| Assignment in DATA step | `mutate(new = expression)` |
| Nested if/then/else | `case_when(...)` |
| `proc means by group` | `group_by() |> summarise()` |
| RETAIN within BY group | `group_by() |> mutate()` |
| `first.var` flag | `group_by() |> mutate(first = row_number() == 1)` |
| `last.var` flag | `group_by() |> mutate(last = row_number() == n())` |
| `if first.var` (subset) | `group_by() |> slice(1)` or `slice_min()` |
| `if last.var` (subset) | `group_by() |> slice(n())` or `slice_max()` |
| LAG function | `lag(var)` (group-aware) |
| RETAIN cumulative | `cumsum()`, `cummax()`, etc. |

## 17. Key takeaways

- The five core dplyr verbs — `filter`, `select`, `mutate`, `summarise`, `arrange` — plus `group_by()` cover most DATA-step patterns
- `case_when()` is the clean alternative to nested `ifelse()` — and `if_else()` is the type-strict binary version
- Always use `na.rm = TRUE` when summarizing — R defaults to NA-propagation, unlike SAS
- `group_by() + summarise()` collapses rows; `group_by() + mutate()` keeps rows but computes within groups (the RETAIN equivalent)
- For FIRST./LAST. logic, use `slice_min()`, `slice_max()`, or `row_number()` patterns
- `lag()` and `lead()` are group-aware — safer than SAS's LAG
- `across()` lets you apply operations to many columns at once

## 18. What's next

Lesson 05 covers **joins, SQL, and writing your own functions** — translating PROC SQL queries and SAS macros into their R equivalents. You'll learn `left_join`, `inner_join`, `anti_join`, the `dbplyr` SQL bridge, and how R functions compare to and improve on SAS macros.

After Lesson 05, you'll have everything needed to read pharmaverse source code fluently.

---

## Self-check questions

1. Translate this SAS code to dplyr: `data result; set adsl; where saffl="Y" and age >= 65; agegrp = ifelse(age < 75, "65-74", "75+"); run;`
2. What's the difference between `if_else()` and `ifelse()`?
3. How do you replicate `if last.usubjid then output;` in dplyr?
4. Why do you almost always need `na.rm = TRUE` when summarizing?
5. What's the difference between `group_by() |> summarise()` and `group_by() |> mutate()`?
6. Translate to dplyr: "for each subject, flag the highest visit number".

## Glossary

- **dplyr verb** — One of `filter`, `select`, `mutate`, `summarise`, `arrange`, `group_by` and friends
- **Grouped data frame** — A tibble with active grouping, set by `group_by()`
- **tidyselect helpers** — `starts_with()`, `ends_with()`, `contains()`, `matches()`, `where()`, `everything()`
- **`across()`** — Apply a function across multiple columns
- **`case_when()`** — Multi-condition vectorized assignment
- **`if_else()`** — Type-strict binary conditional assignment (preferred over base `ifelse()`)
- **`slice_min()` / `slice_max()`** — Pick rows with smallest/largest values of a column within a group
