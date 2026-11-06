# 本地生信工具箱前端。启动时只构建界面；分析仅由“运行当前工具”触发。
app_root <- local({
  file <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
  if (!is.null(file)) dirname(normalizePath(file, winslash = "/")) else getwd()
})
if (!file.exists(file.path(app_root, "R", "toolbox.R"))) {
  app_root <- file.path(getwd(), "app")
}
if (!requireNamespace("shiny", quietly = TRUE)) stop("缺少 shiny，请先安装界面依赖。")
library(shiny)
source(file.path(app_root, "R", "toolbox.R"), encoding = "UTF-8")
source(file.path(app_root, "R", "example_inputs.R"), encoding = "UTF-8")
source(file.path(app_root, "R", "figure_layout.R"), encoding = "UTF-8")
source(file.path(app_root, "R", "immune.R"), encoding = "UTF-8")
source(file.path(app_root, "R", "bulk_workflow.R"), encoding = "UTF-8")
source(file.path(app_root, "R", "string_reference.R"), encoding = "UTF-8")
source(file.path(app_root, "R", "workbench_settings.R"), encoding = "UTF-8")
source(file.path(app_root, "R", "settings_ui.R"), encoding = "UTF-8")
preview_root <- file.path(app_root, "results", "toolbox", "catalog-previews")
if (dir.exists(preview_root)) addResourcePath("catalog-previews", preview_root)
upload_limit <- 1024^3
options(shiny.maxRequestSize = upload_limit) # 单文件上传上限 1 GiB；较大文件使用本地路径。

catalog <- tb_tool_catalog()
heatmap_modes <- c("目标基因表达" = "custom_heatmap", "通路注释与差异表达" = "manual_heatmap")
heatmap_title <- "基因表达与通路注释热图"
menu_catalog <- rbind(data.frame(id = "bulk", title = "Bulk RNA-seq 自动化分析", category = "分析流程",
  description = "从原始 Count 到 PPI 和组图。逐步审核、调整并确认。", kind = "workflow"),
  catalog[catalog$id != "manual_heatmap", , drop = FALSE])
target_entry <- menu_catalog$id == "custom_heatmap"
menu_catalog$title[target_entry] <- heatmap_title
menu_catalog$description[target_entry] <- "按目标基因列表绘图，或依据差异表达结果按通路分块展示。"
defaults <- tb_default_settings(dirname(app_root))
`%or%` <- function(x, y) if (is.null(x) || !length(x)) y else x
tool_help <- list(
  pca = "对计数矩阵进行 DESeq2/VST 转换，选择高变基因后计算 PCA。中心化、是否标准化和基因数都会影响坐标。",
  deg = "使用原始整数 Count 拟合 DESeq2。正 log2FC 表示实验组相对对照组上调；FDR 与展示筛选阈值分别设置。",
  volcano = "从完整差异表按校正 P 值和 log2FC 阈值分类，输出火山图和入图数据。 ",
  heatmap = "从差异基因或高变基因中选取表达矩阵。逐行 Z-score 用于比较同一基因在样本间的变化，不表示基因间绝对表达量。",
  custom_heatmap = "使用处理后的表达矩阵，按目标基因列表绘图。 ",
  manual_heatmap = "使用项目原有手工通路注释热图流程。提供 pathway_annotation.xlsx，保留同一基因在多个通路中的重复展示及已确认样式。",
  go = "使用本机人或小鼠 GO 注释或固定版本的本地 GMT 做过度富集分析。背景来自实际受检且可映射的基因。",
  kegg = "使用已下载且明确版本的 KEGG GMT 做富集。请确认 GMT 的 ID 类型与项目一致；不会静默联网下载数据库。",
  gsea = "使用完整有效统计量排序做 GSEA，不先筛选显著差异基因。结果取决于排名、基因集和随机种子。",
  gsva = "对表达矩阵计算通路分数，再按分组建模。输入本地固定版本 GMT；通路分数不等于基因表达量。",
  network = "Node 与 Edge 分别上传。自动匹配 id、STRING_id 或 gene_id；支持 from/to、source/target。文件模式直接绘制已有网络，不重新拟合差异模型。",
  matrix_pca = "直接分析数值矩阵，不执行 RNA-seq 标准化。首列为行名、首行为样本名；样本按列排列。",
  immune = "使用归一化表达矩阵计算 ssGSEA 分数。细胞标志反映相对富集，GO、KEGG 和疾病签名反映基因集富集。",
  figure_layout = "按序号上传图片。自动裁白并按阅读顺序排列不同大小的面板；生成后可打开编辑器调整图和序号。",
  matrix_heatmap = "直接绘制通用数值矩阵，可选择 log2 变换、行 Z-score、行列聚类及距离方法。",
  circos = "使用染色体长度、区域特征和区间连线绘制环形图。输入 Tab 分隔文件，单位统一为碱基 bp。"
)
input_meta <- list(
  counts = c("原始计数矩阵", "CSV；gene_id、gene_name 与原始样本列。Count 必须为非负整数。", ".csv,.tsv,.txt"),
  groups = c("样本分组表", "CSV；支持项目的 Sample/Group 或工作台的 sample_id/condition 表。", ".csv,.tsv,.txt"),
  targets = c("目标基因表", "CSV；GeneKey、可选 Pathway 和 Use。Count 热图按基因名或 ID 匹配，忽略大小写。", ".csv,.tsv,.txt"),
  annotation = c("手工通路注释", "Excel；使用 GeneAnnotation 工作表。", ".xlsx"),
  gmt = c("本地基因集", "GMT；每行：通路 ID、描述、基因列表，以 Tab 分隔。", ".gmt"),
  nodes = c("Node · 节点表", "CSV / TSV；id、STRING_id 或 gene_id；可附 label、gene_name、log2FC、group。", ".csv,.tsv,.txt"),
  edges = c("Edge · 连线表", "CSV / TSV；from,to 或 source,target；可附 score / combined_score。", ".csv,.tsv,.txt"),
  matrix = c("数值矩阵", "CSV / TSV；第一列为行标识，其他列为样本数值，不含额外注释列。", ".csv,.tsv,.txt"),
  deg = c("已有差异结果（可选）", "不填时从 Count 分析。支持项目差异结果列及工作台标准结果。", ".csv,.tsv,.txt"),
  chromosomes = c("染色体长度", "CSV / TSV，含表头 chr,length；长度单位 bp。", ".tsv,.txt,.csv"),
  features = c("区域特征（可选）", "CSV / TSV，含表头 chr,start,end,label；0 起点、半开区间。", ".tsv,.txt,.csv"),
  links = c("区间连线（可选）", "CSV / TSV，含表头 chr1,start1,end1,chr2,start2,end2。", ".tsv,.txt,.csv")
)
panel_keys <- tb_panel_fields(12)
input_meta[panel_keys] <- lapply(seq_along(panel_keys), function(i) c(paste("图片", i),
  "单帧 PNG、JPEG 或 TIFF，最多 1 亿像素。", ".png,.jpg,.jpeg,.tif,.tiff"))

# Explanation is attached to its local control after Shiny renders dynamic inputs.
help_note <- function(text) tags$span(class = "context-note", `data-note` = text, hidden = "hidden")
tool_help[tb_general_tools] <- as.list(tb_general_help)

tb_palette_ui <- function(style) {
  presets <- tb_palettes()
  div(class = "palette-tool", `data-default-colors` = paste(c(style$low, style$mid, style$high), collapse = ";"),
    tags$details(class = "palette-list", tags$summary("科研配色预设"),
      lapply(names(presets), function(name) {
        p <- presets[[name]]
        colors <- c(p$low, p$mid, p$high)
        tags$button(type = "button", class = "palette-option", `data-colors` = paste(colors, collapse = ";"),
          span(name), span(class = "palette-ramp", style = paste0("background:linear-gradient(90deg,", paste(colors, collapse = ","), ")")))
      })),
    div(class = "palette-ramp palette-current", `aria-label` = "当前配色色尺"),
    tags$label("自定义色尺", tags$select(class = "palette-mode",
      tags$option(value = "1", "单色"), tags$option(value = "2", "双色"),
      tags$option(value = "3", selected = "selected", "三色"),
      tags$option(value = "4", "多色（4 色起，可输入 4–8 色）"))),
    div(class = "palette-pickers"),
    textInput("style_gradient", "HEX / RGB 颜色（分号分隔）", value = style$gradient %or% "",
      placeholder = "#245F67; rgb(239,235,217); #A95A46"))
}
section_title <- function(number, title, hint = NULL) {
  div(class = "section-heading", span(class = "step-index", number),
      div(h3(title, `data-help` = hint, tabindex = if (!is.null(hint)) "0")))
}
file_control <- function(name, value = NULL, meta = input_meta[[name]], uploaded = NULL, example_id, example_checked = FALSE) {
  div(class = "file-control", `data-help` = meta[2], textInput(paste0("path_", name), meta[1],
      value = value %or% defaults$inputs[[name]] %or% "", placeholder = "本机路径 / 上传文件"),
      div(class = if (!is.null(example_id)) "upload-with-example", div(class = "upload-zone", `data-key` = name, `data-limit` = format(upload_limit, scientific = FALSE),
        tags$button(type = "button", class = "upload-drop",
          span("拖拽文件到这里，或点击选择"),
          tags$small(paste0(gsub(",", " / ", toupper(meta[3])), " · 单文件最大 1 GiB", if (startsWith(name, "panel_")) " · 1 亿像素"))),
        div(class = "upload-file-row", hidden = if (is.null(uploaded)) "hidden",
          span(class = "upload-filename", uploaded$name %or% ""),
          tags$button(type = "button", class = "upload-remove", "移除")),
        div(class = "upload-native", fileInput(paste0("upload_", name), NULL, accept = meta[3])),
        div(class = "upload-feedback", `aria-live` = "polite")),
        if (!is.null(example_id)) checkboxInput(example_id, "示例数据", value = example_checked)))
}
num <- function(name, label, default, min = 0, max = NA, step = 1) {
  numericInput(name, label, value = defaults$params[[name]] %or% default,
               min = min, max = max, step = step)
}
check <- function(name, label, default = FALSE) {
  checkboxInput(name, label, defaults$params[[name]] %or% default)
}

