# Lesson 42 — Custom teal Modules, Deployment, and Validation

**Module**: 8 — Interactive applications with Shiny and teal
**Estimated length**: ~28 min spoken
**Prerequisites**: Lessons 38-41 (Shiny, teal architecture, teal modules)

---

## Learning objectives

By the end of this lesson, you will be able to:

1. Build a custom teal module from scratch using the `module()` function
2. Wire a custom module to receive filtered data from teal's filter panel
3. Add reproducibility ("Show R Code") and reporting support to a custom module
4. Deploy a teal app to Posit Connect (or shinyapps.io / Shiny Server)
5. Apply GxP-appropriate validation strategies for teal apps
6. Recognize the patterns sponsor teams use for organization-wide teal infrastructure

---

## 1. Why custom modules matter

Pre-built modules (Lessons 40-41) cover ~80% of clinical analyses. The remaining 20% needs custom modules:

- **Sponsor-specific TLG templates** that don't match FDA-aligned defaults
- **Specialized therapeutic-area analyses** (e.g., a specific NSCLC efficacy table)
- **Biomarker explorers** with custom logic
- **Quality monitoring dashboards** for in-flight studies
- **Tools integrating non-CDISC data** (clinical operations, manufacturing)

A custom module is just a Shiny module (Lesson 38) wrapped in teal's `module()` constructor. If you can build a Shiny module, you can build a teal module.

## 2. The `module()` constructor

teal provides `module()` to wrap your Shiny module so teal recognizes it:

```r
my_module <- module(
  label = "My Custom Module",
  ui = function(id, ...) {
    ns <- NS(id)
    tagList(
      sliderInput(ns("threshold"), "Threshold:", 0, 100, 50),
      plotOutput(ns("plot"))
    )
  },
  server = function(id, data, filter_panel_api, reporter, ...) {
    moduleServer(id, function(input, output, session) {
      output$plot <- renderPlot({
        df <- data()[["ADSL"]]      # filtered data from teal
        df_filt <- df |> filter(AGE > input$threshold)
        ggplot(df_filt, aes(AGE)) + geom_histogram()
      })
    })
  },
  datanames = "ADSL"      # which datasets this module needs
)
```

Key elements:

- **`label`**: tab name in the app
- **`ui = function(id, ...)`**: standard Shiny module UI, takes a namespace id
- **`server = function(id, data, filter_panel_api, reporter, ...)`**: standard Shiny module server, but with extra arguments teal passes
- **`datanames`**: which datasets the module needs access to

The `data` argument in the server function is a reactive that returns a list of datasets (filtered per the global filter panel). Access with `data()[["DATASET_NAME"]]`.

## 3. The data reactivity flow

A subtle point: when the user changes a filter in the panel, `data()` invalidates and your reactive blocks reading `data()` re-run automatically.

```r
server = function(id, data, ...) {
  moduleServer(id, function(input, output, session) {
    output$summary <- renderTable({
      df <- data()[["ADSL"]]      # this re-runs when filters change
      df |> summarise(n = n(), mean_age = mean(AGE, na.rm = TRUE))
    })
  })
}
```

You don't manually watch the filter panel — `data()` handles it. The reactive dependency on `data()` automatically tracks filter changes.

For modules using multiple datasets:

```r
output$plot <- renderPlot({
  adsl <- data()[["ADSL"]]
  adae <- data()[["ADAE"]]

  # Both are pre-filtered per the panel state
  ggplot(...)
})
```

teal applies the filter panel to all requested datasets simultaneously.

## 4. A complete custom module example

A biomarker correlation explorer — not in teal.modules.clinical but easy to build:

