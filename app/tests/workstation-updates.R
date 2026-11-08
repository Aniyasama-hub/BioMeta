# 本轮定向验证：不运行用户研究数据，不下载参考库。
args <- commandArgs(TRUE)
root <- normalizePath(args[1], winslash = "/", mustWork = TRUE)
source(file.path(root, "R", "toolbox.R"), encoding = "UTF-8")
source(file.path(root, "R", "example_inputs.R"), encoding = "UTF-8")
source(file.path(root, "R", "toolbox_render.R"), encoding = "UTF-8")
source(file.path(root, "R", "toolbox_analysis.R"), encoding = "UTF-8")
engine <- tb_engine(root)
stage <- tempfile("workstation-check-")
dir.create(stage)


# 导出入口同时兼容旧的图名、作图数据及多组子目录。
stopifnot(tb_output_name("figure.png", "volcano") == "volcano_map.png",
  tb_output_name("plot_data.csv", "gsva") == "gsva_heatmap_plot_data.csv",
  tb_output_name("old_Heatmap.pdf", "manual_heatmap") == "annotated_heatmap.pdf",
  tb_export_target("comparison-002/figure.svg", "heatmap") == "comparison-002/heatmap.svg")
dir.create(file.path(root, "results/toolbox/jobs"), recursive = TRUE, showWarnings = FALSE)
job <- tempfile("20000101-000000-", tmpdir = file.path(root, "results/toolbox/jobs"))
dir.create(file.path(job, "outputs"), recursive = TRUE)
saveRDS(list(tool = "volcano", project_name = "MyProject"), file.path(job, "request.rds"))
jsonlite::write_json(list(status = "completed"), file.path(job, "status.json"), auto_unbox = TRUE)
writeLines("fixture", file.path(job, "outputs", "figure.png"))
write.csv(data.frame(gene_id = "A"), file.path(job, "outputs", "plot_data.csv"), row.names = FALSE)
writeLines("fixture", file.path(job, "outputs", "manifest.json"))
stopifnot(grepl(paste0("^MyProject_", format(Sys.time(), "%Y%m%d", tz = "Asia/Shanghai"), "[0-9]{6}[.]zip$"), tb_archive_name(job)))
archive <- file.path(stage, "export.zip")
tb_zip_results(job, archive)
entries <- zip::zip_list(archive)$filename
stopifnot(any(endsWith(entries, "/volcano_map.png")),
  any(endsWith(entries, "/volcano_map_plot_data.csv")), any(endsWith(entries, "/manifest.json")),
  !any(grepl("/(figure[.]|plot_data[.])", entries)))
cat("PASS descriptive filenames, download timestamp, ZIP content\n")

# 九套示例的输入、比较、清洗记录和完整差异结果对应。
folders <- tb_geo_catalog(root)
stopifnot(length(folders) == 9L)
counts_n <- 0L
for (folder in folders) {
  read <- function(file) read.delim(file.path(folder, file), check.names = FALSE)
  groups <- read("groups.tsv")
  matrix <- read("matrix.tsv")
  deg <- read.csv(file.path(folder, "deg.csv"), check.names = FALSE)
  preset <- jsonlite::read_json(file.path(folder, "preset.json"))
  stopifnot(identical(names(matrix)[-1], groups$Sample), !anyDuplicated(matrix[[1]]),
    all(is.finite(as.matrix(matrix[-1]))), !anyDuplicated(deg$gene_id), nrow(deg) > 1000,
    all(c("gene_id", "log2FoldChange", "stat", "pvalue", "padj") %in% names(deg)),
    file.exists(file.path(folder, "cleaning_summary.csv")),
    all(c(preset$control, preset$treatment) %in% groups$Group),
    tb_example_path(root, "volcano", "deg", list(dataset = basename(folder))) == normalizePath(file.path(folder, "deg.csv"), winslash = "/"))
  if (isTRUE(preset$count)) {
    counts <- read("counts.tsv")
    values <- as.matrix(counts[, groups$Sample, drop = FALSE])
    stopifnot(all(is.finite(values) & values >= 0 & values == floor(values)),
      !anyDuplicated(counts$gene_id), !anyDuplicated(counts), all(deg$gene_id %in% counts$gene_id))
    counts_n <- counts_n + 1L
  } else stopifnot(!file.exists(file.path(folder, "counts.tsv")))
}
stopifnot(counts_n == 7L)
cat("PASS nine examples: seven Count / DESeq2, two normalized / limma\n")

