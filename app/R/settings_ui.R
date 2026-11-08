tb_runtime_picker <- function(id, label, value) div(class = "runtime-picker",
  textInput(paste0("settings_", id), label, value, placeholder = "选择配置方式，或直接输入地址"),
  selectInput(paste0("runtime_method_", id), "配置方式",
    c("选择方式…" = "", "自动嗅探" = "detect", "浏览本地选择" = "browse", "手动输入" = "manual")),
  uiOutput(paste0("runtime_candidates_", id)))

tb_system_ui <- function(root, project_ui) {
  cfg <- tb_read_settings(root)
  external <- function(url, label) tags$a(href = url, target = "_blank", rel = "noopener", label)
  modalDialog(title = "设置", size = "l", easyClose = TRUE,
    tabsetPanel(
      tabPanel("项目工作空间", project_ui),
      tabPanel("界面风格",
        radioButtons("settings_theme", "选择前端风格", c("黑夜" = "night", "亮色" = "classic"), selected = cfg$theme),
        p("只改变工作站界面，不改变科研图片配色、分析参数或已有结果。"),
        actionButton("settings_theme_save", "应用并保存风格", class = "primary-button")),
      tabPanel("示例数据", uiOutput("example_catalog"), uiOutput("example_details"),
        downloadButton("download_example_data", "下载数据"),
        p("下载当前示例在本机提供的全部输入、来源与说明；未提供原始 Count 的数据集不会生成虚构 Count。")),
      tabPanel("保存设置",
        textInput("settings_export_folder", "结果导出保存地址（留空仅保留工作站任务结果）", cfg$export_folder),
        actionButton("settings_export_browse", "浏览本地文件夹", class = "secondary-button"),
        checkboxInput("settings_workflow_autosave", "自动化分析逐步保存", cfg$workflow_autosave),
        p("完成的任务自动复制到所选地址。流程进度、输入和选图在刷新或重启后可恢复；确认开始新流程时替换当前进度。"),
        actionButton("settings_storage_save", "保存设置", class = "primary-button")),
      tabPanel("运行环境", p(paste("当前 R", getRversion(), "·", R.home())),
        tb_runtime_picker("rscript", "Rscript 地址", cfg$rscript),
        tb_runtime_picker("python", "Python 地址（可选）", cfg$python),
        tb_runtime_picker("rstudio", "RStudio 地址（可选）", cfg$rstudio),
        tags$p("Bioconductor 发行版本由所选 R 决定；它不是一个可执行程序。"),
        p("当前分析由 R 执行。Python 配置用于版本记录和本机环境检查。"),
        p("嗅探会检查 PATH、Windows 注册表、各磁盘常见安装目录、Conda/虚拟环境及 Python 启动器。发现多个环境时请指定一个；不会自动覆盖已保存的选择。R 更换后需重启，正在运行的分析继续使用原环境。"),
        actionButton("settings_probe", "检查环境与版本", class = "small-button"),
        actionButton("settings_runtime_save", "保存运行环境", class = "secondary-button"),
        verbatimTextOutput("settings_versions"),
        div(class = "runtime-links", strong("友情网址"),
          p(external("https://www.r-project.org/", "R"), " · ",
            external("https://www.python.org/", "Python"), " · ",
            external("https://posit.co/download/rstudio-desktop/", "RStudio"), " · ",
            external("https://bioconductor.org/", "Bioconductor")))),
      tabPanel("R 软件包", uiOutput("package_controls"), uiOutput("dependency_table", class = "package-table-scroll"),
        verbatimTextOutput("package_update_log")),
      tabPanel("任务缓存",
        numericInput("settings_retain", "保留最近任务数（0 表示不限）", cfg$retain, min = 0, max = 10000, step = 1),
        p("保存后清理较早的任务。正在运行、当前查看或被 Bulk 流程使用的任务会暂时保留。"),
        actionButton("settings_retain_save", "保存并清理", class = "secondary-button")),
      tabPanel("退出",
        p("结束本机工作站服务。已保存的任务可在下次启动后查看。"),
        actionButton("settings_exit", "退出工作站", class = "secondary-button"))),
    footer = modalButton("关闭"))
}

