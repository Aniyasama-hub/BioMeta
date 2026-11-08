# Run from repository root. Only temporary synthetic files; no analyses or updates.
source("app/R/bulk_workflow.R", encoding = "UTF-8")
source("app/R/settings_tools.R", encoding = "UTF-8")
local({
  root <- tempfile("archive-fixture-")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  run <- file.path(root, "job")
  dir.create(run)
  dir.create(file.path(run, "outputs"))
  dir.create(file.path(run, "inputs"))
  writeLines("output", file.path(run, "outputs", "deg_summary.csv"))
  writeLines("log", file.path(run, "job.log"))
  writeLines("input", file.path(run, "inputs", "counts.csv"))
  file <- file.path(root, "all.zip")
  tb_bulk_archive(list(skipped = list(), project_name = "synthetic"),
    list(deg = list(directory = run)), list(), file)
  stopifnot(all(c("02_deg/outputs/deg_summary.csv", "02_deg/job.log",
    "02_deg/inputs/counts.csv", "workflow.json") %in% zip::zip_list(file)$filename))
})
stopifnot(!any(c("R_HOME", "R_LIBS", "R_LIBS_USER", "R_LIBS_SITE") %in% names(tb_runtime_env())))
r <- tb_find_runtime("R")
version <- processx::run(r, c("--vanilla", "-e", "cat(as.character(getRversion()))"),
  env = tb_runtime_env(), timeout = 10000)$stdout
stopifnot(nzchar(version))
stopifnot(grepl("不是患者", as.character(tb_example_document("app/examples/README.md"))))
cat("PASS full task ZIP, selected-R isolation/discovery and compact example text\n")
