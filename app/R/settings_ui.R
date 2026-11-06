tb_system_ui <- function(root, project_ui) {
  cfg <- tb_read_settings(root)
  external <- function(url, label) tags$a(href = url, target = "_blank", rel = "noopener", label)
  modalDialog(title = "系统设置", size = "l", easyClose = TRUE,
    tabsetPanel(
      tabPanel("项目工作空间", project_ui),
      tabPanel("运行环境", p(paste("当前 R", getRversion(), "·", R.home())),
        textInput("settings_rscript", "下次启动使用的 Rscript 路径", cfg$rscript, placeholder = "留空使用启动器默认 R"),
        textInput("settings_python", "Python 可执行文件路径（可选）", cfg$python),
        p("当前分析由 R 执行。Python 配置用于版本记录和本机环境检查。"),
        actionButton("settings_probe", "检查版本", class = "small-button"),
        actionButton("settings_runtime_save", "保存运行环境", class = "secondary-button"),
        verbatimTextOutput("settings_versions"),
        p(external("https://cran.r-project.org/bin/windows/base/", "R 官方下载"), " · ",
          external("https://www.python.org/downloads/windows/", "Python 官方下载"))),
      tabPanel("R 软件包", uiOutput("package_controls"), tableOutput("dependency_table"),
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
  notify_error <- function(e) showNotification(conditionMessage(e), type = "error", duration = 12)
  runtime_fields <- function() {
    r <- trimws(input$settings_rscript %||% "")
    python <- trimws(input$settings_python %||% "")
    rv <- tb_runtime_version(r, "R")
    pv <- tb_runtime_version(python, "Python")
    versions(paste("R", if (nzchar(rv)) rv else paste(getRversion(), "（当前）"),
      "\nPython", if (nzchar(pv)) sub("^Python ", "", pv) else "未配置"))
    list(rscript = r, python = python)
  }
  observeEvent(input$show_environment, showModal(tb_system_ui(root, project_ui())))
  observeEvent(input$settings_probe, tryCatch(runtime_fields(), error = notify_error))
  observeEvent(input$settings_runtime_save, tryCatch({
    values <- runtime_fields()
    tb_save_settings(root, utils::modifyList(tb_read_settings(root), values))
    showNotification("已保存，R 路径在下次启动生效。")
  }, error = notify_error))
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

  output$dependency_table <- renderTable(tb_dependency_report(), striped = TRUE, bordered = FALSE)
  output$package_controls <- renderUI({
    packages <- tb_dependency_report()
    tagList(selectizeInput("settings_packages", "选择要安装或更新的工作站软件包",
      packages$package, multiple = TRUE),
      p("更新使用当前 R 的 CRAN／Bioconductor 仓库，安装到工作站专用库。成功后重启工作站生效。"),
      actionButton("settings_update_packages", "安装或更新所选包", class = "secondary-button"))
  })
  output$package_update_log <- renderText({
    invalidateLater(1500, session)
    state <- .tb_package_update$message %||% ""
    path <- .tb_package_update$log
    log <- if (!is.null(path) && file.exists(path)) tail(readLines(path, warn = FALSE, encoding = "UTF-8"), 16L)
    paste(c(state, log), collapse = "\n")
  })
  observeEvent(input$settings_update_packages, tryCatch({
    if (tb_jobs_running() || tb_package_updating()) stop("请等待正在运行的分析或更新结束。")
    packages <- intersect(input$settings_packages, tb_dependency_report()$package)
    if (!length(packages)) stop("请先选择要安装或更新的软件包。")
    base <- file.path(root, "results", "toolbox", "libraries")
    dir.create(base, recursive = TRUE, showWarnings = FALSE)
    lib <- tempfile("workbench-", tmpdir = base)
    dir.create(lib)
    cfg <- tb_read_settings(root)
    version <- as.character(getRversion())
    previous <- cfg$package_library
    if (identical(cfg$library_r, version) && dir.exists(previous)) {
      existing <- list.dirs(previous, full.names = TRUE, recursive = FALSE)
      if (!all(file.copy(existing, lib, recursive = TRUE))) stop("无法复制上次的软件包库。")
    }
    log <- paste0(lib, ".log")
    rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
    process <- processx::process$new(rscript,
      c("--vanilla", file.path(root, "update-packages.R"), lib, packages),
      stdout = log, stderr = "2>&1", windows_hide_window = TRUE, cleanup = TRUE)
    .tb_package_update$process <- process
    .tb_package_update$busy <- TRUE
    .tb_package_update$log <- log
    .tb_package_update$message <- "正在安装或更新所选软件包…"
    finish <- function() {
      if (process$is_alive()) {
        later::later(finish, delay = 1)
        return(invisible(NULL))
      }
      on.exit({ .tb_package_update$busy <- FALSE }, add = TRUE)
      tryCatch({
        if (process$get_exit_status() != 0L) stop("更新未完成，当前软件包配置已保留。")
        current <- tb_read_settings(root)
        current$package_library <- lib
        current$library_r <- version
        tb_save_settings(root, current)
        .tb_package_update$message <- "更新完成，重启工作站生效。"
      }, error = function(e) .tb_package_update$message <- conditionMessage(e))
    }
    later::later(finish, delay = 1)
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
