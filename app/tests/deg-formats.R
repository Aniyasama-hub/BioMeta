# Verify the summary chart obeys the requested formats without refitting a model.
root <- normalizePath("app", winslash = "/")
source(file.path(root, "R/toolbox.R"), encoding = "UTF-8")
source(file.path(root, "R/toolbox_analysis.R"), encoding = "UTF-8")
engine <- tb_engine(root)
cfg <- engine$load_config(file.path(root, "config/project.R"))
cfg$style$colors <- c(Up = "#C62828", Down = "#1565C0", Not_significant = "#999999")
out <- tempfile("deg-formats-", tmpdir = tempdir()); dir.create(out)
dir.create(file.path(out, "outputs"))
tb_selection_output(list(deg = read.csv(file.path(root, "examples/demo_deg.csv"))), cfg, out, engine,
  make_pie = TRUE, style = list(formats = c("svg", "pdf"), dpi = 96))
stopifnot(all(file.exists(file.path(out, "outputs", paste0("deg_proportions.", c("svg", "pdf"))))),
  !file.exists(file.path(out, "outputs/deg_proportions.png")))
cat("PASS DEG summary exports only requested SVG/PDF, no forced PNG\n")
