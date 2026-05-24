# Lesson 39 — `{teal}` Part 1: Framework Architecture

**Module**: 8 — Interactive applications with Shiny and teal
**Estimated length**: ~25 min spoken
**Prerequisites**: Lesson 38 (Shiny foundations); Lessons 14-19 (admiral) for context

---

## Learning objectives

By the end of this lesson, you will be able to:

1. Explain teal's architecture: the relationship between teal, teal.data, teal.slice, teal.transform, teal.reporter, teal.code
2. Use `teal_data()` or `cdisc_data()` to wrap ADaM datasets for a teal app
3. Use `init()` to build a teal app with data + modules + filter panel
4. Apply `join_keys()` and `default_cdisc_join_keys` for relational ADaM data
5. Understand the reproducibility model: every teal app can output the R code that produced its current view
6. Recognize the filter panel — what it does, how it propagates, why it matters

---

## 1. What teal is

`{teal}` is Roche's open-source **Shiny framework for clinical data exploration**. It's not a single Shiny app — it's a system for assembling Shiny apps from pre-built modules with standardized infrastructure: data handling, filtering, reproducibility, and reporting.

The mental model:

```
Module: one analysis (demographics summary, K-M plot, AE table, …)
   ↓
teal app: a composition of modules with shared data, shared filters,
          shared reproducibility, shared reporting
```

A typical teal app has 5-20 modules: each module is a "page" the user clicks through. All modules share the same dataset, the same filter panel, and the same reporting system. Filter once, see consistent results across every module.

This is fundamentally different from rolling your own Shiny app: teal provides the **infrastructure** (data flow, filtering, code reproducibility) so module authors focus on **the analysis** (one specific table or plot type).

Origin: developed inside Roche starting ~2017, open-sourced 2022 as part of pharmaverse, now maintained as part of Roche's `insightsengineering` GitHub organization. Current stable: teal 0.x line, actively developed.

## 2. The teal package family

teal is not one package — it's six tightly-coupled packages, each handling one layer:

| Package | Role |
|---|---|
| **`teal`** | Main app framework: `init()`, module composition |
| **`teal.data`** | Data layer: `teal_data()`, `cdisc_data()`, `join_keys()` |
| **`teal.slice`** | Filter panel: dynamic filtering UI shared across modules |
| **`teal.transform`** | Variable selection helpers used inside modules |
| **`teal.code`** | Reproducibility: tracks the code executed to produce outputs |
| **`teal.reporter`** | Reporting: adds outputs to a downloadable PDF/Word report |
| **`teal.widgets`** | Common UI widgets used inside modules (encoding panels, etc.) |
| **`teal.logger`** | Logging input changes across the app for debugging/audit |

When you `library(teal)`, the others get loaded as dependencies for typical uses. You don't directly interact with most of them — they're internal to the framework.

For a basic teal app, you'll use functions from `teal` (`init()`, `modules()`) and `teal.data` (`teal_data()`, `cdisc_data()`). Everything else is plumbing.

## 3. Installation

```r
install.packages("teal")
install.packages("teal.modules.general")     # general modules
install.packages("teal.modules.clinical")    # clinical modules
install.packages("pharmaverseadam")           # test data
```

For development versions (latest features, less stable):

```r
install.packages("pak")
pak::pak("insightsengineering/teal@*release")
```

## 4. The minimum-viable teal app

The simplest possible teal app:

```r
library(teal)
library(pharmaverseadam)

# Step 1: wrap data
data <- teal_data(
  ADSL = pharmaverseadam::adsl,
  ADAE = pharmaverseadam::adae
)

# Step 2: define modules
mods <- modules(
  example_module()    # placeholder module
)

# Step 3: initialize the app
app <- init(
  data = data,
  modules = mods
)

# Step 4: run it
shinyApp(app$ui, app$server)
```

Running this opens a browser showing a single-tab app with the example module, plus the filter panel on the left side.

That's the entire pattern. Real apps differ from this only in:

- More datasets in `teal_data()`
- More modules (especially `tm_*` clinical modules) in `modules()`
- Optional configuration in `init()`

The framework handles everything else: filter UI, data flow, reproducibility, reporting.

## 5. `teal_data()` — the data wrapper

`teal_data()` creates a special environment that holds your datasets plus the code used to construct them. This is the reproducibility foundation.

Two ways to use it:

