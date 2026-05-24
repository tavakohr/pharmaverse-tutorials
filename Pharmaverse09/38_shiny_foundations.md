# Lesson 38 — Shiny Foundations for SAS Programmers

**Module**: 8 — Interactive applications with Shiny and teal
**Estimated length**: ~22 min spoken
**Prerequisites**: Lessons 03-06 (R foundations)

---

## Learning objectives

By the end of this lesson, you will be able to:

1. Explain what Shiny is and why it's the foundation for clinical interactive applications in R
2. Understand the reactive programming model — the most important conceptual shift from procedural SAS programming
3. Recognize the three core pieces: UI, server, reactive dependencies
4. Build a minimal Shiny app from scratch — input → reactive → output
5. Understand Shiny modules — the pattern teal apps build on
6. Recognize when Shiny is the right tool, when it's overkill, and what alternatives exist

---

## 1. Why this lesson exists

Module 8 covers **teal**, Roche's framework for building interactive clinical data applications. teal is built on Shiny. Before we can talk about teal, you need a working mental model of Shiny.

If you've never written a Shiny app, the conceptual shift is bigger than the syntax. SAS programmers in particular often struggle with one specific idea: **reactive programming**. Once that clicks, teal makes sense; until it does, every teal example feels like magic.

This lesson covers Shiny just deeply enough to make teal comprehensible. We're not aiming to make you a Shiny developer — we're aiming to make you a Shiny *reader* who can debug a teal app, customize a module, or understand why a particular UI behavior is happening.

For deeper Shiny coverage, the canonical resource is Hadley Wickham's free book *Mastering Shiny* ([https://mastering-shiny.org](https://mastering-shiny.org)).

## 2. What Shiny is

Shiny is an R package developed by Posit (formerly RStudio) that lets you build **interactive web applications using only R code**. No JavaScript or HTML required for basic apps — Shiny generates the web frontend automatically from your R code.

A Shiny app is a website that runs R on the backend. When a user clicks a button or types in a field, the user's browser sends that input back to R, which recomputes outputs and sends the updated values back to the browser. The user sees the page update without refreshing.

For pharma, this enables:

- **Exploratory dashboards** for study teams — change filters, see updated tables/plots
- **Patient profiles** — drill into individual subjects' data
- **Interactive QC tools** — flag and review data issues
- **Sponsor/CRO collaboration interfaces** — share study insights without sending raw data

Shiny has been around since 2012; it's mature, stable, and broadly adopted across industries. In pharma, Shiny adoption accelerated when teal was open-sourced by Roche (~2022), giving the industry a structured framework for clinical Shiny apps.

## 3. The mental model: reactive programming

Here's the central concept. Don't skip this section.

**SAS is procedural.** You write code that runs top-to-bottom. Each step transforms the state of the world (datasets, macro variables) and the next step uses that new state. The order of execution is exactly the order you wrote.

```sas
* SAS example;
data demo;
  set sashelp.heart;
  bmi_category = ...;
run;

proc means data=demo;
  var weight;
run;
```

Procedure 1 runs, then Procedure 2 runs. Linear. Predictable.

**Shiny is reactive.** You don't write the order of execution. Instead, you declare relationships: "this output depends on those inputs." Shiny figures out when to recompute based on what changed. The order is determined by the dependency graph, not by the order you wrote the code.

```r
# Conceptual Shiny example
output$plot <- renderPlot({
  data_filtered <- input$dataset |> filter(group == input$group)
  ggplot(data_filtered, aes(x, y)) + geom_point()
})
```

When the user changes `input$group`, Shiny notices that `output$plot` depends on `input$group` and re-runs the `renderPlot` block automatically. You didn't write "if input changes, recompute plot" — Shiny inferred it.

This is the conceptual jump. In SAS you control execution; in Shiny you declare dependencies and let the framework control execution.

For SAS programmers, this often feels backwards at first. "Where is the loop?" There is no loop. The framework watches inputs and re-runs the blocks that depend on them, automatically, when needed.

## 4. The three layers of a Shiny app

Every Shiny app has three pieces:

