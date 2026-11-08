tb_capture_job_source <- function(root, directory) {
  target <- file.path(directory, "execution_source")
  files <- c("toolbox_worker.R", "run.R", "config/project.R",
    file.path("R", list.files(file.path(root, "R"), pattern = "[.]R$")))
  files <- files[file.exists(file.path(root, files))]
  for (name in files) {
    path <- file.path(target, name)
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    if (!file.copy(file.path(root, name), path)) stop("无法保存本次执行脚本快照：", name)
  }
  manifest <- data.frame(file = files, sha256 = vapply(file.path(target, files),
    function(path) digest::digest(file = path, algo = "sha256"), character(1)))
  utils::write.csv(manifest, file.path(target, "source_manifest.csv"), row.names = FALSE)
}

tb_capture_runtime <- function(directory, error = NULL) {
  writeLines(c(paste("Captured UTC:", format(Sys.time(), tz = "UTC", usetz = TRUE)),
    paste("R home:", R.home()), paste("Library:", .libPaths()), capture.output(sessionInfo())),
    file.path(directory, "sessionInfo.txt"), useBytes = TRUE)
  if (!is.null(error)) jsonlite::write_json(list(code = error$code %||% "BW-A01",
    message = conditionMessage(error), hint = error$hint, files = error$files,
    call = paste(deparse(conditionCall(error)), collapse = " "),
    trace = if (!is.null(error$trace)) capture.output(print(error$trace)) else capture.output(rlang::trace_back()),
    parent = if (!is.null(error$parent)) conditionMessage(error$parent)),
    file.path(directory, "error_details.json"), auto_unbox = TRUE, pretty = TRUE, null = "null")
}

tb_zip_diagnostics <- function(directory, file, root) {
  directory <- normalizePath(directory, winslash = "/", mustWork = TRUE)
  jobs <- normalizePath(file.path(root, "results/toolbox/jobs"), winslash = "/", mustWork = TRUE)
  if (!identical(dirname(directory), jobs) || tb_read_status(directory)$status != "failed")
    stop("只有工作站内的失败任务可以导出诊断包。")
  stage <- tempfile("biometa-debug-"); dir.create(stage)
  stage <- normalizePath(stage, winslash = "/", mustWork = TRUE)
  if (!identical(dirname(stage), normalizePath(tempdir(), winslash = "/"))) stop("诊断临时目录无效。")
  on.exit(unlink(stage, recursive = TRUE), add = TRUE)
  # Copy this task only, including input snapshots and partial analysis outputs.
  files <- list.files(directory, all.files = TRUE, recursive = TRUE, no.. = TRUE)
  for (name in files) {
    destination <- file.path(stage, "task", name)
    dir.create(dirname(destination), recursive = TRUE, showWarnings = FALSE)
    if (!file.copy(file.path(directory, name), destination)) stop("诊断文件复制失败：", name)
  }
  original <- dir.exists(file.path(directory, "execution_source"))
  if (!original) {
    dir.create(file.path(stage, "current_source_NOT_original"))
    tb_capture_job_source(root, file.path(stage, "current_source_NOT_original"))
  }
  notes <- c("biometa failed-task diagnostics", "",
    "Contains this task's original input snapshots, parameters, style, logs, status, errors and partial results.",
    if (original) "execution_source is the code snapshot saved for this task at launch."
      else "Historical task has NO execution-time code snapshot. current_source_NOT_original is current code, NOT proof of the historical execution version.",
    "The original reproduce.R, if present, is preserved under task/.",
    "replay_current/ is an optional standalone replay generated with CURRENT code. It is not an original execution log.",
    "Only files already stored in this task are collected. No other projects or global settings are included.",
    "Missing historical sessionInfo/error_details cannot be reconstructed and are not fabricated.")
  replay <- file.path(stage, "replay_current"); dir.create(replay)
  tryCatch(tb_write_reproduce(tb_job_request(directory), file.path(replay, "reproduce.R"), root),
    error = function(e) writeLines(conditionMessage(e), file.path(replay, "generation_error.txt")))
  writeLines(notes, file.path(stage, "README.txt"))
  files <- list.files(stage, recursive = TRUE, all.files = TRUE, no.. = TRUE)
  utils::write.csv(data.frame(file = files, bytes = file.info(file.path(stage, files))$size,
    sha256 = vapply(file.path(stage, files), function(path) digest::digest(file = path, algo = "sha256"), character(1))),
    file.path(stage, "diagnostic_manifest.csv"), row.names = FALSE)
  zip::zipr(file, list.files(stage, all.files = TRUE, no.. = TRUE), root = stage, include_directories = TRUE)
  invisible(file)
}
