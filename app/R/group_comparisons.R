tb_comparison_path <- function(directory, id) file.path(directory, "working", "comparisons", id)

tb_publish_comparison <- function(child, output, id) {
  source <- file.path(child, "outputs")
  if (dir.exists(source) && !file.rename(source, file.path(output, id))) stop("无法保存比较结果：", id)
}

tb_run_comparisons <- function(spec, plan, root, directory) {
  output <- file.path(directory, "outputs")
  dir.create(output, recursive = TRUE, showWarnings = FALSE)
  records <- plan$pairs
  records$id <- sprintf("comparison-%03d", seq_len(nrow(records)))
  records$status <- "completed"
  records$message <- ""
  for (i in seq_len(nrow(records))) {
    id <- records$id[i]
    tb_status_write(directory, "running", floor(95 * (i - 1L) / nrow(records)),
      sprintf("比较 %d/%d：%s vs %s", i, nrow(records), records$treatment[i], records$control[i]))
    child <- tb_comparison_path(directory, id)
    dir.create(file.path(child, "inputs"), recursive = TRUE)
    request <- spec
    request$params$group_mode <- "pair"
    request$params$model_groups <- plan$groups
    request$params$control <- records$control[i]
    request$params$treatment <- records$treatment[i]
    tryCatch({
      if (!is.null(spec$upstream_deg)) {
        index <- utils::read.csv(file.path(spec$upstream_deg, "outputs", "comparisons.csv"))
        match <- which(index$control == records$control[i] & index$treatment == records$treatment[i] & index$status == "completed")
        if (length(match) != 1L) stop("未找到该比较已完成的上游差异结果。")
        request <- tb_link_deg_outputs(request, file.path(spec$upstream_deg, "outputs", index$id[match]))
      }
      tb_run_request(request, root, child)
    }, error = function(e) {
      records$status[i] <<- "failed"
      records$message[i] <<- conditionMessage(e)
      message(id, ": ", conditionMessage(e))
    })
    tb_publish_comparison(child, output, id)
  }
  utils::write.csv(records, file.path(output, "comparisons.csv"), row.names = FALSE)
  if (!any(records$status == "completed")) stop("所有比较均未完成，请查看运行日志。")
  saveRDS(records, file.path(directory, "batch.rds"))
  tb_write_reproduce(spec, file.path(directory, "reproduce.R"), root)
  tb_status_write(directory, "completed", 100, sprintf("完成 %d/%d 个比较；比较索引记录每项状态。",
    sum(records$status == "completed"), nrow(records)))
  invisible(output)
}

tb_redraw_comparisons <- function(spec, root, directory) {
  previous <- spec$redraw_from
  records <- readRDS(file.path(previous, "batch.rds"))
  output <- file.path(directory, "outputs")
  dir.create(output)
  for (id in records$id) {
    old <- tb_comparison_path(previous, id)
    child <- tb_comparison_path(directory, id)
    before <- file.path(previous, "outputs", id)
    if (records$status[match(id, records$id)] == "completed" && file.exists(file.path(old, "render.rds"))) {
      dir.create(child, recursive = TRUE)
      request <- spec
      request$redraw_from <- old
      tb_redraw_request(request, root, child, previous_output = before)
      tb_publish_comparison(child, output, id)
    } else if (dir.exists(before) && !file.copy(before, output, recursive = TRUE)) {
      stop("无法复制比较结果：", id)
    }
  }
  utils::write.csv(records, file.path(output, "comparisons.csv"), row.names = FALSE)
  saveRDS(records, file.path(directory, "batch.rds"))
  tb_write_reproduce(spec, file.path(directory, "reproduce.R"), root)
  tb_status_write(directory, "completed", 100, "已复用各组比较的绘图数据。")
}
