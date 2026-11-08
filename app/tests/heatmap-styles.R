args <- commandArgs(TRUE)
root <- normalizePath(args[1], winslash = "/")
source(file.path(root, "R/toolbox.R"), encoding = "UTF-8")
source(file.path(root, "R/toolbox_analysis.R"), encoding = "UTF-8")
source(file.path(root, "R/toolbox_render.R"), encoding = "UTF-8")
engine <- tb_engine(root)
stage <- tempfile("legacy-heatmap-")
dir.create(stage)
expression <- read.csv(file.path(root, "examples/demo_expression.csv"), check.names = FALSE)
deg <- read.csv(file.path(root, "examples/demo_deg.csv"))
expression <- cbind(deg[, c("gene_id", "gene_name", "padj")], log2FC = deg$log2FoldChange, expression[-1])
write.csv(expression, file.path(stage, "expression.csv"), row.names = FALSE)
style <- utils::modifyList(tb_default_settings(dirname(root))$style,
  list(width = 8, height = 6, dpi = 96, formats = "pdf", heat_cell_width = 4, heat_cell_height = 3))
for (tool in c("manual_heatmap", "custom_heatmap")) {
  output <- file.path(stage, tool)
  dir.create(output)
  overrides <- list(work_dir = stage, output_dir = output, out_path = output,
    metadata_file = file.path(root, "examples/demo_groups.csv"),
    normalization_method = "none", heatmap_scale = "row", output_formats = "pdf", show_column_names = TRUE)
  if (tool == "manual_heatmap") {
    overrides$expression_file <- file.path(stage, "expression.csv")
    overrides$manual_annotation_file <- file.path(root, "examples/annotation.xlsx")
    overrides$distance_rows <- overrides$distance_columns <- "euclidean"
    overrides$group_mean_distance <- "euclidean"
    script <- "04.3_manual_pathway_heatmap.R"
  } else {
    overrides$group_file <- file.path(root, "examples/demo_groups.csv")
    overrides$count_file <- file.path(root, "examples/demo_counts.csv")
    overrides$target_genes <- sprintf("g%03d", 1:20)
    overrides$cluster_rows <- overrides$cluster_columns <- TRUE
    script <- "04.4_custom_gene_count_heatmap.R"
  }
  bundle <- tb_run_legacy(file.path(dirname(root), "legacy", script), overrides,
    normalize_counts = tool == "custom_heatmap")
  results <- list()
  for (reverse in c(FALSE, TRUE)) for (show in c(FALSE, TRUE)) {
    spec <- tb_normalize_spec(list(tool = tool, style = utils::modifyList(style,
      list(reverse_rows = reverse, reverse_columns = reverse, show_row_tree = show, show_column_tree = show))), root)
    tb_render_legacy(bundle, spec, output, engine, root)
    grDevices::pdf(file.path(output, paste0("order_", reverse, "_", show, ".pdf")), width = 8, height = 6)
    drawn <- tryCatch(ComplexHeatmap::draw(bundle$context$ht), finally = grDevices::dev.off())
    rows <- unlist(ComplexHeatmap::row_order(drawn), use.names = FALSE)
    columns <- unlist(ComplexHeatmap::column_order(drawn), use.names = FALSE)
    results[[paste(reverse, show)]] <- list(rows = rows, columns = columns)
  }
  stopifnot(identical(results[["FALSE FALSE"]], results[["FALSE TRUE"]]),
    identical(results[["TRUE FALSE"]], results[["TRUE TRUE"]]),
    identical(results[["TRUE FALSE"]]$rows, rev(results[["FALSE FALSE"]]$rows)),
    identical(results[["TRUE FALSE"]]$columns, rev(results[["FALSE FALSE"]]$columns)))
  cat("PASS", tool, "tree visibility and exact reversal\n")
}
