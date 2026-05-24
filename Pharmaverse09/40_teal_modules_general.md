# Lesson 40 — `{teal.modules.general}`: General-Purpose Modules

**Module**: 8 — Interactive applications with Shiny and teal
**Estimated length**: ~22 min spoken
**Prerequisites**: Lesson 39 (teal architecture)

---

## Learning objectives

By the end of this lesson, you will be able to:

1. Recognize the four families of general teal modules: data viewing, visualization, exploratory analysis, data quality
2. Use `tm_data_table()` and `tm_variable_browser()` for data inspection
3. Use `tm_g_distribution()`, `tm_g_scatterplot()`, `tm_g_bivariate()` for visualization
4. Use `tm_missing_data()` and `tm_outliers()` for data quality assessment
5. Use `tm_a_regression()` and `tm_a_pca()` for simple statistical exploration
6. Build a complete "study orientation" teal app combining ~6 general modules

---

## 1. What teal.modules.general is for

`{teal.modules.clinical}` (next lesson) provides clinical-purpose-built modules — AE tables, demographics, K-M plots. These are heavily clinical-aware.

`{teal.modules.general}` provides **general-purpose** modules — viewing, visualizing, exploring any data, clinical or not. It's the foundation for "data orientation" apps: when a study team gets fresh ADaM data, the first questions are "what's in here?", "any quality issues?", "any obvious patterns?" — these are general questions, answered by general modules.

teal.modules.general modules work with:

- CDISC ADaM datasets
- CDISC SDTM datasets
- Independent tabular datasets
- Any relational data with proper join keys

Roche developers, Genentech, Boehringer Ingelheim, and other NEST-aligned sponsors maintain it. Current version 0.4.x as of mid-2026.

## 2. Installation

```r
install.packages("teal.modules.general")
library(teal.modules.general)
```

