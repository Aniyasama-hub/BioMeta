tb_bulk_steps <- c(pca = "PCA", deg = "差异表达", volcano = "火山图", heatmap = "热图",
  go = "GO", kegg = "KEGG", gsea = "GSEA", gsva = "GSVA", network = "PPI", figure_layout = "组图")

tb_bulk_source <- function(ids, custom = FALSE) {
  if (custom) return("custom")
  if (length(ids) && all(startsWith(ids, "GO:"))) return("go")
  if (length(ids) && all(grepl("^(hsa|mmu)[0-9]{5}$", ids))) return("kegg")
  "reactome"
}

tb_bulk_spec <- function(flow, tool, defaults, style = list()) {
  p <- utils::modifyList(defaults$params, flow$params)
  key <- tb_flow_nodes(flow)[[flow$step]]$id
  if (tool == "pca" && p$group_mode != "pair") p$group_mode <- "joint"
  if (tool == "network" && is.null(flow$stage_params[[key]]$network_mode))
    p$network_mode <- if (nzchar(flow$inputs$counts %||% "")) "deg" else if (nzchar(flow$inputs$deg %||% "")) "results" else "files"
  if (tool %in% c(tb_processed_tools, "volcano") && !nzchar(flow$inputs$counts %||% "")) p$downstream_input <- TRUE
  p$ppi_require_edges <- TRUE
  p$ppi_reference <- TRUE
  if (tool %in% tb_pathway_tools) {
    terms <- flow$terms[[tool]]
    p$pathway_terms <- if (tool != "gsea") terms else ""
    p$pathway_id <- if (tool == "gsea") terms else ""
    p$pathway_source <- if (flow$synthetic || (tool %in% c("gsea", "gsva") && flow$custom)) "custom"
      else if (tool %in% c("go", "kegg")) tool else tb_bulk_source(tb_parse_terms(terms))
  }
  p <- utils::modifyList(p, flow$stage_params[[key]] %||% list())
  request <- list(tool = tool, inputs = utils::modifyList(utils::modifyList(defaults$inputs, flow$inputs), flow$stage_inputs[[key]] %||% list()), params = p,
    style = utils::modifyList(utils::modifyList(tb_flow_style(defaults$style, flow), flow$stage_styles[[key]] %||% list()), style),
    project_name = flow$project_name)
  nodes <- tb_flow_nodes(flow)
  previous <- rev(seq_len(max(0L, flow$step - 1L)))
  deg_keys <- vapply(nodes[previous], function(x) if (x$tool == "deg") x$id else "", character(1))
  source <- NULL
  for (id in deg_keys[nzchar(deg_keys)]) if (!is.null(flow$approved[[id]])) { source <- flow$approved[[id]]; break }
  if (!is.null(source) && tool %in% c("volcano", "heatmap", tb_pathway_tools, "network")) {
    if (p$group_mode == "pair") request <- tb_link_deg_outputs(request, file.path(source, "outputs"))
    else request$upstream_deg <- source
  }
  request
}

# Complete task directories, including inputs/logs/reproduction records, grouped by step.
tb_bulk_archive <- function(flow, jobs, figures, file) {
  stage <- tempfile("bulk-export-")
  dir.create(stage)
  on.exit(unlink(stage, recursive = TRUE), add = TRUE)
  nodes <- tb_flow_nodes(flow)
  for (i in seq_along(nodes)) {
    id <- nodes[[i]]$id
    run <- jobs[[id]]
    if (is.null(run)) next
    target <- file.path(stage, sprintf("%02d_%s", i, id))
    dir.create(target)
    files <- list.files(run$directory, full.names = TRUE, all.files = TRUE, no.. = TRUE)
    if (length(files) && !all(file.copy(files, target, recursive = TRUE)))
      stop("全流程打包失败。")
  }
  edits <- Filter(function(x) startsWith(x$id, "ppi-"), figures)
  if (length(edits)) {
    keys <- vapply(nodes, `[[`, character(1), "id")
    for (x in edits) {
      index <- match(x$step %||% "network", keys)
      if (is.na(index)) next
      target <- file.path(stage, sprintf("%02d_%s", index, nodes[[index]]$id), "edited")
      dir.create(target, recursive = TRUE, showWarnings = FALSE)
      if (!file.copy(x$path, file.path(target, basename(x$path)))) stop("精细编辑图片打包失败。")
    }
  }
  manifest <- list(skipped = flow$skipped, project = flow$project_name,
    figures = lapply(figures, function(x) x[c("id", "tool", "step", "name", "favorite", "size")]))
  jsonlite::write_json(manifest, file.path(stage, "workflow.json"), auto_unbox = TRUE, pretty = TRUE)
  zip::zipr(file, list.files(stage, full.names = TRUE), root = stage)
}

# Presets are stored with settings, separately from disposable flow images.
tb_flow_nodes <- function(flow = NULL) {
  if (!is.null(flow$nodes)) return(flow$nodes)
  lapply(names(tb_bulk_steps), function(id) list(id = id, tool = id))
}
tb_flow_nodes_from_tools <- function(tools) {
  seen <- list()
  lapply(tools, function(tool) {
    n <- (seen[[tool]] %||% 0L) + 1L
    seen[[tool]] <<- n
    list(id = if (n == 1L) tool else paste0(tool, "_", n), tool = tool)
  })
}
tb_flow_validate <- function(nodes, allowed) {
  if (!length(nodes) || length(nodes) > 40L) stop("请选择 1–40 个分析步骤。")
  tools <- vapply(nodes, `[[`, character(1), "tool")
  if (!all(tools %in% allowed)) stop("流程含有未注册的工具。")
  ids <- vapply(nodes, `[[`, character(1), "id")
  if (anyDuplicated(ids) || any(!grepl("^[a-z0-9_]+$", ids))) stop("步骤 ID 必须唯一。")
  if (any(tools == "figure_layout") && tail(tools, 1) != "figure_layout") stop("组图应放在流程最后。")
  if (sum(tools == "figure_layout") > 1L) stop("流程只保留一个最终组图步骤。")
  invisible(TRUE)
}

