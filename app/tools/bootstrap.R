#!/usr/bin/env Rscript
# Check by default. Package installation happens only with an explicit --install.
args <- commandArgs(trailingOnly = TRUE)
if (length(args) && !all(args %in% c("--check", "--install"))) stop("Use --check or --install.")
script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1L])
root <- normalizePath(file.path(dirname(script), ".."), winslash = "/", mustWork = TRUE)
source(file.path(root, "R/toolbox.R"), encoding = "UTF-8")
report <- tb_dependency_report()
if ("--install" %in% args && any(!report$installed)) {
  if (!requireNamespace("BiocManager", quietly = TRUE))
    install.packages("BiocManager", repos = "https://cloud.r-project.org")
  BiocManager::install(report$package[!report$installed], ask = FALSE, update = FALSE)
  report <- tb_dependency_report()
}
cat("R", as.character(getRversion()), "\n")
print(report[c("package", "installed", "version")], row.names = FALSE)
quit(status = if (all(report$installed)) 0L else 1L)
