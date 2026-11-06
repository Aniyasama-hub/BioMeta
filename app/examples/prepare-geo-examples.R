# Convert locally supplied GEO example matrices to the workbench's input schema.
# Usage: Rscript prepare-geo-examples.R APP_ROOT HUMAN_DIR MOUSE_DIR
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3L) stop("Expected APP_ROOT HUMAN_DIR MOUSE_DIR")
read_tsv <- function(path) utils::read.delim(path, check.names = FALSE, stringsAsFactors = FALSE)
write_table <- function(data, path) utils::write.table(data, path, sep = "\t", quote = FALSE, row.names = FALSE)
for (species in c("human", "mouse")) {
  directory <- args[if (species == "human") 2L else 3L]
  dest <- file.path(args[1], "results", "toolbox", "examples", species)
  dir.create(dest, recursive = TRUE, showWarnings = FALSE)
  groups <- read_tsv(file.path(directory, "group.tsv"))
  expression <- read_tsv(file.path(directory, "log2cpm.tsv.gz"))
  stopifnot(identical(names(expression)[-1], groups$sample_id), !anyDuplicated(expression[[1]]))
  write_table(data.frame(Sample = groups$sample_id, Group = groups$group), file.path(dest, "groups.tsv"))
  names(expression)[1] <- "gene_id"
  write_table(expression, file.path(dest, "matrix.tsv"))
  if (species == "human") {
    counts <- read_tsv(file.path(directory, "counts.tsv.gz"))
    stopifnot(identical(names(counts)[-1], groups$sample_id), !anyDuplicated(counts[[1]]),
      all(vapply(counts[-1], function(x) all(is.finite(x) & x >= 0 & x == floor(x)), logical(1))))
    write_table(data.frame(gene_id = counts[[1]], gene_name = counts[[1]], counts[-1], check.names = FALSE),
      file.path(dest, "counts.tsv"))
    markers <- intersect(c("CD3D", "CD3E", "CD4", "CD8A", "MS4A1", "CD19", "LYZ", "CD68",
      "ITGAM", "CXCL9", "CXCL10", "IFNG", "STAT1", "HLA-DRA", "GBP1"), counts[[1]])
    write_table(data.frame(GeneKey = markers, Use = TRUE), file.path(dest, "targets.tsv"))
  }
}
