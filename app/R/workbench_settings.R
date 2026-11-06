tb_settings_file <- function(root) file.path(root, "results", "toolbox", "settings.json")

tb_read_settings <- function(root) {
  path <- tb_settings_file(root)
  saved <- if (file.exists(path)) tryCatch(jsonlite::read_json(path, simplifyVector = TRUE), error = function(e) NULL)
  utils::modifyList(list(rscript = "", python = "", retain = 0L, package_library = "", library_r = "", project_folder = "", project_auto = FALSE), saved %||% list())
}

tb_save_settings <- function(root, settings) {
  path <- tb_settings_file(root)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  temp <- tempfile(tmpdir = dirname(path))
  on.exit(unlink(temp), add = TRUE)
  jsonlite::write_json(settings, temp, auto_unbox = TRUE, pretty = TRUE)
  if (!suppressWarnings(file.rename(temp, path))) {
    backup <- tempfile(tmpdir = dirname(path))
    if (!file.rename(path, backup)) stop("无法替换系统设置。")
    if (!file.rename(temp, path)) {
      file.rename(backup, path)
      stop("无法保存系统设置。")
    }
    unlink(backup)
  }
  invisible(settings)
}

tb_runtime_version <- function(path, kind) {
  path <- trimws(path)
  if (!nzchar(path)) return("")
  expected <- if (kind == "R") "^Rscript([.]exe)?$" else "^python(w|[0-9.]*)?([.]exe)?$"
  if (!grepl(expected, basename(path), ignore.case = TRUE) || !file.exists(path))
    stop("请选择有效的 ", kind, " 可执行文件。")
  args <- if (kind == "R") c("--vanilla", "-e", "cat(as.character(getRversion())); ok <- all(vapply(c('shiny','jsonlite','processx'),requireNamespace,logical(1),quietly=TRUE)); quit(status=if(ok) 0 else 2)") else "--version"
  version <- processx::run(normalizePath(path, winslash = "/"), args,
    timeout = 10000, error_on_status = FALSE, stderr_to_stdout = TRUE)
  if (version$status == 2L && kind == "R") stop("所选 R 缺少启动依赖，请先在该版本安装 shiny、jsonlite 和 processx。")
  if (version$status != 0L) stop(kind, " 无法正常运行。")
  trimws(version$stdout)
}

.tb_task_views <- new.env(parent = emptyenv())
.tb_package_update <- new.env(parent = emptyenv())

tb_pinned_runs <- function() unique(unlist(as.list(.tb_task_views), use.names = FALSE))
tb_package_updating <- function() isTRUE(.tb_package_update$busy)

tb_jobs_running <- function() {
  jobs <- Filter(Negate(is.null), as.list(.tb_jobs))
  any(vapply(jobs, function(job) job$process$is_alive(), logical(1)))
}

tb_delete_run <- function(root, directory) {
  jobs <- file.path(root, "results", "toolbox", "jobs")
  if (!dir.exists(directory)) return(FALSE)
  normalized <- normalizePath(directory, winslash = "/", mustWork = TRUE)
  if (!identical(dirname(normalized), normalizePath(jobs, winslash = "/", mustWork = TRUE)) ||
      !grepl("^[0-9]{8}-[0-9]{6}-[a-zA-Z0-9]+$", basename(normalized))) stop("无法确认任务目录。")
  active <- tb_lookup_job(normalized)
  if (basename(normalized) %in% tb_pinned_runs() || (!is.null(active) && active$process$is_alive()) ||
      tb_read_status(normalized)$status %in% c("queued", "running")) return(FALSE)
  if (unlink(normalized, recursive = TRUE) != 0L || dir.exists(normalized)) stop("无法删除任务文件。")
  id <- basename(normalized)
  if (exists(id, envir = .tb_jobs, inherits = FALSE)) rm(list = id, envir = .tb_jobs)
  TRUE
}

tb_prune_runs <- function(root, limit) {
  if (limit == 0L) return(invisible(0L))
  runs <- tb_list_runs(root)
  old <- if (nrow(runs) > limit) tail(runs$directory, nrow(runs) - limit) else character()
  sum(vapply(rev(old), function(path) tb_delete_run(root, path), logical(1)))
}

tb_zip_outputs <- function(directory, file) {
  root <- file.path(directory, "outputs")
  files <- list.files(root, all.files = TRUE, recursive = TRUE)
  if (!length(files)) stop("此任务暂无可导出的输出。")
  zip::zipr(file, files, root = root, include_directories = FALSE, mode = "mirror")
}
