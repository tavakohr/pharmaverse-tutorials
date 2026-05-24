# Lesson 02 — Environment Setup: R, RStudio, and Pharmaverse Packages

**Module**: 0 — Introduction
**Estimated length**: ~20 min spoken
**Prerequisites**: Lessons 00–01

---

## Learning objectives

By the end of this lesson, you will be able to:

1. Install R and RStudio on Windows, macOS, or Linux — or choose Posit Cloud as a no-install alternative
2. Configure RStudio for clinical R work (project structure, options, useful add-ins)
3. Install pharmaverse packages individually, via the pharmaverse R-universe, or via the CRAN Task View
4. Set up a project with `renv` for reproducibility — critical for regulated work
5. Verify your installation by loading `admiral` and accessing test data
6. Troubleshoot the most common setup issues

---

## 1. Choose your platform

Before installing anything, decide where you'll run R. There are four reasonable options:

**Option A — Local R + RStudio Desktop (recommended for most learners).** Free, runs on your own machine, full control. Best for learning and personal projects. You'll install R itself and RStudio Desktop separately.

**Option B — Posit Cloud (recommended if you can't install software).** A browser-based R environment. Free tier exists, paid tiers for heavier use. Pre-configured with packages. Best when you're on a locked-down corporate machine, on a tablet, or training a class where you can't ask every participant to install software. The pharmaverse Examples site uses Posit Cloud explicitly for this reason.

**Option C — Posit Workbench (your company likely has this).** The enterprise version, typically deployed on a Linux server inside your company. Same RStudio interface, but the R session runs on the server, not your laptop. If your company has it, use it for real study work — IT has already validated the environment.

**Option D — Docker container.** For reproducibility freaks. Build a fixed image with exact package versions, ship it with your study. We won't cover this in this lesson but the `rocker/r-ver` and `pharmaverse/pharmaverse` Docker images are starting points.

For this curriculum, we'll assume **Option A (local R + RStudio Desktop)** with notes for Posit Cloud where they diverge. Once you've used R locally for a week, Posit Cloud and Workbench will feel identical.

## 2. Install R (the language)

R is the language. RStudio is the editor. You must install R first; RStudio without R does nothing.

Download R from the official CRAN mirror: **<https://cran.r-project.org>**

Pick your operating system, then the latest release. For this curriculum we assume **R version ≥ 4.3.0**. Some pharmaverse packages (notably newer `gtsummary` versions) require R ≥ 4.2.

**Windows**: Download the `.exe` installer, run it, click Next through defaults. The default installation directory is fine.

**macOS**: Download the `.pkg` for your processor (Apple Silicon → arm64, Intel → x86_64). Run it. If you have an Apple Silicon Mac, take the arm64 build — performance is dramatically better.

**Linux**: Use your distro's package manager. On Ubuntu, follow the instructions at <https://cran.r-project.org/bin/linux/ubuntu/> rather than installing the version in your distro's default repository, which is often years out of date.

After installation, verify by opening a terminal (or Command Prompt on Windows) and typing:

```bash
R --version
```

You should see something like:

```
R version 4.3.2 (2023-10-31) -- "Eye Holes"
```

If you see "command not found," R isn't on your PATH. Reinstalling usually fixes this on Windows; on macOS/Linux, double-check the installer completed.

## 3. Install RStudio Desktop (the editor)

R alone is usable, but RStudio adds a script editor, debugger, package manager, plot viewer, and dozens of other conveniences. Free for personal and academic use.

Download from: **<https://posit.co/download/rstudio-desktop/>**

It will auto-detect your installed R. Install with defaults.

When you launch RStudio, you'll see a four-pane interface:

```
┌──────────────────────┬──────────────────────┐
│                      │                      │
│  Source (your code)  │  Environment / Hist  │
│                      │                      │
├──────────────────────┼──────────────────────┤
│                      │                      │
│  Console (R itself)  │  Files / Plots /     │
│                      │  Packages / Help     │
│                      │                      │
└──────────────────────┴──────────────────────┘
```

If you're coming from SAS Enterprise Guide or SAS Studio, the layout will feel familiar. The Source pane is your program editor. The Console is the SAS-equivalent log + output combined. The Environment pane shows the datasets currently in memory (R's equivalent of the SAS WORK library).

