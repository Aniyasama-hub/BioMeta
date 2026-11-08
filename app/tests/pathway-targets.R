# Synthetic data: targets must annotate results without changing their statistics.
root <- normalizePath("app", winslash = "/")
for (module in c("toolbox", "workbench_settings", "bulk_workflow", "toolbox_analysis", "toolbox_render", "public_pathways", "group_comparisons"))
  source(file.path(root, "R", paste0(module, ".R")), encoding = "UTF-8")
output <- tempfile("pathway-targets-", tmpdir = file.path(root, "tests/_enhancements"))
dir.create(output, recursive = TRUE)
target_file <- file.path(output, "targets.csv")
write.csv(data.frame(pathway_name = "Synthetic set 3"), target_file, row.names = FALSE)
engine <- tb_engine(root)
for (tool in c("go", "kegg", "gsva")) {
  spec <- tb_default_settings(dirname(root)); spec$tool <- tool
  spec$inputs$deg <- file.path(root, "examples/demo_deg.csv")
  spec$inputs$gmt <- file.path(root, "examples/demo_sets.gmt")
  spec$inputs$pathway_names <- target_file
  if (tool == "gsva") {
    spec$inputs$matrix <- file.path(root, "examples/demo_expression.csv")
    spec$inputs$groups <- file.path(root, "examples/demo_groups.csv")
  }
  spec$params$downstream_input <- TRUE
  spec$params$pathway_source <- "custom"; spec$params$gmt_id_type <- "gene_id"
  spec$params$database_version <- "BioWorkbench synthetic fixtures"
  spec$params$target_pathways <- "Synthetic set 1\nDEMO_2\nMissing term"
  spec$params$ora_fdr <- 1; spec$params$pathway_top <- 2L
  spec$style$formats <- c("png", "svg", "tiff", "pdf"); spec$style$dpi <- 90
  spec$style$width <- 8; spec$style$height <- 6
  spec$style$pathway_target_fill <- "#FFF1E6"
  if (tool == "kegg") {
    spec$style$enrichment_kind <- "bar"; spec$style$enrichment_orientation <- "vertical"
  }
  directory <- file.path(output, tool)
  dir.create(file.path(directory, "inputs"), recursive = TRUE)
  saveRDS(spec, file.path(directory, "request.rds"))
  tb_run_request(spec, root, directory)
  report <- read.csv(file.path(directory, "outputs/target_pathway_matches.csv"))
  stopifnot(!report$in_results[report$requested == "Missing term"],
    all(report$in_results[report$requested != "Missing term"]), sum(report$in_figure) <= 2L)
  bundle <- readRDS(file.path(directory, "render.rds"))
  if (tool == "gsva") stopifnot(any(bundle$extras$row_targets)) else {
    stopifnot(any(bundle$data$target_pathway))
    # Inspect text colors inside the rendered axis rather than relying on a theme declaration.
    style <- engine$.resolve_plot_style(spec$style)
    plot <- engine$.plot_enrichment(bundle$data, style)
    collect <- function(grob) {
      if (inherits(grob, "text")) return(grob$gp$col)
      if (inherits(grob, "gtable")) return(unlist(lapply(grob$grobs, collect)))
      if (inherits(grob, "gTree")) return(unlist(lapply(grob$children, collect)))
      character()
    }
    stopifnot(spec$style$pathway_target_color %in% collect(plot))
  }
  # Reapply target marking to a copy: only the annotation column may differ.
  pathways <- readRDS(file.path(directory, "outputs/pathways.rds"))
  key <- if (tool == "gsva") "gsva" else "ora"
  before <- pathways[[key]]$results
  spec$params$target_pathways <- ""; spec$inputs$pathway_names <- ""
  after <- tb_mark_pathway_targets(pathways, spec, file.path(directory, "outputs"), engine)[[key]]$results
  stopifnot(isTRUE(all.equal(before[setdiff(names(before), "target_pathway")],
    after[setdiff(names(after), "target_pathway")])) )
  # Execute the actual export in a new R process, with no Shiny service.
  result <- processx::run(file.path(R.home("bin"), "Rscript.exe"), c("--vanilla", "reproduce.R"),
    wd = directory, stderr_to_stdout = TRUE, error_on_status = FALSE, timeout = 180000)
  writeLines(result$stdout, file.path(directory, "standalone.log"))
  if (result$status != 0L) stop(result$stdout)
  cat("PASS", tool, "target matching, four formats, highlight, invariant statistics and standalone export\n")
}
cat("Artifacts:", output, "\n")
