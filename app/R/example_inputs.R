tb_geo_catalog <- function(root) {
  folders <- list.dirs(file.path(root, "examples", "datasets"), recursive = FALSE)
  folders <- folders[file.exists(file.path(folders, "preset.json"))]
  stats::setNames(folders, basename(folders))
}

tb_geo_preset <- function(root, dataset) {
  directory <- tb_geo_catalog(root)[dataset]
  if (!length(directory) || is.na(directory)) return(NULL)
  jsonlite::read_json(file.path(directory, "preset.json"))
}

tb_zip_example <- function(root, dataset, file) {
  folders <- tb_geo_catalog(root)
  directory <- if (identical(dataset, "synthetic")) file.path(root, "examples") else unname(folders[dataset])
  if (length(directory) != 1L || is.na(directory) || !dir.exists(directory)) stop("当前示例目录不存在。")
  files <- list.files(directory, recursive = TRUE, full.names = FALSE)
  if (identical(dataset, "synthetic")) files <- files[!grepl("[/\\\\]|[.]R$", files, ignore.case = TRUE)]
  files <- files[!dir.exists(file.path(directory, files))]
  if (!length(files)) stop("当前示例没有可下载的文件。")
  zip::zipr(file, files, root = directory, include_directories = FALSE)
}

tb_example_dataset <- function(root, tool, species) {
  counts <- tool %in% c("bulk", "pca", "deg", "volcano", "heatmap", "custom_heatmap", tb_pathway_tools)
  matrix <- tool %in% c("matrix_pca", "matrix_heatmap", "immune")
  preset <- if (counts) "human" else if (matrix) species else "synthetic"
  file <- if (counts) "counts.tsv" else "matrix.tsv"
  path <- file.path(root, "results", "toolbox", "examples", preset, file)
  if (file.exists(path)) preset else "synthetic"
}

tb_example_path <- function(root, tool, name, params) {
  dataset <- params$dataset %||% "synthetic"
  directory <- tb_geo_catalog(root)[dataset]
  if (length(directory) && !is.na(directory)) {
    filename <- switch(name, deg = "deg.csv", counts = "counts.tsv", groups = "groups.tsv",
      matrix = "matrix.tsv", targets = "targets.tsv", "")
    path <- file.path(directory, filename)
    return(if (nzchar(filename) && file.exists(path)) normalizePath(path, winslash = "/") else "")
  }
  if (dataset != "synthetic") {
    if (!name %in% c("counts", "groups", "matrix", "targets", "deg")) return("")
    path <- file.path(root, "results", "toolbox", "examples", dataset, paste0(name, if (name == "deg") ".csv" else ".tsv"))
    return(if (file.exists(path)) normalizePath(path, winslash = "/") else "")
  }
  file <- switch(name,
    counts = "demo_counts.csv",
    groups = if (tool %in% c("matrix_pca", "matrix_heatmap")) "groups.csv" else "demo_groups.csv",
    targets = "demo_targets.csv", annotation = "annotation.xlsx", deg = "demo_deg.csv",
    nodes = "ppi_nodes.csv",
    edges = if ((params$network_mode %||% "files") %in% c("deg", "results")) "demo_model_edges.csv" else "ppi_edges.csv",
    gmt = "demo_sets.gmt",
    chromosomes = "circos_chromosomes.csv", features = "circos_features.csv", links = "circos_links.csv",
    matrix = if (tool %in% c("sankey", "venn", "kmeans", "beeswarm", "radar")) paste0("demo_", tool, ".csv") else
      if (tool %in% c("immune", tb_processed_tools)) "demo_expression.csv" else "matrix.csv")
  if (is.null(file)) return("")
  path <- file.path(root, "examples", file)
  if (file.exists(path)) normalizePath(path, winslash = "/") else ""
}
