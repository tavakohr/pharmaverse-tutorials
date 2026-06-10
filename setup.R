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
# What this script does:
#   1. Verifies R version is >= 4.4
#   2. Configures the Posit Public Package Manager (P3M) so Windows / macOS
#      users get pre-built binary packages (no Rtools / Xcode needed)
#   3. Installs (or upgrades) the renv package itself
#   4. Activates the project library and runs renv::restore() non-interactively
#   5. On failure, falls back to install.packages() for the critical pharmaverse
#      packages so the tutorials can still run
# ==============================================================================

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

# ---- Restore lockfile --------------------------------------------------------
restore_ok <- tryCatch({
  renv::restore(prompt = FALSE, clean = FALSE)
  TRUE
}, error = function(e) {
  message("renv::restore() failed: ", conditionMessage(e))
  FALSE
})

# ---- Fallback: install critical packages directly ----------------------------
if (!restore_ok) {
  message("Falling back to direct install.packages() for the core stack ...")

  core_pkgs <- c(
    "learnr", "gradethis", "shiny", "rmarkdown", "knitr",
    "dplyr", "tidyr", "tibble", "stringr", "lubridate", "purrr", "forcats",
    "rlang", "glue", "jsonlite",
    "pharmaverseadam", "pharmaversesdtm", "pharmaverseraw",
    "admiral", "admiraldev",
    "metacore", "metatools", "xportr",
    "cards", "cardx", "cardinal", "gtsummary", "gt", "tfrmt",
    "rtables", "tern", "r2rtf", "Tplyr", "tidytlg",
    "diffdf", "riskmetric", "logrx", "datasetjson",
    "teal", "teal.data", "teal.modules.clinical", "teal.widgets"
  )

  for (pkg in core_pkgs) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      try(install.packages(pkg), silent = TRUE)
    }
  }
}

# ---- Report ------------------------------------------------------------------
missing_critical <- c("learnr", "dplyr", "pharmaverseadam", "admiral")
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