| Piece | What it does | Where it lives |
|---|---|---|
| **UI** | Defines the layout — inputs, outputs, panels, styling | An R object (typically a `fluidPage()` call) |
| **Server** | Defines the reactivity — how outputs respond to inputs | A function `function(input, output, session) { ... }` |
| **App object** | Combines UI + server into a runnable app | `shinyApp(ui, server)` |

A minimal complete Shiny app:

```r
library(shiny)

# UI
ui <- fluidPage(
  titlePanel("Hello Shiny"),
  sidebarLayout(
    sidebarPanel(
      sliderInput("bins", "Number of bins:", min = 1, max = 50, value = 30)
    ),
    mainPanel(
      plotOutput("distPlot")
    )
  )
)

# Server
server <- function(input, output, session) {
  output$distPlot <- renderPlot({
    x <- faithful$waiting
    bins <- seq(min(x), max(x), length.out = input$bins + 1)
    hist(x, breaks = bins, col = "steelblue", main = "")
  })
}

# Combine and run
shinyApp(ui, server)
```

Running this opens a browser window with a slider and a histogram. Moving the slider changes the number of bins; the histogram updates automatically.

The reactive bit: `output$distPlot` reads `input$bins`. Shiny notices this dependency. Whenever `input$bins` changes (slider moves), Shiny re-runs `renderPlot` to refresh `output$distPlot`. No explicit code says "when slider moves, refresh plot." The framework infers it.

## 5. Inputs and outputs

Shiny provides dozens of input widgets and output renderers:

**Common inputs** (UI):
- `sliderInput(id, label, ...)` — slider
- `selectInput(id, label, choices)` — dropdown
- `numericInput(id, label, value)` — number entry
- `textInput(id, label)` — text entry
- `checkboxInput(id, label)` — toggle
- `dateInput(id, label)` — calendar
- `actionButton(id, label)` — clickable button
- `fileInput(id, label)` — file upload

**Common outputs** (UI):
- `plotOutput(id)` — for ggplot/base plots
- `tableOutput(id)` — for simple tables
- `dataTableOutput(id)` — for interactive DT tables
- `textOutput(id)` — for text
- `verbatimTextOutput(id)` — for pre-formatted text
- `uiOutput(id)` — for dynamically generated UI

**Server renderers** (paired with UI outputs):
- `renderPlot({ ... })` paired with `plotOutput`
- `renderTable({ ... })` paired with `tableOutput`
- `renderDataTable({ ... })` paired with `dataTableOutput`
- `renderText({ ... })` paired with `textOutput`
- `renderUI({ ... })` paired with `uiOutput`

The pattern: assign output via `output$id <- render*({ ... })` in the server; reference it in UI via `*Output(id)`. The "id" string links them. Inside the render block, read `input$id` to access any input — that creates the reactive dependency.

## 6. Reactive expressions

For computation reused across multiple outputs, wrap it in `reactive()`:

```r
server <- function(input, output, session) {
  # Compute once, reuse twice
  filtered_data <- reactive({
    iris |> filter(Species == input$species)
  })

  output$summary <- renderTable({
    filtered_data() |> summarise_all(mean)
  })

  output$plot <- renderPlot({
    ggplot(filtered_data(), aes(Sepal.Length, Sepal.Width)) + geom_point()
  })
}
```

`filtered_data` is a reactive expression. Both `output$summary` and `output$plot` call it (note the `()` — reactives are accessed like functions). When `input$species` changes:

1. Shiny invalidates `filtered_data`
2. Both outputs become invalid (they depend on `filtered_data`)
3. Shiny re-runs `filtered_data()` once
4. Both outputs re-render using the new result

Without `reactive()`, the filter would run twice — once per output. `reactive()` is the cache + dependency tracker.

This is essential for performance in larger apps. A teal app filtering a 100k-row clinical dataset doesn't want to re-filter for every output.

## 7. Observers and side effects

`reactive()` is for computing values. For side effects (writing files, sending emails, downloading), use `observeEvent()` or `observe()`:

```r
server <- function(input, output, session) {
  observeEvent(input$download_btn, {
    write.csv(some_data, "outputs/data.csv")
    showNotification("Downloaded!")
  })
}
```

`observeEvent` runs when the named input changes (or button is clicked). It doesn't produce a value — just triggers code.

