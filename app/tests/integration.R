# 发布前小型合成数据集成检查；不读取用户科研数据。
root <- normalizePath(commandArgs(trailingOnly = TRUE)[1], winslash = "/")
source(file.path(root, "R/toolbox.R"), encoding = "UTF-8")
out <- file.path(root, "tests/_integration")
dir.create(out, recursive = TRUE, showWarnings = FALSE)
set.seed(42)
ids <- sprintf("g%03d", 1:160)
counts <- matrix(rnbinom(160 * 6, mu = 200, size = 40), nrow = 160)
counts[1:30, 4:6] <- counts[1:30, 4:6] * 6
counts[31:60, 1:3] <- counts[31:60, 1:3] * 6
colnames(counts) <- paste0("S", 1:6)
write.csv(data.frame(gene_id = ids, gene_name = ids, counts), file.path(out, "counts.csv"), row.names = FALSE)
write.csv(data.frame(Sample = colnames(counts), Group = rep(c("A", "B"), each = 3)), file.path(out, "groups.csv"), row.names = FALSE)
write.csv(data.frame(GeneKey = ids[1:20], Use = TRUE), file.path(out, "targets.csv"), row.names = FALSE)
write.csv(data.frame(from = ids[1:29], to = ids[2:30], score = .9), file.path(out, "edges.csv"), row.names = FALSE)
writeLines(vapply(0:7, function(i) paste(c(paste0("TERM", i), paste0("Synthetic", i), ids[(1:20) + i * 20]), collapse = "\t"), character(1)), file.path(out, "test.gmt"))
requested <- commandArgs(trailingOnly = TRUE)[-1]
tools <- c("deg", "pca", "heatmap", "volcano", "go", "kegg", "gsea", "gsva", "network", "custom_heatmap", "manual_heatmap",
           "matrix_pca", "matrix_heatmap", "circos", "network_files")
report_path <- file.path(out, "report.json")
report <- if (length(requested) && file.exists(report_path)) jsonlite::read_json(report_path) else list()
if (length(requested)) tools <- intersect(tools, requested)
for (tool in tools) {
  cat("CHECK", tool, "\n")
  inputs <- list(counts = file.path(out, "counts.csv"), groups = file.path(out, "groups.csv"),
    targets = file.path(out, "targets.csv"), edges = file.path(out, "edges.csv"),
    gmt = file.path(out, "test.gmt"), annotation = file.path(root, "examples/annotation.xlsx"),
    matrix = file.path(root, "examples/matrix.csv"), nodes = file.path(root, "examples/ppi_nodes.csv"),
    chromosomes = file.path(root, "examples/circos_chromosomes.csv"),
    features = file.path(root, "examples/circos_features.csv"), links = file.path(root, "examples/circos_links.csv"))
  if (tool == "network_files") inputs$edges <- file.path(root, "examples/ppi_edges.csv")
  spec <- list(tool = if (tool == "network_files") "network" else tool, inputs = inputs, params = list(control = "A", treatment = "B", fit_type = "mean",
    min_count = 1, min_samples = 2, padj = .5, log2fc = .5, pca_top = 60, heatmap_top = 20,
    min_set_size = 5, max_set_size = 80, gmt_id_type = "gene_id", database_version = "synthetic-test",
    network_mode = if (tool == "network_files") "files" else "deg"), style = list(formats = "svg", width = 5, height = 4, dpi = 96))
  result <- tryCatch({
    job <- tb_launch_job(spec, root)
    job$process$wait(timeout = 180000)
    if (job$process$is_alive()) { tb_stop_job(job); stop("synthetic job timed out") }
    state <- tb_read_job(job$directory)
    if (state$status != "completed") stop(paste(state$error, state$log, collapse = "\n"))
    stopifnot(!any(grepl("[.]png$", state$files)))
    if (tool == "pca") stopifnot(any(grepl("pca_loadings", state$files)))
    "PASS"
  }, error = function(e) paste("FAIL", conditionMessage(e)))
  report[[tool]] <- result
  cat(tool, result, "\n")
}
jsonlite::write_json(report, file.path(out, "report.json"), auto_unbox = TRUE, pretty = TRUE)
if (any(!vapply(report, identical, logical(1), "PASS"))) quit(status = 1L)
cat("ALL SYNTHETIC INTEGRATION CHECKS PASSED\n")
