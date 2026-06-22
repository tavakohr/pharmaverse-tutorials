# ==============================================================================
# setup.R — first-time clone bootstrap
# ------------------------------------------------------------------------------
# Run once after cloning, from the project root:
#
#   Rscript setup.R
#
# or, inside an R session opened in the project folder:
#
#   source("setup.R")
#
# What this script does (DEFAULT — lightweight mode):
#   1. Verifies R version is >= 4.4
#   2. Configures the Posit Public Package Manager (P3M) so Windows / macOS
#      users get pre-built binary packages (no Rtools / Xcode needed)
#   3. Installs (or upgrades) the renv package itself, then activates the
#      project library
#   4. Installs ONLY the runtime packages the tutorials need that are not
#      already available — it does NOT reinstall the whole lockfile. Packages
#      you already have are reused; nothing is rebuilt from scratch.
#   5. Verifies the critical packages load and reports a clear pass/fail
#
# FULL REPRODUCIBLE MODE (opt-in):
#   Restore the EXACT lockfile (every package + version, incl. dev tooling like
#   devtools / covr / rcmdcheck). Slow on a cold clone — installs everything.
#   Enable with either:
#       Rscript setup.R full
#       PHARMAVERSE_FULL_RESTORE=1 Rscript setup.R
#   Use this only when you need bit-for-bit reproducibility, not for running
#   the tutorials.
# ==============================================================================

# ---- Mode selection ----------------------------------------------------------
.args <- commandArgs(trailingOnly = TRUE)
full_restore <- ("full" %in% .args) ||
  identical(Sys.getenv("PHARMAVERSE_FULL_RESTORE"), "1")

required_r <- "4.4.0"
if (getRversion() < required_r) {
  stop(sprintf(
    "This project needs R >= %s. You are running R %s. Please upgrade R first.",
    required_r, getRversion()
  ))
}

# ---- P3M binary repos (Windows / macOS get pre-compiled .zip / .tgz) ---------
p3m_url <- "https://packagemanager.posit.co/cran/latest"
options(
  repos = c(CRAN = p3m_url),
  HTTPUserAgent = sprintf(
    "R/%s R (%s)",
    getRversion(),
    paste(getRversion(), R.version$platform, R.version$arch, R.version$os)
  ),
  install.packages.check.source = "no",
  install.packages.compile.from.source = "never",
  renv.config.pak.enabled = FALSE
)

message("Using package repository: ", p3m_url)
message("R version: ", getRversion(), " on ", R.version$platform)

# ---- Ensure renv is installed ------------------------------------------------
if (!requireNamespace("renv", quietly = TRUE)) {
  message("Installing renv ...")
  install.packages("renv")
}

# ---- Activate project library ------------------------------------------------
source("renv/activate.R")

# ---- The core stack every tutorial needs -------------------------------------
# The runtime packages — and ONLY these (plus their dependencies) get installed
# in default mode. No dev/check tooling. Mirrors the libraries loaded across the
# pharmaverse_tutorials/ Rmd setup chunks.
core_pkgs <- c(
  "learnr", "gradethis", "shiny", "rmarkdown", "knitr",
  "dplyr", "tidyr", "tibble", "stringr", "lubridate", "purrr", "forcats",
  "rlang", "glue", "jsonlite", "remotes",
  "pharmaverseadam", "pharmaversesdtm", "pharmaverseraw",
  "admiral", "admiraldev", "sdtm.oak",
  "metacore", "metatools", "xportr",
  "cards", "cardx", "cardinal", "gtsummary", "gt", "tfrmt",
  "rtables", "tern", "r2rtf", "Tplyr", "tidytlg",
  "diffdf", "riskmetric", "logrx", "datasetjson",
  "teal", "teal.data", "teal.modules.clinical", "teal.widgets"
)

# ---- Full reproducible restore (opt-in only) ---------------------------------
# Materializes the ENTIRE lockfile. This is what pulls in dev/check tooling
# (devtools, covr, rcmdcheck, ...) and reinstalls everything on a cold clone.
# Skipped by default so the tutorials get a lean, fast setup.
if (full_restore) {
  message("FULL restore requested — installing the complete lockfile ...")
  tryCatch(
    renv::restore(prompt = FALSE, clean = FALSE),
    error = function(e)
      message("renv::restore() problem: ", conditionMessage(e),
              "\nFalling through to the missing-only install.")
  )
}

# ---- Install ONLY the missing runtime packages -------------------------------
# requireNamespace() sees every active library path, so anything already
# installed (in the renv project library OR your user library) is reused — only
# genuinely missing packages are downloaded. install_versions intentionally
# ignored: we want "available", not "exact lockfile version", for the tutorials.
#
# Uses renv::install when renv is active (cache-aware, binary-first, no prompt)
# and falls back to install.packages, retrying on the pharmaverse /
# insightsengineering r-universe repos for packages CRAN/P3M does not carry.
.install_one <- function(pkg) {
  uni <- c("https://pharmaverse.r-universe.dev",
           "https://insightsengineering.r-universe.dev", p3m_url)
  if (requireNamespace("renv", quietly = TRUE)) {
    ok <- tryCatch({ renv::install(pkg, prompt = FALSE); TRUE },
                   error = function(e) FALSE)
    if (ok && requireNamespace(pkg, quietly = TRUE)) return(invisible())
  }
  try(install.packages(pkg), silent = TRUE)
  if (!requireNamespace(pkg, quietly = TRUE)) {
    message("  ! '", pkg, "' not on the configured repo — trying r-universe ...")
    try(install.packages(pkg, repos = uni), silent = TRUE)
  }
  invisible()
}

install_missing <- function(pkgs) {
  missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing) == 0) {
    message("All ", length(pkgs), " core packages already available — nothing to install.")
    return(invisible(character(0)))
  }
  message("Installing ", length(missing), " missing runtime package(s): ",
          paste(missing, collapse = ", "))
  for (pkg in missing) .install_one(pkg)
  pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
}

install_missing(core_pkgs)

# ---- Report ------------------------------------------------------------------
missing_critical <- c("learnr", "dplyr", "pharmaverseadam", "admiral", "cards")
still_missing <- missing_critical[
  !vapply(missing_critical, requireNamespace, logical(1), quietly = TRUE)
]

if (length(still_missing) == 0) {
  message("\nSetup complete. You can now open any tutorial in pharmaverse_tutorials/")
  message("and click 'Run Document' in RStudio, or run:")
  message("  rmarkdown::run(\"pharmaverse_tutorials/04_datastep_to_dplyr.Rmd\")")
} else {
  warning(
    "Setup finished with missing packages: ",
    paste(still_missing, collapse = ", "),
    ".\nCheck your internet connection / proxy and re-run setup.R, or install them manually."
  )
}