Distinction: `reactive()` *computes*; `observe()` *acts*. Use the right one.

## 8. Shiny modules — composable Shiny pieces

For apps larger than a single page, Shiny supports **modules** — reusable UI+server pairs that can be combined into a full app. This is the structural foundation teal builds on.

A Shiny module is:

- A **module UI function** that takes a namespace `id` and returns UI elements with namespaced ids
- A **module server function** that takes a namespace `id` and a function body containing reactive logic
- Both functions are paired by the `id` — calling `moduleServer(id, ...)` connects them

A minimal module:

```r
# Module UI
counterUI <- function(id) {
  ns <- NS(id)
  tagList(
    actionButton(ns("button"), "Click me"),
    textOutput(ns("count"))
  )
}

# Module server
counterServer <- function(id) {
  moduleServer(id, function(input, output, session) {
    n <- reactiveVal(0)
    observeEvent(input$button, { n(n() + 1) })
    output$count <- renderText({ paste("Count:", n()) })
  })
}

# App using the module
ui <- fluidPage(
  counterUI("counter1"),
  counterUI("counter2")
)

server <- function(input, output, session) {
  counterServer("counter1")
  counterServer("counter2")
}

shinyApp(ui, server)
```

The result: two independent counters on one page. Each has its own state because they have different namespace ids. The same module is reused; the framework keeps the state isolated.

This is the foundation of teal: **each clinical analysis (demographics, AE, K-M plot) is a Shiny module**. A teal app composes multiple modules into a single application with shared filtering.

Once you understand Shiny modules, teal's vocabulary (`tm_t_summary()`, `tm_g_km()`, etc.) makes sense — each `tm_*` function is a pre-built Shiny module for a specific clinical analysis.

## 9. Layouts and theming

Shiny supports several layout patterns:

```r
# Sidebar + main panel
fluidPage(
  sidebarLayout(
    sidebarPanel(...),
    mainPanel(...)
  )
)

# Tabs
fluidPage(
  tabsetPanel(
    tabPanel("Tab 1", ...),
    tabPanel("Tab 2", ...)
  )
)

# Navigation bar (top-level pages)
navbarPage(
  "App title",
  tabPanel("Page 1", ...),
  tabPanel("Page 2", ...)
)
```

For more modern layouts, the `{bslib}` package extends Shiny with Bootstrap 5-based components (cards, value boxes, accordions). teal uses a fixed layout, but understanding Shiny layouts helps when you need to customize.

For theming, `{bslib}` provides theme customization (colors, fonts). Pharma teams often define a sponsor-specific theme matching corporate branding.

## 10. Reactivity gotchas

Three common bugs that trip up new Shiny developers:

### Reading reactives without `()`

```r
# Wrong
output$plot <- renderPlot({
  ggplot(filtered_data, aes(...))   # missing ()
})

# Right
output$plot <- renderPlot({
  ggplot(filtered_data(), aes(...))   # () makes it reactive
})
```

`filtered_data` is the function object; `filtered_data()` calls it and gets the value.

### Mutating reactives directly

```r
# Wrong — can't assign to reactives like variables
filtered_data <- new_data

# Right — use reactiveVal()
data_state <- reactiveVal(NULL)
data_state(new_data)              # set value
current <- data_state()           # read value
```

For mutable reactive state, use `reactiveVal()` (single value) or `reactiveValues()` (list of values).

### Side effects inside `reactive()`

```r
# Wrong — reactives should be pure computations
my_reactive <- reactive({
  write.csv(data, "file.csv")     # side effect!
  data
})

# Right — separate the side effect
observeEvent(input$save_btn, {
  write.csv(data, "file.csv")
})
```

Reactives should only compute; observers handle actions.

## 11. Running and deploying

Locally, `shinyApp(ui, server)` opens the app in a browser. For deployment to a server (so colleagues can use it):

- **shinyapps.io**: Posit's hosted service (free tier exists; paid tiers for more compute)
- **Shiny Server (open source)**: self-hosted on Linux server
- **Posit Connect** (formerly RStudio Connect): commercial enterprise platform with auth, scheduled jobs, version control
- **Posit Workbench**: developer-focused R/Python environment with built-in Shiny preview
- **Docker**: containerize and deploy anywhere

