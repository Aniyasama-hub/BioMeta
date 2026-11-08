# 用固定R环境执行，只报告依赖版本；不会安装或更新任何包。
packages <- c(
  "shiny", "markdown", "processx", "zip", "readxl", "scatterplot3d",
  "org.Hs.eg.db", "org.Mm.eg.db", "GO.db", "AnnotationDbi",
  "digest", "jsonlite", "DESeq2", "SummarizedExperiment", "tximport",
  "ggplot2", "ggrepel", "svglite", "ComplexHeatmap", "circlize",
  "patchwork", "limma", "clusterProfiler", "fgsea", "GSVA", "BiocParallel", "igraph"
)
versions <- vapply(packages, function(package) {
  path <- find.package(package, quiet = TRUE)
  if (!length(path)) return(NA_character_)
  tryCatch(unname(read.dcf(file.path(path, "DESCRIPTION"), fields = "Version")[1, 1]),
             error = function(e) NA_character_)
}, character(1))
print(data.frame(package = packages, version = versions,
                 status = ifelse(is.na(versions), "missing", "installed")), row.names = FALSE)
cat("R:", as.character(getRversion()), "\n")
