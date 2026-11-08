# Generate and execute every tool's standalone R export using synthetic data.
# Run from the repository root; no Shiny service or user dataset is used.
root <- normalizePath("app", winslash = "/")
for (module in c("toolbox", "example_inputs", "immune"))
  source(file.path(root, "R", paste0(module, ".R")), encoding = "UTF-8")
output <- file.path(root, "tests", "_enhancements", "portable-all")
dir.create(output, recursive = TRUE, showWarnings = FALSE)
requests <- list()
for (tool in tb_tool_catalog()$id) {
  request <- tb_default_settings(dirname(root)); request$tool <- tool
  if (tool %in% c("volcano", "heatmap", "custom_heatmap", "manual_heatmap", tb_pathway_tools)) request$params$downstream_input <- TRUE
  if (tool %in% tb_pathway_tools) request$params$pathway_source <- "custom"
  if (tool == "immune") request$params$immune_source <- "custom"
  request$style$formats <- "png"; request$style$dpi <- 72
  request$style$width <- 5; request$style$height <- 4
  for (key in tb_active_inputs(request)) request$inputs[[key]] <- tb_example_path(root, tool, key, list(dataset = "synthetic"))
  if (tool == "figure_layout") for (key in tb_panel_fields(4)) request$inputs[[key]] <- file.path(root, "www/catalog-previews/pca.png")
  requests[[tool]] <- request
}
raw <- requests$custom_heatmap
raw$inputs$matrix <- ""; raw$params$downstream_input <- FALSE
raw$inputs$counts <- file.path(root, "examples", "demo_counts.csv")
requests[["custom-counts"]] <- raw
failed <- character()
selected_tools <- commandArgs(trailingOnly = TRUE)
if (!length(selected_tools)) selected_tools <- names(requests)
for (tool in selected_tools) {
  directory <- file.path(output, tool)
  dir.create(directory, showWarnings = FALSE)
  path <- file.path(directory, "reproduce.R")
  tb_portable_write(requests[[tool]], path, root)
  invisible(parse(path, encoding = "UTF-8"))
  result <- processx::run(file.path(R.home("bin"), "Rscript.exe"), c("--vanilla", "reproduce.R"),
    wd = directory, timeout = 180000, error_on_status = FALSE, stderr_to_stdout = TRUE)
  writeLines(result$stdout, file.path(directory, "execution.log"), useBytes = TRUE)
  cat(if (result$status == 0L) "PASS" else "FAIL", tool, "\n")
  flush.console()
  if (result$status != 0L) {
    failed <- c(failed, tool)
    cat("Exit status:", result$status, "\n")
    cat(tail(strsplit(result$stdout, "\n")[[1L]], 8L), sep = "\n")
  }
}
if (length(failed)) stop("Independent export failures: ", paste(failed, collapse = ", "))
cat("PASS", length(selected_tools), "standalone exports outside the workstation\n")