For pharma production, Posit Connect is the most common choice — it's GxP-validatable and integrates with corporate authentication (SAML, LDAP, OIDC).

Self-hosted Shiny Server works for smaller teams; shinyapps.io is fine for prototypes and internal demos.

## 12. When Shiny is the right tool

Shiny excels at:

- **Internal data exploration tools** for study teams
- **Patient profile viewers** for medical reviewers
- **Ad-hoc analysis interfaces** for biostatisticians
- **Interactive reports** complementing static CSR tables
- **QC dashboards** for in-flight studies

Shiny is **not** the right tool for:

- **Final regulatory submission outputs** — those are static RTFs from your TLG stack
- **High-traffic public websites** — Shiny is single-tenant per R process; scaling requires careful design
- **Mobile-first apps** — Shiny works on mobile but isn't optimized for it
- **Apps where R isn't already the right backend** — if your data is in a SQL database accessed by a Java team, Shiny may not be a fit

For pharma specifically: **Shiny is the interactive complement to static TLGs**, not a replacement. CSR tables stay static (regulatory requirement); Shiny apps add interactive exploration on top.

## 13. The SAS programmer's transition

Common stumbling blocks for SAS programmers learning Shiny:

| SAS habit | Shiny equivalent / shift |
|---|---|
| "Run this PROC after that PROC" | Declare reactive dependencies; framework controls execution order |
| "Save dataset, then use it" | Reactives cache values; no intermediate disk I/O needed |
| "%macro for reuse" | Functions + Shiny modules for reuse |
| "Output window shows results" | Browser shows results; updates push without refresh |
| "PROC PRINT" | `renderDataTable()` for interactive tables |
| "PROC SGPLOT" | `renderPlot()` with ggplot2 |
| "Restart and rerun" | Live reactive updates; can pause via debugger |
| "Submit and wait" | Inputs trigger immediately; can use `bindEvent()` to delay |

The shift takes practice. A useful exercise: pick a SAS report you currently produce, and rebuild a piece of it in Shiny. The first one takes a day; subsequent ones take an hour.

## 14. Shiny + the broader R ecosystem

Shiny doesn't replace the rest of your R toolkit. It wraps it:

- **dplyr / tidyverse** still handles data manipulation inside reactive blocks
- **ggplot2** renders plots in `renderPlot`
- **DT** provides interactive tables via `renderDataTable`
- **plotly** adds interactive plots
- **leaflet** for maps
- **gtsummary / flextable** render tables in Shiny

For clinical Shiny specifically, teal sits on top of all of this — providing the structural framework, the clinical-specific modules, and the standardized filter panel. Shiny is the foundation; teal is the clinical-purpose-built layer.

## 15. Performance considerations

Shiny apps can be slow if you're not careful. Key principles:

- **Cache expensive computations** via `reactive()` so they only run once per input change
- **Use `bindCache()`** to cache reactives across sessions (Shiny 1.6+)
- **Filter early**: subset data once at the top of the reactive chain, not in each output
- **Use server-side processing for large tables** (DT's `server = TRUE` option)
- **Async / future** for long-running computations that shouldn't block the UI

For a typical clinical app filtering a 5,000-subject ADSL, performance is fine without optimization. For apps processing millions of rows (e.g., raw EDC monitoring across multiple studies), optimization matters.

## 16. Validation considerations

For GxP-relevant Shiny apps (e.g., apps used to support regulatory decisions):

- The Shiny package itself has a long stable history with extensive testing
- Apps you build need their own validation — typically computational testing of the analytical logic separately from UI testing
- For pharma production, **Posit Connect** provides version control, audit trails, and access control suitable for validated environments
- Some sponsors use **GxP Validation Summit** patterns and the **`{validation}`** package for app validation documentation

Shiny apps are increasingly accepted in GxP environments. The package's stability and validation evidence (`riskmetric` scores it favorably — covered in Lesson 46) supports this.

## 17. Putting it together: a clinical mini-app

A small app that filters ADSL and shows demographics:

```r
library(shiny)
library(dplyr)
library(ggplot2)
library(pharmaverseadam)

adsl <- pharmaverseadam::adsl

ui <- fluidPage(
  titlePanel("ADSL Demographics Explorer"),
  sidebarLayout(
    sidebarPanel(
      selectInput("treatment", "Treatment:",
                  choices = c("All", levels(factor(adsl$TRT01A)))),
      selectInput("sex", "Sex:",
                  choices = c("All", "M", "F"))
    ),
    mainPanel(
      h3("Summary"),
      tableOutput("summary"),
      h3("Age Distribution"),
      plotOutput("agePlot")
    )
  )
)

server <- function(input, output, session) {
  filtered <- reactive({
    df <- adsl
    if (input$treatment != "All") df <- df |> filter(TRT01A == input$treatment)
    if (input$sex != "All")       df <- df |> filter(SEX == input$sex)
    df
  })

  output$summary <- renderTable({
    filtered() |>
      summarise(
        N        = n(),
        Mean_Age = mean(AGE, na.rm = TRUE),
        SD_Age   = sd(AGE, na.rm = TRUE)
      )
  })

  output$agePlot <- renderPlot({
    ggplot(filtered(), aes(AGE)) +
      geom_histogram(binwidth = 5, fill = "steelblue", color = "white") +
      labs(x = "Age (years)", y = "Count")
  })
}

shinyApp(ui, server)
```

50 lines of code → an interactive demographics explorer. Change either filter; both the summary and the plot update. This is roughly what a single-module teal app looks like under the hood.

## 18. Key takeaways

- Shiny is R's framework for building interactive web apps
- The conceptual core is **reactive programming**: declare dependencies, let the framework manage execution
- Three pieces: UI (layout), server (reactivity), `shinyApp()` (combine)
- `reactive()` for cached computations; `observe()`/`observeEvent()` for side effects
- Shiny modules enable composable, reusable UI+server pairs — the foundation of teal
- For pharma: complementary to static TLGs, not a replacement; ideal for exploratory dashboards and patient profiles
- Posit Connect is the typical production deployment in regulated environments
- The shift from procedural (SAS) to reactive (Shiny) thinking is the main conceptual hurdle

## 19. What's next

Lesson 39 covers **`{teal}` Part 1** — the framework architecture. Where this lesson covered Shiny generically, Lesson 39 covers teal's clinical-specific structure: `teal_data()`, `init()`, the filter panel, reproducibility, and the modular composition pattern that makes teal apps assembled rather than coded.

After teal Part 1: teal.modules.general (Lesson 40), teal.modules.clinical deep dive (Lesson 41), and custom modules + deployment + validation (Lesson 42).

---

## Self-check questions

1. Explain reactive programming to a SAS programmer in one paragraph.
2. What's the difference between `reactive()` and `observe()`?
3. Why must you call a reactive with parentheses (`filtered_data()`) when reading it?
4. What is a Shiny module, and why does it matter for teal?
5. Translate to Shiny vocabulary: "When the user changes the dropdown, update the histogram below."
6. When would you use Shiny in pharma, and when would you stay with static reports?

## Glossary

- **Shiny** — Posit's R package for building interactive web applications
- **Reactive programming** — Programming model where outputs are declared as functions of inputs; framework controls execution order based on dependencies
- **UI / Server / `shinyApp()`** — The three pieces of every Shiny app
- **`input$id` / `output$id`** — Shiny's input/output namespace
- **`render*()`** — Server functions paired with `*Output()` UI elements
- **`reactive()`** — A cached reactive computation; accessed with `()`
- **`observe()` / `observeEvent()`** — Side-effect reactive blocks
- **`reactiveVal()` / `reactiveValues()`** — Mutable reactive state
- **Shiny module** — Reusable UI+server pair with namespaced ids; foundation of teal
- **`NS(id)`** — Namespace constructor for module ids
- **`moduleServer(id, function)`** — Module server attachment
- **Posit Connect** — Commercial deployment platform for Shiny in regulated environments
- **shinyapps.io** — Posit's hosted Shiny service
- **`{bslib}`** — Modern Bootstrap-based layouts and themes for Shiny
- **`bindEvent()`** — Delays a reactive's invalidation until a specific trigger
- **GxP** — Good Practice; the family of FDA quality regulations
