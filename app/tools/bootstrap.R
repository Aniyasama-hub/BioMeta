#!/usr/bin/env Rscript
# Check by default. Package installation happens only with an explicit --install.
args <- commandArgs(trailingOnly = TRUE)
if (length(args) && !all(args %in% c("--check", "--install"))) stop("Use --check or --install.")
script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1L])
root <- normalizePath(file.path(dirname(script), ".."), winslash = "/", mustWork = TRUE)
# Match the library configured in Settings; a fresh installation needs a writable library.
settings_file <- file.path(root, "results/toolbox/settings.json")
if (file.exists(settings_file) && requireNamespace("jsonlite", quietly = TRUE)) {
  settings <- jsonlite::read_json(settings_file, simplifyVector = TRUE)
  if (identical(settings$library_r, as.character(getRversion())) &&
      length(settings$package_library) == 1L && dir.exists(settings$package_library))
    .libPaths(c(settings$package_library, .libPaths()))
}
if ("--install" %in% args && file.access(.libPaths()[1L], 2L) != 0L) {
  library <- strsplit(Sys.getenv("R_LIBS_USER"), .Platform$path.sep, fixed = TRUE)[[1L]][1L]
  if (!nzchar(library)) stop("No writable R library. Configure R_LIBS_USER and retry.")
  dir.create(library, recursive = TRUE, showWarnings = FALSE)
  .libPaths(c(library, .libPaths()))
}
options(repos = c(CRAN = "https://mirrors.tuna.tsinghua.edu.cn/CRAN/"))
source(file.path(root, "R/toolbox.R"), encoding = "UTF-8")
report <- tb_dependency_report()
if ("--install" %in% args && any(!report$installed)) {
  if (!requireNamespace("BiocManager", quietly = TRUE))
    install.packages("BiocManager")
  BiocManager::install(report$package[!report$installed], ask = FALSE, update = FALSE)
  report <- tb_dependency_report()
}
cat("R", as.character(getRversion()), "\n")
print(report[c("package", "installed", "version")], row.names = FALSE)
quit(status = if (all(report$installed)) 0L else 2L)