This loads alongside `library(teal)` for typical apps. Each `tm_*` function is documented separately; their reference page is at [https://insightsengineering.github.io/teal.modules.general/](https://insightsengineering.github.io/teal.modules.general/).

## 3. The four module families

The modules naturally cluster into four groups:

### Family A — Data viewing
- `tm_data_table()` — interactive table viewer (DT-based)
- `tm_variable_browser()` — variable-by-variable summaries with histograms/bar charts
- `tm_file_viewer()` — show files (HTML, PDF, R scripts) inside the app
- `tm_front_page()` — landing page with study metadata

### Family B — Visualization
- `tm_g_distribution()` — univariate distributions (histograms, density, boxplots)
- `tm_g_scatterplot()` — XY scatterplots with grouping and regression overlays
- `tm_g_scatterplotmatrix()` — pairwise scatterplots
- `tm_g_bivariate()` — bivariate visualizations
- `tm_g_response()` — response distribution by predictor
- `tm_g_association()` — categorical-categorical association plots

### Family C — Data quality
- `tm_missing_data()` — missing-data patterns and summaries
- `tm_outliers()` — outlier detection with multiple methods

### Family D — Exploratory analysis
- `tm_a_pca()` — Principal Component Analysis
- `tm_a_regression()` — linear/logistic regression with diagnostic plots
- `tm_t_crosstable()` — categorical cross-tabulations

Approximately 15 modules total. Most CSR-style teal apps use 3-6 of these.

## 4. `tm_data_table()` — interactive table viewing

The most basic module: display a dataset as an interactive table with sortable columns, search, and pagination.

```r
tm_data_table(
  label = "ADSL Data",
  variables_selected = list(
    ADSL = c("USUBJID", "ARM", "AGE", "SEX", "RACE", "BMIBL", "SAFFL")
  ),
  dt_args = list(
    options = list(pageLength = 25)
  )
)
```

Useful for:

- Letting users browse the raw data underlying any analysis
- Inspecting specific records (e.g., "who are the subjects with AGE > 80?")
- Quick sanity checks

Behind the scenes it uses the `{DT}` package — DataTables.js interactive tables. Users get sort, search, column selection, CSV export for free.

For very large datasets (millions of rows), set `server_rendering = TRUE` so DT does server-side pagination (only sends the visible page to the browser).

## 5. `tm_variable_browser()` — exploratory variable summaries

Click through each variable in a dataset, see appropriate visualizations and summaries.

```r
tm_variable_browser(
  label = "Variable Browser"
)
```

For each variable, the module shows:

- **Numeric**: histogram, density plot, summary stats (N, mean, SD, quartiles, missing)
- **Categorical/factor**: bar chart, counts/proportions, missing
- **Date/time**: timeline plot
- **Character**: top values

This is often the **first module** in any teal app. New users land on it and immediately see what variables exist, what their distributions look like, and any obvious issues (e.g., 30% missingness on a key variable).

Pairs well with `tm_data_table()`: variable browser shows the shape, data table shows specific values.

## 6. `tm_g_distribution()` — univariate distributions

For deeper distribution analysis:

```r
tm_g_distribution(
  label = "Distribution Analysis",
  dist_var = data_extract_spec(
    dataname = "ADSL",
    select = select_spec(
      label = "Variable",
      choices = variable_choices(adsl, c("AGE", "BMIBL", "WEIGHTBL", "HEIGHTBL")),
      selected = "AGE",
      multiple = FALSE
    )
  ),
  strata_var = data_extract_spec(
    dataname = "ADSL",
    select = select_spec(
      label = "Strata",
      choices = variable_choices(adsl, c("ARM", "SEX", "RACE")),
      selected = "ARM",
      multiple = FALSE
    )
  )
)
```

The module renders:

- Histogram with optional overlay (normal density, theoretical distribution)
- Boxplot stratified by chosen variable
- Q-Q plot for normality assessment
- Summary statistics table

The `data_extract_spec()` / `select_spec()` / `variable_choices()` pattern is teal.modules's standard way to declare variable selectors. It looks verbose but is consistent across all modules.

## 7. `tm_g_scatterplot()` — XY relationships

```r
tm_g_scatterplot(
  label = "Scatterplot",
  x = data_extract_spec(
    dataname = "ADSL",
    select = select_spec(
      choices = variable_choices(adsl, c("AGE", "BMIBL", "HEIGHTBL")),
      selected = "AGE"
    )
  ),
  y = data_extract_spec(
    dataname = "ADSL",
    select = select_spec(
      choices = variable_choices(adsl, c("WEIGHTBL", "BMIBL")),
      selected = "WEIGHTBL"
    )
  ),
  color_by = data_extract_spec(
    dataname = "ADSL",
    select = select_spec(
      choices = variable_choices(adsl, c("ARM", "SEX")),
      selected = "ARM",
      multiple = FALSE
    )
  )
)
```

Renders an interactive ggplot scatter with the chosen X/Y variables, optional color/facet variables, optional regression overlay (via the `add_lines` checkbox in the UI).

For biomarker exploration, lab vs lab correlations, and similar bivariate questions, this is the workhorse.

## 8. `tm_missing_data()` — data quality assessment

Critical for any new dataset:

```r
tm_missing_data(label = "Missing Data Analysis")
```

The module shows:

- **By variable**: % missing per variable, sortable
- **By subject**: how many missing per subject, distribution
- **Patterns**: which variables tend to be missing together (Aggregation Patterns plot)
- **Cumulative**: subjects sorted by missingness

For CDISC ADaM data, this immediately surfaces issues like:

- "30% of subjects missing AVAL on Week 8 → visit window problem?"
- "Subjects with missing BMIBL → upstream issue in ADSL build"
- "AETERM occasionally NULL → MedDRA coding issue"

A standard inclusion in any "study orientation" teal app.

## 9. `tm_outliers()` — outlier detection

```r
tm_outliers(label = "Outlier Detection")
```

Multiple methods: Tukey's IQR-based, percentile cutoffs, Z-score based. Users pick the variable, the method, the threshold.

For pre-CSR sanity checks: "any AGE outliers? Anyone reporting weight of 5 kg or 500 kg?"

Some quality issues are caught at SDTM/ADaM build (`{sdtmchecks}`, Lesson 11). Others surface only when you visualize. `tm_outliers()` is the visualization-driven QC path.

## 10. `tm_a_regression()` — interactive regression

```r
tm_a_regression(
  label = "Linear Regression",
  response = data_extract_spec(
    dataname = "ADSL",
    select = select_spec(
      choices = variable_choices(adsl, c("WEIGHTBL", "BMIBL")),
      selected = "WEIGHTBL"
    )
  ),
  regressor = data_extract_spec(
    dataname = "ADSL",
    select = select_spec(
      choices = variable_choices(adsl, c("AGE", "HEIGHTBL")),
      selected = "AGE",
      multiple = TRUE
    )
  )
)
```

Lets users build a regression model interactively: pick response, pick predictors, see coefficients, R², residual plots. Supports linear and (with type switching) logistic regression.

For exploratory "is X associated with Y" questions before formal modeling. Not a replacement for the formal Cox or ANCOVA done elsewhere; an exploratory complement.

## 11. `tm_a_pca()` — principal component analysis

For high-dimensional data (e.g., biomarker panels with 50+ markers):

```r
tm_a_pca(label = "PCA")
```

Users select variables, the module computes PCA, displays:

- Scree plot
- PC1 vs PC2 scatter (with optional grouping)
- Loadings plot
- Variance explained table

Useful when exploring multivariate datasets — biomarker assays, omics, multiple-domain integration.

## 12. `tm_t_crosstable()` — categorical cross-tabs

```r
tm_t_crosstable(
  label = "Cross-Table",
  x = data_extract_spec(
    dataname = "ADSL",
    select = select_spec(
      choices = variable_choices(adsl, c("ARM", "SEX")),
      selected = "ARM",
      multiple = FALSE
    )
  ),
  y = data_extract_spec(
    dataname = "ADSL",
    select = select_spec(
      choices = variable_choices(adsl, c("AGEGR1", "RACE")),
      selected = "RACE",
      multiple = FALSE
    )
  )
)
```

Renders a frequency cross-table with optional chi-squared / Fisher's exact test. Quick way to look at "are arms balanced across race?" or "do AE rates differ by sex within arm?" type questions.

For more sophisticated cross-tabulations with proper safety conventions, use `tm_t_summary` from `teal.modules.clinical` (next lesson). `tm_t_crosstable` is for ad-hoc exploration.

## 13. The general teal app pattern

A typical "study orientation" teal app for a new dataset:

```r
library(teal)
library(teal.modules.general)
library(pharmaverseadam)

data <- cdisc_data(
  ADSL = pharmaverseadam::adsl,
  ADAE = pharmaverseadam::adae,
  ADLB = pharmaverseadam::adlb,
  ADVS = pharmaverseadam::advs,
  ADTTE = pharmaverseadam::adtte
)

mods <- modules(
  modules(
    label = "Overview",
    tm_front_page(
      label = "Study Front Page",
      header_text = c(
        "Title" = "Phase III Oncology Study",
        "Sponsor" = "Example Pharma",
        "Indication" = "NSCLC"
      ),
      tables = list("ADSL summary" = data.frame(...))
    )
  ),
  modules(
    label = "Data",
    tm_data_table("Data Tables"),
    tm_variable_browser("Variable Browser")
  ),
  modules(
    label = "Visualizations",
    tm_g_distribution("Distributions"),
    tm_g_scatterplot("Scatterplot"),
    tm_g_bivariate("Bivariate")
  ),
  modules(
    label = "Quality",
    tm_missing_data("Missing Data"),
    tm_outliers("Outliers")
  ),
  modules(
    label = "Exploration",
    tm_a_regression("Regression"),
    tm_t_crosstable("Cross Tables")
  )
)

app <- init(
  data = data,
  modules = mods,
  title = "Study X Explorer",
  filter = teal_slices(
    teal_slice(dataname = "ADSL", varname = "SAFFL", selected = "Y")
  )
)

shinyApp(app$ui, app$server)
```

The result: a five-tab-group app covering everything a new study team needs to orient itself in the data. The user can:

- Browse the front page for study metadata
- Inspect any dataset row by row
- Visualize any variable distribution
- Find data quality issues
- Run quick exploratory analyses

All with consistent filtering, reproducible code, and reportable snapshots.

For ~100 lines of code, you've replaced what would otherwise be 20 separate "exploration scripts" each study team rewrites for itself.

## 14. Transformators and decorators (newer pattern)

A newer teal pattern (~2024-2025): **transformators** and **decorators** modify module behavior without changing the module itself.

- **Transformators**: change the data passed to a module (e.g., apply a custom derivation)
- **Decorators**: change the output of a module (e.g., apply a custom plot theme)

Example: applying a sponsor color theme to all plots:

```r
sponsor_theme <- teal_transform_module(
  label = "Apply sponsor theme",
  ui = function(id) NULL,
  server = function(id, data) {
    moduleServer(id, function(input, output, session) {
      reactive({
        within(data(), {
          # apply custom theme to ggplot objects
        })
      })
    })
  }
)

tm_g_distribution(
  ...,
  decorators = list(plot = sponsor_theme)
)
```

This is more advanced; most teams don't need it initially. As you build more complex apps with sponsor styling, transformators/decorators provide a clean extension mechanism without forking the module code.

## 15. Module configuration: `data_extract_spec` deep dive

A subtle but important pattern across all `tm_*` modules: **`data_extract_spec()`** wraps a variable selector.

```r
data_extract_spec(
  dataname = "ADSL",
  select = select_spec(
    label = "X variable",
    choices = variable_choices(adsl, c("AGE", "BMIBL")),
    selected = "AGE",
    multiple = FALSE,
    fixed = FALSE
  )
)
```

The pieces:

- `dataname`: which dataset to pull from
- `select_spec()`: the selector UI configuration
- `variable_choices()`: dynamically extract variable names from the dataset
- `selected`: default value
- `multiple`: allow multi-select?
- `fixed`: lock the user out from changing?

For complex modules, you'll see many `data_extract_spec()` arguments. Each one is a configurable variable selector. Users see dropdowns in the module UI corresponding to each spec.

This pattern looks repetitive at first but scales well: every module exposes the same configuration mechanism, so users learn it once.

## 16. The "Show R Code" output for general modules

Every module supports "Show R Code". For `tm_g_distribution`, the output looks like:

```r
# Data
library(teal.data)
library(pharmaverseadam)
ADSL <- pharmaverseadam::adsl

# Filter
ADSL <- ADSL |> dplyr::filter(SAFFL == "Y")

# Module logic
ggplot(ADSL, aes(AGE)) +
  geom_histogram(bins = 20, fill = "steelblue") +
  facet_wrap(~ARM) +
  labs(title = "Age Distribution by Treatment Arm")
```

This is the actual R code that, if pasted into an R session, produces the same plot. For pharma:

- Save it as a standalone script for QC
- Adapt it for the formal CSR plot
- Share it with collaborators who need to reproduce

The code is editable in the modal — users can tweak it and re-render before exporting.

## 17. teal gallery and TLG Catalog

For more examples beyond what's covered here:

- **teal gallery**: official demo apps showing module combinations — [https://insightsengineering.github.io/teal.gallery/](https://insightsengineering.github.io/teal.gallery/)
- **TLG Catalog**: also includes interactive teal-app examples for many tables — [https://insightsengineering.github.io/tlg-catalog/stable/](https://insightsengineering.github.io/tlg-catalog/stable/)

Browse these when designing a new teal app. Most patterns you'll need have been demonstrated somewhere.

## 18. When to use general vs clinical modules

A simple decision rule:

- **Use general modules when**: any tabular data, exploration before specific analyses, data quality checks, exploratory visualization
- **Use clinical modules when**: producing a specific clinical analysis (AE summary, K-M plot, demographics with proper safety conventions, ANCOVA)
- **Use both together**: typical clinical teal apps have ~3 general modules (data viewer, variable browser, missing data) + ~5-10 clinical modules (demographics, AE summary, AE detail, K-M, lab shift, etc.)

The general modules are the entry point; the clinical modules are the substantive analyses. Most production teal apps have both.

## 19. Key takeaways

- `{teal.modules.general}` provides general-purpose modules for any data: viewing, visualization, exploratory analysis, data quality
- Four families: data viewing (`tm_data_table`, `tm_variable_browser`), visualization (`tm_g_*`), quality (`tm_missing_data`, `tm_outliers`), analysis (`tm_a_*`, `tm_t_crosstable`)
- The standard variable-selector pattern: `data_extract_spec()` + `select_spec()` + `variable_choices()`
- Modules work with CDISC and non-CDISC data
- Every module supports "Show R Code" and "Add to Report" — reproducibility plus reporting come free
- Transformators and decorators provide newer-style module customization
- Typical "study orientation" app combines 5-10 modules from this package
- Complementary to teal.modules.clinical: general modules for exploration, clinical modules for specific clinical analyses

## 20. What's next

Lesson 41 covers **`{teal.modules.clinical}`** in depth — the 30+ clinical-purpose-built modules implementing standard CSR analyses interactively. We'll cover the AE family (`tm_t_events`, `tm_t_events_summary`, `tm_t_events_patyear`), the demographics modules (`tm_t_summary`), the survival modules (`tm_g_km`, `tm_t_tte`, `tm_t_coxreg`), the lab modules (`tm_t_abnormality`, `tm_t_shift_by_grade`), and the patient profile modules.

After clinical modules: Lesson 42 covers building **custom teal modules**, deployment to Posit Connect, and validation considerations.

---

## Self-check questions

1. Name the four families of teal.modules.general modules.
2. When would you use `tm_data_table()` vs `tm_variable_browser()`?
3. What does `data_extract_spec()` do?
4. Why is `tm_missing_data()` a standard inclusion in any "study orientation" app?
5. Translate to teal: "Add a scatterplot module showing WEIGHTBL vs HEIGHTBL, colored by ARM, with optional regression line."
6. Why do most clinical teal apps use both teal.modules.general and teal.modules.clinical?

## Glossary

- **`{teal.modules.general}`** — General-purpose teal modules for any tabular data
- **`tm_data_table()`** — Interactive data table viewer (DT-based)
- **`tm_variable_browser()`** — Variable-by-variable summaries with visualizations
- **`tm_front_page()`** — Landing page with study metadata
- **`tm_g_distribution()`** — Univariate distribution module
- **`tm_g_scatterplot()`** — XY scatter with grouping
- **`tm_g_bivariate()`** — Bivariate visualization
- **`tm_missing_data()`** — Missing data pattern analysis
- **`tm_outliers()`** — Outlier detection module
- **`tm_a_regression()`** — Interactive regression module
- **`tm_a_pca()`** — Principal component analysis
- **`tm_t_crosstable()`** — Categorical cross-tabulation
- **`data_extract_spec()`** — Module variable-selector specification
- **`select_spec()`** — UI selector configuration within `data_extract_spec`
- **`variable_choices()`** — Dynamic variable name extraction
- **Transformator** — Newer pattern for modifying data before module use
- **Decorator** — Newer pattern for modifying module output (e.g., applying custom themes)
- **teal gallery** — Official demo apps showing module combinations
- **TLG Catalog** — Cross-referenced catalog of TLG implementations including teal versions