```r
biomarker_explorer <- function(label = "Biomarker Correlation") {
  module(
    label = label,

    ui = function(id) {
      ns <- NS(id)
      tagList(
        selectInput(ns("x_var"), "X variable:",
                    choices = c("BMRKR1", "BMRKR2", "AGE", "BMIBL"),
                    selected = "BMRKR1"),
        selectInput(ns("y_var"), "Y variable:",
                    choices = c("BMRKR1", "BMRKR2", "AGE", "BMIBL"),
                    selected = "BMRKR2"),
        selectInput(ns("color_var"), "Color by:",
                    choices = c("ARM", "SEX", "RACE"),
                    selected = "ARM"),
        checkboxInput(ns("show_lm"), "Show regression line", TRUE),
        plotOutput(ns("plot"), height = 500),
        verbatimTextOutput(ns("cor_text"))
      )
    },

    server = function(id, data, ...) {
      moduleServer(id, function(input, output, session) {
        df <- reactive({
          data()[["ADSL"]]
        })

        output$plot <- renderPlot({
          p <- ggplot(df(),
                     aes(x = .data[[input$x_var]],
                         y = .data[[input$y_var]],
                         color = .data[[input$color_var]])) +
            geom_point() +
            labs(x = input$x_var, y = input$y_var)
          if (input$show_lm) p <- p + geom_smooth(method = "lm", se = TRUE)
          p
        })

        output$cor_text <- renderPrint({
          cor_val <- cor(df()[[input$x_var]],
                          df()[[input$y_var]],
                          use = "pairwise.complete.obs")
          cat(sprintf("Pearson correlation: %.3f\n", cor_val))
        })
      })
    },

    datanames = "ADSL"
  )
}

# Use in an app
app <- init(
  data = cdisc_data(ADSL = pharmaverseadam::adsl),
  modules = modules(biomarker_explorer("Biomarker Explorer"))
)

shinyApp(app$ui, app$server)
```

~50 lines. The custom module:

- Lets users pick X, Y, color variables
- Renders an interactive scatterplot with optional regression
- Shows the correlation coefficient
- Responds to global filter changes (via `data()`)

This module pattern adapts to essentially any custom analysis: define inputs, react to data, render outputs.

## 5. Adding reproducibility ("Show R Code")

For your custom module to support the "Show R Code" feature, the module's server must return a `teal_data` object containing the executed code:

```r
server = function(id, data, ...) {
  moduleServer(id, function(input, output, session) {
    
    # Build a teal_data object with code captured
    output_data <- reactive({
      teal.code::eval_code(data(), expr = bquote({
        df_subset <- ADSL |> dplyr::filter(AGE > .(input$threshold))
        plot_obj <- ggplot(df_subset, aes(AGE)) + geom_histogram()
      }))
    })

    output$plot <- renderPlot({
      output_data()[["plot_obj"]]
    })

    # Return the teal_data for the framework
    output_data
  })
}
```

The pattern:

- Wrap your module's computation in `eval_code()` so the code is captured
- Use `bquote()` to substitute user inputs into the captured code
- Return the resulting `teal_data` from the moduleServer

When the user clicks "Show R Code", teal stitches together:

1. The data-loading code (from `teal_data()`)
2. The filter-panel state (as filter expressions)
3. Your module's captured code

Producing a complete runnable script. This is the price of admission for production-grade teal modules.

For complex modules, see `vignette("teal-code-and-reporter", package = "teal")` for current patterns. The API has evolved across teal versions; check current docs.

## 6. Adding "Add to Report" support

For reporting integration, your module's server accepts a `reporter` argument:

```r
server = function(id, data, reporter, ...) {
  moduleServer(id, function(input, output, session) {

    output$plot <- renderPlot({
      # ... rendering logic ...
    })

    # Reporter integration
    if (!is.null(reporter)) {
      teal.reporter::add_card_button_srv(
        "add_to_report",
        reporter = reporter,
        card_fun = function(card = teal.reporter::ReportCard$new()) {
          card$append_text("My Module Output", "header2")
          card$append_plot(my_plot_reactive())
          card$append_src(my_code_text())
          card
        }
      )
    }
  })
}

# And in the UI:
ui = function(id) {
  ns <- NS(id)
  tagList(
    teal.reporter::add_card_button_ui(ns("add_to_report")),
    plotOutput(ns("plot"))
  )
}
```

The `card_fun` defines what gets added when the user clicks "Add to Report": titles, plots, tables, source code. The card becomes one section in the downloaded Word/PDF report.

Most pre-built modules already include this. For custom modules, adding it is ~10 extra lines for full reporting integration.

## 7. Modular app organization

For large teal apps with many custom modules, organize as a package:

```
my_sponsor_teal/
├── DESCRIPTION
├── NAMESPACE
├── R/
│   ├── module_biomarker.R         # custom biomarker module
│   ├── module_sponsor_demog.R     # sponsor-specific demographics
│   ├── module_quality_dash.R      # data quality dashboard
│   └── app_builder.R               # function to assemble the full app
├── inst/
│   └── apps/
│       └── csr_companion/
│           └── app.R                # entry point
└── tests/
    └── testthat/
        └── test-modules.R           # unit tests
```