ui <- fluidPage(
  tags$head(tags$title("生信工作台 · BioWorkbench"), tags$script(src = "uploads.js"),
    tags$meta(name = "viewport", content = "width=device-width, initial-scale=1"),
    tags$link(rel = "stylesheet", href = "toolbox.css"),
    tags$link(rel = "stylesheet", href = "studio.css"),
    tags$script(src = "toolbox.js")),
  div(class = "app-shell",
    tags$aside(class = "sidebar",
      div(class = "brand", div(class = "brand-symbol", "B"),
        div(strong("转录组分析工作站"), tags$small("BIOWORKBENCH"))),
      div(class = "sidebar-project", span(class = "live-dot"), "本地项目",
          textOutput("project_name", inline = TRUE)),
      textInput("tool_search", NULL, placeholder = "搜索工具 / PCA / 热图…"),
      actionButton("show_home", "分析工具目录", class = "home-button"),
      uiOutput("tool_navigation"),
      div(class = "sidebar-bottom", `data-help` = "数据与分析结果保存在本机。",
          span("本地分析"))),
    tags$main(class = "main-shell",
      div(class = "topbar", div(textOutput("breadcrumb_tool", inline = TRUE)),
        div(class = "topbar-right", span(class = "local-badge", `data-help` = "服务仅监听 127.0.0.1；分析结果保存在本机。", tabindex = "0", "本机"),
            actionButton("refresh_history", "任务记录", class = "quiet-button"),
            actionButton("show_environment", "系统设置", class = "quiet-button"))),
      uiOutput("workspace"),
      div(class = "app-footer", "转录组分析工作站")))
)