# 树显示与反转的排列：既定的聚类顺序不应因显隐改变。
set.seed(7)
m <- matrix(rnorm(48), 8, 6, dimnames = list(paste0("g", 1:8), paste0("s", 1:6)))
extras <- list(row_order = hclust(dist(m))$order, column_order = hclust(dist(t(m)))$order,
  matrix_units = "row_zscore", clustering = list(cluster_rows = TRUE, cluster_columns = TRUE,
    distance = "euclidean", linkage = "complete", column_cluster_mode = "global"))
style <- engine$.resolve_plot_style(list(formats = "pdf", width = 6, height = 5))
for (reverse in c(FALSE, TRUE)) {
  actual <- lapply(c(FALSE, TRUE), function(show) {
    settings <- utils::modifyList(style, list(show_row_tree = show, show_column_tree = show,
      reverse_rows = reverse, reverse_columns = reverse, heat_cell_width = 4, heat_cell_height = 3))
    ht <- engine$.plot_heatmap(m, extras, settings)$plot
    grDevices::pdf(file.path(stage, paste0("heatmap_", reverse, "_", show, ".pdf")))
    drawn <- tryCatch(ComplexHeatmap::draw(ht), finally = grDevices::dev.off())
    list(rows = rownames(drawn@ht_list[[1]]@matrix)[ComplexHeatmap::row_order(drawn)],
      columns = colnames(drawn@ht_list[[1]]@matrix)[ComplexHeatmap::column_order(drawn)])
  })
  stopifnot(identical(actual[[1]], actual[[2]]))
  expected_r <- rownames(m)[extras$row_order]; expected_c <- colnames(m)[extras$column_order]
  if (reverse) { expected_r <- rev(expected_r); expected_c <- rev(expected_c) }
  stopifnot(identical(actual[[1]]$rows, expected_r), identical(actual[[1]]$columns, expected_c))
}
cat("PASS heatmap dimensions, tree visibility, exact row/column reversal\n")

# 条形长度与宽度调整不改写基因比例。
d <- data.frame(term_id = c("A", "B"), description = c("one", "two"), padj = c(.001, .01),
  gene_ratio = c(.2, .1), count = c(4, 2), source = "test")
for (orientation in c("horizontal", "vertical")) {
  a <- engine$.plot_enrichment(d, utils::modifyList(style, list(enrichment_kind = "bar", enrichment_orientation = orientation,
    enrichment_bar_width = .4, enrichment_bar_length = 50)))
  b <- engine$.plot_enrichment(d, utils::modifyList(style, list(enrichment_kind = "bar", enrichment_orientation = orientation,
    enrichment_bar_width = .9, enrichment_bar_length = 90)))
  stopifnot(identical(a$data$gene_ratio, b$data$gene_ratio), identical(a$data$gene_ratio, c(.2, .1)))
  ggplot2::ggsave(file.path(stage, paste0("bar_", orientation, ".pdf")), b, width = 6, height = 4)
}
cat("PASS horizontal/vertical bars preserve true data ratios\n")

# 所有入口都有独立 Markdown 帮助页，新增色板格式合法。
app <- new.env(parent = globalenv())
sys.source(file.path(root, "app.R"), app, keep.source = FALSE)
for (tool in c(tb_tool_catalog()$id, "bulk")) {
  html <- paste(as.character(app$ui(list(QUERY_STRING = paste0("guide=", tool)))), collapse = "\n")
  stopifnot(grepl("guide-page", html), grepl("方法引用", html), grepl("怎样计算", html))
}
for (palette in tb_palettes()) stopifnot(all(grepl("^#[0-9A-Fa-f]{6}$", palette$colors %||% unlist(palette[c("low", "mid", "high")]))))
cat("PASS all tool guides, palette values, Shiny app construction\n")
shiny::testServer(app$server, {
  session$setInputs(tool_id = "volcano")
  session$setInputs(example_choice = names(folders)[1], example_volcano = TRUE)
  stopifnot(example_checked(), file.exists(read_input("deg")),
    basename(read_input("deg")) == "deg.csv")
  input_html <- paste(output$input_file_rows$html, collapse = "\n")
  stopifnot(grepl("deg.csv", input_html, fixed = TRUE))
  session$setInputs(example_volcano = FALSE, path_deg = "user_difference_table.csv")
  stopifnot(!example_checked(), read_input("deg") == "user_difference_table.csv")
})
cat("PASS example switch uses system inputs and restores user upload mode\n")