Pattern:

- Each custom module in its own `.R` file
- `app_builder.R` exports a function `build_csr_companion_app()` that constructs the full app
- `inst/apps/csr_companion/app.R` is the deployable Shiny script: `MySponsorTeal::build_csr_companion_app() |> shiny::runApp()`
- Tests cover module-level logic separate from teal infrastructure

This pattern enables:

- Version-controlled module library (semver, NEWS, docs)
- Reuse across studies (each study uses the package + its data)
- Independent validation of modules vs apps
- CI/CD pipelines for testing and deployment

Several large sponsors (Roche, GSK, Pfizer) maintain internal R packages exactly like this.

## 8. Testing custom modules

Modules can be unit-tested with `{shinytest2}` or `{testthat}` + Shiny testing helpers:

```r
library(testthat)
library(shinytest2)

test_that("biomarker explorer renders without error", {
  app <- AppDriver$new(
    biomarker_test_app(),
    height = 800,
    width = 1200
  )

  # Set inputs
  app$set_inputs(`module-x_var` = "AGE")
  app$set_inputs(`module-y_var` = "BMIBL")

  # Wait for plot to render
  app$wait_for_idle()

  # Snapshot test
  app$expect_screenshot()
})
```

`shinytest2` programmatically drives a Shiny app — sets inputs, waits for updates, snapshots outputs. For each custom module, you'd:

1. Build a minimal test app (the module wrapped in `init()`)
2. Test with various input combinations
3. Snapshot outputs for regression testing

This catches "the module crashes when X is missing" or "the plot renders empty when Y is selected" type bugs before deployment.

Coverage tools: `{covr}` works on teal modules. Aim for 80%+ coverage on production modules.

## 9. Deployment options

Once your app is built, you need to deploy it for users:

### Option A — Local development

```r
shiny::runApp("app.R")
```

Fine for solo development; not for sharing.

### Option B — shinyapps.io

Posit's hosted service. Free tier for prototypes; paid tiers for production:

```r
library(rsconnect)
rsconnect::deployApp("path/to/app/")
```

Strengths: easy, no infrastructure to maintain. Weaknesses: limited compute on lower tiers; not GxP-validatable.

### Option C — Posit Connect (formerly RStudio Connect)

Commercial enterprise platform — the standard for pharma production:

```r
# Push from RStudio: click "Publish" → choose Connect server
# Or via API:
rsconnect::deployApp(
  appDir = "path/to/app/",
  server = "your-connect-server"
)
```

Strengths: GxP-validatable, SAML/LDAP/OIDC auth, role-based access control, scheduled jobs, version history, audit trail.

Most large pharma sponsors run Posit Connect internally. App deployment becomes a standard CI/CD step.

### Option D — Shiny Server (open source)

Self-hosted on Linux:

```bash
# After installing shiny-server
sudo cp -r my_app /srv/shiny-server/
# App available at http://server/my_app/
```

Strengths: free, full control. Weaknesses: you manage auth, monitoring, scaling; less GxP-friendly than Posit Connect.

### Option E — Docker / Kubernetes

Containerize the app:

```dockerfile
FROM rocker/shiny:4.4.0
COPY app/ /srv/shiny-server/my_app/
RUN R -e "install.packages(c('teal', 'teal.modules.clinical', ...))"
```

For sponsors with existing Kubernetes infrastructure, this is the cloud-native path. Deploy to AWS/Azure/GCP managed Kubernetes services.

For pharma production, the typical setup is **Posit Connect on-premise** (or in a private cloud) with sponsor SSO. This balances ease-of-use with GxP requirements.

## 10. Performance optimization for production

For apps used by many concurrent users:

### Caching
Use `bindCache()` (Shiny 1.6+) to cache expensive reactives across sessions:

```r
heavy_computation <- reactive({
  # Expensive analysis
}) |> bindCache(input$dataset, input$arm)
```

Different users with the same inputs get cached results.

### Async computation
Use `{future}` and `{promises}` for long-running operations that shouldn't block other users:

```r
library(future)
library(promises)
plan(multisession)

output$result <- renderPlot({
  future({
    # Long computation
    Sys.sleep(5)
    ggplot(...) + ...
  }) %...>%
    print()
})
```

While the future runs, other users' requests are unaffected.

### Server-side rendering for tables
For `DT::renderDataTable` on large data, use server-side processing:

```r
output$table <- renderDataTable(
  large_data,
  server = TRUE,
  options = list(pageLength = 25, lengthMenu = c(10, 25, 50))
)
```

Only the visible page is sent to the browser; sorting/searching happens on the server.

### Posit Connect runtime tuning
Adjust `max-processes`, `max-connections-per-process`, and `min-processes` in your app's `manifest.json` to balance concurrent users.

For typical pharma teal apps with 10-100 users, default settings work. For 1000+ users (e.g., a sponsor-wide safety monitoring dashboard), tuning matters.

## 11. Authentication and access control

For pharma production, apps need authentication. Options:

### Posit Connect built-in auth
- SAML 2.0 (most enterprise SSO systems)
- OIDC (modern identity providers)
- LDAP / Active Directory
- Local accounts (for development)

Configure in Connect's admin panel. Users authenticate at the Connect level before reaching your app.

### Per-app role-based access
Within Connect, define groups (e.g., "Study Team", "Biostatistics", "Medical Reviewers"). Grant access to specific apps per group.

In the app itself, access the user identity:

```r
server <- function(input, output, session) {
  user_email <- session$userData$user
  user_groups <- session$userData$groups

  # Conditionally enable features
  if ("biostatistics" %in% user_groups) {
    # show advanced modules
  }
}
```

For multi-study apps where different users see different studies, this controls per-user data access.

### Custom auth for self-hosted Shiny
Without Posit Connect, you'd typically reverse-proxy through nginx with OAuth2-Proxy or similar. More setup; same end result.

For GxP environments, **audit trail** is mandatory: who logged in, when, what they viewed. Posit Connect provides this; rolling your own is significant additional work.

## 12. GxP validation considerations

For apps used in GxP-relevant contexts:

### Validate the framework
The packages themselves (Shiny, teal, teal.modules.*) need risk assessment. The `{riskmetric}` package (Lesson 47) scores R packages on validation-relevant criteria; teal scores well due to active development and testing.

The Pharma R Adoption book and `{validation}` package frameworks help document this for your QA.

### Validate the app
For each app:

- **Requirements**: user stories ("medical reviewer needs to view patient AE timeline")
- **Specifications**: how each module addresses requirements
- **Testing**: unit tests (shinytest2), user acceptance testing (UAT) with study team members
- **Documentation**: app architecture, deployment procedure, user guide

### Validate the outputs
For numbers that influence regulatory decisions:

- The methodology comes from validated packages (tern, rtables)
- The intermediate data comes from validated ADaMs (admiral)
- The display is via validated modules (teal.modules.clinical)
- The traceability proof is the "Show R Code" output

So a teal-produced number that goes into a regulatory filing has a clear validation lineage: ADaM → tern → module → output. Each layer is validated independently.

### Production controls
- Lock the package versions (use `{renv}` or Posit Package Manager snapshots)
- Use Posit Connect's version history (every deployment archived)
- Restrict who can deploy to production (Connect role-based)
- Maintain change logs and re-validation triggers

GxP for teal is achievable but takes intentional process. Sponsors with mature R adoption (Roche, Novartis, GSK, Pfizer) have established patterns.

## 13. Organization-wide teal patterns

Larger sponsors typically build a **shared teal infrastructure**:

### Central package: `{<sponsor>.teal>`
Internal R package containing:
- Sponsor-specific custom modules
- App builder functions
- Themes and branding
- Auth/access helpers
- Common data loaders

Each study uses this package + study-specific data → assembles its own app with consistent infrastructure.

### Study app template
Standardized study-app structure:

```
study_xyz/
├── data/                  # study ADaMs
├── app.R                  # entry: builds app using sponsor package
├── modules/               # study-specific custom modules
├── tests/
└── deploy.yml             # CI/CD config
```

Programmers fork the template for new studies. The shared infrastructure means most of the app comes "for free"; only study-specific pieces are coded fresh.

### Cross-study comparison apps
With shared infrastructure, build apps that aggregate across studies:

```r
data <- cdisc_data(
  ADSL_STUDY_A = read_xpt("study_a/adsl.xpt"),
  ADSL_STUDY_B = read_xpt("study_b/adsl.xpt")
)

# Custom module that compares
cross_study_demog <- module(...)
```

Useful for portfolio safety reviews, dose-finding across studies, sponsor-wide drug-class monitoring.

## 14. Common pitfalls

