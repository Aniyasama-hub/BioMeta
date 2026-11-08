# Small synthetic fixtures only; no RNA-seq modelling or personal research data.
root <- normalizePath("app", winslash = "/")
source(file.path(root, "R/toolbox.R"), encoding = "UTF-8")
source(file.path(root, "R/toolbox_analysis.R"), encoding = "UTF-8")
source(file.path(root, "R/toolbox_render.R"), encoding = "UTF-8")
source(file.path(root, "R/public_pathways.R"), encoding = "UTF-8")
out <- file.path(root, "tests/_pathway-review")
dir.create(out, recursive = TRUE, showWarnings = FALSE)

data <- data.frame(gene_id = LETTERS[1:4], Study_P = c(.01, .1, .03, NA),
  Study_FDR = c(.2, .3, .04, NA), Study_LFC = c(2, -3, .5, 4))
p <- list(ora_filter_mode = "probability", ora_p_column = "Study_P", padj = .05)
selection <- tb_ora_selection(data, p)
stopifnot(identical(which(selection$selected), c(1L, 3L)), sum(selection$tested) == 3L)
p$ora_p_column <- "Study_FDR"
stopifnot(identical(which(tb_ora_selection(data, p)$selected), 3L))
p <- list(ora_filter_mode = "effect", ora_effect_column = "Study_LFC", log2fc = 2, direction = "all")
stopifnot(identical(which(tb_ora_selection(data[c("gene_id", "Study_LFC")], p)$selected), c(1L, 2L, 4L)))
stopifnot(inherits(try(tb_ora_selection(data, list(ora_filter_mode = "probability", ora_p_column = "Study_LFC")), silent = TRUE), "try-error"))
stats <- data.frame(pvalue = c(.1, .01), p.adjust = c(.2, .03))
stopifnot(identical(tb_pathway_metric(stats, "padj"), tb_pathway_metric(stats, "FDR")),
  identical(tb_pathway_metric(stats, "pvalue"), stats$pvalue))

table <- file.path(out, "target_names.csv")
write.csv(data.frame(pathway_name = "Table target"), table, row.names = FALSE)
spec <- list(params = list(target_pathways = "Typed target", target_pathway_input = "text"), inputs = list(pathway_names = table))
stopifnot(identical(tb_pathway_input(spec), "Typed target"))
spec$params$target_pathway_input <- "table"
stopifnot(identical(tb_pathway_input(spec), "Table target"))
cat("PASS input-column selection, probability-only/effect-only, BH aliases and exclusive pathway inputs\n")

run <- function(spec) {
  job <- tb_launch_job(spec, root)
  job$process$wait()
  state <- tb_read_job(job$directory)
  if (state$status != "completed") stop(state$error %||% state$summary)
  job
}
demo <- read.csv(file.path(root, "examples/demo_deg.csv"), check.names = FALSE)
probability <- data.frame(gene_id = demo$gene_id, gene_name = demo$gene_name, Study_adjP = demo$padj)
input <- file.path(out, "probability_only.csv"); write.csv(probability, input, row.names = FALSE)
spec <- list(tool = "go", inputs = list(deg = input, gmt = file.path(root, "examples/demo_sets.gmt")),
  params = list(pathway_source = "custom", database_version = "synthetic metric fixture", gmt_id_type = "gene_id",
    ora_filter_mode = "probability", ora_p_column = "Study_adjP", ora_fdr = 1, min_set_size = 2,
    gsea_sort = "pvalue", target_pathway_input = "text", target_pathways = "Synthetic set 1"),
  style = list(formats = "png", dpi = 96, width = 7, height = 6, enrichment_kind = "bar"))
prob_job <- run(spec)
selection <- jsonlite::read_json(file.path(prob_job$directory, "outputs/ora_input_selection.json"))
stopifnot(selection$mode == "probability", selection$probability_column == "Study_adjP")
cat("PASS actual ORA worker accepts probability-only DEG and records its chosen source column\n")

effect <- data.frame(gene_id = demo$gene_id, gene_name = demo$gene_name, Study_LFC = demo$log2FoldChange)
input <- file.path(out, "effect_only.csv"); write.csv(effect, input, row.names = FALSE)
spec$inputs$deg <- input
spec$params$ora_filter_mode <- "effect"; spec$params$ora_p_column <- ""; spec$params$ora_effect_column <- "Study_LFC"
effect_job <- run(spec)
cat("PASS actual ORA worker accepts effect-only DEG without probability columns\n")