tb_flow_style <- function(defaults, flow) utils::modifyList(defaults, flow$style %||% list())

tb_flow_checkpoint <- function(root) file.path(root, "results", "toolbox", "workflow", "current.rds")

tb_flow_forget <- function(root) {
  path <- tb_flow_checkpoint(root)
  saved <- tb_flow_load(root)
  if (!is.null(saved)) {
    id <- saved$flow$id
    if (is.character(id) && length(id) == 1L && grepl("^flow-[a-zA-Z0-9]+$", id)) {
      target <- file.path(dirname(path), id)
      if (dir.exists(target) && identical(dirname(normalizePath(target, winslash = "/")),
          normalizePath(dirname(path), winslash = "/"))) unlink(target, recursive = TRUE)
    }
    unlink(c(path, paste0(path, ".previous")))
  }
}

# Save an atomic manifest; only session-uploaded inputs are copied here. Job
# outputs retain their original task paths and are protected from cache pruning.
tb_flow_save <- function(root, flow, jobs, gallery) {
  if (is.null(flow) || !isTRUE(tb_read_settings(root)$workflow_autosave)) return(invisible(NULL))
  path <- tb_flow_checkpoint(root)
  current <- tb_flow_load(root)
  if (!is.null(current) && !identical(current$flow$id, flow$id)) return(invisible(NULL))
  assets <- file.path(dirname(path), flow$id, "inputs")
  dir.create(assets, recursive = TRUE, showWarnings = FALSE)
  snapshot <- function(inputs, prefix) {
    for (key in names(inputs)) {
      source <- inputs[[key]]
      if (is.character(source) && length(source) == 1L && nzchar(source) && !file.exists(source)) {
        existing <- file.path(assets, paste0(prefix, "-", key, ".", tools::file_ext(source)))
        if (file.exists(existing)) inputs[[key]] <- normalizePath(existing, winslash = "/")
      }
      if (is.character(source) && length(source) == 1L && nzchar(source) && file.exists(source)) {
        target <- file.path(assets, paste0(prefix, "-", key, ".", tools::file_ext(source)))
        if (!identical(normalizePath(source, winslash = "/"), normalizePath(target, winslash = "/", mustWork = FALSE)) &&
            !file.copy(source, target, overwrite = TRUE)) stop("无法保存流程输入：", key)
        inputs[[key]] <- normalizePath(target, winslash = "/")
      }
    }
    inputs
  }
  flow$inputs <- snapshot(flow$inputs, "shared")
  for (key in names(flow$stage_inputs)) flow$stage_inputs[[key]] <- snapshot(flow$stage_inputs[[key]], key)
  images <- file.path(dirname(path), flow$id, "images")
  dir.create(images, recursive = TRUE, showWarnings = FALSE)
  for (key in names(gallery)) {
    target <- file.path(images, paste0(key, ".png"))
    if (!file.copy(gallery[[key]]$path, target, overwrite = TRUE)) stop("无法保存流程选图。")
    gallery[[key]]$path <- target
  }
  records <- lapply(jobs, function(x) x[c("directory", "id", "tool")])
  temp <- tempfile(tmpdir = dirname(path))
  saveRDS(list(flow = flow, jobs = records, gallery = gallery, saved = Sys.time()), temp)
  previous <- paste0(path, ".previous")
  if (file.exists(path) && !file.rename(path, previous)) stop("无法替换流程进度。")
  if (!file.rename(temp, path)) {
    if (file.exists(previous)) file.rename(previous, path)
    stop("无法保存流程进度。")
  }
  if (file.exists(previous)) unlink(previous)
  invisible(path)
}

tb_flow_load <- function(root) {
  path <- tb_flow_checkpoint(root)
  if (!file.exists(path) && file.exists(paste0(path, ".previous"))) path <- paste0(path, ".previous")
  if (!file.exists(path)) return(NULL)
  readRDS(path)
}

tb_restored_job <- function(record) {
  active <- tb_lookup_job(record$directory)
  if (!is.null(active)) return(active)
  record$process <- list(is_alive = function() FALSE)
  if (tb_read_status(record$directory)$status %in% c("queued", "running"))
    tb_status_write(record$directory, "failed", summary = "上次服务已停止，请重新运行当前步骤；已完成步骤仍可查看。")
  record
}

tb_save_result_copy <- function(root, directory) {
  destination <- tb_read_settings(root)$export_folder
  if (!nzchar(destination %||% "")) return(invisible(NULL))
  destination <- normalizePath(destination, winslash = "/", mustWork = TRUE)
  target <- file.path(destination, paste0("biometa-", basename(directory)))
  if (identical(normalizePath(directory, winslash = "/"), target)) return(invisible(NULL))
  dir.create(target, showWarnings = FALSE)
  files <- list.files(directory, full.names = TRUE, all.files = TRUE, no.. = TRUE)
  files <- files[basename(files) != "working"]
  if (!all(file.copy(files, target, recursive = TRUE, overwrite = TRUE))) stop("结果保存地址写入失败：", target)
  invisible(target)
}