## 4. Configure RStudio for clinical work

A few settings make life easier:

**Tools → Global Options → Code → Editing**:
- Auto-indent code after newline: on
- Insert spaces for tab: on
- Tab width: 2 (R community convention)

**Tools → Global Options → Code → Display**:
- Show line numbers: on
- Highlight selected line: on
- Show indent guides: on
- Margin column: 80 (clinical code reviewers prefer narrow lines)

**Tools → Global Options → General → R Sessions**:
- Restore .RData into workspace at startup: **off** (critical — see next paragraph)
- Save workspace to .RData on exit: **never**

That last one matters. By default, RStudio will save your entire workspace when you close it and restore it next time. This is *terrible* for reproducibility — you end up running scripts against ghosts of yesterday's data. Always start with a clean session. If you need data persisted, save it explicitly to a file.

**Tools → Global Options → Code → Diagnostics**:
- Show diagnostics for R: on
- Check arguments to R function calls: on
- Warn if variable used has no definition in scope: on

These give you SAS-log-like warnings inside the editor as you type.

## 5. Understand R's package model

Coming from SAS, your mental model of "macros" → "R packages" is approximately right, but with key differences:

- **Packages are versioned, installed, then loaded.** You install once (per machine) and load every session.
- **Packages live in a local library**, typically `~/R/x86_64-pc-linux-gnu-library/4.3` on Linux or `Documents/R/win-library/4.3` on Windows.
- **Installation comes from CRAN by default**, but pharmaverse packages can come from CRAN, GitHub, or the pharmaverse R-universe.



Install a package:

```r

installed.packages()[, "Package"]

install.packages("admiral")
```

Load a package (every session):

```r
library(admiral)
```

Update a package:

```r
update.packages("admiral")
# or
install.packages("admiral")  # re-installs latest
```

Check version:

```r
packageVersion("admiral")
```

## 6. Install pharmaverse packages

There are three reasonable ways to get the packages.

### Way 1 — Install individual packages from CRAN

This is the recommended approach for most users. CRAN versions are stable, tested, and have passed CRAN's quality checks.

For the foundational stack covered early in this curriculum:

```r
install.packages(c(
  "admiral",           # ADaM derivations
  "pharmaversesdtm",   # test SDTM data
  "pharmaverseadam",   # test ADaM data
  "metacore",          # metadata objects
  "metatools",         # metadata-driven dataset building
  "xportr",            # XPT v5 export for FDA submission
  "cards",             # ARD generation
  "gtsummary",         # ARD → tables
  "dplyr",             # tidyverse data manipulation
  "tidyr"              # tidyverse data reshaping
))
```

This will pull in their dependencies automatically. Expect this to take 5–15 minutes on a fresh installation.

### Way 2 — Install via the pharmaverse CRAN Task View

This pulls everything pharmaverse-affiliated at once:

```r
install.packages("ctv")
ctv::install.views("Pharmaverse")
```

Useful for setting up a training environment, but heavy if you only need a subset.

### Way 3 — Install development versions via the pharmaverse R-universe

The R-universe provides automatic builds of the latest development versions. Use when you need a recent feature not yet on CRAN:

```r
install.packages("admiral",
                 repos = c("https://pharmaverse.r-universe.dev",
                           "https://cloud.r-project.org"))
```

**For regulated production work, prefer CRAN versions** (Way 1). CRAN releases are stable and reproducible. Use development versions only when CRAN has a known critical bug or you need a feature that's been merged but not yet released.

### A faster installer: `{pak}`

The base `install.packages()` is fine but slow. `{pak}` is dramatically faster, handles dependencies more intelligently, and gives better error messages:

```r
install.packages("pak")

pak::pkg_install(c("admiral", "cards", "gtsummary", "xportr",
                   "metacore", "metatools", "pharmaverseadam"))
```

This is what the pharmaverse Examples site uses. I recommend adopting it.

## 7. Set up a project (always work in projects)

In SAS, you might have loose programs floating in folders. In R, work is organized into **projects** — self-contained folders with their own working directory, history, and ideally their own package library.

**Create a project**: RStudio → File → New Project → New Directory → New Project. Pick a folder name like `pharmaverse_tutorial` and a parent location.

A project gives you:

- A `.Rproj` file that, when opened, sets the working directory automatically
- Per-project command history
- A logical container for your code, data, and outputs
- The foundation for `renv` (next section)

Within the project, a useful folder layout:

```
pharmaverse_tutorial/
├── pharmaverse_tutorial.Rproj
├── R/                  # your reusable functions
├── scripts/            # one .R file per analysis step
│   ├── 01_build_adsl.R
│   ├── 02_build_adae.R
│   └── 03_demographics_table.R
├── data/               # input data (or symlinks to it)
├── output/             # generated tables, listings, XPT files
└── renv/               # managed by renv, see next section
```

This mirrors what most clinical R projects look like in production.

## 8. Reproducibility with `renv` — critical for regulated work

Here's a scenario every SAS programmer dreads: you produce a submission in 2025 using `admiral 1.0.2`. In 2027, a regulator asks you to re-run a sensitivity analysis. You go to your machine, but `admiral` is now at version 1.4.0 and the function arguments have changed. Your old code breaks.

`{renv}` solves this. It creates a project-local package library, snapshots exactly which versions are in use, and restores them on demand.

```r
install.packages("renv")
pak::pkg_install(c("renv"))
```

Inside your project:

```r
renv::init()        # initialize: create project-local library
                    # automatically detects packages used in your code

renv::snapshot()    # record current package versions in renv.lock

# Later, on a different machine or after time has passed:
renv::restore()     # install exactly the recorded versions
```

The `renv.lock` file is text-based JSON. Check it into version control alongside your code. Anyone who clones your project and runs `renv::restore()` gets a bit-for-bit identical R environment.

**For any study work intended for submission, `renv` is essentially mandatory.** Without it, you cannot reliably reproduce your analysis years later — and reproducibility is the regulatory baseline.

A typical workflow:

1. `renv::init()` when you start the project
2. Install packages as needed: `pak::pkg_install("admiral")`
3. `renv::snapshot()` after major changes to lock in the new state
4. Commit `renv.lock` and `renv/activate.R` to git; don't commit `renv/library/`
5. When you (or a colleague) restore the project, `renv::restore()` rebuilds the library

## 9. Verify your installation

Run this in the RStudio console. If everything works, you're set.

```r
# Load core packages
library(dplyr)
library(admiral)
library(pharmaverseadam)

# Look at the bundled ADSL
data("adsl", package = "pharmaverseadam")
glimpse(adsl)

# Use one admiral function — derive ADSL date variables from a sample
adsl |>
  select(USUBJID, TRTSDT, TRTEDT, TRTDURD) |>
  head()
```

You should see output describing 254 rows of the ADSL dataset, with columns including USUBJID, TRTSDT, TRTEDT, TRTDURD, and more. If you see this, your environment is working.

Check key versions:

```r
packageVersion("admiral")
packageVersion("cards")
packageVersion("gtsummary")
packageVersion("xportr")
```

Record these in a notebook or in your project's README. You'll thank yourself later.

## 10. Common installation issues

**Issue: `install.packages()` fails with a compilation error.**

On Windows, install Rtools from <https://cran.r-project.org/bin/windows/Rtools/>. Match the Rtools version to your R version (Rtools43 for R 4.3.x). On macOS, install Xcode Command Line Tools: `xcode-select --install`. On Linux (Ubuntu), `sudo apt-get install r-base-dev`.