### Performance issues from data not being pre-filtered
Don't load 5 GB of raw data into `teal_data()`. Pre-filter to the relevant analysis subset before app launch:

```r
# Bad
data <- teal_data(BIG = read_raw_5gb())

# Good
data <- teal_data(
  ADSL = pharmaverseadam::adsl |> filter(SAFFL == "Y", STUDYID == "MY_STUDY")
)
```

### Module crashes when filter results in empty data
Add defensive checks:

```r
output$plot <- renderPlot({
  df <- data()[["ADSL"]]
  req(nrow(df) > 0)         # Skip if empty
  ggplot(df, ...) + ...
})
```

`req()` is Shiny's "skip if condition not met" — handles the empty-data case gracefully.

### Reactivity cycles
Don't have two reactives that each invalidate the other. Shiny catches obvious cycles but subtle ones can hang the app. If outputs flash repeatedly, suspect a cycle.

### Modules that mutate the data unexpectedly
teal_data is locked precisely to prevent this. Stick with `eval_code()` for modifications; don't try to assign back to data directly.

## 15. Resources and community

- **teal documentation**: [https://insightsengineering.github.io/teal/](https://insightsengineering.github.io/teal/)
- **teal gallery**: [https://insightsengineering.github.io/teal.gallery/](https://insightsengineering.github.io/teal.gallery/) — demo apps
- **TLG Catalog**: [https://insightsengineering.github.io/tlg-catalog/](https://insightsengineering.github.io/tlg-catalog/) — table examples including teal versions
- **pharmaverse Slack**: active teal channel for questions
- **Posit Conference**: pharma track with teal content
- **R/Pharma conference**: dedicated teal workshops

For organization-wide teal adoption, the Roche / Genentech teams that built teal often present case studies and patterns at these venues.

## 16. The full validation lifecycle for a teal app

A realistic GxP-relevant app deployment timeline:

1. **Requirements**: study team specifies the app's purpose, user roles, key analyses (1-2 weeks)
2. **Architecture**: choose pre-built modules, identify custom modules needed, design data flow (1 week)
3. **Development**: code modules, integrate with teal, local testing (2-6 weeks depending on customization)
4. **Validation**: unit tests, UAT with study team, regression tests, performance tests (2-4 weeks)
5. **Documentation**: app guide, technical spec, validation summary (1-2 weeks)
6. **Deployment to staging**: Posit Connect staging environment, additional UAT (1-2 weeks)
7. **Production deployment**: with formal change control sign-off (1 week)
8. **Maintenance**: ongoing user support, periodic re-validation as packages update

Total: 8-16 weeks for a full new app. Subsequent studies reusing infrastructure: 2-4 weeks.

For non-GxP apps (internal exploration tools, scientific deep-dives): much faster — days to weeks.

## 17. Putting it together: a custom module + reporting + deployment

A complete sponsor-grade workflow:

```r
# In package R/module_biomarker.R
biomarker_explorer <- function(label = "Biomarker Explorer") {
  module(
    label = label,
    ui = function(id) { ... },
    server = function(id, data, reporter, ...) {
      moduleServer(id, function(input, output, session) {
        # Reactive code with eval_code for traceability
        analysis_data <- reactive({
          teal.code::eval_code(data(), expr = bquote({
            df <- ADSL |> dplyr::filter(BMRKR1 > .(input$threshold))
            plot_obj <- ggplot2::ggplot(df, ggplot2::aes(BMRKR1, BMRKR2)) +
              ggplot2::geom_point()
          }))
        })

        output$plot <- renderPlot(analysis_data()[["plot_obj"]])

        # Reporter integration
        teal.reporter::add_card_button_srv(
          "add_to_report",
          reporter = reporter,
          card_fun = function(card) {
            card$append_text("Biomarker Analysis", "header2")
            card$append_plot(analysis_data()[["plot_obj"]])
            card$append_src(deparse(teal.code::get_code(analysis_data())))
            card
          }
        )
      })
    },
    datanames = "ADSL"
  )
}

# In package R/app_builder.R
build_csr_companion <- function(adsl, adae, adlb) {
  data <- cdisc_data(ADSL = adsl, ADAE = adae, ADLB = adlb)
  mods <- modules(
    # Standard modules
    tm_t_summary("Demographics", dataname = "ADSL", ...),
    tm_t_events("AEs", dataname = "ADAE", ...),
    # Custom modules
    biomarker_explorer("Biomarker")
  )
  init(data = data, modules = mods, title = "Study X")
}

# In inst/apps/csr_companion/app.R (deployable entry point)
library(MySponsorTeal)
adsl <- haven::read_xpt(Sys.getenv("ADSL_PATH"))
adae <- haven::read_xpt(Sys.getenv("ADAE_PATH"))
adlb <- haven::read_xpt(Sys.getenv("ADLB_PATH"))

app <- build_csr_companion(adsl, adae, adlb)
shiny::shinyApp(app$ui, app$server)
```

Deployment:

```bash
# In CI/CD pipeline
rsconnect::deployApp(
  appDir = "inst/apps/csr_companion/",
  appFiles = c("app.R", ".Renviron"),
  server = "production-connect.sponsor.com",
  appName = "study-x-csr-companion"
)
```

The app is now live on Posit Connect, accessible to authorized users, with full validation lineage from ADaM through teal to rendered output.

## 18. Key takeaways

- Custom teal modules wrap Shiny modules with `module(label, ui, server, datanames)`
- The server's `data()` argument provides filtered data reactively — invalidates when filters change
- For "Show R Code" support, wrap computation in `teal.code::eval_code()` with `bquote()` for input substitution
- For "Add to Report" support, integrate `{teal.reporter}` cards via `add_card_button_srv()`
- Organize custom modules in an internal R package; deploy via Posit Connect for production
- GxP validation: framework risk assessment + app validation + output traceability — achievable with discipline
- Larger sponsors build sponsor-wide `{<sponsor>.teal}` packages with shared custom modules, themes, and app builders
- Performance optimization: pre-filter data, use `bindCache()`, async via `{future}`, server-side DT rendering
- Authentication via Posit Connect SAML/OIDC/LDAP; role-based access control for sensitive data

## 19. What's next

**Module 8 is complete.** You can now:

- Build a Shiny app from scratch (Lesson 38)
- Assemble a teal app from data + modules (Lesson 39)
- Use general modules for exploration (Lesson 40)
- Use clinical modules for CSR analyses (Lesson 41)
- Write custom modules and deploy to production (Lesson 42)

Together with Modules 6-7 (TLG production), you have the full toolkit for both **static CSR deliverables** and **interactive companion applications**.

**Module 9** covers **submission packaging** — turning your ADaM datasets and TLGs into the actual XPT v5 (`{xportr}`) files and emerging Dataset-JSON v1.1 (`{datasetjson}`) format the FDA accepts. Then Module 10 covers traceability (logrx, diffdf, riskmetric), and Module 11 is the capstone end-to-end synthetic oncology study.

---

## Self-check questions

1. What's the minimum structure of a custom teal module?
2. How does a custom module receive filtered data from the global filter panel?
3. What's `teal.code::eval_code()` for?
4. List three deployment options for a teal app and when each is appropriate.
5. How does GxP validation work for a teal app — what gets validated at each layer?
6. Why do large sponsors build an internal `{<sponsor>.teal}` R package?

## Glossary

- **`module()`** — teal's wrapper around a Shiny module
- **`data()`** — Reactive providing filtered datasets to a custom module
- **`filter_panel_api`** — Server argument exposing filter panel state/control
- **`reporter`** — Server argument providing teal.reporter integration
- **`teal.code::eval_code()`** — Wrap computation so code is captured for reproducibility
- **`bquote()`** — R base function for partial expression quoting, used with `eval_code`
- **`teal.reporter::add_card_button_srv()`** — Adds "Add to Report" button to a module
- **Shiny module** — UI + server function pair with namespaced ids
- **`bindCache()`** — Cache reactive results across sessions (Shiny 1.6+)
- **`shinytest2`** — Programmatic Shiny app testing framework
- **Posit Connect** — Commercial enterprise deployment platform for Shiny
- **shinyapps.io** — Posit's hosted Shiny service
- **Shiny Server** — Open-source self-hosted Shiny platform
- **SAML / OIDC / LDAP** — Enterprise authentication protocols
- **GxP** — Good Practice; FDA quality regulations
- **`{renv}`** — R environment locking for reproducible package versions
- **Sponsor teal package** — Internal R package containing custom modules, themes, app builders for organization-wide consistency
- **App builder function** — Function that assembles a complete teal app from data + module config
- **`{validation}` / `{riskmetric}`** — Packages for documenting R package validation evidence
- **`req()`** — Shiny's "skip if condition fails" helper for empty-data handling
