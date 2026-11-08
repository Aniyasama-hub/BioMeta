# 小型合成数据回归测试：不拟合真实 Count，不下载数据库。
args <- commandArgs(trailingOnly = TRUE)
root <- normalizePath(args[1], winslash = "/", mustWork = TRUE)
source(file.path(root, "R", "toolbox.R"), encoding = "UTF-8")
source(file.path(root, "R", "toolbox_analysis.R"), encoding = "UTF-8")
source(file.path(root, "R", "toolbox_render.R"), encoding = "UTF-8")
source(file.path(root, "R", "network_import.R"), encoding = "UTF-8")
engine <- tb_engine(root)
directory <- file.path(root, "tests", "_output")
dir.create(directory, recursive = TRUE, showWarnings = FALSE)
defaults <- tb_default_settings(dirname(root))
style <- utils::modifyList(defaults$style, list(width = 5, height = 4, dpi = 96))
spec <- tb_normalize_spec(list(tool = "network", inputs = list(
  nodes = file.path(root, "examples", "ppi_nodes.csv"), edges = file.path(root, "examples", "ppi_edges.csv")),
  style = style), root)
stopifnot(!"counts" %in% tb_active_inputs(spec))
tb_validate_inputs(spec, root)
network_dir <- file.path(directory, "network")
dir.create(network_dir, showWarnings = FALSE)
bundle <- tb_import_network(spec, network_dir)
stopifnot(nrow(bundle$data) == 4L, bundle$data$degree[bundle$data$gene_id == "GeneD"] == 0)
engine$render_bundle(bundle, style, network_dir)
tb_write_interactive_network(bundle, style, root, network_dir)
stopifnot(file.exists(file.path(network_dir, "network.html")))
cat("PASS dual node/edge import, isolated nodes, network export + offline viewer\n")

# 模拟 STRING Node 同时含 STRING_id 与 gene_id 的实际输入。
node <- data.frame(STRING_id = c("10090.A", "10090.B"), gene_id = c("ENSMUSG_A", "ENSMUSG_B"),
                     gene_name = c("A", "B"), log2FC = c(1, -1))
edge <- data.frame(source = c("10090.A", "10090.B"), target = c("10090.B", "10090.A"), combined_score = c(800, 950))
utils::write.csv(node, file.path(directory, "string_nodes.csv"), row.names = FALSE)
utils::write.csv(edge, file.path(directory, "string_edges.csv"), row.names = FALSE)
spec$inputs$nodes <- file.path(directory, "string_nodes.csv")
spec$inputs$edges <- file.path(directory, "string_edges.csv")
string_dir <- file.path(directory, "string")
dir.create(string_dir, showWarnings = FALSE)
result <- tb_import_network(spec, string_dir)
stopifnot(identical(result$extras$node_id_column, "STRING_id"), nrow(result$extras$edges) == 1L,
            abs(result$extras$edges$score - 0.95) < 1e-10, "input_gene_id" %in% names(result$data))
cat("PASS STRING IDs, source/target, score units, reverse duplicate maximum\n")
edge$target[1] <- "UNKNOWN"
utils::write.csv(edge, file.path(directory, "invalid_edges.csv"), row.names = FALSE)
spec$inputs$edges <- file.path(directory, "invalid_edges.csv")
error <- tryCatch({tb_import_network(spec, string_dir); NULL}, error = function(e) conditionMessage(e))
stopifnot(!is.null(error), grepl("Node", error))
cat("PASS unknown endpoint rejection\n")

spec <- tb_normalize_spec(list(tool = "matrix_pca", inputs = list(matrix = file.path(root, "examples", "matrix.csv")), style = style), root)
for (id in c("matrix_pca", "matrix_heatmap")) {
  spec$tool <- id
  tb_validate_inputs(spec, root)
  bundle <- tb_matrix_bundle(spec, engine)
  output <- file.path(directory, id)
  dir.create(output, showWarnings = FALSE)
  engine$export_bundle(bundle, output)
  engine$render_bundle(bundle, style, output)
  cat("PASS", id, "four formats\n")
}

volcano <- data.frame(gene_id = paste0("G", 1:6), gene_name = paste0("Gene", 1:6),
  log2FoldChange = c(-2, -1.5, 0, 0.2, 1.4, 2), padj = c(.001, .02, .9, .5, .03, .001),
  minus_log10_padj = -log10(c(.001, .02, .9, .5, .03, .001)),
  regulation = c("Down", "Down", "Not_significant", "Not_significant", "Up", "Up"), label = c(TRUE, FALSE, FALSE, FALSE, FALSE, TRUE))
output <- file.path(directory, "volcano")
engine$render_bundle(list(type = "volcano", data = volcano, extras = list(padj_cutoff = .05, log2fc_cutoff = 1)), style, output)
cat("PASS volcano threshold / points / labels\n")

enrichment <- data.frame(term_id = c("T1", "T2", "T3"), description = c("Inflammatory response pathway", "Cell signalling", "Metabolic process"),
  padj = c(.0001, .005, .03), gene_ratio = c(.25, .18, .1), count = c(15, 10, 5), source = "synthetic")
for (kind in c("dot", "bar")) {
  local_style <- utils::modifyList(style, list(enrichment_kind = kind))
  engine$render_bundle(list(type = "enrichment", data = enrichment), local_style, file.path(directory, paste0("enrichment_", kind)))
}
cat("PASS enrichment bubble + bar renderers\n")

gsea <- data.frame(rank = 1:30, running_es = cumsum(c(rep(.1, 8), rep(-.03, 22))),
                    hit = seq_len(30) %% 4 == 0, rank_score = seq(3, -3, length.out = 30))
engine$render_bundle(list(type = "gsea", data = gsea, extras = list(pathway_id = "SYNTHETIC", nes = 1.8, padj = .01)),
                       style, file.path(directory, "gsea"))
cat("PASS GSEA curve / ticks / ranked-score areas\n")

spec <- tb_normalize_spec(list(tool = "circos", inputs = list(
  chromosomes = file.path(root, "examples", "circos_chromosomes.csv"),
  features = file.path(root, "examples", "circos_features.csv"), links = file.path(root, "examples", "circos_links.csv")), style = style), root)
output <- file.path(directory, "circos")
dir.create(output, showWarnings = FALSE)
tb_render_circos(tb_prepare_circos(spec, output, engine), spec$style, output)
cat("PASS Circos tracks / links / export\n")

for (id in tb_tool_catalog()$id) {
  fields <- names(do.call(c, unname(tb_style_schema(id))))
  stopifnot(all(fields %in% names(style)))
  if (id == "deg") stopifnot(length(fields) == 0L)
  if (id %in% c("gsea", "network", "circos")) stopifnot(!"z_limit" %in% fields, !"point_size" %in% fields)
  if (id %in% c("heatmap", "manual_heatmap", "custom_heatmap", "matrix_heatmap", "gsva")) stopifnot(!"point_size" %in% fields)
}
files <- list.files(directory, recursive = TRUE, full.names = TRUE)
figures <- files[grepl("figure[.](png|svg|tiff|pdf)$", files)]
stopifnot(length(figures) == 36L, all(file.info(figures)$size > 100))
cat("PASS current schemas; 9 synthetic figure routes (including both volcano orientations) x 4 formats\n")
writeLines(capture.output(utils::sessionInfo()), file.path(directory, "sessionInfo.txt"))
cat("SMOKE CHECK COMPLETE\n")