**Issue: A package fails to install because a dependency fails to install.**

Read the error carefully — it usually names the dependency. Install that explicitly, then retry. Sometimes you need a system library (on Linux, things like `libxml2-dev`, `libssl-dev`). The error message names the file it's looking for.

**Issue: `library()` works but functions aren't found.**

Two packages may have conflicting function names. Check with `conflicts()`. Use the explicit `package::function()` form when in doubt, e.g. `dplyr::filter()` vs the older `stats::filter()` (which is a time-series function).

**Issue: Everything is slow.**

Check whether your antivirus is scanning every file R touches. On Windows this can be devastating. Add the R installation directory and your R library directory to the antivirus exclusion list.

**Issue: On a corporate machine, CRAN downloads fail.**

Your company likely runs an internal CRAN mirror (Posit Package Manager or similar). Ask IT for the URL, then set it in your `~/.Rprofile`:

```r
options(repos = c(CRAN = "https://your-company-cran-mirror.com"))
```

## 11. A note on Posit Cloud specifically

If you're using Posit Cloud instead of local RStudio, everything above applies with two differences:

- **Skip installing R and RStudio.** They're pre-installed.
- **Memory and CPU are limited on the free tier.** For learning, fine. For real study work, you'll outgrow it quickly.

To follow this curriculum on Posit Cloud:

1. Sign up at <https://posit.cloud>
2. Create a new project
3. Run the installation commands from sections 6 and 8 above
4. The project will persist across browser sessions

Many pharmaverse examples link directly to runnable Posit Cloud environments — look for the "Launch Posit Cloud" button on the Examples site. These come pre-configured with all needed packages.

## 12. Optional but recommended: install Quarto

Quarto is the modern R Markdown — a system for writing documents that mix prose, code, and output. Pharmaverse uses it for all examples and most documentation. Many TLG workflows produce final reports as Quarto documents rendered to RTF, PDF, or HTML.

Download from <https://quarto.org/docs/get-started/>. It installs alongside R. You don't need it for the early lessons, but you'll want it by Module 6.

## 13. Key takeaways

- R + RStudio Desktop is the standard local setup; Posit Cloud is a fine alternative if you can't install software
- Configure RStudio to *not* save/restore `.RData` — fresh sessions are reproducible sessions
- Use `pak::pkg_install()` instead of `install.packages()` for faster, more reliable installs
- Always work in **projects**, not loose files
- Use `renv` for any project intended for production — it's the only way to guarantee reproducibility of an analysis years later
- Verify your installation by loading `admiral` and inspecting bundled `pharmaverseadam::adsl`

## 14. What's next

Your environment is ready. Lesson 03 starts the R fundamentals — explained for SAS programmers, with side-by-side comparisons. We'll cover R's data structures, types, and the equivalents of SAS variables, missing values, and the SAS WORK library.

If you're already comfortable in R, skim Lessons 03–06 and jump to Module 2 (`{pharmaverseraw}`).

---

## Self-check questions

1. What's the difference between R and RStudio?
2. Why should you turn off "Restore .RData into workspace at startup"?
3. What does `renv` give you, and why is it essentially mandatory for submission work?
4. Name three ways to install pharmaverse packages. When would you use each?
5. What's the difference between `install.packages("admiral")` and `library(admiral)`?

## Glossary

- **CRAN** — Comprehensive R Archive Network; the canonical R package repository
- **R-universe** — Alternative package repository; pharmaverse uses it for dev versions
- **RStudio** — IDE for R, made by Posit (formerly RStudio PBC)
- **Posit Cloud** — Hosted RStudio in a browser; free tier available
- **Posit Workbench** — Enterprise RStudio on a corporate server
- **`{renv}`** — Project-local package library + lockfile system for reproducibility
- **`{pak}`** — Modern, faster alternative to `install.packages()`
- **Project** — A folder with a `.Rproj` file; the recommended unit of R work organization
- **Quarto** — Successor to R Markdown; literate-programming system for mixing prose, code, and output