tb_settings_server <- function(input, output, session, root, refresh_history, project_ui) {
  versions <- reactiveVal("")
  candidates <- reactiveValues(rscript = NULL, python = NULL, rstudio = NULL)
  observeEvent(input$settings_theme_save, tryCatch({
    theme <- input$settings_theme
    if (length(theme) != 1L || !theme %in% c("night", "classic")) stop("请选择有效的界面风格。")
    tb_save_settings(root, utils::modifyList(tb_read_settings(root), list(theme = theme)))
    session$sendCustomMessage("workbench-theme", list(theme = theme))
    showNotification("界面风格已应用并保存。", type = "message")
  }, error = function(e) showNotification(conditionMessage(e), type = "error")))
  notify_error <- function(e) showNotification(conditionMessage(e), type = "error", duration = 12)
  observeEvent(input$settings_export_browse, tryCatch({
    path <- tb_pick_local(root, "folder")
    if (nzchar(path)) updateTextInput(session, "settings_export_folder", value = path)
  }, error = notify_error))
  observeEvent(input$settings_storage_save, tryCatch({
    path <- trimws(input$settings_export_folder %||% "")
    if (nzchar(path)) {
      if (!grepl("^([A-Za-z]:[/\\\\]|/|\\\\\\\\)", path)) stop("请填写完整的本地文件夹地址。")
      dir.create(path, recursive = TRUE, showWarnings = FALSE)
      if (!dir.exists(path) || file.access(path, 2) != 0L) stop("保存地址不存在或不可写。")
      path <- normalizePath(path, winslash = "/", mustWork = TRUE)
    }
    tb_save_settings(root, utils::modifyList(tb_read_settings(root), list(export_folder = path,
      workflow_autosave = isTRUE(input$settings_workflow_autosave))))
    showNotification("保存设置已更新。")
  }, error = notify_error))
  runtime_fields <- function() {
    if (any(vapply(c("rscript", "python", "rstudio"), function(field) !is.null(candidates[[field]]), logical(1))))
      stop("请先确认嗅探结果中的环境，或取消本次选择。")
    r <- trimws(input$settings_rscript %||% "")
    python <- trimws(input$settings_python %||% "")
    rv <- tb_runtime_version(r, "R")
    pv <- tb_runtime_version(python, "Python")
    studio <- trimws(input$settings_rstudio %||% "")
    if (nzchar(studio) && (!file.exists(studio) || !grepl("^rstudio[.]exe$", basename(studio), ignore.case = TRUE))) stop("请选择真实的 rstudio.exe。")
    selected_r <- if (nzchar(r)) r else file.path(R.home("bin"), "Rscript.exe")
    bioc <- processx::run(selected_r, c("--vanilla", "-e", "if(requireNamespace('BiocManager',quietly=TRUE)) cat(as.character(BiocManager::version())) else cat('尚未安装 BiocManager')"), timeout = 15000, env = tb_runtime_env(), windows_hide_window = TRUE)$stdout
    versions(paste("R", if (nzchar(rv)) rv else paste(getRversion(), "（当前）"),
      "\nPython", if (nzchar(pv)) sub("^Python ", "", pv) else "未配置", "\nBioconductor", bioc, "\nRStudio", if (nzchar(studio)) studio else "未配置"))
    list(rscript = r, python = python, rstudio = studio)
  }
  observeEvent(input$show_environment, showModal(tb_system_ui(root, project_ui())))
  observeEvent(input$settings_probe, tryCatch(runtime_fields(), error = notify_error))
  observeEvent(input$settings_runtime_save, tryCatch({
    values <- runtime_fields()
    tb_save_settings(root, utils::modifyList(tb_read_settings(root), values))
    showNotification("已保存，R 路径在下次启动生效。")
  }, error = notify_error))
  for (id in c("rscript", "python", "rstudio")) local({
    field <- id; kind <- c(rscript = "R", python = "Python", rstudio = "RStudio")[[field]]
    output[[paste0("runtime_candidates_", field)]] <- renderUI({
      rows <- candidates[[field]]
      if (is.null(rows)) return(NULL)
      div(class = "runtime-candidates", strong(paste("发现", nrow(rows), "个", kind, "环境，请指定本工作站使用的版本")),
        radioButtons(paste0("runtime_choice_", field), "版本与实际地址",
          stats::setNames(rows$path, paste(rows$version, "·", rows$path, "·", rows$source)), selected = character()),
        actionButton(paste0("runtime_confirm_", field), "使用所选环境", class = "primary-button"),
        actionButton(paste0("runtime_cancel_", field), "取消选择", class = "small-button"))
    })
    observeEvent(input[[paste0("runtime_confirm_", field)]], tryCatch({
      rows <- candidates[[field]]; chosen <- input[[paste0("runtime_choice_", field)]] %||% ""
      if (!nzchar(chosen) || !chosen %in% rows$path[rows$available]) stop("请选择一个能正常运行的环境。不可用环境可浏览或手动重新指定。")
      updateTextInput(session, paste0("settings_", field), value = chosen)
      candidates[[field]] <- NULL
      showNotification("环境已选定；检查后点击保存。")
    }, error = notify_error))
    observeEvent(input[[paste0("runtime_cancel_", field)]], candidates[[field]] <- NULL)
    observeEvent(input[[paste0("runtime_method_", field)]], tryCatch({
      method <- input[[paste0("runtime_method_", field)]]
      if (identical(method, "detect")) {
        note <- showNotification(paste("正在查找", kind, "环境并核验版本…"), duration = NULL)
        on.exit(removeNotification(note))
        rows <- tb_find_runtimes(kind, root, input[[paste0("settings_", field)]] %||% "")
        if (nrow(rows) == 1L && rows$available[1]) {
          updateTextInput(session, paste0("settings_", field), value = rows$path[1])
          candidates[[field]] <- NULL
          showNotification(paste("找到", kind, rows$version[1], "；请检查并保存。"))
        } else candidates[[field]] <- rows
      }
      if (identical(method, "browse")) {
        path <- tb_pick_local(root, kind)
        if (nzchar(path)) {
          candidates[[field]] <- NULL
          updateTextInput(session, paste0("settings_", field), value = path)
        }
      }
      if (identical(method, "manual")) {
        candidates[[field]] <- NULL
        session$sendCustomMessage("runtime-focus", paste0("settings_", field))
      }
      updateSelectInput(session, paste0("runtime_method_", field), selected = "")
    }, error = notify_error))
  })
  output$settings_versions <- renderText(versions())

  observeEvent(input$settings_retain_save, tryCatch({
    n <- input$settings_retain
    if (length(n) != 1L || !is.finite(n) || n != floor(n) || n < 0L || n > 10000L)
      stop("保留条目数须为 0–10000 的整数。")
    cfg <- tb_read_settings(root)
    cfg$retain <- as.integer(n)
    tb_save_settings(root, cfg)
    removed <- tb_prune_runs(root, cfg$retain)
    refresh_history()
    showNotification(paste("已保存。清理任务", removed, "项。"))
  }, error = notify_error))

  report <- reactiveVal(NULL)
  package_process <- reactiveVal(NULL)
  package_message <- reactiveVal("点击一键检测，查询所选 R 对应仓库的兼容最新版本。")
  output$package_controls <- renderUI(tagList(
    actionButton("settings_check_packages", "一键检测", class = "secondary-button"),
    actionButton("settings_update_packages", "一键更新", class = "primary-button"),
    p("检查全部已安装的非基础包。更新写入工作站专用库；完成后自动重新核验，重启后加载新版。")))
  output$dependency_table <- renderUI({
    data <- report()
    required <- tb_dependency_report()
    if (is.null(data)) data <- data.frame(package = required$package,
      current = ifelse(required$installed, required$version, "未安装"), latest = NA_character_,
      description = required$role, url = tb_package_url(required$package), outdated = FALSE)
    render_packages <- function(data) tags$table(class = "table table-striped", tags$thead(tags$tr(lapply(
      c("包名", "当前版本", "最新版本", "功能简介", "包对应网址", "操作"), tags$th))),
      tags$tbody(lapply(seq_len(nrow(data)), function(i) {
        row <- data[i, ]
        tags$tr(tags$td(row$package), tags$td(row$current), tags$td(if (is.na(row$latest)) "未查到（网络或仓库未收录）" else row$latest),
          tags$td(row$description), tags$td(if (grepl("^https?://", row$url)) tags$a(href = row$url, target = "_blank", "包主页")),
          tags$td(tags$button(type = "button", class = if (row$outdated) "primary-button" else "small-button",
            disabled = if (!row$outdated) "disabled", `data-update-package` = row$package,
            if (row$outdated) "更新包" else if (is.na(row$latest)) "未查到版本" else "无需更新")))
      })))
    core <- data[data$package %in% required$package, , drop = FALSE]
    missing <- setdiff(required$package, core$package)
    if (length(missing)) core <- rbind(core, data.frame(package = missing, current = "未安装",
      latest = NA_character_, description = "工作站功能依赖", url = "", outdated = FALSE))
    core$description <- unname(tb_package_purpose[core$package])
    core$url <- tb_package_url(core$package)
    extra <- data[!data$package %in% required$package, , drop = FALSE]
    tagList(h4("工作站基本软件包"), p("默认列出运行工作站所需的包；最新版本在联网检测后更新。"), render_packages(core),
      if (nrow(extra)) tagList(h4("其他已安装软件包"), render_packages(extra)))
  })
  start_packages <- function(mode, packages = character()) {
    if (tb_jobs_running() || tb_package_updating() || (!is.null(package_process()) && package_process()$is_alive())) stop("请等待分析或包管理任务完成。")
    cfg <- tb_read_settings(root)
    selected_r <- if (nzchar(cfg$rscript)) cfg$rscript else file.path(R.home("bin"), "Rscript.exe")
    selected_version <- trimws(processx::run(selected_r,
      c("--vanilla", "-e", "cat(as.character(getRversion()))"), timeout = 10000, env = tb_runtime_env())$stdout)
    lib <- cfg$package_library
    if (!nzchar(lib) || !identical(cfg$library_r, selected_version))
      lib <- file.path(root, "results", "toolbox", "libraries", paste0("R-", selected_version))
    if (mode == "update") {
      previous <- lib
      lib <- tempfile("update-", tmpdir = file.path(root, "results", "toolbox", "libraries"))
      dir.create(dirname(lib), recursive = TRUE, showWarnings = FALSE)
      dir.create(lib)
      if (dir.exists(previous)) {
        files <- list.files(previous, full.names = TRUE, all.files = TRUE, no.. = TRUE)
        if (length(files) && !all(file.copy(files, lib, recursive = TRUE))) stop("无法准备独立更新库。")
      }
    }
    dir.create(lib, recursive = TRUE, showWarnings = FALSE)
    path <- tempfile("package-report-", tmpdir = dirname(lib), fileext = ".rds")
    process <- tb_package_job(root, mode, path, packages, lib)
    package_process(process)
    .tb_package_update$busy <- TRUE
    package_message(if (mode == "update") "正在更新；完成后自动重新检测…" else "正在读取所选 R 的软件包与仓库版本…")
    finish <- function() {
      if (process$is_alive()) { later::later(finish, 1); return() }
      .tb_package_update$busy <- FALSE
      if (process$get_exit_status() == 0L && file.exists(path)) {
        report(readRDS(path))
        if (mode == "update") {
          cfg <- tb_read_settings(root); cfg$package_library <- lib
          cfg$library_r <- attr(readRDS(path), "R_version"); tb_save_settings(root, cfg)
        }
        package_message("检测完成。最新版本指与所选 R / Bioconductor 发行版兼容的仓库版本。")
      } else package_message(paste(c("操作失败，未确认成功；请检查网络及所选 R 的 BiocManager。", tail(readLines(paste0(path, ".log"), warn = FALSE), 12)), collapse = "\n"))
    }
    later::later(finish, 1)
  }
  output$package_update_log <- renderText(package_message())
  observeEvent(input$settings_check_packages, tryCatch(start_packages("check"), error = notify_error))
  observeEvent(input$settings_update_packages, tryCatch({
    data <- report()
    if (is.null(data)) return(start_packages("update", "__all__"))
    packages <- data$package[data$outdated]
    if (!length(packages)) stop("目前没有检测到可更新的包。")
    start_packages("update", packages)
  }, error = notify_error))
  observeEvent(input$update_one_package, tryCatch({
    data <- req(report()); name <- input$update_one_package
    if (!name %in% data$package[data$outdated]) stop("该包没有可更新版本。")
    start_packages("update", name)
  }, error = notify_error))

  observeEvent(input$settings_exit, {
    if (tb_jobs_running() || tb_package_updating()) {
      showNotification("请等待运行中的分析或更新结束，再退出工作站。", type = "warning")
    } else {
      showModal(modalDialog(title = "退出工作站", p("确认结束本机服务？"),
        footer = tagList(modalButton("返回"), actionButton("settings_exit_confirm", "确认退出"))))
    }
  })
  observeEvent(input$settings_exit_confirm, {
    if (tb_jobs_running() || tb_package_updating()) return(showNotification("还有任务正在运行。", type = "warning"))
    shiny::stopApp()
  })
}