### Style A — direct assignment

```r
data <- teal_data(
  ADSL = pharmaverseadam::adsl,
  ADAE = pharmaverseadam::adae,
  ADLB = pharmaverseadam::adlb
)
```

Each named argument becomes a dataset in the teal app. Names should be ALL CAPS for CDISC datasets.

### Style B — using `within()` for executable code

```r
data <- within(teal_data(), {
  ADSL <- pharmaverseadam::adsl
  ADAE <- pharmaverseadam::adae
  # Custom derivations
  ADSL <- ADSL |> dplyr::filter(SAFFL == "Y")
})
```

Style B captures the **code** that produced the datasets, not just the data. This becomes important for reproducibility — the "Show R Code" button in modules will include this code.

Behind the scenes, `teal_data()` returns an object that:

- Inherits from R's `environment` class (so `$` access works: `data$ADSL`)
- Is **locked**: you can't modify datasets directly — must use `eval_code()` or `within()`
- Tracks the code used to construct each dataset

This locking is intentional. It prevents accidental data mutation during app runtime, which could break reproducibility.

## 6. `cdisc_data()` — the CDISC convenience wrapper

For CDISC datasets specifically, `cdisc_data()` is a wrapper around `teal_data()` that **auto-detects join keys**:

```r
data <- cdisc_data(
  ADSL = pharmaverseadam::adsl,
  ADAE = pharmaverseadam::adae,
  ADLB = pharmaverseadam::adlb
)
```

Equivalent to `teal_data()` plus automatic application of `default_cdisc_join_keys` which knows the standard CDISC primary/foreign keys for common ADaM datasets:

```r
default_cdisc_join_keys
# A named list mapping dataset pairs to their join keys
# e.g., ADSL → ADAE joined on c("STUDYID", "USUBJID")
# e.g., ADLB → ADSL parent on c("STUDYID", "USUBJID")
```

Why this matters: modules that need to join datasets (e.g., a K-M plot module that needs subject-level treatment from ADSL plus event dates from ADTTE) need to know how to join them. With `cdisc_data()`, you don't specify; teal infers from CDISC conventions.

For non-standard or custom join relationships, you can override:

```r
data <- teal_data(
  ADSL = my_adsl,
  CUSTOM_DATA = my_custom_data
)

join_keys(data) <- join_keys(
  join_key("CUSTOM_DATA", "ADSL", keys = c("STUDYID", "USUBJID"))
)
```

For most CSR-style apps with standard ADaMs, `cdisc_data()` works without configuration.

## 7. `init()` — the app constructor

`init()` takes the data and modules and produces the Shiny app objects:

```r
app <- init(
  data = data,
  modules = modules(...),
  title = "My Clinical App",
  filter = teal_slices(...),       # optional initial filters
  header = "Sponsor logo + title",
  footer = "Footer text"
)
```

Key arguments:

- `data`: the `teal_data` object
- `modules`: result of `modules(...)` wrapping individual module objects
- `title`: browser tab title
- `filter`: pre-configured filters via `teal_slices()` (next section)
- `header`/`footer`: HTML for top/bottom of app
- `landing_popup`: optional welcome modal (set via `add_landing_modal()`)

The return value is a list with `ui` and `server` elements, ready to pass to `shinyApp()`:

```r
shinyApp(app$ui, app$server)
```

For deployment, you'd save this in an `app.R` file with the same final call.

## 8. `modules()` — composing modules

`modules()` is a wrapper that combines individual module objects into a single argument for `init()`:

```r
mods <- modules(
  tm_data_table("Data View"),
  tm_variable_browser("Variables"),
  tm_g_distribution("Distribution"),
  tm_t_summary(
    "Demographics",
    dataname = "ADSL",
    arm_var = choices_selected(c("TRT01A", "TRT01P"), "TRT01A"),
    summarize_vars = choices_selected(c("AGE", "SEX", "RACE"), c("AGE", "SEX"))
  )
)
```

Each `tm_*` call returns a module object. `modules()` wraps them; `init(modules = mods)` consumes the wrapper. The order in `modules()` determines the order of tabs in the rendered app.

For larger apps, you can nest modules into groups:

```r
mods <- modules(
  modules(
    label = "Exploration",
    tm_variable_browser("Variables"),
    tm_data_table("Data View")
  ),
  modules(
    label = "Demographics",
    tm_t_summary("Summary"),
    tm_g_distribution("Plots")
  ),
  modules(
    label = "Safety",
    tm_t_events_summary("AE Overview"),
    tm_t_events("AE Detail")
  )
)
```

