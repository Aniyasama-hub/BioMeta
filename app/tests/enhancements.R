# Synthetic inputs only; test products stay in the existing ignored test folder.
Sys.setlocale("LC_CTYPE", "English_United States.utf8")
root <- normalizePath("app", winslash = "/")
for (module in c("toolbox", "workbench_settings", "bulk_workflow", "example_inputs", "toolbox_analysis",
  "toolbox_render", "group_comparisons", "public_pathways", "general_plots", "general_plot_render", "figure_layout", "immune", "network_import"))
  source(file.path(root, "R", paste0(module, ".R")), encoding = "UTF-8")
dir.create(file.path(root, "tests", "_enhancements"), recursive = TRUE, showWarnings = FALSE)
output <- tempfile("backend-", tmpdir = file.path(root, "tests", "_enhancements"))
dir.create(output, recursive = TRUE, showWarnings = FALSE)
defaults <- tb_default_settings(dirname(root))
request <- utils::modifyList(defaults, list(tool = "volcano",
  inputs = list(deg = file.path(root, "examples", "demo_deg.csv")),
  params = list(downstream_input = TRUE, target_text = "g001\ng002\nMISSING"),
  style = list(formats = c("png", "svg", "pdf", "tiff"), width = 6, height = 5, dpi = 90)))
run <- function(spec, name) {
  directory <- file.path(output, name)
  dir.create(file.path(directory, "inputs"), recursive = TRUE, showWarnings = FALSE)
  saveRDS(spec, file.path(directory, "request.rds"))
  tb_run_request(spec, root, directory)
  directory
}
volcano <- run(request, "volcano")
stopifnot(length(list.files(file.path(volcano, "outputs"), pattern = "[.](png|svg|tiff|pdf)$", recursive = TRUE)) == 8L)
targets <- read.csv(file.path(volcano, "outputs", "target_gene_match_report.csv"))
stopifnot(identical(targets$status, c("matched", "matched", "unmatched")))
source <- readLines(file.path(volcano, "reproduce.R"), warn = FALSE, encoding = "UTF-8")
stopifnot(!any(grepl("tb_launch_job|source\\(file.path\\(root", source)))
invisible(parse(file.path(volcano, "reproduce.R"), encoding = "UTF-8"))
cat("PASS volcano dual exports and standalone script syntax\n")

request$tool <- "heatmap"
request$inputs$matrix <- file.path(root, "examples", "demo_expression.csv")
request$inputs$groups <- file.path(root, "examples", "demo_groups.csv")
request$inputs$gmt <- file.path(root, "examples", "demo_sets.gmt")
request$params$heatmap_kind <- "annotated"
request$params$annotation_mode <- "auto"
request$params$annotation_source <- "custom"
request$params$annotation_terms <- "Synthetic set 1\nDEMO_2"
request$params$heatmap_top <- 25L
request$params$cluster_columns <- TRUE
request$style$gene_label_fill <- "preset"
request$style$pathway_font_face <- "bold"
annotated <- run(request, "annotated-auto")
table <- read.csv(file.path(annotated, "outputs", "annotated_expression.csv"))
stopifnot(all(c("matched_id", "Pathway", "log2FoldChange", "padj", "S1") %in% names(table)), length(unique(table$Pathway)) == 2L)
bundle <- readRDS(file.path(annotated, "render.rds"))
stopifnot(length(rle(bundle$extras$row_annotation$Pathway[bundle$extras$row_order])$values) == 2L)
request$params$pathway_cluster <- FALSE
request$style$reverse_rows <- TRUE
request$style$reverse_columns <- TRUE
request$style$formats <- "png"
run(request, "annotated-global")
manual <- tb_annotation_template()
manual[[1L]] <- c("g001", "g002"); manual[[2L]] <- c("g001", "g002")
manual[[3L]] <- c("Manual A", "Manual B"); manual[[4L]] <- "TRUE"
path <- file.path(output, "annotation.csv"); write.csv(manual, path, row.names = FALSE, fileEncoding = "UTF-8")
request$inputs$annotation <- path
request$params$annotation_mode <- "manual"
request$params$pathway_cluster <- TRUE
request$tool <- "manual_heatmap"
run(request, "annotated-manual")
cat("PASS annotated heatmap auto/manual, path grouping, fills and reversals\n")

isolated <- file.path(output, "settings")
dir.create(isolated, recursive = TRUE, showWarnings = FALSE)
tb_save_settings(isolated, list(workflow_autosave = TRUE))
flow <- list(id = "flow-test", step = 1L, inputs = list(deg = request$inputs$deg),
  style = tb_palettes()[[1L]], nodes = list(list(id = "volcano", tool = "volcano")))
tb_flow_save(isolated, flow, list(volcano = list(directory = volcano, id = "test", tool = "volcano")), list())
saved <- tb_flow_load(isolated)
stopifnot(file.exists(saved$flow$inputs$deg), identical(saved$flow$step, 1L))
restored <- tb_restored_job(saved$jobs$volcano)
stopifnot(!restored$process$is_alive())
tb_flow_forget(isolated)
stopifnot(is.null(tb_flow_load(isolated)))
zipfile <- file.path(output, "example.zip"); tb_zip_example(root, "synthetic", zipfile)
stopifnot(all(c("demo_counts.csv", "demo_groups.csv", "demo_expression.csv", "demo_deg.csv") %in% zip::zip_list(zipfile)$filename))
cat("PASS checkpoint persistence/reset and complete example ZIP\n")
