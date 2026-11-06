args <- commandArgs(trailingOnly = TRUE)
library_path <- args[1L]
packages <- args[-1L]
.libPaths(c(library_path, .libPaths()))
options(repos = c(CRAN = "https://cloud.r-project.org"))
if (!requireNamespace("BiocManager", quietly = TRUE)) install.packages("BiocManager", lib = library_path)
BiocManager::install(packages, lib = library_path, ask = FALSE, update = FALSE, force = TRUE)
if (!all(vapply(packages, function(pkg) length(find.package(pkg, lib.loc = library_path, quiet = TRUE)) > 0L,
                logical(1)))) stop("Some selected packages could not be installed in the workbench library.")