# Use real public identifiers with deliberately synthetic statistics.
db <- getExportedValue("org.Hs.eg.db", "org.Hs.eg.db")
ids <- head(AnnotationDbi::keys(db, keytype = "ENTREZID"), 350)
symbols <- unname(AnnotationDbi::mapIds(db, ids, "SYMBOL", "ENTREZID", multiVals = "asNA"))
public <- data.frame(gene_id = ids, gene_name = symbols,
  Study_adjP = ifelse(seq_along(ids) <= 80, .001, .8))
input <- file.path(out, "public_identifiers_synthetic_statistics.csv"); write.csv(public, input, row.names = FALSE)
spec$inputs <- list(deg = input)
spec$params <- list(species = "human", pathway_source = "go", ora_filter_mode = "probability",
  ora_p_column = "Study_adjP", ora_fdr = 1, min_set_size = 2, max_set_size = 10000,
  pathway_top = 2, go_output_scope = "both", gsea_sort = "FDR")
spec$style <- list(formats = "png", dpi = 96, width = 9, height = 10,
  enrichment_kind = "both", enrichment_orientation = "horizontal", term_wrap = 35)
go_job <- run(spec)
output <- file.path(go_job$directory, "outputs")
plots <- list.files(output, pattern = "[.]png$", recursive = TRUE)
stopifnot(length(plots) == 8L, all(c("BP", "CC", "MF") %in% read.csv(file.path(output, "go_plot_categories.csv"))$ontology))
bundle <- readRDS(file.path(go_job$directory, "render.rds"))
stopifnot(bundle$type == "enrichment_collection", length(bundle$plots) == 4L,
  all(table(bundle$plots$go_BP_CC_MF$data$ontology) <= 2L))
redraw <- list(tool = "go", inputs = list(), params = spec$params,
  style = list(formats = "png", dpi = 96, width = 9, height = 7, enrichment_kind = "bar", enrichment_orientation = "vertical"))
redraw_job <- tb_launch_job(redraw, root, go_job$directory); redraw_job$process$wait()
if (tb_read_job(redraw_job$directory)$status != "completed") stop(tb_read_job(redraw_job$directory)$error)
stopifnot(length(list.files(file.path(redraw_job$directory, "outputs"), pattern = "[.]png$", recursive = TRUE)) == 4L)
cat("PASS actual GO BP/CC/MF combined plus single plots, bar/dot export and vertical redraw\n")

# Fake transport is confined to a temporary cache; it never contaminates real KEGG maps.
local({
  temp <- tempfile("map-fixture-", tmpdir = out); dir.create(temp)
  temp <- normalizePath(temp, winslash = "/", mustWork = TRUE)
  stopifnot(identical(dirname(temp), normalizePath(out, winslash = "/")))
  on.exit(unlink(temp, recursive = TRUE))
  fixture <- list.files(output, pattern = "[.]png$", full.names = TRUE, recursive = TRUE)[1L]
  fetch <- function(url, destfile, ...) { file.copy(fixture, destfile); 0L }
  report <- tb_export_kegg_maps(c("hsa00010", "mmu00010", "not-a-pathway"), temp, temp, "human", fetch)
  stopifnot(nrow(report) == 1L, report$status == "downloaded", file.exists(file.path(temp, report$file)))
  fail <- function(...) stop("synthetic transport failure")
  report <- suppressWarnings(tb_export_kegg_maps("hsa00020", temp, temp, "human", fail))
  stopifnot(report$status == "failed", grepl("synthetic transport failure", report$error))
})
cat("PASS mechanism-map species filtering, PNG validation, hashes and explicit failure reports\n")

if ("--with-kegg" %in% commandArgs(TRUE)) {
  spec$tool <- "kegg"; spec$params$pathway_source <- "kegg"; spec$params$pathway_top <- 1
  spec$params$kegg_maps <- "displayed"; spec$style$enrichment_kind <- "dot"
  kegg_job <- run(spec)
  report <- read.csv(file.path(kegg_job$directory, "outputs/kegg_map_downloads.csv"))
  stopifnot(nrow(report) == 1L, all(report$status == "downloaded"))
  cat("PASS actual KEGG worker downloads its selected pathway's official mechanism PNG\n")
}
jsonlite::write_json(list(go_job = go_job$directory, vertical_job = redraw_job$directory,
  probability_job = prob_job$directory, effect_job = effect_job$directory),
  file.path(out, "jobs.json"), auto_unbox = TRUE, pretty = TRUE)