server <- function(input, output, session) {
  selected <- reactiveVal("home")
  bulk <- reactiveVal(NULL)
  bulk_active <- reactiveVal(FALSE)
  bulk_step <- function() {
    flow <- bulk()
    if (bulk_active() && !is.null(flow)) names(tb_bulk_steps)[flow$step] else NULL
  }
  in_bulk_step <- function() identical(selected(), bulk_step())
  job <- reactiveVal(NULL)
  result <- reactiveVal(NULL)
  last_spec <- reactiveVal(NULL)
  history_tick <- reactiveVal(0L)
  view_id <- reactiveVal(NULL)
  visible_job <- reactive({
    current <- job()
    if (!is.null(current) && identical(current$id, view_id()) && identical(current$tool, selected())) current
  })
  visible_result <- reactive(if (!is.null(visible_job())) result())
  sync_pins <- function() {
    flow <- bulk()
    .tb_task_views[[session$token]] <- unique(c(view_id(), basename(as.character(unlist(flow$approved %or% list()))),
      vapply(as.list(bulk_jobs), function(run) run$id, character(1))))
  }
  observe(sync_pins())
  tb_settings_server(input, output, session, app_root, function() history_tick(history_tick() + 1L), function() project_settings_ui())
  group_choices <- reactiveVal(unique(c(defaults$params$control, defaults$params$treatment)))
  groups_message <- reactiveVal("")
  upload_paths <- reactiveValues()
  path_cache <- reactiveValues()
  style_cache <- reactiveValues()
  resource_paths <- character()
  saved_project <- tb_read_settings(app_root)
  folder <- if (dir.exists(saved_project$project_folder)) saved_project$project_folder else dirname(app_root)
  project_folder <- reactiveVal(folder)
  project_auto <- reactiveVal(isTRUE(saved_project$project_auto))
  detected <- if (isTRUE(saved_project$project_auto)) tb_project_inputs(folder) else character()
  auto_paths <- reactiveVal(detected)
  for (name in names(detected)) path_cache[[name]] <- unname(detected[name])
  output$project_name <- renderText(basename(project_folder()))
  project_settings_ui <- function() tagList(
    textInput("project_path", "工作文件夹", project_folder()),
    uiOutput("project_subfolders"),
    actionButton("project_parent", "上一级", class = "small-button"),
    checkboxInput("project_scan", "自动选取原始数据", project_auto()),
    p("仅匹配当前目录中名称明确且唯一的 Count、分组和注释文件。"),
    actionButton("save_project", "应用工作空间", class = "secondary-button"))
  output$project_subfolders <- renderUI({
    path <- trimws(input$project_path %or% "")
    if (!dir.exists(path)) return(NULL)
    children <- list.dirs(path, recursive = FALSE, full.names = TRUE)
    selectInput("project_child", "进入子目录", c("选择子目录" = "", stats::setNames(children, basename(children))))
  })
  observeEvent(input$project_child, {
    if (nzchar(input$project_child)) updateTextInput(session, "project_path", value = input$project_child)
  })
  observeEvent(input$project_parent, {
    if (dir.exists(input$project_path)) updateTextInput(session, "project_path",
      value = dirname(normalizePath(input$project_path, winslash = "/")))
  })
  observeEvent(input$save_project, {
    path <- trimws(input$project_path %or% "")
    if (!dir.exists(path)) {
      showNotification("工作文件夹不存在。", type = "error")
      return()
    }
    path <- normalizePath(path, winslash = "/")
    settings <- tb_read_settings(app_root)
    settings$project_folder <- path
    settings$project_auto <- isTRUE(input$project_scan)
    saved <- tryCatch({ tb_save_settings(app_root, settings); TRUE }, error = function(e) {
      showNotification(conditionMessage(e), type = "error")
      FALSE
    })
    if (!saved) return()
    old <- auto_paths()
    found <- if (isTRUE(input$project_scan)) tb_project_inputs(path) else character()
    for (name in union(names(old), names(found))) {
      current <- path_cache[[name]] %or% ""
      if (!nzchar(current) || identical(current, unname(old[name]))) {
        value <- if (name %in% names(found)) unname(found[name]) else ""
        path_cache[[name]] <- value
        updateTextInput(session, paste0("path_", name), value = value)
      }
    }
    project_folder(path)
    project_auto(isTRUE(input$project_scan))
    auto_paths(found)
    showNotification(paste0("工作文件夹：", basename(path), " · 唯一匹配文件 ", length(found), " 项"))
  })
  for (name in names(input_meta)) local({
    key <- name
    observeEvent(input[[paste0("path_", key)]], {
      path_cache[[key]] <- input[[paste0("path_", key)]]
    }, ignoreNULL = TRUE)
  })

  choose_tool <- function(id) {
    previous <- isolate(selected())
    if (previous %in% catalog$id) {
      fields <- names(do.call(c, unname(tb_style_schema(previous))))
      saved <- list()
      for (field in c(fields, "formats", "gradient")) {
        value <- isolate(input[[paste0("style_", field)]])
        if (!is.null(value)) saved[[field]] <- value
      }
      style_cache[[previous]] <- saved
    }
    if (!identical(previous, id)) view_id(NULL)
    selected(id)
  }
  observeEvent(input$show_home, { bulk_active(FALSE); choose_tool("home") })
  observeEvent(input$tool_id, {
    if (identical(input$tool_id, "bulk")) {
      flow <- bulk()
      if (is.null(flow)) choose_tool("bulk") else open_bulk_step(flow, launch = FALSE)
    } else if (input$tool_id %in% catalog$id) {
      bulk_active(FALSE)
      choose_tool(input$tool_id)
    }
  })

  for (name in names(input_meta)) local({
    key <- name
    observeEvent(input[[paste0("upload_", key)]], {
      uploaded <- input[[paste0("upload_", key)]]
      req(uploaded)
      extension <- paste0(".", tolower(tools::file_ext(uploaded$name)))
      if (nrow(uploaded) != 1L || uploaded$size > upload_limit ||
          !extension %in% strsplit(input_meta[[key]][3], ",", fixed = TRUE)[[1]]) {
        session$sendCustomMessage("upload-state", list(key = key, error = paste("[BW-I06]", uploaded$name, "文件类型或大小超出上传框标明的限制。")))
        return()
      }
      directory <- file.path(tempdir(), paste0("bioworkbench-", session$token))
      dir.create(directory, recursive = TRUE, showWarnings = FALSE)
      destination <- tempfile(paste0(key, "-"), tmpdir = directory, fileext = extension)
      if (!file.copy(uploaded$datapath, destination, overwrite = TRUE)) {
        session$sendCustomMessage("upload-state", list(key = key, error = "无法保存上传文件，请使用本机路径。"))
        return()
      }
      previous <- upload_paths[[key]]
      if (!is.null(previous)) unlink(previous$path)
      upload_paths[[key]] <- list(path = destination, name = uploaded$name)
      path_cache[[key]] <- destination
      updateCheckboxInput(session, example_key(key), value = FALSE)
      updateTextInput(session, paste0("path_", key), value = destination)
      session$sendCustomMessage("upload-state", list(key = key, name = uploaded$name))
    }, ignoreNULL = TRUE)
    observeEvent(input[[paste0("remove_upload_", key)]], {
      uploaded <- upload_paths[[key]]
      if (is.null(uploaded)) return()
      if (identical(path_cache[[key]], uploaded$path)) {
        path_cache[[key]] <- ""
        updateTextInput(session, paste0("path_", key), value = "")
      }
      upload_paths[[key]] <- NULL
      unlink(uploaded$path)
    }, ignoreNULL = TRUE)
  })

  example_key <- function(name) {
    if (name == "groups" && "counts" %in% active_fields()) name <- "counts"
    paste("example", selected(), name, sep = "_")
  }
  example_checked <- function(name) isTRUE(input[[example_key(name)]])
  active_fields <- function() {
    id <- selected()
    if (id == "bulk") return(c("counts", "groups", "gmt", "edges"))
    if (in_bulk_step() && id != "figure_layout") return(switch(id, network = "edges",
      go = "gmt", kegg = "gmt", gsea = "gmt", gsva = "gmt", character()))
    if (id == "figure_layout") {
      count <- input$panel_count %or% defaults$params$panel_count
      if (!is.finite(count) || count != floor(count) || count < 2 || count > 12) return(character())
      return(tb_panel_fields(count))
    }
    if (id == "home") return(character())
    params <- defaults$params
    params$downstream_input <- id %in% c(tb_processed_tools, "volcano")
    params$network_mode <- input$network_mode %or% params$network_mode
    params$matrix_use_groups <- isTRUE(input$matrix_use_groups)
    # Keep optional GMT upload mounted when switching reference sources.
    if (id == "immune") params$immune_source <- "custom"
    group_mode <- input$group_mode %or% params$group_mode
    params$heatmap_mode <- switch(group_mode, joint = "variable", pair = input$heatmap_mode %or% params$heatmap_mode, "deg")
    tb_active_inputs(list(tool = id, params = params, inputs = list(matrix = "", deg = "")))
  }
  example_dataset <- function() tb_example_dataset(app_root, selected(), input$species %or% defaults$params$species)
  example_path <- function(name) tb_example_path(app_root, selected(), name,
    list(dataset = example_dataset(), network_mode = if (selected() == "bulk") "deg" else input$network_mode))
  read_input <- function(name) {
    if (example_checked(name)) {
      path <- example_path(name)
      if (nzchar(path)) return(path)
    }
    path <- input[[paste0("path_", name)]] %or% path_cache[[name]] %or% defaults$inputs[[name]] %or% ""
    trimws(path)
  }
  refresh_groups <- function() {
    tryCatch({
      path <- read_input("groups")
      if (!file.exists(path)) stop("分组表不存在。")
      groups <- tb_read_groups(path)
      choices <- unique(groups$condition)
      choices <- choices[!is.na(choices) & nzchar(choices)]
      if (length(choices) < 2) stop("至少需要两个分组。")
      group_choices(choices)
      subset <- intersect(isolate(input$group_subset) %or% character(), choices)
      updateSelectizeInput(session, "group_subset", choices = choices, selected = subset)
      previous_control <- isolate(input$control) %or% defaults$params$control
      previous_treatment <- isolate(input$treatment) %or% defaults$params$treatment
      control <- if (previous_control %in% choices) previous_control else choices[1]
      treatments <- setdiff(choices, control)
      updateSelectInput(session, "control", choices = choices,
        selected = control)
      updateSelectInput(session, "treatment", choices = choices,
        selected = if (previous_treatment %in% treatments) previous_treatment else treatments[1])
      groups_message(paste(nrow(groups), "个样本 ·", length(choices), "个组：",
                           paste(choices, collapse = " / ")))
    }, error = function(e) {
      groups_message(conditionMessage(e))
      showNotification(conditionMessage(e), type = "warning")
    })
  }
  observeEvent(input$refresh_groups, refresh_groups())

  filtered_catalog <- reactive({
    search <- tolower(trimws(input$tool_search %or% ""))
    if (!nzchar(search)) return(menu_catalog)
    menu_catalog[grepl(search, tolower(paste(menu_catalog$title, menu_catalog$id,
      menu_catalog$category, menu_catalog$description)), fixed = TRUE), , drop = FALSE]
  })
  output$tool_navigation <- renderUI({
    tools <- filtered_catalog()
    tagList(lapply(unique(tools$category), function(category) {
      members <- tools[tools$category == category, , drop = FALSE]
      div(class = "nav-category", div(class = "category-label", category),
        lapply(seq_len(nrow(members)), function(i) {
          tags$button(type = "button", class = paste("tool-nav", if ((bulk_active() && members$id[i] == "bulk") || (!bulk_active() && selected() == members$id[i]) ||
            (members$id[i] == "custom_heatmap" && selected() == "manual_heatmap")) "active"),
            `data-tool` = members$id[i], span(class = "nav-dot"), members$title[i])
        }))
    }))
  })
  output$breadcrumb_tool <- renderText({
    if (selected() == "home") "工具总览" else if (selected() == "bulk" || bulk_active()) "Bulk RNA-seq 自动化分析" else if (selected() %in% heatmap_modes) heatmap_title else catalog$title[match(selected(), catalog$id)]
  })

  output$workspace <- renderUI({
    if (selected() == "home") {
      return(div(class = "workspace home-workspace",
        div(class = "home-hero",
          div(class = "hero-composition", div(h1("转录组分析", tags$br(), span("与数据可视化"))),
            div(class = "hero-art", `aria-hidden` = "true", div(class = "art-orbit orbit-one"), div(class = "art-orbit orbit-two"),
                div(class = "art-axis"), span(class = "art-node n1"), span(class = "art-node n2"), span(class = "art-node n3"),
                span(class = "art-node n4"), span(class = "art-caption", "EXPRESSION / PATHWAY / NETWORK")))),
        div(class = "home-section-title", h2("分析工具目录"), span(paste(nrow(menu_catalog), "项"))),
        div(class = "catalog-filters", radioButtons("catalog_category", "分析分类",
          c("全部" = "all", unique(menu_catalog$category)), inline = TRUE)),
        uiOutput("tool_cards"),
        div(class = "history-section", div(class = "home-section-title", h2("最近任务")), uiOutput("history_list"))))
    }
    if (selected() == "bulk") return(bulk_setup_ui())
    tool <- catalog[match(selected(), catalog$id), , drop = FALSE]
    div(class = "workspace tool-workspace",
      div(class = "tool-header", div(div(class = "eyebrow", tool$category),
        h1(if (selected() %in% heatmap_modes) heatmap_title else tool$title, `data-help` = tool$description, tabindex = "0"))),
      if (bulk_active()) uiOutput("bulk_progress"),
      div(class = "tool-layout",
        div(class = "configuration-column",
          div(class = "panel",
            if (selected() == "figure_layout") section_title("01", "图片输入", "上传图片或填写本机图片路径")
            else section_title("01", "数据输入", "使用本机路径、上传文件或勾选示例"),
            if (selected() == "figure_layout") num("panel_count", "图片数量", 4, 2, 12),
            if (!bulk_active() && selected() != "figure_layout") actionButton("use_all_examples", "勾选整套示例", class = "small-button"),
              if (selected() %in% heatmap_modes) div(class = "group-refresh",
                lapply(names(heatmap_modes), function(label) {
                  mode <- heatmap_modes[[label]]
                  tags$button(type = "button", class = "small-button heatmap-mode",
                    `data-tool` = mode, `aria-pressed` = if (selected() == mode) "true" else "false",
                    disabled = if (selected() == mode) "disabled", label)
                })),
              uiOutput("input_controls")),
          div(class = "panel", section_title("02", "分析参数", tool_help[[selected()]]),
              uiOutput("parameter_controls")),
          if (selected() == "figure_layout") conditionalPanel("output.figure_ready === true",
            div(class = "panel", section_title("03", "纸张、布局与导出", "设置纸张方向、阅读顺序及序号字体"), uiOutput("style_controls")))
          else if (selected() != "deg") div(class = "panel", tags$details(tags$summary("图形样式与导出",
              `data-help` = "调整样式后点击「仅重新绘图」复用当前结果。画布单位为英寸，DPI 仅影响位图。", tabindex = "0"),
              div(class = "details-content", uiOutput("style_controls")))),
          div(class = "run-bar", actionButton("validate_inputs", "检查输入", class = "secondary-button"),
              actionButton("run_tool", "运行当前工具", class = "primary-button")),
          help_note("运行会执行分析。仅修改样式时，可从已完成结果重新绘图。")),
        div(class = "results-column", uiOutput("job_status"),
          div(class = "panel result-panel", div(class = "result-heading", h3("结果工作区"),
              uiOutput("result_badge")),
            uiOutput("comparison_picker"),
            tabsetPanel(id = "result_tab", type = "tabs",
              tabPanel("图形预览", uiOutput("preview_panel")),
              if (selected() == "network") tabPanel("交互网络", uiOutput("interactive_network")),
              tabPanel("数据表", uiOutput("data_selector"), tableOutput("data_preview")),
              tabPanel("运行日志", tags$pre(class = "job-log", textOutput("job_log"))),
              tabPanel("输出文件", uiOutput("file_list"))),
            uiOutput("redraw_action"), uiOutput("download_actions")))))
  })
  output$tool_cards <- renderUI({
    tools <- filtered_catalog()
    category <- input$catalog_category %or% "all"
    if (category != "all") tools <- tools[tools$category == category, , drop = FALSE]
    if (!nrow(tools)) return(div(class = "empty-small", "没有匹配的工具，请换一个关键词。"))
    div(class = "tool-card-grid", lapply(seq_len(nrow(tools)), function(i) {
      preview <- paste0(tools$id[i], ".png")
      tags$button(type = "button", class = "tool-card", `data-tool` = tools$id[i], `data-help` = tools$description[i],
        if (file.exists(file.path(preview_root, preview))) tags$img(class = "tool-card-preview",
          src = paste0("catalog-previews/", preview), alt = "", loading = "lazy", `aria-hidden` = "true"),
        span(class = "card-category", tools$category[i]),
        h3(tools$title[i]), p(tools$description[i]), span(class = "card-link", "↗", `aria-hidden` = "true"))
    }))
  })
  output$input_controls <- renderUI({
    req(selected() != "home")
    pathway <- selected() %in% tb_pathway_tools
    tagList(uiOutput("input_file_rows"), if (pathway) textOutput("reference_detail"))
  })
  output$input_file_rows <- renderUI({
    req(selected() != "home")
    fields <- active_fields()
    if (selected() == "figure_layout") validate(need(length(fields), "图片数量须为 2–12 的整数。"))
    pathway <- selected() %in% tb_pathway_tools
    immune <- selected() == "immune"
    staged <- if (in_bulk_step()) tb_bulk_spec(bulk(), selected(), defaults) else NULL
    panel_choices <- if (!is.null(staged) && selected() == "figure_layout") tb_bulk_figures(bulk()) else character()
    tagList(if (!is.null(staged) && selected() != "figure_layout") p(if (is.null(bulk()$approved$deg)) "沿用流程设置中的 Count、分组和比较方向。" else "读取已确认的 DEG 输出。"),
      if (pathway) selectInput("pathway_source", "参考注释库", tb_pathway_sources(selected()),
        selected = staged$params$pathway_source %or% isolate(input$pathway_source)),
      if (immune) tagList(selectInput("immune_source", "基因集来源", tb_immune_sources,
        selected = isolate(input$immune_source) %or% "cell"), uiOutput("immune_presets")),
      lapply(fields, function(name) {
        meta <- if (selected() %in% tb_general_tools) c("绘图数据表", tool_help[[selected()]], input_meta[[name]][3]) else input_meta[[name]]
        if (name == "deg") meta[1L:2L] <- if (selected() == "gsea")
          c("完整差异结果或排序表", "gene_id 与有符号 stat 或 score。请保留全部有效排序基因。")
          else c("完整差异结果表 · deg_all.csv", "gene_id、log2FoldChange 或 log2FC，以及 padj 或完整表 pvalue。")
        if (name == "matrix" && selected() %in% tb_processed_tools) meta[1L:2L] <-
          c("处理后表达矩阵 · vst.csv", "首列 gene_id，其余列为样本表达值。可使用 DEG 输出的 VST 或已有归一化矩阵。")
        if (name == "groups" && selected() %in% tb_processed_tools) meta[1L] <- "样本分组 · sample_mapping.csv"
        initial <- if (name %in% c("edges", "gmt")) staged$inputs[[name]] else NULL
        control <- file_control(name, initial %or% isolate(path_cache[[name]]), meta, isolate(upload_paths[[name]]),
          if (is.null(staged) && !(name == "groups" && "counts" %in% fields) && nzchar(isolate(example_path(name)))) example_key(name),
          isolate(example_checked(name)))
        if (selected() == "figure_layout") {
          key <- paste0("weight_", name)
          slider <- sliderInput(key, "相对大小", min = 50, max = 200, step = 10,
            value = isolate(input[[key]]) %or% 100, post = "%", ticks = FALSE)
          if (!length(panel_choices)) return(tagList(control, slider))
        }
        if (length(panel_choices)) {
          index <- match(name, fields)
          key <- paste0("bulk_", name)
          old <- isolate(input[[key]])
          choice <- if (!is.null(old) && old %in% c("", panel_choices)) old else if (index <= length(panel_choices)) unname(panel_choices[index]) else ""
          return(tagList(selectInput(key, paste("面板", index, "来源"), c("上传图片或填路径" = "", panel_choices), selected = choice),
            conditionalPanel(sprintf("input.%s === ''", key), control), slider))
        }
        if (pathway && name == "gmt") conditionalPanel("input.pathway_source === 'custom'", control)
        else if (immune && name == "gmt") conditionalPanel("input.immune_source === 'custom'", control)
        else control
      }),
      if (selected() %in% c("matrix_pca", "matrix_heatmap"))
        help_note("勾选分析参数中的“使用分组表”，即可上传分组并用于绘图。"))
  })

  observeEvent(input$use_all_examples, {
    req(selected() != "figure_layout")
    fields <- active_fields()
    for (name in fields) {
      if (nzchar(example_path(name))) updateCheckboxInput(session, example_key(name), value = TRUE)
    }
    synthetic <- example_dataset() == "synthetic"
    if (selected() %in% tb_pathway_tools) updateSelectInput(session, "pathway_source",
      selected = if (synthetic) "custom" else unname(tb_pathway_sources(selected())[1]))
    if (selected() == "immune") updateSelectInput(session, "immune_source", selected = if (synthetic) "custom" else "cell")
  })

  observeEvent({
    fields <- active_fields()
    list(example_dataset(), vapply(fields %or% character(), example_checked, logical(1)))
  }, {
    fields <- active_fields()
    if (is.null(fields)) return()
    dataset <- example_dataset()
    if (dataset != "synthetic" && any(vapply(intersect(fields, c("counts", "matrix", "groups", "deg")), example_checked, logical(1)))) {
      updateSelectInput(session, "species", selected = dataset)
    }
    if ("groups" %in% fields && example_checked("groups") && !selected() %in% c("matrix_pca", "matrix_heatmap")) {
      refresh_groups()
    }
  }, ignoreInit = TRUE)

  output$immune_presets <- renderUI({
    source <- input$immune_source %or% "cell"
    if (source == "custom") return(NULL)
    choices <- tb_immune_choices(app_root, input$species %or% defaults$params$species, source)
    if (!length(choices)) return(div(class = "empty-small", "此物种的预设缓存不可用，请检查 references 目录。"))
    selectizeInput("immune_terms", "预设基因集", choices, selected = head(unname(choices), 6),
      multiple = TRUE, options = list(maxItems = 40, placeholder = "搜索基因集 ID 或名称"))
  })

  output$reference_detail <- renderText({
    source <- input$pathway_source
    if (is.null(source) || source == "custom") return("")
    species <- input$species %or% defaults$params$species
    switch(source, go = if (species == "human") "Gene Ontology · org.Hs.eg.db" else "Gene Ontology · org.Mm.eg.db",
      kegg = paste("KEGG PATHWAY", if (species == "human") "hsa" else "mmu", "· 首次联网 · 限符合 KEGG 条款的学术使用"),
      reactome = paste("Reactome", if (species == "human") "Homo sapiens" else "Mus musculus", "· 首次联网"))
  })

  group_mode_ui <- function(tool, initial) {
    choices <- group_choices()
    joint <- tool %in% c("pca", "custom_heatmap", "heatmap")
    modes <- c("指定两组" = "pair",
      if (joint) c("多组联合展示" = "joint"),
      if (!tool %in% c("pca", "custom_heatmap", "heatmap", "manual_heatmap")) c("各组分别对照基准组" = "reference", "所有组两两比较" = "all_pairs"))
    current <- isolate(input$group_mode) %or% initial$group_mode
    if (!current %in% modes) current <- "pair"
    pick <- function(value, fallback) if (value %in% choices) value else fallback
    control <- pick(isolate(input$control) %or% initial$control, choices[1L])
    treatment <- pick(isolate(input$treatment) %or% initial$treatment, setdiff(choices, control)[1L])
    if (identical(control, treatment)) treatment <- setdiff(choices, control)[1L]
    tagList(selectInput("group_mode", "分组分析方式", modes, selected = current),
      conditionalPanel("input.group_mode !== 'pair'",
        selectizeInput("group_subset", "纳入组别（留空使用全部）", choices, multiple = TRUE,
          selected = intersect(isolate(input$group_subset) %or% character(), choices))),
      div(class = "two-columns",
        conditionalPanel("input.group_mode === 'pair' || input.group_mode === 'reference'",
          selectInput("control", "对照组 · 分母", choices, selected = control)),
        conditionalPanel("input.group_mode === 'pair'",
          selectInput("treatment", "实验组 · 分子", choices, selected = treatment))))
  }


  output$parameter_controls <- renderUI({
    id <- selected()
    req(id != "home")
    matrix_tool <- id %in% c("matrix_pca", "matrix_heatmap", "circos", "immune", "figure_layout", tb_general_tools)
    staged <- if (in_bulk_step()) tb_bulk_spec(bulk(), id, defaults) else NULL
    initial <- staged$params %or% defaults$params
    network_files <- id == "network" && is.null(staged) && (input$network_mode %or% "files") == "files"
    ppi_counts <- id == "network" && identical(input$network_mode, "deg")
    needs_groups <- ppi_counts || id %in% c("pca", "deg", "heatmap", "custom_heatmap", "manual_heatmap", "gsva")
    basic <- if (is.null(staged) && needs_groups && !matrix_tool && !network_files) tagList(
      group_mode_ui(id, initial),
      div(class = "group-refresh", actionButton("refresh_groups", "读取当前分组", class = "small-button"),
          textOutput("group_summary", inline = TRUE)),
      if (ppi_counts || id %in% c("pca", "deg", "gsva")) tags$details(tags$summary(if (id == "gsva") "批次与协变量" else "模型与低表达过滤"), div(class = "details-content two-columns",
        if (id != "gsva") num("min_count", "Count 下限", 10, 0),
        if (id != "gsva") num("min_samples", "至少达到下限的样本数", 3, 1),
        if (id != "gsva") num("alpha", "模型独立过滤 FDR", 0.05, 0.000001, 1, 0.01),
        if (id != "gsva") selectInput("fit_type", "离散度拟合", c("Parametric" = "parametric", "Local" = "local", "Mean" = "mean"),
          selected = defaults$params$fit_type %or% "parametric"),
        check("use_batch", "将技术批次纳入模型"),
        textInput("covariates", "分类协变量（逗号分隔）", defaults$params$covariates %or% "")),
        help_note("批次需在工作台格式分组表中明确填写；与分组完全混杂时直接报错。")))
    selection <- if (id %in% c("deg", "volcano", "heatmap", "go", "kegg") || (id == "network" && !network_files)) tagList(
      div(class = "two-columns", numericInput("padj", "筛选 FDR 上限", initial$padj, min = 0.000001, max = 1, step = 0.01),
          numericInput("log2fc", "|log₂FC| 下限", initial$log2fc, min = 0, step = 0.1)),
      selectInput("direction", "差异方向", c("全部" = "all", "上调" = "up", "下调" = "down"),
                  selected = initial$direction))
    specific <- switch(id,
      pca = tagList(num("pca_top", "参与 PCA 的高变基因数", 500, 2), check("pca_scale", "PCA 前按基因标准化"),
                   check("labels", "显示样本标签")),
      deg = help_note("比较方向：实验组 / 对照组；输出全部统计量及差异筛选表。"),
      volcano = tagList(check("labels", "标注显著基因"),
                         help_note("直接使用差异表达任务输出的 deg_all.csv。")),
      heatmap = tagList(
        conditionalPanel("input.group_mode === 'pair'",
          selectInput("heatmap_mode", "候选基因", c("差异基因" = "deg", "高变基因" = "variable"),
            selected = defaults$params$heatmap_mode)),
        conditionalPanel("input.group_mode === 'joint'", p("联合展示按所选组筛选高变基因。")),
        conditionalPanel("input.group_mode === 'reference' || input.group_mode === 'all_pairs'",
          p("批量模式按各比较的差异基因分别出图。"))),
      custom_heatmap = help_note("读取现成的样本表达值，可在下方选择逐行 Z-score。"),
      manual_heatmap = help_note("手工通路热图保留项目脚本的参数与已确认版式；通用样式项未必覆盖该流程全部设置。"),

      network = tagList(
        if (is.null(staged)) selectInput("network_mode", "数据来源", c("直接绘图 · Node + Edge" = "files", "生成 Node / Edge · 已有 DEG" = "results",
          "生成 Node / Edge · 原始 Count + 分组" = "deg"), selected = input$network_mode %or% "files"),
        selectInput("network_layout", "静态导出布局", c("力导向 FR" = "fr", "Kamada–Kawai" = "kk", "圆形" = "circle", "网格" = "grid"), selected = defaults$params$network_layout %or% "fr"),
        selectInput("network_score_scale", "Edge 分数单位", c("按字段名识别（combined_score ÷ 1000）" = "auto", "已是 0–1" = "unit", "STRING 0–1000" = "thousand"), selected = defaults$params$network_score_scale %or% "auto"),
        num("ppi_score", "标准化置信分数下限（0–1）", 0.7, 0, 1, 0.05),
        help_note(if (network_files) "Node / Edge 的 ID 必须对应。"
          else "按差异阈值筛选基因，再与互作参考匹配，导出可重新导入的 Node 和 Edge。留空参考边表时使用本机 STRING 物理互作库。")),
      matrix_pca = tagList(check("matrix_use_groups", "使用分组表（可选）", FALSE),
                           check("pca_scale", "PCA 前按特征标准化", TRUE), check("labels", "显示样本标签"),
                           help_note("矩阵按特征为行、样本为列排列。")),
      matrix_heatmap = tagList(check("matrix_use_groups", "使用分组表（可选）", FALSE),
                selectInput("matrix_transform", "矩阵变换", c("不变换" = "none", "log₂(x + 伪计数)" = "log2"),
                selected = defaults$params$matrix_transform %or% "none"),
                num("log_pseudocount", "log₂ 伪计数", 1, 0.000001, NA, 0.1)),
      circos = help_note("长度与区域起止必须使用相同单位。跨染色体连线的端点须存在于长度表。"))
    heatmap_options <- if (id %in% c("heatmap", "custom_heatmap", "manual_heatmap", "matrix_heatmap", "gsva")) tagList(
      num("heatmap_top", "最多显示基因 / 通路数", 50, 1),
      check("row_scale", "逐行 Z-score", TRUE),
      div(class = "two-columns", check("cluster_rows", "聚类基因／条目（行）", TRUE),
          check("cluster_columns", "聚类样本（列）", FALSE)),
      if (id != "manual_heatmap") conditionalPanel("input.cluster_columns",
        selectInput("column_cluster_mode", "样本聚类范围",
          c("按组分块，组内聚类" = "within", "全局聚类，可跨组排列" = "global"),
          selected = defaults$params$column_cluster_mode)),
      div(class = "two-columns", selectInput("distance", "距离度量",
        c("Pearson (1 − r)" = "pearson", "Spearman (1 − ρ)" = "spearman", "欧氏距离" = "euclidean", "曼哈顿距离" = "manhattan"),
          selected = defaults$params$distance %or% "pearson"),
        selectInput("linkage", "层次聚类连接算法", c("Complete 完全连接" = "complete",
          "Average 平均连接" = "average", "Single 单连接" = "single", "Ward.D2 最小方差" = "ward.D2"),
          selected = defaults$params$linkage %or% "complete")),
      help_note("Ward.D2 仅搭配欧氏距离。组内聚类保持同组样本相邻；颜色反映实际表达值。"))
    pathway_options <- if (id %in% tb_pathway_tools) tagList(
      if (id == "go") conditionalPanel("input.pathway_source === 'go'", tagList(
        checkboxGroupInput("go_ontology_multi", "GO 分类（可多选）",
          c("生物过程 · BP" = "BP", "细胞组分 · CC" = "CC", "分子功能 · MF" = "MF"),
          selected = initial$go_ontology, inline = TRUE),
        actionButton("go_select_all", "全选", class = "small-button"))),
      if (id %in% c("gsea", "gsva")) conditionalPanel("input.pathway_source === 'go'",
        selectInput("go_ontology", "GO 分类", c("生物过程 · BP" = "BP", "细胞组分 · CC" = "CC",
          "分子功能 · MF" = "MF"), selected = initial$go_ontology)),
      conditionalPanel("input.pathway_source === 'custom'", selectInput("gmt_id_type", "GMT 基因标识", c("Gene Symbol" = "SYMBOL", "稳定 gene_id" = "gene_id"),
        selected = initial$gmt_id_type),
      textInput("database_version", "本地数据库版本 / 来源标记",
        value = initial$database_version, placeholder = "如 MSigDB 版本或下载日期")),
      div(class = "two-columns", num("min_set_size", "最小基因集大小", 10, 1),
          num("max_set_size", "最大基因集大小", 500, 1)),
      if (id %in% c("go", "kegg")) num("ora_fdr", "通路富集 FDR 上限", .05, .000001, 1, .01),
      num("pathway_top", if (id == "gsea") "输出前 N 条通路曲线" else "出图条目数（全部所选分类合计）", 15, 1,
        if (id == "gsea") 100 else NA),
      if (id == "gsea") div(class = "two-columns",
        selectInput("gsea_sort", "通路排序指标", c("FDR（校正 P 值 / padj）" = "padj", "原始 P 值" = "pval"),
          selected = initial$gsea_sort),
        selectInput("gsea_order", "排序方向", c("从低到高" = "asc", "从高到低" = "desc"), selected = initial$gsea_order)),
      if (id == "gsea") textInput("pathway_id", "指定曲线通路 ID（可选）",
        initial$pathway_id, placeholder = "留空按结果选择")
      else textInput("pathway_terms", "优先展示指定条目 ID（可选）", initial$pathway_terms,
        placeholder = "多个 ID 用逗号或空格分隔"),
      help_note("GO 使用内置注释时记录包版本。使用 GMT 时请填写其实际来源版本。"))
    immune_options <- if (id == "immune") tagList(
      conditionalPanel("input.immune_source === 'custom'",
        textInput("database_version", "标志基因集来源与版本", "")),
      num("immune_min_genes", "每组最少匹配基因数", 5, 2))
    general <- switch(id,
      figure_layout = num("panel_trim", "裁白容差（%）", 3, 0, 20, 1),
      sankey = num("sankey_gap", "节点间隔（总流量比例）", .1, 0, .5, .02),
      venn = help_note("集合内重复项仅计一次，圆面积不代表集合大小。"),
      kmeans = tagList(num("kmeans_k", "聚类数 K", 3, 2, 100), num("kmeans_seed", "随机种子", 1, 0, 100000),
        check("kmeans_scale", "按列标准化后聚类")),
      beeswarm = tagList(check("beeswarm_box", "叠加箱线图"), check("beeswarm_log", "使用 log10 纵轴")),
      radar = check("radar_normalize", "各指标按输入对象范围归一化至 0–1"))
    tagList(if (is.null(staged) && !id %in% c(tb_general_tools, "figure_layout")) selectInput("species", "物种", tb_species_choices,
      selected = isolate(input$species) %or% defaults$params$species),
      basic, selection, specific, heatmap_options, pathway_options, immune_options, general)
  })
  output$group_summary <- renderText(groups_message())
  output$figure_ready <- reactive({
    if (selected() != "figure_layout") return(FALSE)
    paths <- vapply(active_fields(), figure_input, character(1))
    length(paths) > 0L && all(file.exists(paths))
  })
  outputOptions(output, "figure_ready", suspendWhenHidden = FALSE)
  output$style_controls <- renderUI({
    req(selected() != "home")
    schema <- tb_style_schema(selected())
    if (!length(schema)) return(help_note("差异分析输出统计表，本工具没有图形样式。图像设置请在火山图或热图中调整。"))
    saved <- isolate(style_cache[[selected()]] %or% list())
    if (selected() == "figure_layout" && is.null(saved$panel_paper)) saved$panel_paper <- "A4"
    style <- utils::modifyList(defaults$style, saved)
    render_field <- function(name, definition) {
      id <- paste0("style_", name)
      value <- style[[name]]
      control <- switch(definition$type,
        text = textInput(id, definition$label, value, placeholder = definition$placeholder),
        number = numericInput(id, definition$label, value, min = definition$min, max = definition$max, step = definition$step),
        color = div(class = "color-control", tags$span(class = "color-swatch", style = paste0("background:", value)), textInput(id, definition$label, value)),
        select = selectInput(id, definition$label, definition$choices, selected = value),
        flag = checkboxInput(id, definition$label, value))
      region_on <- "(input.style_pca_ellipse_2d || input.style_pca_ellipse_3d)"
      condition <- if (name %in% c("pca_confidence", "pca_region_type", "pca_region_fill")) region_on
        else if (name == "pca_region_color") paste(region_on, "&& input.style_pca_region_fill === 'solid'")
        else if (name == "pca_region_alpha") paste(region_on, "&& input.style_pca_region_fill !== 'outline'")
        else if (name %in% c("legend_align", "legend_text_size", "legend_title_size", "legend_key_size", "legend_gap")) "input.style_legend_position !== 'none'"
        else if (selected() == "figure_layout" && name %in% c("width", "height")) "input.style_panel_paper === 'custom'"
        else if (name == "panel_orientation") "input.style_panel_paper !== 'custom'"
        else if (name == "enrichment_orientation") "input.style_enrichment_kind === 'bar'"
        else if (name %in% c("enrichment_size_min", "enrichment_size_max")) "input.style_enrichment_kind === 'dot'" else if (name %in% c("network_low", "network_mid", "network_high")) "input.style_network_color_by === 'auto' || input.style_network_color_by === 'log2FC'" else if (name == "network_node_color") "input.style_network_color_by !== 'log2FC'" else if ((name == "network_label_top" || (selected() == "network" && name == "label_size"))) "input.style_network_labels" else NULL
      if (name == "panel_rows") control <- tagList(control, uiOutput("paper_preview"))
      if (is.null(condition)) control else conditionalPanel(condition, control)
    }
    tagList(if (selected() != "figure_layout") tb_palette_ui(style),
      lapply(names(schema), function(group) tags$fieldset(class = "style-group",
      tags$legend(group), div(class = "two-columns", lapply(names(schema[[group]]), function(name) render_field(name, schema[[group]][[name]]))))),
      checkboxGroupInput("style_formats", "导出格式", c("PNG" = "png", "SVG" = "svg", "TIFF" = "tiff", "PDF" = "pdf"),
        selected = style$formats, inline = TRUE))
  })

  output$paper_preview <- renderUI({
    req(selected() == "figure_layout")
    fields <- active_fields()
    req(length(fields))
    style <- defaults$style
    for (name in c("panel_paper", "panel_orientation", "width", "height", "panel_rows")) {
      style[[name]] <- input[[paste0("style_", name)]] %or% style[[name]]
    }
    style$panel_weights <- vapply(fields, function(key) (input[[paste0("weight_", key)]] %or% 100) / 100, numeric(1))
    tryCatch({
      paper <- tb_figure_paper(style)
      req(is.finite(paper$width), is.finite(paper$height), paper$width > 0, paper$height > 0)
      panels <- tb_figure_positions(list(images = rep(list(list(crop = c(0, 0, 4, 3))), length(fields))), paper)
      height <- 100 * paper$height / paper$width
      tags$figure(class = "paper-preview",
        tags$svg(viewBox = paste(0, 0, 100, height), role = "img", `aria-label` = "纸张分栏预览",
          tags$rect(x = 0, y = 0, width = 100, height = height, fill = "white", stroke = "#9B9789"),
          lapply(seq_len(nrow(panels)), function(i) {
            p <- panels[i, ]
            tags$g(tags$rect(x = p$x * 100, y = p$y * height, width = p$width * 100,
              height = p$height * height, fill = "#E6EAE1", stroke = "#637266", `stroke-width` = .4),
              tags$text(x = (p$x + p$width / 2) * 100, y = (p$y + p$height / 2) * height,
                `text-anchor` = "middle", `dominant-baseline` = "middle", `font-size` = 5, i))
          })),
        tags$figcaption("分栏示意 · 实际排版按裁切后的图片比例调整"))
    }, error = function(e) {
      if (inherits(e, "shiny.silent.error")) return(NULL)
      p(class = "field-help", conditionMessage(e))
    })
  })

  bulk_jobs <- new.env(parent = emptyenv())

  bulk_setup_ui <- function() {
    div(class = "workspace tool-workspace",
      div(class = "tool-header", h1("Bulk RNA-seq 自动化分析")),
      p(paste(unname(tb_bulk_steps), collapse = " → ")),
      div(class = "tool-layout",
        div(class = "configuration-column",
          div(class = "panel", section_title("01", "分析输入", "上传原始 Count 和分组表"),
            actionButton("use_all_examples", "勾选整套示例", class = "small-button"),
            uiOutput("input_controls")),
          div(class = "panel", section_title("02", "物种与比较", "同一个比较贯穿全流程"),
            selectInput("species", "物种", tb_species_choices),
            group_mode_ui("bulk", defaults$params),
            actionButton("refresh_groups", "读取当前分组", class = "small-button"),
            textOutput("group_summary"),
            tags$details(tags$summary("共享模型参数"), div(class = "two-columns",
              num("bulk_min_count", "Count 下限", defaults$params$min_count, 0),
              num("bulk_min_samples", "最少样本数", defaults$params$min_samples, 1),
              selectInput("bulk_fit_type", "离散度拟合", c("Parametric" = "parametric", "Local" = "local", "Mean" = "mean")),
              checkboxInput("bulk_batch", "纳入技术批次"),
              textInput("bulk_covariates", "分类协变量（逗号分隔）")))),
          actionButton("bulk_start", "启动流程 · 运行 PCA", class = "primary-button")),
        div(class = "configuration-column",
          div(class = "panel", section_title("03", "通路与互作", "可在相应步骤继续调整"),
            textInput("bulk_go", "GO 条目 ID（可选）", placeholder = "GO:0006955"),
            textInput("bulk_kegg", "KEGG 条目 ID（可选）", placeholder = "hsa04620 或 mmu04620"),
            textInput("bulk_gsea", "GSEA 曲线条目 ID（可选）"),
            textInput("bulk_gsva", "GSVA 热图条目 ID（可选）"),
            p("多个 ID 用逗号或空格分隔。GSEA 选择一条曲线。"),
            checkboxInput("bulk_custom", "GSEA 和 GSVA 使用已上传的自建 GMT"),
            selectInput("bulk_gmt_id", "自建 GMT 的基因标识", c("Gene Symbol" = "SYMBOL", "稳定 gene_id" = "gene_id")),
            textInput("bulk_gmt_version", "自建 GMT 来源与版本"),
            p("PPI 默认用所选物种的本机 STRING 物理互作库。也可在此处或 PPI 步骤上传 Edge 表覆盖预设，需含 from、to、score（0–1）。")))))
  }

  restore_job <- function(current) {
    job(current)
    view_id(current$id)
    last_spec(if (!is.null(current)) readRDS(file.path(current$directory, "request.rds")) else NULL)
    result(if (!is.null(current)) tb_read_job(current$directory) else NULL)
  }

  submit_job <- function(spec, redraw_from = NULL) {
    if (tb_package_updating()) stop("软件包更新正在进行，请稍后再运行分析。")
    current <- tb_launch_job(spec, app_root, redraw_from)
    restore_job(current)
    if (in_bulk_step()) bulk_jobs[[spec$tool]] <- current
    sync_pins()
    history_tick(history_tick() + 1L)
    invisible(current)
  }

  open_bulk_step <- function(flow, launch = TRUE) {
    current <- job()
    step <- names(tb_bulk_steps)[flow$step]
    saved <- bulk_jobs[[step]]
    if (!is.null(current) && current$process$is_alive() && !identical(current$directory, saved$directory)) {
      showNotification("请先等待当前任务完成，或取消后再返回流程。", type = "warning")
      return(invisible(NULL))
    }
    bulk(flow)
    bulk_active(TRUE)
    choose_tool(step)
    restore_job(saved)
    if (!launch || step == "figure_layout") return(invisible(NULL))
    spec <- tb_bulk_spec(flow, step, defaults, isolate(style_cache[[step]]) %or% list())
    if (step == "network" && !nzchar(spec$inputs$edges) &&
        !all(file.exists(tb_string_reference(app_root, spec$params$species)$paths))) return(invisible(NULL))
    tryCatch({
      submitted <- submit_job(spec)
      if (step == "pca") {
        snapshot <- last_spec()$inputs
        flow$inputs[c("counts", "groups")] <- snapshot[c("counts", "groups")]
        bulk(flow)
      }
      invisible(submitted)
    }, error = function(e) showNotification(conditionMessage(e), type = "error", duration = 12))
  }

  observeEvent(input$bulk_start, {
    if (selected() != "bulk" || (!is.null(job()) && job()$process$is_alive())) return()
    tryCatch({
      fields <- active_fields()
      paths <- stats::setNames(lapply(fields, read_input), fields)
      if (!all(file.exists(unlist(paths[c("counts", "groups")])))) stop("请提供原始 Count 矩阵和分组表。")
      groups <- unique(tb_read_groups(paths$groups)$condition)
      mode <- input$group_mode %or% "pair"
      subset <- input$group_subset %or% character()
      included <- if (length(subset) && mode != "pair") intersect(groups, subset) else groups
      if (length(included) < 2L) stop("至少纳入两个组。")
      contrast <- switch(mode, pair = c(input$control, input$treatment),
        reference = c(input$control, setdiff(included, input$control)[1L]), all_pairs = included[1:2])
      if (length(contrast) != 2L || anyDuplicated(contrast) || !all(contrast %in% included))
        stop("请先读取分组表，并选择两个不同的组。")
      ids <- c(go = trimws(input$bulk_go), kegg = trimws(input$bulk_kegg),
        gsea = trimws(input$bulk_gsea), gsva = trimws(input$bulk_gsva))
      if (length(tb_parse_terms(ids[["gsea"]])) > 1L) stop("GSEA 曲线只接受一个条目 ID。")
      synthetic <- all(vapply(c("counts", "groups", "gmt"), example_checked, logical(1)))
      custom <- isTRUE(input$bulk_custom)
      if (custom && (!file.exists(paths$gmt) || !nzchar(trimws(input$bulk_gmt_version))))
        stop("自建注释需要上传 GMT 并填写来源与版本。")
      species <- if (example_checked("counts") && example_dataset() != "synthetic") example_dataset() else input$species
      parameters <- list(species = species, control = contrast[1L], treatment = contrast[2L],
        group_mode = mode, group_subset = subset,
        min_count = input$bulk_min_count, min_samples = input$bulk_min_samples, fit_type = input$bulk_fit_type,
        use_batch = isTRUE(input$bulk_batch), covariates = input$bulk_covariates %or% "",
        database_version = if (synthetic) "BioWorkbench synthetic example" else input$bulk_gmt_version,
        gmt_id_type = if (synthetic) "gene_id" else input$bulk_gmt_id)
      flow <- list(step = 1L, inputs = paths, params = parameters, terms = ids,
        custom = custom, synthetic = synthetic, approved = list(), skipped = list())
      tb_validate_inputs(tb_bulk_spec(flow, "pca", defaults), app_root)
      open_bulk_step(flow)
    }, error = function(e) showNotification(conditionMessage(e), type = "error", duration = 15))
  })

  output$bulk_progress <- renderUI({
    flow <- req(bulk())
    step <- req(bulk_step())
    current <- job()
    match_job <- !is.null(current) && identical(current$directory, bulk_jobs[[step]]$directory)
    complete <- match_job && identical(result()$status, "completed")
    can_skip <- step %in% c("heatmap", "go", "kegg", "gsea", "gsva", "network") &&
      (is.null(current) || (match_job && identical(result()$status, "failed")))
    div(class = "panel bulk-progress",
      tags$ol(lapply(names(tb_bulk_steps), function(id) tags$li(
        class = if (id == step) "current" else if (!is.null(flow$approved[[id]])) "approved" else if (!is.null(flow$skipped[[id]])) "skipped",
        `aria-current` = if (id == step) "step", title = flow$skipped[[id]], tb_bulk_steps[[id]]))),
      if (step == "figure_layout") p("按面板编号选择已确认的 PNG 或上传外部图片。设置序号样式后运行组图。")
      else if (step == "network" && is.null(current)) p("请补交本地互作 Edge 表，再运行本步。"),
      if (step == "pca" && !complete && (is.null(current) || !current$process$is_alive()))
        actionButton("bulk_back_setup", "返回输入设置", class = "secondary-button"),
      if (complete && step != "figure_layout") actionButton("bulk_next", "确认结果并运行下一步", class = "primary-button"),
      if (can_skip) actionButton("bulk_skip_dialog", "记录原因并跳过本步", class = "secondary-button"),
      if (step == "figure_layout" && complete) actionButton("bulk_new", "新建 Bulk 流程", class = "secondary-button"))
  })

  advance_bulk <- function(skip_reason = NULL) {
    flow <- req(bulk())
    step <- bulk_step()
    req(!is.null(step), step != "figure_layout")
    current <- job()
    if (is.null(skip_reason)) {
      req(current, identical(current$directory, bulk_jobs[[step]]$directory), identical(result()$status, "completed"))
      flow$approved[[step]] <- current$directory
      if (step == "deg") {
        fields <- c("padj", "log2fc", "direction")
        flow$params[fields] <- last_spec()$params[fields]
      }
    } else {
      req(step %in% c("heatmap", tb_pathway_tools, "network"))
      if (!is.null(current)) req(identical(result()$status, "failed"))
      flow$skipped[[step]] <- skip_reason
    }
    flow$step <- flow$step + 1L
    open_bulk_step(flow)
  }

  observeEvent(input$bulk_next, advance_bulk())
  observeEvent(input$bulk_skip_dialog, {
    req(in_bulk_step())
    showModal(modalDialog(title = "记录未完成的步骤", textInput("bulk_skip_reason", "跳过原因"),
      footer = tagList(modalButton("取消"), actionButton("bulk_skip", "确认跳过"))))
  })
  observeEvent(input$bulk_skip, {
    reason <- trimws(input$bulk_skip_reason %or% "")
    if (!nzchar(reason)) return(showNotification("请填写跳过原因。", type = "warning"))
    removeModal()
    advance_bulk(reason)
  })
  reset_bulk <- function() {
    bulk(NULL)
    rm(list = ls(bulk_jobs), envir = bulk_jobs)
    bulk_active(FALSE)
    choose_tool("bulk")
  }
  observeEvent(input$bulk_back_setup, {
    req(identical(bulk_step(), "pca"), is.null(job()) || !job()$process$is_alive())
    reset_bulk()
  })
  observeEvent(input$bulk_new, {
    req(identical(bulk_step(), "figure_layout"), identical(result()$status, "completed"))
    reset_bulk()
  })

  figure_input <- function(name) {
    if (identical(bulk_step(), "figure_layout")) {
      choices <- tb_bulk_figures(bulk())
      index <- match(name, active_fields())
      value <- input[[paste0("bulk_", name)]]
      if (is.null(value) && index <= length(choices)) value <- unname(choices[index])
      if (!is.null(value) && value %in% choices) return(value)
    }
    read_input(name)
  }


  observeEvent(input$go_select_all, updateCheckboxGroupInput(session, "go_ontology_multi", selected = tb_go_ontologies("ALL")))

  collect_spec <- function() {
    req(selected() != "home")
    parameters <- defaults$params
    for (name in names(parameters)) {
      value <- input[[name]]
      if (!is.null(value)) parameters[[name]] <- value
    }
    if (selected() == "go") parameters$go_ontology <- input$go_ontology_multi %or% character()
    if (!in_bulk_step()) {
      parameters$downstream_input <- selected() %in% c(tb_processed_tools, "volcano")
      if (selected() == "network" && parameters$network_mode %in% c("deg", "results")) {
        parameters$ppi_reference <- TRUE
        parameters$ppi_require_edges <- TRUE
      }
    }
    if (!selected() %in% c("pca", "deg", "volcano", "heatmap", "custom_heatmap", "manual_heatmap", tb_pathway_tools, "network") ||
        (selected() == "network" && parameters$network_mode != "deg")) parameters$group_mode <- "pair"
    if (selected() == "heatmap" && parameters$group_mode != "pair")
      parameters$heatmap_mode <- if (parameters$group_mode == "joint") "variable" else "deg"
    style <- defaults$style
    for (name in names(do.call(c, unname(tb_style_schema(selected()))))) {
      value <- input[[paste0("style_", name)]]
      if (!is.null(value)) style[[name]] <- value
    }
    style$gradient <- input$style_gradient %or% ""
    style$formats <- if (selected() == "deg") defaults$style$formats else input$style_formats %or% character()
    fields <- active_fields()
    inputs <- stats::setNames(lapply(fields, if (selected() == "figure_layout") figure_input else read_input), fields)
    if (example_dataset() != "synthetic" &&
        any(vapply(intersect(fields, c("matrix", "counts", "groups")), example_checked, logical(1)))) {
      parameters$species <- example_dataset()
    }
    if ("gmt" %in% fields && example_checked("gmt") && nzchar(example_path("gmt")) &&
        (identical(parameters$pathway_source, "custom") || identical(parameters$immune_source, "custom"))) {
      parameters$database_version <- "BioWorkbench synthetic example"
      parameters$gmt_id_type <- "gene_id"
    }
    if (!in_bulk_step() && selected() %in% c("volcano", "go", "kegg", "gsea", "manual_heatmap")) parameters$group_mode <- "pair"
    if (selected() == "figure_layout") style$panel_weights <- vapply(fields,
      function(key) (input[[paste0("weight_", key)]] %or% 100) / 100, numeric(1))
    input_names <- lapply(fields, function(key) {
      uploaded <- upload_paths[[key]]
      if (identical(inputs[[key]], uploaded$path)) uploaded$name
    })
    spec <- list(tool = selected(), inputs = inputs, params = parameters, style = style,
      input_names = stats::setNames(input_names, fields))
    if (in_bulk_step() && selected() == "figure_layout") {
      flow <- bulk()
      spec$bulk_review <- list(approved_jobs = lapply(flow$approved, basename), skipped = flow$skipped)
    }
    if (in_bulk_step() && selected() != "figure_layout") {
      base <- tb_bulk_spec(bulk(), selected(), defaults)
      fixed <- c("species", "control", "treatment", "min_count", "min_samples", "alpha",
        "fit_type", "use_batch", "covariates", "network_mode", "ppi_require_edges", "ppi_reference", "group_mode", "group_subset", "downstream_input")
      spec$params[fixed] <- base$params[fixed]
      if (selected() == "heatmap" && spec$params$group_mode != "pair") spec$params$heatmap_mode <- "deg"
      spec$inputs <- utils::modifyList(base$inputs, spec$inputs)
      spec$upstream_deg <- base$upstream_deg
    }
    spec
  }
  observeEvent(input$validate_inputs, {
    spec <- NULL
    tryCatch({
      spec <- collect_spec()
      checks <- tb_validate_inputs(spec, app_root)
      body <- p(paste(checks, collapse = "\n"))
      if (is.data.frame(checks)) {
        output$checks_table <- renderTable(checks, striped = TRUE)
        body <- tableOutput("checks_table")
      }
      showModal(modalDialog(title = "输入检查", body,
        p("检查不会执行 DESeq2、富集或绘图。"), easyClose = TRUE, footer = modalButton("关闭")))
    }, error = function(e) showNotification(tags$pre(tb_error_text(e, spec)), type = "error", duration = 15))
  })
  output$redraw_action <- renderUI({
    current <- job()
    state <- result()
    if (selected() != "deg" && !is.null(visible_job()) && !is.null(state) && state$status == "completed" &&
        identical(selected(), current$tool) && any(file.exists(file.path(current$directory, c("render.rds", "batch.rds"))))) {
      actionButton("redraw", "仅重新绘图", class = "secondary-button")
    }
  })
  observeEvent(input$redraw, {
    current <- req(visible_job())
    if (current$process$is_alive()) return()
    tryCatch({
      request <- collect_spec()
      submit_job(request, redraw_from = current$directory)
    }, error = function(e) showNotification(conditionMessage(e), type = "error"))
  })
  observeEvent(input$run_tool, {
    current <- job()
    if (!is.null(current) && current$process$is_alive()) {
      showNotification("已有任务正在运行，请等待完成或先取消。", type = "warning")
      return()
    }
    spec <- NULL
    tryCatch({
      spec <- collect_spec()
      submit_job(spec)
      updateTabsetPanel(session, "result_tab", selected = "运行日志")
      showNotification("任务已提交，正在独立 R 进程中运行。", type = "message")
    }, error = function(e) showNotification(tags$pre(tb_error_text(e, spec)), type = "error", duration = 15))
  })
  observe({
    invalidateLater(1000, session)
    current <- job()
    if (is.null(current)) return()
    if (!dir.exists(current$directory)) return(restore_job(NULL))
    state <- tb_read_job(current$directory)
    if (state$status %in% c("queued", "running") && !current$process$is_alive()) {
      state$status <- "failed"
      state$error <- state$error %or% "[BW-R02] 分析进程已结束，但没有完成记录。请查看运行日志。"
    }
    previous <- isolate(result())
    if (!identical(previous, state)) {
      result(state)
      if (!state$status %in% c("queued", "running") && !identical(previous$status, state$status)) {
        sync_pins()
        tb_prune_runs(app_root, tb_read_settings(app_root)$retain)
        history_tick(isolate(history_tick()) + 1L)
        if (state$status == "completed" && !is.null(visible_job())) {
          updateTabsetPanel(session, "result_tab", selected = "图形预览")
          showNotification("任务完成，结果与作图数据已保存。", type = "message")
        }
      }
    }
  })
  observeEvent(input$cancel_job, {
    current <- req(visible_job())
    tryCatch({
      tb_stop_job(current)
      sync_pins()
      tb_prune_runs(app_root, tb_read_settings(app_root)$retain)
      result(tb_read_job(current$directory))
      history_tick(history_tick() + 1L)
    }, error = function(e) showNotification(conditionMessage(e), type = "error"))
  })
  output$job_status <- renderUI({
    state <- visible_result()
    if (is.null(state)) return(div(class = "status-card status-idle", span(class = "status-dot"),
      div(strong("待运行"), `data-help` = "配置参数后点击运行。")))
    labels <- c(queued = "排队中", running = "正在计算", completed = "任务完成", failed = "运行失败", cancelled = "已取消")
    div(class = paste("status-card", paste0("status-", state$status)), span(class = "status-dot"),
      div(strong(labels[[state$status]] %or% state$status),
          if (!is.null(state$error) && nzchar(state$error)) tags$pre(class = "task-error", state$error)
          else p(paste(state$summary %or% "计算状态与日志实时更新。", collapse = " · "))),
      if (state$status %in% c("queued", "running")) actionButton("cancel_job", "取消", class = "small-button"))
  })
  output$result_badge <- renderUI({
    state <- visible_result()
    if (is.null(state)) span(class = "result-tag", "尚无结果") else {
      tool <- catalog$title[match(visible_job()$tool, catalog$id)]
      span(class = "result-tag", tool, " · ", length(state$files %or% character()), " 个文件")
    }
  })
  all_completed_files <- reactive({
    state <- visible_result()
    if (is.null(state) || state$status != "completed") return(character())
    files <- state$files %or% character()
    files[file.exists(files) & !dir.exists(files)]
  })
  comparison_records <- reactive({
    files <- all_completed_files()
    index <- files[basename(files) == "comparisons.csv"]
    if (length(index)) utils::read.csv(index[1L], stringsAsFactors = FALSE, fileEncoding = "UTF-8")
  })
  comparison_id <- reactive({
    records <- comparison_records()
    if (is.null(records)) return(NULL)
    id <- input$comparison_id %or% ""
    if (id %in% records$id) id else records$id[1L]
  })
  output$comparison_picker <- renderUI({
    records <- comparison_records()
    if (is.null(records)) return(NULL)
    label <- paste(records$treatment, "vs", records$control)
    label[records$status == "failed"] <- paste(label[records$status == "failed"], "· 未完成")
    tagList(selectInput("comparison_id", "查看比较", stats::setNames(records$id, label), selected = isolate(comparison_id())),
      textOutput("comparison_note"))
  })
  output$comparison_note <- renderText({
    records <- comparison_records()
    id <- comparison_id()
    if (length(id) && identical(records$status[match(id, records$id)], "failed")) records$message[match(id, records$id)]
  })
  completed_files <- reactive({
    files <- all_completed_files()
    id <- comparison_id()
    if (is.null(id)) return(files)
    base <- normalizePath(file.path(visible_job()$directory, "outputs", id), winslash = "/", mustWork = FALSE)
    normalized <- gsub("\\\\", "/", files)
    files[startsWith(normalized, paste0(base, "/")) | basename(files) == "comparisons.csv"]
  })
  output$preview_panel <- renderUI({
    files <- completed_files()
    images <- files[grepl("[.]png$", files, ignore.case = TRUE) & basename(dirname(files)) != "figure-assets"]
    if (!length(images)) {
      state <- visible_result()
      return(div(class = "preview-empty", div(class = "empty-chart", span(), span(), span(), span()),
        h4(if (!is.null(state) && state$status == "completed") "此任务没有 PNG 预览" else "等待结果"),
        help_note(if (!is.null(state) && state$status == "completed") "差异分析请查看数据表；绘图预览需启用 PNG 导出。" else "配置参数并运行后显示结果。")))
    }
    names <- if (selected() == "gsea") tb_gsea_image_labels(images) else basename(images)
    if (selected() %in% c("pca", "matrix_pca")) {
      variants <- basename(dirname(images))
      names <- ifelse(variants == "pca_3d", "PCA · 三维",
        ifelse(variants == "pca_loadings", "PCA · 变量负荷", "PCA · 二维"))
    }
    tagList(selectInput("preview_file", "图形", stats::setNames(images, names)),
      downloadButton("download_preview", "下载当前图"),
      imageOutput("preview_image", height = "auto"))
  })
  output$interactive_network <- renderUI({
    files <- completed_files()
    network <- files[basename(files) == "network.html"]
    if (!length(network)) return(div(class = "preview-empty", h4("等待网络结果"), `data-help` = "任务完成后可拖动节点、缩放和切换布局。", tabindex = "0"))
    prefix <- paste0("network-", substr(session$token, 1, 12), "-", basename(visible_job()$directory),
      if (!is.null(comparison_id())) paste0("-", comparison_id()))
    addResourcePath(prefix, dirname(network[1]))
    if (!prefix %in% resource_paths) resource_paths <<- c(resource_paths, prefix)
    tags$iframe(src = paste0(prefix, "/network.html"), title = "PPI interactive network", class = "network-frame")
  })
  output$preview_image <- renderImage({
    req(input$preview_file, input$preview_file %in% completed_files())
    list(src = input$preview_file, contentType = "image/png", alt = basename(input$preview_file), width = "100%")
  }, deleteFile = FALSE)
  output$download_preview <- downloadHandler(
    filename = function() {
      image <- req(input$preview_file)
      if (selected() == "gsea" && grepl("^gsea-[0-9]+$", basename(dirname(image))))
        paste0(basename(dirname(image)), ".png") else basename(image)
    },
    content = function(file) {
      image <- req(input$preview_file)
      req(image %in% completed_files(), grepl("[.]png$", image, ignore.case = TRUE))
      if (!file.copy(image, file, overwrite = TRUE)) stop("无法下载当前图。")
    }
  )
  output$data_selector <- renderUI({
    files <- completed_files()[grepl("[.]csv$", completed_files(), ignore.case = TRUE)]
    if (!length(files)) return(div(class = "empty-small", "运行完成后可查看数据表。"))
    tagList(selectInput("data_file", "选择结果数据", stats::setNames(files, basename(files))),
      help_note("界面显示前 200 行；完整数据保存在输出文件中。"))
  })
  output$data_preview <- renderTable({
    req(input$data_file, input$data_file %in% completed_files())
    tb_read_preview(input$data_file, n = 200)
  }, striped = TRUE, bordered = FALSE, spacing = "s")
  output$job_log <- renderText({
    state <- visible_result()
    if (is.null(state)) return("暂无日志。")
    paste(state$log %or% "等待日志…", collapse = "\n")
  })
  output$file_list <- renderUI({
    files <- completed_files()
    if (!length(files)) return(div(class = "empty-small", "当前没有已完成的输出文件。"))
    tagList(div(class = "output-directory", visible_job()$directory %or% ""),
      selectInput("download_file_choice", "选择下载文件", stats::setNames(files, basename(files))),
      downloadButton("download_file", "下载所选文件", class = "secondary-button"),
      tags$ul(class = "output-files", lapply(files, function(file) tags$li(span(basename(file)),
          tags$small(format(file.info(file)$size, big.mark = ","), " bytes")))))
  })
  output$download_actions <- renderUI({
    files <- completed_files()
    if (!length(files)) return(NULL)
    editor <- files[basename(files) == "figure-layout.html"]
    open_editor <- if (length(editor)) {
      prefix <- paste0("figure-", substr(session$token, 1, 12), "-", basename(visible_job()$directory))
      if (!prefix %in% resource_paths) {
        addResourcePath(prefix, dirname(editor[1]))
        resource_paths <<- c(resource_paths, prefix)
      }
      tags$a(href = paste0(prefix, "/figure-layout.html"), target = "_blank", rel = "noopener",
        class = "btn secondary-button", "打开排版编辑器 ↗")
    }
    div(class = "download-actions", open_editor, downloadButton("download_zip", "下载结果包", class = "primary-button"),
      downloadButton("download_recipe", "复现 R 脚本", class = "secondary-button"))
  })
  output$download_file <- downloadHandler(
    filename = function() basename(input$download_file_choice),
    content = function(file) {
      req(input$download_file_choice %in% completed_files())
      file.copy(input$download_file_choice, file, overwrite = TRUE)
    })
  output$download_zip <- downloadHandler(
    filename = function() paste0("BioWorkbench-", visible_job()$id, ".zip"),
    content = function(file) {
      req(visible_result()$status == "completed")
      tb_zip_results(visible_job()$directory, file)
    }, contentType = "application/zip")
  output$download_recipe <- downloadHandler(
    filename = function() paste0("reproduce-", last_spec()$tool, ".R"),
    content = function(file) {
      req(visible_job(), last_spec())
      tb_write_reproduce(last_spec(), file, app_root)
    })

  history_page <- reactiveVal(1L)
  history_size <- reactiveVal(20L)
  history_pages <- reactive(max(1L, ceiling(nrow(history()) / history_size())))
  observeEvent(input$history_size, {
    size <- input$history_size
    if (length(size) == 1L && is.finite(size) && size == floor(size) && size >= 1L && size <= 200L) {
      history_size(as.integer(size))
      history_page(1L)
    }
  }, ignoreInit = TRUE)
  observeEvent(input$history_page, {
    page <- input$history_page
    if (is.numeric(page) && length(page) == 1L && is.finite(page)) history_page(max(1L, min(history_pages(), as.integer(page))))
  })
  observeEvent(history_pages(), if (history_page() > history_pages()) history_page(history_pages()))
  output$history_pager <- renderUI({
    page <- min(history_page(), history_pages())
    pages <- history_pages()
    button <- function(n, label, disabled = FALSE) tags$button(type = "button", class = "small-button",
      `data-history-page` = n, `aria-current` = if (identical(as.integer(n), as.integer(page))) "page",
      disabled = if (disabled) "disabled", label)
    div(class = "history-pages", span(paste0("第 ", page, " / ", pages, " 页 · ", nrow(history()), " 项")),
      button(page - 1L, "上一页", page <= 1L),
      lapply(sort(unique(c(1L, seq.int(max(1L, page-2L), min(pages, page+2L)), pages))), function(n) button(n, n)),
      button(page + 1L, "下一页", page >= pages))
  })
  observeEvent(input$refresh_history, {
    history_tick(history_tick() + 1L)
    showModal(modalDialog(title = "任务记录", size = "l", div(class = "history-scroll", uiOutput("history_modal")),
      easyClose = TRUE, footer = div(class = "history-footer",
        numericInput("history_size", "每页任务数", history_size(), min = 1, max = 200, step = 1),
        uiOutput("history_pager"), modalButton("关闭"))))
  })
  history <- reactive({
    history_tick()
    tb_list_runs(app_root)
  })
  pending_delete <- reactiveVal(NULL)
  history_ui <- function(modal = FALSE) {
    runs <- history()
    if (is.null(runs) || !nrow(runs)) return(div(class = "history-empty", span(class = "history-icon", "↗"),
      div(strong("暂无任务"))))
    page <- if (modal) min(history_page(), history_pages()) else 1L
    size <- if (modal) history_size() else 10L
    indexes <- seq.int((page-1L)*size+1L, min(page*size, nrow(runs)))
    tags$div(class = "history-list", lapply(indexes, function(i) {
      title <- catalog$title[match(runs$tool[i], catalog$id)]
      path <- runs$directory[i]
      live <- runs$status[i] %in% c("queued", "running")
      has_outputs <- !live && length(list.files(file.path(path, "outputs"), recursive = TRUE, all.files = TRUE)) > 0L
      quick <- if (has_outputs) {
        key <- paste0(if (modal) "history_zip_" else "recent_zip_", gsub("-", "_", runs$id[i]))
        output[[key]] <- downloadHandler(
          filename = function() paste0("BioWorkbench-", basename(path), ".zip"),
          content = function(file) { req(dir.exists(path)); tb_zip_outputs(path, file) },
          contentType = "application/zip")
        downloadLink(key, "快速导出", class = "small-button")
      }
      div(class = "history-item", div(strong(if (is.na(title)) runs$tool[i] else title),
          tags$small(runs$created[i], " · ", runs$id[i])),
        span(class = paste("history-status", paste0("history-", runs$status[i])), runs$status[i]),
        div(class = "history-actions",
          tags$button(type = "button", class = "small-button", `data-run` = path, "查看"),
          quick,
          tags$button(type = "button", class = "small-button", `data-run-delete` = path,
            disabled = if (live) "disabled", "删除")))
    }))
  }
  output$history_list <- renderUI(history_ui())
  output$history_modal <- renderUI(history_ui(modal = TRUE))
  observeEvent(input$history_delete, {
    runs <- history()
    req(input$history_delete %in% runs$directory)
    pending_delete(input$history_delete)
    showModal(modalDialog(title = "删除任务", p("删除任务 ", basename(input$history_delete), " 及其本地输出和输入快照？"),
      footer = tagList(modalButton("取消"), actionButton("history_delete_confirm", "确认删除"))))
  })
  observeEvent(input$history_delete_confirm, {
    path <- req(pending_delete())
    viewing <- identical(basename(path), view_id())
    if (viewing) view_id(NULL)
    sync_pins()
    removed <- tryCatch(tb_delete_run(app_root, path), error = function(e) {
      showNotification(conditionMessage(e), type = "error")
      FALSE
    })
    if (removed) {
      if (identical(job()$directory, path)) restore_job(NULL)
      history_tick(history_tick() + 1L)
      showNotification("任务已删除。")
    } else {
      if (viewing && dir.exists(path)) view_id(basename(path))
      sync_pins()
      showNotification("任务正在使用或已不存在。", type = "warning")
    }
    pending_delete(NULL)
    removeModal()
  })
  observeEvent(input$history_run, {
    # 只允许从服务端生成的任务记录选择路径。
    runs <- history()
    req(input$history_run %in% runs$directory)
    directory <- input$history_run
    existing <- job()
    if (!is.null(existing) && existing$process$is_alive()) {
      showNotification("请等待当前任务完成后再查看其他记录。", type = "warning")
      return()
    }
    row <- runs[runs$directory == directory, , drop = FALSE][1, ]
    # 同一服务中仍在运行的历史任务保留真实进程句柄；查看不会启动新任务。
    stopped <- list(is_alive = function() FALSE)
    live <- if (exists("tb_lookup_job", mode = "function")) tb_lookup_job(directory) else NULL
    restored <- live %or% list(process = stopped, directory = directory, id = row$id)
    restored$tool <- row$tool
    bulk_active(FALSE)
    if (row$tool %in% catalog$id) choose_tool(row$tool)
    restore_job(restored)
    removeModal()
  })
  session$onSessionEnded(function() {
    .tb_task_views[[session$token]] <- NULL
    for (prefix in resource_paths) removeResourcePath(prefix)
    # 浏览器断开后任务由服务注册表保持；关闭启动器会结束服务及其子进程。
    invisible(NULL)
  })
}

shinyApp(ui, server)