The result: top-level tab groups ("Exploration", "Demographics", "Safety") with sub-tabs inside each. This structure helps users navigate apps with many modules.

## 9. The filter panel

Every teal app has a **left-side filter panel** by default. The panel shows the variables available in each dataset; users add filters (e.g., "TRT01A == Placebo", "AGE > 65") and all modules respond.

The filter panel is provided by `{teal.slice}`. It's automatic — you don't write code to create it.

To **pre-configure** filters that apply when the app loads:

```r
app <- init(
  data = data,
  modules = mods,
  filter = teal_slices(
    teal_slice(dataname = "ADSL", varname = "SAFFL", selected = "Y"),
    teal_slice(dataname = "ADSL", varname = "AGE", selected = c(50, 80))
  )
)
```

This loads the app with SAFFL = "Y" and AGE between 50 and 80 already applied. Users can change or remove these.

To **hide** filters from the panel (so users can't change a specific filter):

```r
teal_slice(
  dataname = "ADSL",
  varname = "SAFFL",
  selected = "Y",
  fixed = TRUE        # cannot be changed by user
)
```

`fixed = TRUE` is useful for security-relevant filters (e.g., "only show data for studies the user has access to") or for filters baked into the app's purpose ("this is the safety-population dashboard, period").

## 10. Reproducibility: the "Show R Code" feature

teal's signature feature: every module has a **"Show R Code"** button (`</>` icon) that displays the R code that produced the current view. Users can copy this code into a script and reproduce the output offline.

This works because:

- `teal_data()` captures the data-loading code
- The filter panel captures the current filter state as code
- Each module knows the code template for its analysis
- teal combines all three into a single executable script

The output of "Show R Code" looks like:

```r
# Data
library(teal.data)
library(pharmaverseadam)
ADSL <- pharmaverseadam::adsl
ADAE <- pharmaverseadam::adae

# Filters
ADSL <- ADSL |> dplyr::filter(SAFFL == "Y")
ADAE <- ADAE |> dplyr::filter(SAFFL == "Y" & TRTEMFL == "Y")

# Module output
library(tern)
lyt <- basic_table() |>
  split_cols_by("ARM") |>
  analyze_vars(vars = c("AGE", "SEX"))
build_table(lyt, ADSL)
```

This is a real R script that can be saved, run offline, and produce the same result. For pharma, this is huge: study teams can use teal for exploration, then save the code that produced an insight, then run that code in a validated environment for the formal CSR table.

## 11. Reporting: building snapshots into a downloadable report

A related teal feature: users can **add outputs to a report** as they navigate. Then they download a single Word/PDF document containing all their snapshots.

Workflow:

1. User navigates to a module, configures inputs, sees an output
2. Clicks "Add to Report" button
3. teal captures the output as a snapshot
4. User can also add commentary text
5. Eventually, user clicks "Download Report" — receives a Word/PDF with all snapshots + commentary

This is enabled by `{teal.reporter}`. Modules built with reporter support automatically get the "Add to Report" button. Most pre-built teal modules support it.

For your own custom modules, you add reporter support via a few extra function calls — covered in Lesson 42.

## 12. The complete minimum app — expanded

Putting the concepts together:

```r
library(teal)
library(teal.modules.general)
library(teal.modules.clinical)
library(pharmaverseadam)

# Data — using cdisc_data for auto-join-keys
data <- cdisc_data(
  ADSL = pharmaverseadam::adsl,
  ADAE = pharmaverseadam::adae,
  ADLB = pharmaverseadam::adlb
)

# Modules — three real modules
mods <- modules(
  tm_data_table("Data View"),
  tm_variable_browser("Variable Browser"),
  tm_t_summary(
    label = "Demographics",
    dataname = "ADSL",
    arm_var = choices_selected(c("ARM", "ACTARM"), "ARM"),
    summarize_vars = choices_selected(c("AGE", "SEX", "RACE"), c("AGE", "SEX"))
  )
)

# Pre-configured filter for safety population
filters <- teal_slices(
  teal_slice(dataname = "ADSL", varname = "SAFFL", selected = "Y", fixed = TRUE)
)

# Build the app
app <- init(
  data = data,
  modules = mods,
  filter = filters,
  title = "My Study Explorer"
)

# Run
shinyApp(app$ui, app$server)
```

What this gives you:

- Three-tab app (Data View, Variable Browser, Demographics)
- Left filter panel showing ADSL/ADAE/ADLB variables
- SAFFL == "Y" fixed at top
- Show R Code button on every module
- Add to Report button on every module

About 30 lines of code. The reactivity, layout, filter UI, data joining, code-tracking, and reporting infrastructure all come from teal.

## 13. `data_extract_spec` — how modules select data

Inside modules, the **`data_extract_spec()` / `choices_selected()`** pattern is how you specify "this UI dropdown should let users choose among variables, with a default."

```r
arm_var = choices_selected(
  choices = c("ARM", "ACTARM", "TRT01A", "TRT01P"),
  selected = "ARM"
)
```

This produces a dropdown in the module with the four arm options, defaulting to "ARM". The user can change at runtime.

For more complex selection (e.g., choosing variables that exist in a specific dataset):

```r
arm_var = choices_selected(
  choices = variable_choices(data = ADSL, subset = c("ARM", "ACTARM", "TRT01A")),
  selected = "ARM"
)
```

`variable_choices()` introspects the dataset to find matching variables, with optional filtering. This is how pre-built modules like `tm_t_summary()` give users dynamic variable selection.

You'll see these helpers throughout teal.modules.clinical modules. They're the standard way to expose configurable parameters to the user.

## 14. Per-module vs app-wide filters

The filter panel is shared across all modules. But sometimes you want module-specific filters (e.g., "AE module should only show TRTEMFL = Y; demographics module shouldn't").

The pattern is to set filters at the module level using `transformators` or pre-filter the data before passing it to the module. teal's evolving APIs offer multiple ways:

- **App-wide filter panel**: user-controllable, applies to all modules
- **Pre-configured slices**: set at `init(filter = ...)`, applied at app load
- **Module-local filtering**: data subset applied within a specific module's logic
- **`transformators`**: functions that transform data per-module (newer teal API)

For most CSR-style apps, the app-wide filter panel handles 90% of cases. Module-local filtering is for the remaining 10% — typically safety-population vs ITT-population distinctions where different modules need different default populations.

## 15. Data updates and remote data sources

For long-lived apps that need to refresh data periodically (e.g., a study-team dashboard pulling fresh CDISC data nightly):

- Use `teal_data_module()` instead of static `teal_data()` — defines data loading as a Shiny module that runs at app startup
- Loads data from a database, file system, or API when the user logs in
- Re-runs on a schedule if needed

Pattern:

```r
data_module <- teal_data_module(
  ui = function(id) {
    actionButton(NS(id)("refresh"), "Refresh data")
  },
  server = function(id) {
    moduleServer(id, function(input, output, session) {
      eventReactive(input$refresh, {
        teal_data(
          ADSL = pull_latest("ADSL"),
          ADAE = pull_latest("ADAE")
        )
      })
    })
  }
)

app <- init(data = data_module, modules = mods)
```

For most teal apps, static data loading is sufficient. Reach for `teal_data_module()` only when you need refresh logic.

## 16. Validation and reproducibility

A key teal claim: every output is reproducible because the code is tracked. For GxP environments:

- **Output traceability**: any number in any table can be traced back to the R code that produced it (via Show R Code)
- **Filter history**: the filter state is part of the reproducibility output
- **Module versioning**: each `tm_*` module has a version pinned via its package (e.g., teal.modules.clinical 0.12)

This makes teal apps more validation-friendly than ad-hoc Shiny apps. For regulatory submissions, teal-produced *intermediate* analyses are increasingly accepted; final submission outputs still go through the static TLG pipeline (rtables/cards → RTF).

teal also produces a `teal_data` snapshot showing the full data pipeline. This snapshot can be exported alongside the report for audit purposes.

## 17. teal in a modern pharma workflow

Where teal fits:

```
Static TLG pipeline (validated, regulatory):
ADaM → cards/cardx (or tern) → gtsummary (or rtables) → RTF → CSR submission

Interactive layer (exploratory, complementary):
ADaM → teal app → in-app exploration → "Show R Code" → optional CSR table
```

Study teams use teal for "what do these data look like" before formal analyses. Medical reviewers use teal patient profiles to investigate cases. Biostatisticians use teal for ad-hoc subgroup analyses.

The CSR doesn't include screenshots of teal output. But the CSR is informed by teal-driven exploration. And ad-hoc analyses (FDA questions, post-hoc subgroup investigations) often start in teal and end in a static CSR-style table.

## 18. teal vs custom Shiny

Should you build a custom Shiny app or use teal?

**Use teal when:**

- Building clinical data exploration tools
- Users include study teams, medical reviewers, biostatisticians
- You want standard clinical modules (K-M, demographics, AE tables) without rebuilding
- Reproducibility/reporting/filtering infrastructure is valuable
- Multi-module composition matters

**Custom Shiny when:**

- Highly specific UI not matching teal's structure
- Non-clinical use cases (e.g., manufacturing dashboards)
- Single-purpose app where teal's infrastructure adds overhead
- Need integration with non-R systems where teal's R-centric model doesn't fit

Many teams use both: teal for clinical data exploration, custom Shiny for non-clinical or highly bespoke needs. teal doesn't replace Shiny — it's a structured way to use Shiny for clinical purposes.

## 19. Key takeaways

- `{teal}` is Roche's open-source clinical Shiny framework — a system for assembling apps from pre-built modules
- Six-package family: teal (main), teal.data, teal.slice, teal.transform, teal.code, teal.reporter — usually accessed via the main `teal` package
- Four-step pattern: `teal_data()` (or `cdisc_data()`) → `modules()` → `init()` → `shinyApp()`
- `cdisc_data()` auto-applies CDISC join keys; equivalent to teal_data() + manual `join_keys()` setup
- Filter panel is automatic, shared across modules, configurable via `teal_slices()`
- "Show R Code" exposes the reproducible R script for every view
- "Add to Report" lets users build a downloadable PDF/Word report from snapshots
- Modules are Shiny modules built on `{teal.widgets}` and `{teal.transform}`
- Complementary to static TLGs, not a replacement; teal is for exploration, static pipelines for submission

## 20. What's next

Lesson 40 covers **`{teal.modules.general}`** — the general-purpose teal modules: data viewers (table, variable browser, file viewer), visualizations (scatterplots, distributions, bivariate plots), and exploratory analyses (PCA, regression, association). These work with any data — CDISC or not — and form the foundation for many initial-exploration teal apps.

After teal.modules.general comes teal.modules.clinical (Lesson 41) — the clinical-specific modules implementing standard CSR analyses interactively. Then custom modules + deployment + validation (Lesson 42).

---

## Self-check questions

1. What does `{teal}` add on top of plain Shiny?
2. What's the difference between `teal_data()` and `cdisc_data()`?
3. What does the "Show R Code" feature produce, and why does it matter for pharma?
4. How would you pre-load a teal app with a SAFFL = "Y" filter that users can't change?
5. Translate to teal: "Build an app with ADSL + ADAE, two modules (demographics and AE overview), with a pre-set filter for safety population."
6. When does teal complement static TLGs vs replace them?

## Glossary

- **`{teal}`** — Roche's open-source Shiny framework for clinical data exploration
- **`{teal.data}`** — Data wrapper layer
- **`{teal.slice}`** — Filter panel
- **`{teal.transform}`** — Variable selection helpers
- **`{teal.code}`** — Reproducibility tracking
- **`{teal.reporter}`** — Report-building infrastructure
- **`teal_data()`** — Wrap datasets for a teal app
- **`cdisc_data()`** — CDISC-aware wrapper that auto-applies join keys
- **`init()`** — Construct the app from data + modules
- **`modules()`** — Compose individual modules into the app's module set
- **`teal_slices()` / `teal_slice()`** — Pre-configured filter state
- **`join_keys()`** — Specifies relational keys for joining datasets
- **`default_cdisc_join_keys`** — Built-in CDISC join key conventions
- **`choices_selected()`** — Helper for module dropdowns with defaults
- **`variable_choices()`** — Helper extracting variable names from a dataset
- **"Show R Code"** — teal's reproducibility feature — exports the R script for the current view
- **"Add to Report"** — Snapshot output to a downloadable Word/PDF report
- **NEST** — Roche's broader open-source TLG initiative; teal is its interactive arm
- **`tm_*`** — Naming prefix for teal modules
- **`teal_data_module()`** — Module-based data loading for refresh / remote data scenarios
