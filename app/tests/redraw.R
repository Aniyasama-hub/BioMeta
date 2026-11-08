root <- normalizePath(commandArgs(trailingOnly = TRUE)[1], winslash = "/")
source(file.path(root, "R/toolbox.R"), encoding = "UTF-8")
source(file.path(root, "R/toolbox_analysis.R"), encoding = "UTF-8")
source(file.path(root, "R/toolbox_render.R"), encoding = "UTF-8")
source(file.path(root, "R/general_plots.R"), encoding = "UTF-8")
source(file.path(root, "R/general_plot_render.R"), encoding = "UTF-8")
test <- tempfile()
dir.create(test)
fixtures <- list(
  sankey = data.frame(source = c("A","A","B"), target = c("C","D","D"), value = c(2,3,4)),
  venn = data.frame(set = c("A","A","B","B","C","C"), item = c("x","y","x","z","z","w")),
  kmeans = data.frame(id = LETTERS[1:6], a = c(1,2,10,11,21,22), b = c(3,1,12,11,22,24)),
  beeswarm = data.frame(group = rep(c("A","B"), each = 4), value = c(1,2,3,4,2,3,4,7)),
  radar = data.frame(id = c("A","B"), metric_1 = c(1,2), metric_2 = c(3,2), metric_3 = c(2,2)))
make_spec <- function(tool) {
  file <- file.path(test, paste0(tool, ".csv"))
  write.csv(fixtures[[tool]], file, row.names = FALSE)
  tb_normalize_spec(list(tool = tool, inputs = list(matrix = file),
    style = list(formats = "svg", width = 5, height = 4, gradient = "#123; rgb(240,235,230); #B95153; #4F712E")), root)
}
engine <- tb_engine(root)
for (tool in names(fixtures)) {
  spec <- make_spec(tool)
  tb_validate_inputs(spec, root)
  bundle <- tb_prepare_general(spec)
  directory <- file.path(test, tool)
  tb_render_request(bundle, spec, root, directory, engine)
  stopifnot(file.exists(file.path(directory, "outputs", c("figure.svg", "plot_data.csv"))))
  cat("PASS", tool, "\n")
}
spec <- make_spec("kmeans")
wait <- function(job) {
  job$process$wait(timeout = 90000)
  state <- tb_read_job(job$directory)
  if (state$status != "completed") stop(state$error, "\n", state$log)
  job$directory
}
first <- wait(tb_launch_job(spec, root))
spec$style$gradient <- "#508040"
spec$style$formats <- "png"
second <- wait(tb_launch_job(spec, root, redraw_from = first))
stopifnot(identical(readRDS(file.path(first, "render.rds")), readRDS(file.path(second, "render.rds"))),
          file.exists(file.path(second, "outputs", "kmeans.png")),
          !file.exists(file.path(second, "outputs", "kmeans.svg")))
archive <- file.path(test, "results.zip")
tb_zip_results(second, archive)
contents <- zip::zip_list(archive)$filename
stopifnot(any(grepl("^01_.*/kmeans.png$", contents)),
          any(grepl("^01_.*/kmeans_plot_data.csv$", contents)),
          any(grepl("^02_.*/manifest.json$", contents)),
          !any(grepl("render[.]rds|inputs/", contents)))
folder <- file.path(test, "project")
dir.create(folder)
file.create(file.path(folder, c("gene_count.csv", "group.csv", "annotation.xlsx", "normalized_count.csv")))
stopifnot(length(tb_project_inputs(folder)) == 3L)
file.create(file.path(folder, "other_count.csv"))
stopifnot(!"counts" %in% names(tb_project_inputs(folder)))
cat("PASS worker redraw, ZIP classification and project autofill\n")
