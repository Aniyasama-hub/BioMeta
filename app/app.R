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
source(file.path(app_root, "R", "control_help.R"), encoding = "UTF-8")
source(file.path(app_root, "R", "figure_layout.R"), encoding = "UTF-8")
source(file.path(app_root, "R", "immune.R"), encoding = "UTF-8")
source(file.path(app_root, "R", "bulk_workflow.R"), encoding = "UTF-8")
source(file.path(app_root, "R", "string_reference.R"), encoding = "UTF-8")
source(file.path(app_root, "R", "workbench_settings.R"), encoding = "UTF-8")
source(file.path(app_root, "R", "settings_tools.R"), encoding = "UTF-8")
source(file.path(app_root, "R", "settings_ui.R"), encoding = "UTF-8")
project_root <- dirname(app_root)
source(file.path(project_root, "shared", "platform.R"), encoding = "UTF-8")
source(file.path(project_root, "apps", "biomethod", "R", "service.R"), encoding = "UTF-8")
addResourcePath("platform-assets", file.path(project_root, "shared", "www"))
addResourcePath("biomethod-assets", file.path(project_root, "apps", "biomethod", "www"))
preview_root <- file.path(app_root, "www", "catalog-previews")

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
  bulk = "从计数矩阵出发完成样本检查、差异表达和下游分析。每一步都可以先检查输出，再继续下一步。 使用 DESeq2 和各下游模块的方法。检查分组、样本名和比较方向；流程会复用已确认的差异结果。",
  pca = "把数千个基因的变化压缩成几个坐标，查看样本整体相似程度。 先变换原始计数以减少高低表达量带来的波动差异，再对高变基因做主成分分析。",
  deg = "找出两个条件之间表达变化有统计支持的基因。 用 DESeq2 对原始整数计数建模，可纳入批次或协变量。正的对数倍数表示实验组表达更高。",
  volcano = "在一张图上同时查看基因变化的方向、幅度与统计证据。 使用已完成的完整差异表，按设定阈值标记上调、下调和未达到阈值的基因。",
  heatmap = "查看一批基因在各样本中的表达模式。 从逐样本表达矩阵选取差异或高变基因，可选择距离与聚类方法，也可按组内聚类。",
  custom_heatmap = "只查看你关心的一组基因，适合展示标志基因或自选基因列表。 用基因 ID 或名称匹配归一化表达矩阵，再按绘图设置排序或聚类。",
  manual_heatmap = "按目的通路分块展示基因表达。可从注释库自动查找，或上传 CSV / Excel 注释，匹配完整 DEG 与表达矩阵。同一基因可以出现在多个区块。",
  go = "找出差异基因中经常出现的生物过程、细胞组分和分子功能。 将筛选出的基因与可映射的受检基因背景比较，做过度代表检验，并对多次检验校正。",
  kegg = "找出差异基因较集中的代谢或信号通路。 按物种匹配 KEGG 或自建参考，用可映射的受检基因为背景做过度代表检验。",
  gsea = "找出基因集的成员是否集中在完整排序的某一端。 对带方向的基因统计量排序，沿排序逐一累计基因集命中，并计算标准化富集分数和校正显著性。",
  gsva = "为每个样本计算通路的相对评分，便于比较通路在样本之间的变化。 从逐样本归一化表达矩阵估计基因集评分，再用 limma 比较组间差异。",
  network = "查看候选蛋白之间在参考库里已记录的互作。 输入节点和边可直接画图。用 Count 或 DEG 时，先确定候选基因，再从参考互作表抽取边。精细编辑可按网络指标筛选。",
  matrix_pca = "对已经整理好的数值表寻找样本之间最大的差异。 直接对数值矩阵做主成分分析，可选标准化和分组表。使用原始计数时，应考虑 RNA-seq 专用 PCA。",
  matrix_heatmap = "把一张连续数值表显示成色块，便于查看整体模式。 支持数值变换、逐行标准化和行列聚类。分组表可按需提供。",
  circos = "在同一个圆形画布展示染色体、区域与跨区域连线。 根据染色体长度分配弧段，把区域和两端坐标映射到相应弧段。输入需统一坐标和长度单位。",
  immune = "根据免疫相关基因的表达，为每个样本估计相对富集程度。 对公共或自建基因集进行单样本 GSEA。可用免疫细胞、免疫状态或疾病签名。",
  figure_layout = "把多张科研图组合成符合论文阅读顺序的面板。 R 裁去外缘留白，按图的比例、纸张与行结构初排。浏览器编辑器可调整位置和面板编号。",
  sankey = "用带状连线查看类别之间的流向与分布。 按来源和去向汇总数值，并以带宽表示流量。",
  venn = "查看两个或三个集合分别有哪些成员，哪些成员重叠。 每个集合内先去重，再统计交集和独有成员。",
  kmeans = "把数值特征相近的对象分成指定数量的组。 用 K-means 分配簇，可先标准化，再以 PCA 坐标展示对象。",
  beeswarm = "同时查看各组单个样本值和它们的分布。 在不改变数值轴位置的前提下错开重叠点，可叠加箱线图。",
  radar = "比较多个对象在一组数值指标上的整体轮廓。 每个指标是一条轴，可按该指标的范围归一化。"
)
input_meta <- list(
  counts = c("原始计数矩阵", "每行一个基因，每列一个样本，首列填 gene_id；可加 gene_name。数值应为测序得到的原始非负整数，不能用已取对数的表达量代替。", ".csv,.tsv,.txt"),
  groups = c("样本分组表", "每行对应一个样本，填写样本名称和分组。可用 Sample、Group 两列，或 sample_id、condition 两列。样本名称应与表达表的列名完全相同。", ".csv,.tsv,.txt"),
  targets = c("目标基因表", "GeneKey 列填写你希望查看的基因 ID 或名称，每行一个。可加 Use 列标记是否使用，填 FALSE 的行会跳过；输入前先核对表达表是否包含这些基因。", ".csv,.tsv,.txt"),
  annotation = c("手工通路注释", "CSV 四列：编号、基因名、通路名、是否纳入注释。编号填写 DEG 的稳定 gene_id，留空时按基因名匹配；同一基因可填写多条通路。也兼容旧 Excel GeneAnnotation。", ".csv,.tsv,.xlsx"),
  volcano_targets = c("目的基因表（可选）", "单列基因名称或 ID，也可在参数区每行输入一个。", ".csv,.tsv,.txt,.xlsx"),
  pathway_names = c("目的通路名称表（可选）", "单列或单行通路正式名称 / ID，也可在参数区每行输入一个。", ".csv,.tsv,.txt,.xlsx"),
  gmt = c("本地基因集", "GMT 是基因集文件。每一行依次写通路 ID、通路名称和属于该通路的基因，用制表符隔开；基因 ID 的格式要与分析数据一致。", ".gmt"),
  nodes = c("Node · 节点表", "节点表的每行表示一个基因或蛋白，需有唯一 ID。可额外提供显示名称、变化幅度或分组，这些信息会用于节点标签和颜色。", ".csv,.tsv,.txt"),
  edges = c("Edge · 连线表", "连线表每行表示一对互作。用 from、to 两列写两端节点 ID，也支持 source、target。score 可以填写参考库中的互作置信分数。", ".csv,.tsv,.txt"),
  matrix = c("数值矩阵", "第一列放基因或指标名称，其余各列放样本数值。请把通路、说明等文字注释放在单独的表里；这里的数值通常已经做过归一化。", ".csv,.tsv,.txt"),
  deg = c("已有差异结果（可选）", "上传已经计算完成的差异表达结果，保留所有受检基因。需要基因 ID、变化幅度和显著性等列；可以直接使用工作站输出的 deg_all.csv。", ".csv,.tsv,.txt"),
  chromosomes = c("染色体长度", "CSV / TSV，含表头 chr,length；长度单位 bp。", ".tsv,.txt,.csv"),
  features = c("区域特征（可选）", "CSV / TSV，含表头 chr,start,end,label；0 起点、半开区间。", ".tsv,.txt,.csv"),
  links = c("区间连线（可选）", "CSV / TSV，含表头 chr1,start1,end1,chr2,start2,end2。", ".tsv,.txt,.csv")
)
panel_keys <- tb_panel_fields(12)
input_meta[panel_keys] <- lapply(seq_along(panel_keys), function(i) c(paste("图片", i),
  "单帧 PNG、JPEG 或 TIFF，最多 1 亿像素。", ".png,.jpg,.jpeg,.tif,.tiff"))

# Explanation is attached to its local control after Shiny renders dynamic inputs.
help_note <- function(text) tags$span(class = "context-note", `data-note` = text, hidden = "hidden")


tb_palette_ui <- function(style) {
  presets <- tb_palettes()
  div(class = "palette-tool", `data-default-colors` = paste(c(style$low, style$mid, style$high), collapse = ";"),
    tags$details(class = "palette-list", tags$summary("科研配色预设"),
      lapply(names(presets), function(name) {
        p <- presets[[name]]
        colors <- p$colors %or% c(p$low, p$mid, p$high)
        tags$button(type = "button", class = "palette-option", `data-colors` = paste(colors, collapse = ";"),
          span(name), span(class = "palette-ramp", style = paste0("background:linear-gradient(90deg,", paste(colors, collapse = ","), ")")))
      })),
    uiOutput("saved_palettes"),
    div(class = "palette-ramp palette-current", `aria-label` = "当前配色色尺"),
    tags$label("自定义色尺", tags$select(class = "palette-mode",
      tags$option(value = "1", "单色"), tags$option(value = "2", "双色"),
      tags$option(value = "3", selected = "selected", "三色"),
      tags$option(value = "4", "多色（4 色起，可输入 4–8 色）"))),
    div(class = "palette-pickers"),
    textInput("style_gradient", "HEX / RGB 颜色（分号分隔）", value = style$gradient %or% "",
      placeholder = "#245F67; rgb(239,235,217); #A95A46"),
    div(class = "group-refresh", textInput("palette_name", "预设名称", value = ""),
      actionButton("save_palette", "保存当前配色", class = "small-button")))
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
          tags$button(type = "button", class = "upload-remove small-button", "移除")),
        div(class = "upload-native", fileInput(paste0("upload_", name), NULL, accept = meta[3])),
        div(class = "upload-feedback", `aria-live` = "polite")),
        if (!is.null(example_id)) checkboxInput(example_id, "示例数据", value = example_checked)))
}
num <- function(name, label, default, min = 0, max = NA, step = 1) {
  tb_control_help(name, numericInput(name, label, value = defaults$params[[name]] %or% default,
               min = min, max = max, step = step))
}
check <- function(name, label, default = FALSE) {
  tb_control_help(name, checkboxInput(name, label, defaults$params[[name]] %or% default))
}

workbench_ui <- function(project = "workstation") fluidPage(
  lang = "zh-CN",
  tags$head(platform_assets(project_root), tags$title("生信工作台 · biometa"), tags$script(src = "uploads.js", defer = "defer"), tags$script(src = "settings-actions.js", defer = "defer"),
    tags$meta(name = "viewport", content = "width=device-width, initial-scale=1"),
    tags$link(rel = "stylesheet", href = "toolbox.css"),
    tags$link(rel = "stylesheet", href = "studio.css"),
    tags$link(rel = "stylesheet", href = "themes.css"),
    tags$script(HTML(paste0("document.documentElement.dataset.theme=",
      jsonlite::toJSON(tb_read_settings(app_root)$theme, auto_unbox = TRUE), ";"))),
    tags$script(src = "workbench-ui.js", defer = "defer"),
    tags$script(src = "toolbox.js", defer = "defer")),
  div(id = "workstation-host", class = "app-shell platform-view", hidden = if (project == "biomethod") "hidden",
    tags$aside(class = "sidebar",
      platform_switcher(project_root, "workstation"),
      div(class = "sidebar-project", span(class = "live-dot"), "本地项目",
          textOutput("project_name", inline = TRUE)),
      textInput("tool_search", NULL, placeholder = "搜索工具 / PCA / 热图…"),
      actionButton("show_home", "分析工具目录", class = "home-button"),

      uiOutput("tool_navigation"),
      div(class = "sidebar-bottom", `data-help` = "上传的数据、计算结果和任务记录都保存在本机。切换项目文件夹可指定自己的工作目录，下载结果包可另行保存当前任务。",
          span("本地分析"))),
    tags$main(class = "main-shell",
      div(class = "topbar", div(textOutput("breadcrumb_tool", inline = TRUE)),
        div(class = "topbar-right", span(class = "local-badge", `data-help` = "工作站只允许本机浏览器连接。分析和绘图由本机 R 执行；公共注释库首次使用时可能需要联网下载，输入数据和结果仍保存在本机。", tabindex = "0", "本机"),
            actionButton("refresh_history", "任务记录", class = "quiet-button"),
            actionButton("show_environment", "设置", class = "quiet-button"))),
      uiOutput("workspace"),
      div(class = "app-footer", "转录组分析工作站"))),
  biomethod_shell(project_root, active = project == "biomethod")
)

guide_heading <- function(title, key) {
  mapping <- jsonlite::read_json(file.path(project_root, "shared", "feature-map.json"))
  known <- key %in% names(mapping)
  h1(title, tags$a(class = "help-mark analysis-guide",
    href = if (known) paste0("/biomethod/articles/", mapping[[key]]) else paste0("?guide=", key),
    target = if (!known) "_blank", rel = "noopener", `data-help` = "功能与展示",
    `aria-label` = "功能与展示", "?"))
}

ui <- function(request) {
  if (startsWith(request$PATH_INFO %or% "", "/api/knowledge/")) return(bm_http(request, project_root))
  path <- request$PATH_INFO %or% "/"
  if (!path %in% c("/", "/workstation", "/workstation/", "/biomethod", "/biomethod/") &&
      !startsWith(path, "/biomethod/")) return(NULL)
  key <- parseQueryString(request$QUERY_STRING %or% "")$guide
  if (is.null(key) || !key %in% c(catalog$id, "bulk")) return(platform_document(workbench_ui(if (startsWith(path, "/biomethod")) "biomethod" else "workstation")))
  content <- readLines(file.path(app_root, "docs", "analysis-guides.md"), encoding = "UTF-8", warn = FALSE)
  markers <- grep("^<!-- tool: ", content)
  at <- match(paste0("<!-- tool: ", key, " -->"), content[markers])
  if (is.na(at)) return(platform_document(workbench_ui(if (startsWith(path, "/biomethod")) "biomethod" else "workstation")))
  end <- c(markers[-1L], length(content) + 1L)[at] - 1L
  body <- content[seq.int(markers[at] + 1L, end)]
  fluidPage(lang = "zh-CN", tags$head(tags$title("功能与展示 · biometa"), tags$link(rel = "stylesheet", href = "toolbox.css"),
      tags$link(rel = "stylesheet", href = "studio.css"), tags$link(rel = "stylesheet", href = "themes.css"),
      tags$script(HTML(paste0("document.documentElement.dataset.theme=",
        jsonlite::toJSON(tb_read_settings(app_root)$theme, auto_unbox = TRUE), ";")))),
    tags$main(class = "workspace guide-page",
      tags$a(href = "./", "返回工作站"),
      HTML(markdown::mark(text = paste(body, collapse = "\n"), format = "html", template = FALSE))))
}

server <- function(input, output, session) {
  selected <- reactiveVal("home")
  bulk <- reactiveVal(NULL)
  bulk_active <- reactiveVal(FALSE)
  bulk_step <- function() {
    flow <- bulk()
    if (bulk_active() && !is.null(flow)) tb_flow_nodes(flow)[[flow$step]]$tool else NULL
  }
  bulk_key <- function() { flow <- bulk(); if (bulk_active() && !is.null(flow)) tb_flow_nodes(flow)[[flow$step]]$id else NULL }
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
  example_selection <- reactiveVal(saved_project$example_dataset %or% "synthetic")
  folder <- if (dir.exists(saved_project$project_folder)) saved_project$project_folder else dirname(app_root)
  project_folder <- reactiveVal(folder)
  project_auto <- reactiveVal(isTRUE(saved_project$project_auto))
  detected <- if (isTRUE(saved_project$project_auto)) tb_project_inputs(folder) else character()
  auto_paths <- reactiveVal(detected)
  for (name in names(detected)) path_cache[[name]] <- unname(detected[name])
  output$project_name <- renderText(basename(project_folder()))
  palette_file <- file.path(app_root, "results", "toolbox", "palette_presets.json")
  read_palettes <- function() {
    if (!file.exists(palette_file)) return(list())
    tryCatch(jsonlite::read_json(palette_file, simplifyVector = FALSE), error = function(e) list())
  }
  saved_palettes <- reactiveVal(read_palettes())
  output$saved_palettes <- renderUI({
    presets <- saved_palettes()
    if (!length(presets)) return(NULL)
    tags$details(class = "palette-list", tags$summary("我的配色"),
      lapply(names(presets), function(name) {
        colors <- unlist(presets[[name]], use.names = FALSE)
        tags$button(type = "button", class = "palette-option", `data-colors` = paste(colors, collapse = ";"),
          span(name), span(class = "palette-ramp", style = if (length(colors) == 1L) paste0("background:", colors)
            else paste0("background:linear-gradient(90deg,", paste(colors, collapse = ","), ")")))
      }))
  })
  observeEvent(input$save_palette, {
    tryCatch({
      name <- trimws(input$palette_name %or% "")
      if (!nzchar(name) || nchar(name) > 40) stop("请填写 1–40 个字符作为预设名称。")
      colors <- tb_gradient_colors(list(gradient = input$style_gradient),
        unlist(defaults$style[c("low", "mid", "high")], use.names = FALSE))
      presets <- read_palettes()
      presets[[name]] <- unname(colors)
      dir.create(dirname(palette_file), recursive = TRUE, showWarnings = FALSE)
      jsonlite::write_json(presets, palette_file, auto_unbox = FALSE, pretty = TRUE)
      saved_palettes(presets)
      showNotification("已保存科研配色。", type = "message")
    }, error = function(e) showNotification(conditionMessage(e), type = "error"))
  })
  project_settings_ui <- function() tagList(
    tags$p(id = "project-folder-display", project_folder()),
    actionButton("project_browse", "浏览选择工作文件夹", class = "secondary-button"),
    checkboxInput("project_scan", "自动选取原始数据", project_auto()),
    p("仅匹配当前目录中名称明确且唯一的 Count、分组和注释文件。"),
    actionButton("save_project", "应用工作空间", class = "secondary-button"))
  project_pending <- reactiveVal(NULL)
  observeEvent(input$project_browse, tryCatch({
    path <- tb_pick_local(app_root, "folder")
    if (nzchar(path)) {
      project_pending(path)
      session$sendCustomMessage("local-folder-selected", path)
    }
  }, error = function(e) showNotification(conditionMessage(e), type = "error")))
  observeEvent(input$save_project, {
    path <- project_pending() %or% project_folder()
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
  observeEvent(input$platform_home, { bulk_active(FALSE); choose_tool("home") })
  observe({ session$sendCustomMessage("platform-feature", list(feature = selected())) })
  observeEvent(input$tool_id, {
    if (identical(input$tool_id, "bulk")) {
      flow <- bulk()
      if (is.null(flow)) choose_tool("bulk") else open_bulk_step(flow)
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
      if (startsWith(key, "panel_")) updateCheckboxInput(session, "panel_auto_favorites", value = FALSE)
      path_cache[[key]] <- destination
      if (!key %in% c("volcano_targets", "pathway_names", "annotation")) updateCheckboxInput(session, example_key(), value = FALSE)
      updateTextInput(session, paste0("path_", key), value = destination)
      session$sendCustomMessage("upload-state", list(key = key, name = uploaded$name))
    }, ignoreNULL = TRUE)
    observeEvent(input[[paste0("remove_upload_", key)]], {
      uploaded <- upload_paths[[key]]
      if (is.null(uploaded)) {
        if (startsWith(key, "panel_")) {
          path_cache[[key]] <- ""
          updateTextInput(session, paste0("path_", key), value = "")
          updateCheckboxInput(session, "panel_auto_favorites", value = FALSE)
          session$sendCustomMessage("upload-state", list(key = key, name = ""))
        }
        return()
      }
      if (identical(path_cache[[key]], uploaded$path)) {
        path_cache[[key]] <- ""
        updateTextInput(session, paste0("path_", key), value = "")
      }
      upload_paths[[key]] <- NULL
      unlink(uploaded$path)
    }, ignoreNULL = TRUE)
  })

  example_key <- function() paste("example", selected(), sep = "_")
  example_checked <- function(name = NULL) isTRUE(input[[example_key()]])
  output$example_catalog <- renderUI({
    folders <- tb_geo_catalog(app_root)
    selectInput("example_choice", "默认示例数据集",
      c("通用合成示例" = "synthetic", stats::setNames(names(folders), gsub("_", " ", names(folders), fixed = TRUE))),
      selected = isolate(example_selection()))
  })
  output$download_example_data <- downloadHandler(
    filename = function() paste0(example_selection(), "_data.zip"),
    content = function(file) tb_zip_example(app_root, example_selection(), file))
  output$download_pathway_template <- downloadHandler(
    filename = function() "target_pathways_example.csv",
    content = function(file) {
      source <- if (example_checked() && example_dataset() == "synthetic") "custom" else input$pathway_source %or% selected()
      organism <- if (identical(input$species, "human")) "hsa" else "mmu"
      values <- switch(source, go = c("GO:0006955", "immune response"),
        kegg = paste0(organism, c("04620", "04630")), reactome = "Immune System", c("DEMO_1", "Synthetic set 2"))
      utils::write.csv(data.frame(pathway_name = values), file, row.names = FALSE, fileEncoding = "UTF-8")
    })
  output$download_annotation_template <- downloadHandler(
    filename = function() "pathway_annotation_template.csv",
    content = function(file) utils::write.csv(tb_annotation_template(), file, row.names = FALSE, fileEncoding = "UTF-8"))
  output$example_details <- renderUI({
    folder <- tb_geo_catalog(app_root)[example_selection()]
    file <- if (!length(folder) || is.na(folder)) file.path(app_root, "examples", "README.md")
      else file.path(folder, "README.md")
    div(class = "example-document", tb_example_document(file))
  })
  observeEvent(input$example_choice, {
    choice <- input$example_choice
    if (!choice %in% c("synthetic", names(tb_geo_catalog(app_root)))) return()
    if (identical(choice, isolate(example_selection()))) return()
    tryCatch({
      tb_save_settings(app_root, utils::modifyList(tb_read_settings(app_root), list(example_dataset = choice)))
      example_selection(choice)
      showNotification("默认示例已保存；分析页勾选示例数据后使用。", type = "message")
    }, error = function(e) showNotification(conditionMessage(e), type = "error"))
  }, ignoreInit = TRUE)
  output$active_example <- renderText({
    if (!example_checked()) return("")
    dataset <- example_dataset()
    if (dataset == "synthetic") "当前：通用合成示例" else paste("当前：", gsub("_", " ", dataset, fixed = TRUE))
  })
  example_switch <- function() div(
    `data-help` = "勾选后，本页所需输入全部使用菜单中选定的系统示例，不会混入你上传的文件。取消勾选后可使用自己的文件；特殊图型自动使用格式匹配的合成示例。",
    checkboxInput(example_key(), "示例数据", isolate(example_checked())),
    textOutput("active_example", inline = TRUE))
  active_fields <- function() {
    id <- selected()
    if (id == "bulk") return(c("counts", "groups", "gmt", "edges"))
    if (in_bulk_step() && id != "figure_layout") {
      spec <- tb_bulk_spec(bulk(), id, defaults)
      if (id == "network") spec$params$network_mode <- input$network_mode %or% spec$params$network_mode
      for (key in c("heatmap_kind", "annotation_mode", "annotation_source"))
        spec$params[[key]] <- input[[key]] %or% spec$params[[key]]
      fields <- tb_active_inputs(spec)
      return(fields[!vapply(fields, function(key) key %in% c("counts", "groups") &&
        nzchar(spec$inputs[[key]] %or% "") && file.exists(spec$inputs[[key]]), logical(1))])
    }
    if (id == "figure_layout") {
      count <- input$panel_count %or% defaults$params$panel_count
      if (!is.finite(count) || count != floor(count) || count < 1 || count > 12) return(character())
      return(tb_panel_fields(count))
    }
    if (id == "home") return(character())
    params <- defaults$params
    params$downstream_input <- id %in% c(tb_processed_tools, "volcano")
    params$network_mode <- input$network_mode %or% params$network_mode
    params$matrix_use_groups <- isTRUE(input$matrix_use_groups)
    for (key in c("heatmap_kind", "annotation_mode", "annotation_source")) params[[key]] <- input[[key]] %or% params[[key]]
    # Keep optional GMT upload mounted when switching reference sources.
    if (id == "immune") params$immune_source <- "custom"
    group_mode <- input$group_mode %or% params$group_mode
    params$heatmap_mode <- switch(group_mode, joint = "variable", pair = input$heatmap_mode %or% params$heatmap_mode, "deg")
    tb_active_inputs(list(tool = id, params = params, inputs = list(matrix = "", deg = "")))
  }
  example_dataset <- function() {
    id <- selected()
    if (id %in% c(tb_general_tools, "circos", "manual_heatmap") ||
      (id == "network" && identical(input$network_mode %or% "files", "files"))) return("synthetic")
    example_selection()
  }
  example_preset <- function() tb_geo_preset(app_root, example_dataset())
  example_path <- function(name) tb_example_path(app_root, selected(), name,
    list(dataset = example_dataset(), network_mode = if (selected() == "bulk") "deg" else input$network_mode))
  read_input <- function(name) {
    if (!in_bulk_step() && example_checked(name) && !name %in% c("volcano_targets", "pathway_names")) {
      return(example_path(name))
    }
    path <- input[[paste0("path_", name)]] %or% path_cache[[name]] %or% defaults$inputs[[name]] %or% ""
    trimws(path)
  }
  refresh_groups <- function() {
    tryCatch({
      path <- if (in_bulk_step() && nzchar(bulk()$inputs$groups %or% "")) bulk()$inputs$groups else read_input("groups")
      if (!file.exists(path)) stop("分组表不存在。")
      groups <- tb_read_groups(path)
      choices <- unique(groups$condition)
      choices <- choices[!is.na(choices) & nzchar(choices)]
      if (length(choices) < 2) stop("至少需要两个分组。")
      group_choices(choices)
      subset <- intersect(isolate(input$group_subset) %or% character(), choices)
      updateSelectizeInput(session, "group_subset", choices = choices, selected = subset)
      preset <- if (example_checked()) example_preset()
      previous_control <- preset$control %or% isolate(input$control) %or% defaults$params$control
      previous_treatment <- preset$treatment %or% isolate(input$treatment) %or% defaults$params$treatment
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
          div(class = "hero-composition", div(h1("从表达变化，", tags$br(), span("走向机制理解。")),
              p("转录组分析与科研绘图"),
              tags$button(type = "button", class = "primary-button hero-start", `data-tool` = "bulk", "开始分析")),
            div(class = "hero-art", `aria-hidden` = "true", div(class = "art-orbit orbit-one"), div(class = "art-orbit orbit-two"),
                div(class = "art-axis"), span(class = "art-node n1"), span(class = "art-node n2"), span(class = "art-node n3"),
                span(class = "art-node n4"), span(class = "art-caption", "EXPRESSION / PATHWAY / NETWORK")))),
        div(class = "home-section-title", h2("分析工具目录"), span(paste(nrow(menu_catalog), "项 · 示例图形"))),
        div(class = "catalog-filters", radioButtons("catalog_category", "分析分类",
          c("全部" = "all", unique(menu_catalog$category)), inline = TRUE)),
        uiOutput("tool_cards"),
        div(class = "history-section", div(class = "home-section-title", h2("最近任务")), uiOutput("history_list"))))
    }
    if (selected() == "bulk") return(bulk_setup_ui())
    tool <- catalog[match(selected(), catalog$id), , drop = FALSE]
    div(class = "workspace tool-workspace",
      div(class = "tool-header", div(div(class = "eyebrow", tool$category),
        guide_heading(if (selected() %in% heatmap_modes) heatmap_title else tool$title, selected()))),
      if (bulk_active()) uiOutput("bulk_progress"),
      uiOutput("analysis_steps"),
      div(class = "tool-layout",
        div(class = "configuration-column",
          div(class = "panel",
            if (selected() == "figure_layout") section_title("01", "图片输入", "先选择图片数量，再逐张上传或填写本机路径。可使用 PNG、JPEG 或 TIFF；每张图片对应一个面板，下方滑轨调整其相对大小。")
            else section_title("01", "数据输入", "可以拖入文件、点击上传，或填写本机文件路径。勾选“示例数据”后，系统按菜单选定的数据集提供本页全部输入；文件格式和大小限制见上传区。"),
            if (selected() == "figure_layout") tagList(
              if (bulk_active()) checkboxInput("panel_auto_favorites", "按分析顺序自动填入标星图片，并调整图片数量", FALSE),
              num("panel_count", "图片数量", 4, 1, 12)),
            if (!bulk_active() && selected() != "figure_layout") example_switch(),
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
            div(class = "panel", section_title("03", "纸张、布局与导出", "选择纸张尺寸和横纵方向，再设置每行放几张图以及面板编号。预览会反映分栏变化；导出后也可进入独立编辑器微调位置。"), uiOutput("style_controls")))
          else if (selected() != "deg") div(class = "panel", tags$details(tags$summary("图形样式与导出",
              `data-help` = "调整样式后点击「仅重新绘图」复用当前结果。画布单位为英寸，DPI 仅影响位图。", tabindex = "0"),
              div(class = "details-content", uiOutput("style_controls")))),
          div(class = "run-bar", actionButton("validate_inputs", "检查输入", class = "secondary-button"),
              actionButton("run_tool", "运行当前工具", class = "primary-button")),
          help_note("运行会执行分析。仅修改样式时，可从已完成结果重新绘图。")),
        div(class = "results-column", uiOutput("job_status"), uiOutput("mapping_quality"),
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
      tags$button(type = "button", class = "tool-card", `data-tool` = tools$id[i], `data-help` = tool_help[[tools$id[i]]] %or% tools$description[i],
        if (file.exists(file.path(preview_root, preview))) tags$img(class = "tool-card-preview",
          src = paste0("catalog-previews/", preview), alt = "", loading = "lazy", `aria-hidden` = "true"),
        span(class = "card-category", tools$category[i]),
        h3(tools$title[i]), p(tools$description[i]), span(class = "card-link", "↗", `aria-hidden` = "true"))
    }))
  })
  output$input_controls <- renderUI({
    req(selected() != "home")
    pathway <- selected() %in% tb_pathway_tools
    tagList(uiOutput("input_file_rows"), if (pathway) uiOutput("reference_detail"))
  })
  output$input_file_rows <- renderUI({
    req(selected() != "home")
    fields <- active_fields()
    fields <- setdiff(fields, "pathway_names")
    using_example <- example_checked() && !in_bulk_step() && selected() != "figure_layout"
    example_files <- if (using_example) tagList(lapply(fields, function(name) {
      path <- example_path(name)
      if (nzchar(path)) div(class = "empty-small", strong(input_meta[[name]][1]), " · ", basename(path))
      else if (!name %in% c("gmt", "edges")) div(class = "empty-small", input_meta[[name]][1], " · 此示例未提供")
    }))
    if (selected() == "figure_layout") validate(need(length(fields), "图片数量须为 1–12 的整数。"))
    pathway <- selected() %in% tb_pathway_tools
    immune <- selected() == "immune"
    staged <- if (in_bulk_step()) tb_bulk_spec(bulk(), selected(), defaults) else NULL
    panel_choices <- if (!is.null(staged) && selected() == "figure_layout") unlist(lapply(isolate(gallery()), `[[`, "path")) else character()
    tagList(example_files, if (!is.null(staged) && selected() != "figure_layout") p(if (is.null(bulk()$approved$deg)) "沿用流程设置中的 Count、分组和比较方向。" else "读取已确认的 DEG 输出。"),
      if (pathway) selectInput("pathway_source", "参考注释库", tb_pathway_sources(selected()),
        selected = staged$params$pathway_source %or% isolate(input$pathway_source)),
      if (immune) tagList(selectInput("immune_source", "基因集来源", tb_immune_sources,
        selected = isolate(input$immune_source) %or% "cell"), uiOutput("immune_presets")),
      lapply(fields, function(name) {
        meta <- if (selected() %in% tb_general_tools) c("绘图数据表", tool_help[[selected()]], input_meta[[name]][3]) else input_meta[[name]]
        if (name == "deg") meta[1L:2L] <- if (selected() == "gsea")
          c("完整差异结果或排序表", "每行放一个基因，gene_id 列填写基因编号，stat 或 score 列填写带正负方向的排序分数。保留全部有效基因，不要只留下显著差异基因；分数的正方向应对应实验组更高。")
          else c("完整差异结果表 · deg_all.csv", "每行一个受检基因，保留基因 ID、表达变化幅度和显著性。可直接使用差异分析下载的完整结果表。")
        if (name == "matrix" && selected() %in% tb_processed_tools) meta[1L:2L] <-
          c("处理后表达矩阵 · vst.csv", "第一列放基因 ID，其余列放每个样本的处理后表达量。可以使用工作站差异分析输出的 vst.csv，列名要能与分组表对应。")
        if (name == "groups" && selected() %in% tb_processed_tools) meta[1L] <- "样本分组 · sample_mapping.csv"
        initial <- staged$inputs[[name]]
        if (selected() == "figure_layout") initial <- isolate(path_cache[[name]]) %or% initial
        control <- file_control(name, initial %or% isolate(path_cache[[name]]), meta, isolate(upload_paths[[name]]),
          NULL)
        if (!in_bulk_step() && selected() != "figure_layout" && !name %in% c("volcano_targets", "pathway_names"))
          control <- conditionalPanel(sprintf("!input.%s", example_key()), control)
        if (selected() == "figure_layout") {
          key <- paste0("weight_", name)
          slider <- sliderInput(key, "相对大小", min = 50, max = 200, step = 10,
            value = isolate(input[[key]]) %or% 100, post = "%", ticks = FALSE)
          controls <- tagList(control, slider)
          if (length(panel_choices)) controls <- tagList(tags$button(type = "button", class = "secondary-button",
            `data-bulk-pick-panel` = name, "从本次自动化流程挑选"), controls)
          return(div(class = "figure-input-panel", `data-panel-field` = name,
            div(class = "panel-position-tools",
              tags$button(type = "button", class = "panel-grip", draggable = "true", `data-panel-drag` = name,
                `aria-label` = "按住拖动图片位置", HTML('<svg width="18" height="18" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path d="M4 6h16M4 12h16M4 18h16"/></svg>')),
              tags$button(type = "button", `data-panel-move` = name, `data-position` = "top", "置顶"),
              tags$button(type = "button", `data-panel-move` = name, `data-position` = "bottom", "置尾")),
            div(class = "panel-upload-row", imageOutput(paste0("panel_thumb_", name), width = "90px", height = "90px"), div(controls))))
        }
        if (pathway && name == "gmt") conditionalPanel("input.pathway_source === 'custom'", control)
        else if (immune && name == "gmt") conditionalPanel("input.immune_source === 'custom'", control)
        else control
      }),
      if (selected() %in% c("matrix_pca", "matrix_heatmap"))
        help_note("勾选分析参数中的“使用分组表”，即可上传分组并用于绘图。"))
  })

  observeEvent(list(example_checked(), example_dataset(), active_fields()), {
    req(example_checked(), !in_bulk_step())
    preset <- example_preset()
    synthetic <- is.null(preset)
    if (selected() == "bulk") updateCheckboxInput(session, "bulk_custom", value = FALSE)
    if (!synthetic) {
      updateSelectInput(session, "species", selected = preset$species)
      updateCheckboxInput(session, if (selected() == "bulk") "bulk_batch" else "use_batch", value = preset$use_batch)
      updateSelectInput(session, "fit_type", selected = preset$fit_type %or% "parametric")
      updateTextInput(session, if (selected() == "bulk") "bulk_covariates" else "covariates", value = preset$covariates)
      if ("counts" %in% active_fields() && !isTRUE(preset$count))
        showNotification("这套示例只有归一化表达量。请用矩阵绘图或选择含原始 Count 的示例。", type = "warning")
    } else if ((example_selection()) != "synthetic") {
      showNotification("此工具使用独立的合成示例，以匹配它的输入格式。", type = "message")
    }
    if (selected() %in% tb_pathway_tools) updateSelectInput(session, "pathway_source",
      selected = if (synthetic) "custom" else unname(tb_pathway_sources(selected())[1]))
    if (selected() == "immune") updateSelectInput(session, "immune_source", selected = if (synthetic) "custom" else "cell")
    if ("groups" %in% active_fields() && !selected() %in% c("matrix_pca", "matrix_heatmap") &&
        (!"counts" %in% active_fields() || synthetic || isTRUE(preset$count))) refresh_groups()
  }, ignoreInit = TRUE)

  output$immune_presets <- renderUI({
    source <- input$immune_source %or% "cell"
    if (source == "custom") return(NULL)
    choices <- tb_immune_choices(app_root, input$species %or% defaults$params$species, source)
    if (!length(choices)) return(div(class = "empty-small", "此物种的预设缓存不可用，请检查 references 目录。"))
    selectizeInput("immune_terms", "预设基因集", choices, selected = head(unname(choices), 6),
      multiple = TRUE, options = list(maxItems = 40, placeholder = "搜索基因集 ID 或名称"))
  })

  output$reference_detail <- renderUI({
    source <- input$pathway_source
    if (is.null(source) || source == "custom") return(NULL)
    species <- if (in_bulk_step()) bulk()$params$species else input$species %or% defaults$params$species
    info <- Filter(function(x) x$id == source, bm_annotation_inventory(project_root))[[1L]]
    local <- info$local[[species]]
    div(class = "reference-summary",
      p(info$source), p(local$status, if (!is.null(local$terms)) paste(" · ", local$terms, "个通路 /", local$genes, "个基因")),
      if (!is.null(local$retrieved)) p("缓存获取时间：", local$retrieved, "；", local$release),
      tags$a(href = paste0("/biomethod/articles/", if (source == "reactome") "reactome" else "go-kegg"), "查看注释库来源、版本与使用说明"))
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


  pathway_entry <- function(initial, staged = NULL, annotation = FALSE) {
    mode_id <- if (annotation) "annotation_input" else "target_pathway_input"
    text_id <- if (annotation) "annotation_terms" else "target_pathways"
    mode <- initial[[mode_id]] %or% "auto"
    path <- staged$inputs$pathway_names %or% isolate(path_cache[["pathway_names"]]) %or% ""
    if (mode == "auto") mode <- if (nzchar(path) && !nzchar(initial[[text_id]] %or% "")) "table" else "text"
    div(class = "pathway-entry",
      radioButtons(mode_id, "通路名称输入方式", c("直接填写" = "text", "上传名称表" = "table"),
        selected = mode, inline = TRUE),
      conditionalPanel(sprintf("input.%s === 'text'", mode_id),
        textAreaInput(text_id, "通路正式名称或 ID · 每行一项", initial[[text_id]], rows = 4),
        actionButton("pathway_lookup", "从当前注释库查找名称或编号", class = "secondary-button")),
      conditionalPanel(sprintf("input.%s === 'table'", mode_id),
        file_control("pathway_names", path,
          c("上传通路正式名称或 ID 表", "单列，每行一项；与直接填写是同一内容的两种输入方式，只读取当前选中的方式。", ".csv,.tsv,.txt,.xlsx"),
          isolate(upload_paths[["pathway_names"]]), NULL),
        downloadButton("download_pathway_template", "下载名称表示例")),
      help_note("可以填写注释库中的正式名称或稳定编号。使用所选输入方式，名称和编号都精确匹配；不会按模糊相似名称替代。"))
  }

  pathway_lookup_target <- reactiveVal("target_pathways")
  observeEvent(input$pathway_lookup, tryCatch({
    annotation <- selected() %in% c("heatmap", "manual_heatmap")
    source <- if (annotation) input$annotation_source %or% "go"
      else input$pathway_source %or% unname(tb_pathway_sources(selected())[1L])
    species <- if (in_bulk_step()) bulk()$params$species else input$species %or% defaults$params$species
    catalog <- tb_library_catalog(app_root, source, species)
    pathway_lookup_target(if (annotation) "annotation_terms" else "target_pathways")
    showModal(modalDialog(title = "选择注释库中的目的通路", size = "l",
      selectizeInput("pathway_library_selection", "搜索正式名称或稳定编号", choices = NULL, multiple = TRUE,
        options = list(placeholder = "准备好目录后可输入名称或编号", maxOptions = 60, closeAfterSelect = TRUE,
          onInitialize = I("function(){this.disable();}"), onLoad = I("function(){this.enable();}"))),
      p("加入后保存稳定编号，避免名称相同或标题更新造成歧义；也可以在原输入框继续直接填写正式名称。"),
      footer = tagList(modalButton("取消"), actionButton("pathway_library_add", "加入目的通路"))))
    session$onFlushed(function() updateSelectizeInput(session, "pathway_library_selection",
      choices = stats::setNames(catalog$term, paste(catalog$label, "·", catalog$term)), server = TRUE), once = TRUE)
  }, error = function(e) showNotification(conditionMessage(e), type = "error", duration = 12)))
  observeEvent(input$pathway_library_add, {
    values <- input$pathway_library_selection %or% character()
    if (!length(values)) return(showNotification("请先选择一个或多个通路。", type = "warning"))
    id <- pathway_lookup_target()
    existing <- tb_read_items(input[[id]] %or% "")
    updateTextAreaInput(session, id, value = paste(unique(c(existing, values)), collapse = "\n"))
    removeModal()
    showNotification(paste("已加入", length(values), "个通路编号。"))
  })

  parameter_ids <- reactiveVal(character())
  output$parameter_controls <- renderUI({
    id <- selected()
    req(id != "home")
    matrix_tool <- id %in% c("matrix_pca", "matrix_heatmap", "circos", "immune", "figure_layout", tb_general_tools)
    staged <- if (in_bulk_step()) tb_bulk_spec(bulk(), id, defaults) else NULL
    initial <- staged$params %or% defaults$params
    if (id == "go" && (is.null(staged) || is.null(bulk()$stage_params[[bulk_key()]]$pathway_top)))
      initial$pathway_top <- 5L
    num <- function(name, label, default, min = 0, max = NA, step = 1) tb_control_help(name,
      numericInput(name, label, initial[[name]] %or% default, min = min, max = max, step = step))
    check <- function(name, label, default = FALSE) tb_control_help(name,
      checkboxInput(name, label, initial[[name]] %or% default))
    network_files <- id == "network" && (input$network_mode %or% initial$network_mode %or% "files") == "files"
    ppi_counts <- id == "network" && identical(input$network_mode, "deg")
    needs_groups <- ppi_counts || id %in% c("pca", "deg", "heatmap", "custom_heatmap", "manual_heatmap", "gsva")
    basic <- if (needs_groups && !matrix_tool && !network_files) tagList(
      group_mode_ui(id, initial),
      div(class = "group-refresh", actionButton("refresh_groups", "读取当前分组", class = "small-button"),
          textOutput("group_summary", inline = TRUE)),
      if (ppi_counts || id %in% c("pca", "deg", "gsva")) tags$details(tags$summary(if (id == "gsva") "批次与协变量" else "模型与低表达过滤"), div(class = "details-content two-columns",
        if (id != "gsva") num("min_count", "Count 下限", 10, 0),
        if (id != "gsva") num("min_samples", "至少达到下限的样本数", 3, 1),
        if (id != "gsva") num("alpha", "模型显著性水平", 0.05, 0.000001, 1, 0.01),
        if (id != "gsva") selectInput("fit_type", "离散度拟合", c("Parametric" = "parametric", "Local" = "local", "Mean" = "mean"),
          selected = isolate(input$fit_type) %or% defaults$params$fit_type %or% "parametric"),
        check("use_batch", "将技术批次纳入模型"),
        textInput("covariates", "需额外考虑的分组表列名（逗号分隔）", defaults$params$covariates %or% "")),
        help_note("不同时间、机器或实验批次可能影响表达。若某一组全部来自同一批次，程序无法分开判断是分组还是批次造成差异。")))
    selection <- if (id %in% c("deg", "volcano", "heatmap") || (id == "network" && !network_files)) tagList(
      div(class = "two-columns", numericInput("padj", "校正显著性上限", initial$padj, min = 0.000001, max = 1, step = 0.01),
          numericInput("log2fc", "表达变化幅度下限（对数倍数）", initial$log2fc, min = 0, step = 0.1)),
      selectInput("direction", "差异方向", c("全部" = "all", "上调" = "up", "下调" = "down"),
                  selected = initial$direction))
    annotation_controls <- tagList(
      selectInput("annotation_mode", "通路注释方式", c("自动嗅探" = "auto", "手动注释" = "manual"), selected = initial$annotation_mode),
      conditionalPanel("input.annotation_mode === 'auto'",
        selectInput("annotation_source", "注释库", c("Gene Ontology" = "go", "KEGG" = "kegg", "Reactome" = "reactome", "本地 GMT" = "custom"), selected = initial$annotation_source),
        pathway_entry(initial, staged, TRUE),
        help_note("按正式名称或稳定 ID 精确匹配，不以模糊相似名称替代。请核对物种；使用公共库可能需要联网下载注释。")),
      conditionalPanel("input.annotation_mode === 'manual'", downloadButton("download_annotation_template", "下载 CSV 注释模板")),
      check("pathway_cluster", "按通路分块，块内按表达模式聚类", TRUE),
      help_note("填写编号时优先匹配 DEG 的 gene_id；只填基因名时报告重名歧义。同一基因可在不同通路中重复展示，汇总表保留完整统计值和表达量。"))
    specific <- switch(id,
      pca = tagList(num("pca_top", "参与 PCA 的高变基因数", 500, 2), check("pca_scale", "PCA 前按基因标准化"),
                   check("labels", "显示样本标签")),
      deg = help_note("所有变化都以实验组相对对照组计算：正值表示实验组更高，负值表示更低。输出包括完整受检基因表和按当前阈值筛选的结果，后续富集或排序分析应保留完整表。"),
      volcano = tagList(textAreaInput("target_text", "目的基因（每行一个基因名或 ID，可与单列表格合并）", initial$target_text, rows = 4),
                         help_note("目的基因默认红字、黄点，颜色可在图形样式中单独调整。每次同时导出上下发散和左右发散两版火山图。"),
                         check("labels", "额外标注显著基因"),
                         help_note("可直接上传差异表达任务输出的 deg_all.csv，系统会按当前阈值给上调和下调基因着色。请保留未达到阈值的基因，便于展示完整分布；修改阈值后需要重新运行筛选。")),
      heatmap = tagList(selectInput("heatmap_kind", "热图类型", c("表达热图" = "expression", "带通路注释的热图" = "annotated"), selected = initial$heatmap_kind),
        conditionalPanel("input.heatmap_kind === 'annotated'", annotation_controls),
        conditionalPanel("input.group_mode === 'pair'",
          selectInput("heatmap_mode", "候选基因", c("差异基因" = "deg", "高变基因" = "variable"),
            selected = defaults$params$heatmap_mode)),
        conditionalPanel("input.group_mode === 'joint'", p("联合展示按所选组筛选高变基因。")),
        conditionalPanel("input.group_mode === 'reference' || input.group_mode === 'all_pairs'",
          p("批量模式按各比较的差异基因分别出图。"))),
      custom_heatmap = help_note("每一行只比较同一个基因在不同样本中的高低。勾选按行标准化后，各基因可以共用同一个色尺。"),
      manual_heatmap = annotation_controls,

      network = tagList(
        selectInput("network_mode", "数据来源", c("直接绘图 · Node + Edge" = "files", "生成 Node / Edge · 已有 DEG" = "results",
          "生成 Node / Edge · 原始 Count + 分组" = "deg"), selected = initial$network_mode %or% "files"),
        selectInput("network_layout", "静态导出布局", c("力导向 FR" = "fr", "Kamada–Kawai" = "kk", "圆形" = "circle", "网格" = "grid"), selected = defaults$params$network_layout %or% "fr"),
        selectInput("network_score_scale", "Edge 分数单位", c("按字段名识别（combined_score ÷ 1000）" = "auto", "已是 0–1" = "unit", "STRING 0–1000" = "thousand"), selected = defaults$params$network_score_scale %or% "auto"),
        num("ppi_score", "标准化置信分数下限（0–1）", 0.7, 0, 1, 0.05),
        help_note(if (network_files) "节点表给出要画的基因或蛋白，连线表说明它们如何相连。连线两端的名称应能在节点表里找到。"
          else "按差异阈值筛选基因，再与互作参考匹配，导出可重新导入的 Node 和 Edge。留空参考边表时使用本机 STRING 物理互作库。")),
      matrix_pca = tagList(check("matrix_use_groups", "使用分组表（可选）", FALSE),
                           check("pca_scale", "PCA 前按特征标准化", TRUE), check("labels", "显示样本标签"),
                           help_note("每行填写一个基因或指标，每列填写一个样本。第一列放每行唯一的名称，其他列只填数值。")),
      matrix_heatmap = tagList(check("matrix_use_groups", "使用分组表（可选）", FALSE),
                selectInput("matrix_transform", "矩阵变换", c("不变换" = "none", "取对数，减少极端高值的影响" = "log2"),
                selected = defaults$params$matrix_transform %or% "none"),
                num("log_pseudocount", "取对数前加的数（避免零值）", 1, 0.000001, NA, 0.1)),
      circos = help_note("长度与区域起止必须使用相同单位。跨染色体连线的端点须存在于长度表。"))
    heatmap_options <- if (id %in% c("heatmap", "custom_heatmap", "manual_heatmap", "matrix_heatmap", "gsva")) tagList(
      num("heatmap_top", "最多显示基因 / 通路数", 50, 1),
      check("row_scale", "按行标准化，比较同一基因的相对高低", TRUE),
      div(class = "two-columns", check("cluster_rows", "聚类基因／条目（行）", TRUE),
          check("cluster_columns", "聚类样本（列）", FALSE)),
      conditionalPanel("input.cluster_columns",
        selectInput("column_cluster_mode", "样本聚类范围",
          c("按组分块，组内聚类" = "within", "全局聚类，可跨组排列" = "global"),
          selected = defaults$params$column_cluster_mode)),
      div(class = "two-columns", selectInput("distance", "距离度量",
        c("Pearson · 比较变化趋势" = "pearson", "Spearman · 比较高低排序" = "spearman", "欧氏距离" = "euclidean", "曼哈顿距离" = "manhattan"),
          selected = defaults$params$distance %or% "pearson"),
        selectInput("linkage", "层次聚类连接算法", c("Complete 完全连接" = "complete",
          "Average 平均连接" = "average", "Single 单连接" = "single", "Ward.D2 最小方差" = "ward.D2"),
          selected = defaults$params$linkage %or% "complete")),
      help_note("聚类把表达模式相似的行或列排在附近。选组内聚类时，同组样本会待在一起。Ward.D2 需搭配欧氏距离。"))
    pathway_options <- if (id %in% tb_pathway_tools) tagList(
      uiOutput("pathway_mapping_controls"),
      if (id %in% c("go", "kegg")) uiOutput("ora_metric_controls"),
      if (id == "go") conditionalPanel("input.pathway_source === 'go'", tagList(
        selectInput("go_output_scope", "GO 出图内容",
          c("三类合并与各类单图" = "both", "仅三类合并图" = "combined", "仅单类图" = "single"),
          selected = initial$go_output_scope),
        conditionalPanel("input.go_output_scope === 'single'",
          checkboxGroupInput("go_ontology_multi", "要导出的单类图", c("生物过程 · BP" = "BP", "细胞组分 · CC" = "CC", "分子功能 · MF" = "MF"),
            selected = initial$go_ontology, inline = TRUE)),
        help_note("合并图始终分面展示 BP、CC、MF；没有符合阈值的类别保留面板并说明。单图按所选类别分别导出，统计校正在各分类内进行。"))),
      if (id %in% c("gsea", "gsva")) conditionalPanel("input.pathway_source === 'go'",
        selectInput("go_ontology", "GO 分类", c("生物过程 · BP" = "BP", "细胞组分 · CC" = "CC",
          "分子功能 · MF" = "MF"), selected = head(initial$go_ontology, 1))),
      if (id %in% c("go", "kegg")) tagList(
        selectInput("ora_result_metric", "富集结果保留指标", c("Adjusted P value · BH" = "padj", "FDR · BH" = "FDR", "P value · 未校正" = "pvalue"), selected = initial$ora_result_metric),
        num("ora_fdr", "所选富集结果指标的上限", .05, .000001, 1, .01)),
      if (id == "kegg") conditionalPanel("input.pathway_source === 'kegg'",
        selectInput("kegg_maps", "KEGG 官网机制图",
          c("下载本次出图通路" = "displayed", "下载所有符合结果阈值的通路" = "significant", "不下载" = "off"), selected = initial$kegg_maps),
        help_note("下载官网原始 PNG 参考图，未叠加本次表达量。文件、官网链接和下载状态一同导出；全部通路模式可能需要较长时间。")),
      if (id %in% c("go", "kegg", "gsva")) tags$fieldset(class = "style-group target-pathways",
        tags$legend("目的通路"),
        pathway_entry(initial, staged),
        help_note("示例演示单列格式，正式使用请替换成当前库的名称或 ID。匹配到的通路名称默认标红，样式中可改文字和背景颜色；不改变统计、阈值或排名，匹配与是否出图另存报告。")),
      num("pathway_top", if (id == "gsea") "输出前 N 条通路曲线" else if (id == "go") "每个 GO 分类的出图条目数" else "出图条目数", 15, 1,
        if (id == "gsea") 100 else NA),
      tags$details(tags$summary("基因集、通路排序与指定条目"), div(class = "details-content",
      conditionalPanel("input.pathway_source === 'custom'", selectInput("gmt_id_type", "GMT 基因标识", c("Gene Symbol" = "SYMBOL", "稳定 gene_id" = "gene_id"),
        selected = initial$gmt_id_type),
      textInput("database_version", "本地数据库版本 / 来源标记",
        value = initial$database_version, placeholder = "如 MSigDB 版本或下载日期")),
      div(class = "two-columns", num("min_set_size", "最小基因集大小", 10, 1),
          num("max_set_size", "最大基因集大小", 500, 1)),
      div(class = "two-columns",
        selectInput("gsea_sort", "通路排序指标", c("P value" = "pvalue", "Adjusted P value · BH" = "padj", "FDR · BH" = "FDR",
          if (id %in% c("go", "kegg")) c("Gene ratio" = "gene_ratio", "基因数量" = "count"),
          if (id == "gsva") c("logFC 绝对值" = "logFC")), selected = initial$gsea_sort),
        selectInput("gsea_order", "排序方向", c("从低到高" = "asc", "从高到低" = "desc"), selected = initial$gsea_order)),
      help_note("在本工作站的 BH 校正结果中，Adjusted P value 与 FDR 指向同一列。这里排列的是通路结果；前面的候选基因筛选读取上传 DEG 的实际列，两者分别记录。"),
      if (id == "gsea") textInput("pathway_id", "指定曲线通路 ID（可选）",
        initial$pathway_id, placeholder = "留空按结果选择")
      else textInput("pathway_terms", "限定出图条目 ID（高级筛选，可选）", initial$pathway_terms,
        placeholder = "多个 ID 用逗号或空格分隔"),
      help_note("参考库决定每条通路包含哪些基因。内置 GO 会自动记录注释包版本；自备 GMT 请填写下载来源和版本日期，并核对物种和基因名称格式，以便之后复现分析。" ))))
    immune_options <- if (id == "immune") tagList(
      conditionalPanel("input.immune_source === 'custom'",
        textInput("database_version", "标志基因集来源与版本", "")),
      num("immune_min_genes", "每组最少匹配基因数", 5, 2))
    general <- switch(id,
      figure_layout = num("panel_trim", "裁白容差（%）", 3, 0, 20, 1),
      sankey = num("sankey_gap", "节点间隔（总流量比例）", .1, 0, .5, .02),
      venn = help_note("每行填写集合名和一个成员，同一集合内重复的成员只统计一次。图上的数字表示交集或独有成员数，圆的面积不按成员数缩放；精确成员可查看导出的数据表。"),
      kmeans = tagList(num("kmeans_k", "聚类数 K", 3, 2, 100), num("kmeans_seed", "随机种子", 1, 0, 100000),
        check("kmeans_scale", "按列标准化后聚类")),
      beeswarm = tagList(check("beeswarm_box", "叠加箱线图"), check("beeswarm_log", "使用 log10 纵轴")),
      radar = check("radar_normalize", "各指标按输入对象范围归一化至 0–1"))
    controls <- tagList(if (is.null(staged) && !id %in% c(tb_general_tools, "figure_layout")) selectInput("species", "物种", tb_species_choices,
      selected = isolate(input$species) %or% defaults$params$species),
      basic, selection, specific, heatmap_options, pathway_options, immune_options, general)
    ids <- tb_ui_ids(controls)
    if (id %in% tb_pathway_tools) ids <- c(ids, "gene_id_column", "gene_name_column", "pathway_source")
    if (id %in% c("go", "kegg")) ids <- c(ids, "ora_filter_mode", "ora_p_column", "ora_effect_column", "padj", "log2fc", "direction")
    if (id == "immune") ids <- c(ids, "immune_source", "immune_terms")
    parameter_ids(unique(ids))
    controls
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
    saved <- isolate(if (in_bulk_step()) bulk()$stage_styles[[bulk_key()]] %or% bulk()$style %or% list() else style_cache[[selected()]] %or% list())
    if (selected() == "figure_layout" && is.null(saved$panel_paper)) saved$panel_paper <- "A4"
    style <- utils::modifyList(defaults$style, saved)
    render_field <- function(name, definition) {
      id <- paste0("style_", name)
      value <- style[[name]]
      control <- switch(definition$type,
        text = textInput(id, definition$label, value, placeholder = definition$placeholder),
        number = numericInput(id, definition$label, value, min = definition$min, max = definition$max, step = definition$step),
        color = if (name %in% c("pathway_target_color", "pathway_target_fill")) div(class = "hex-color-control",
          textInput(id, definition$label, value, placeholder = if (name == "pathway_target_fill") "#FFF2CC 或 transparent" else "#C62828"),
          div(class = "hex-color-preview", `data-color-preview-for` = id,
            `data-allow-transparent` = tolower(as.character(name == "pathway_target_fill")),
            tags$span(class = "hex-color-swatch", `aria-hidden` = "true"), tags$small(class = "hex-color-code")),
          tags$small(class = "hex-color-guidance", if (name == "pathway_target_fill")
            "仅铺在目的通路名称后面。填 # 加 6 位十六进制色，如 #FFF2CC；transparent 表示不填充。"
            else "仅改变目的通路名称的文字。填 # 加 6 位十六进制色，如 #C62828。"))
          else div(class = "color-control", tags$span(class = "color-swatch", style = paste0("background:", value)), textInput(id, definition$label, value)),
        select = selectInput(id, definition$label, definition$choices, selected = value),
        flag = checkboxInput(id, definition$label, value))
      region_on <- "(input.style_pca_ellipse_2d || input.style_pca_ellipse_3d)"
      condition <- if (name %in% c("pca_confidence", "pca_region_type", "pca_region_fill")) region_on
        else if (name == "pca_region_color") paste(region_on, "&& input.style_pca_region_fill === 'solid'")
        else if (name == "pca_region_alpha") paste(region_on, "&& input.style_pca_region_fill !== 'outline'")
        else if (name %in% c("legend_align", "legend_text_size", "legend_title_size", "legend_key_size", "legend_gap")) "input.style_legend_position !== 'none'"
        else if (selected() == "figure_layout" && name %in% c("width", "height")) "input.style_panel_paper === 'custom'"
        else if (name == "panel_orientation") "input.style_panel_paper !== 'custom'"
        else if (name %in% c("enrichment_orientation", "enrichment_bar_width", "enrichment_bar_length")) "input.style_enrichment_kind !== 'dot'"
        else if (name %in% c("enrichment_size_min", "enrichment_size_max")) "input.style_enrichment_kind !== 'bar'" else if (name %in% c("network_low", "network_mid", "network_high")) "input.style_network_color_by === 'auto' || input.style_network_color_by === 'log2FC'" else if (name == "network_node_color") "input.style_network_color_by !== 'log2FC'" else if ((name == "network_label_top" || (selected() == "network" && name == "label_size"))) "input.style_network_labels" else NULL
      explanation <- switch(name,
        heat_cell_width = "设置每一列色块的宽度，填 0 由程序自动安排。宽度合计超过画布时会缩回可用范围，请配合画布尺寸调整。",
        heat_cell_height = "设置每一行色块的高度，填 0 自动安排。行很多时，可增大画布高度；很小的色块会自动缩小文字以避免重叠。",
        show_row_tree = "显示基因或条目的相似关系分支。请先在分析设置里启用行聚类；隐藏树后仍保留已有排列。",
        show_column_tree = "显示样本相似关系的分支。需先启用列聚类；按组聚类时，每一组有自己的分支。",
        reverse_rows = "把行的阅读方向上下颠倒。表达数值、基因名称和注释会一起调整。",
        reverse_columns = "把列的阅读方向左右颠倒。样本名称、分组条和图形内容会同步调整。",
        enrichment_bar_width = "统一调整所有柱子的粗细，数值越大，柱子越粗。各条目的真实比例保持原样。",
        enrichment_bar_length = "调整最长一条柱子占数值轴的比例。较小的百分比会留下更多空白，所有柱子按同一尺度变化，统计值保持原样。",
        z_limit = "控制热图颜色变化到哪一个数值达到最深。超过范围的值使用端点颜色，作图原始数据会完整保留。",
        legend_position = "选择图例放在哪一边。图例会占用独立空间，以减少它与主图相互遮挡。",
        legend_text_size = "调整图例中每个名称的字号。分组名或条目名很长时，可配合图例位置和画布尺寸调整。",
        term_wrap = "通路名称每行最多显示的字符数。调小会换成更多行，调大则名称横向更长。",
        NULL)
      if (!is.null(explanation)) control <- div(`data-help` = explanation, control)
      if (name == "panel_rows") control <- tagList(control, uiOutput("paper_preview"))
      if (is.null(condition)) control else conditionalPanel(condition, control)
    }
    tagList(if (selected() != "figure_layout") tb_palette_ui(style),
      lapply(names(schema), function(group) tags$fieldset(class = "style-group",
      tags$legend(group), div(class = if (group == "目的通路标记") "pathway-color-fields" else "two-columns",
        lapply(names(schema[[group]]), function(name) render_field(name, schema[[group]][[name]]))))),
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

  cache_base <- file.path(app_root, "results", "toolbox", "bulk-cache")
  dir.create(cache_base, recursive = TRUE, showWarnings = FALSE)
  cache_dir <- tempfile("flow-", tmpdir = cache_base)
  dir.create(cache_dir)
  cache_prefix <- paste0("bulk-cache-", substr(session$token, 1, 12))
  addResourcePath(cache_prefix, cache_dir)
  gallery <- reactiveVal(list())
  gallery_mode <- reactiveVal("review")
  gallery_panel <- reactiveVal("")
  auto_panel_count <- reactiveVal(NA_integer_)
  gallery_step <- reactiveVal("")
  flow_draft <- reactiveVal(NULL)
  flow_plan <- reactiveVal(tb_read_settings(app_root)$workflow_preset %or% tb_flow_nodes())
  clear_bulk_cache <- function() {
    parent <- normalizePath(dirname(cache_dir), winslash = "/", mustWork = TRUE)
    if (!identical(parent, normalizePath(cache_base, winslash = "/", mustWork = TRUE))) stop("缓存边界校验失败。")
    files <- list.files(cache_dir, full.names = TRUE)
    if (length(files)) unlink(files, recursive = TRUE)
    gallery(list())
  }
  cache_collect <- function(directory, step) {
    files <- list.files(file.path(directory, "outputs"), pattern = "[.]png$", recursive = TRUE, full.names = TRUE, ignore.case = TRUE)
    items <- isolate(gallery())
    for (file in files) {
      key <- digest::digest(normalizePath(file, winslash = "/"), algo = "md5")
      target <- file.path(cache_dir, paste0(key, ".png"))
      if (!file.copy(file, target, overwrite = TRUE)) stop("无法保存流程图片缓存。")
      items[[key]] <- list(id = key, tool = tb_job_request(directory)$tool, step = step, name = basename(file), path = target,
        size = unname(file.info(target)$size), favorite = isTRUE(items[[key]]$favorite))
    }
    gallery(items)
  }
  show_bulk_gallery <- function(mode, panel = "") {
    gallery_mode(mode); gallery_panel(panel); gallery_step(bulk_key())
    nodes <- tb_flow_nodes(bulk())
    ids <- vapply(nodes, `[[`, character(1), "id")
    labels <- paste(seq_along(nodes), vapply(nodes, function(x) catalog$title[match(x$tool, catalog$id)], character(1)))
    showModal(modalDialog(title = if (mode == "review") "哪些图片值得保留关注？" else "从本次自动化流程挑选", size = "l",
      p(if (mode == "review") "点击图片标记感兴趣；黄色星形表示已标记。这里仅展示当前步骤生成的 PNG，不需要事先下载。"
        else "点击图片即可填入当前组图位置。可按步骤或星标筛选，黄色星形表示之前标记的图片。"),
      if (mode != "review") tagList(
        div(class = "bulk-gallery-stages", paste(labels, collapse = " → ")),
        selectInput("gallery_step", "分析步骤", c("全部" = "all", stats::setNames(ids, labels))),
        checkboxInput("gallery_favorites", "只看感兴趣的图片", FALSE),
        selectInput("gallery_sort", "排序", c("文件大小：从大到小" = "desc", "文件大小：从小到大" = "asc"))),
      uiOutput("bulk_gallery_images"),
      footer = if (mode == "review") tagList(modalButton("返回"), actionButton("bulk_gallery_continue", "完成选择，进入下一步")) else modalButton("关闭")))
  }
  output$bulk_gallery_images <- renderUI({
    items <- gallery()
    if (gallery_mode() == "review") {
      items <- Filter(function(x) identical(x$step, gallery_step()), items)
    } else items <- Filter(function(x) (!isTRUE(input$gallery_favorites) || x$favorite) &&
      ((input$gallery_step %or% "all") == "all" || identical(x$step, input$gallery_step)), items)
    if (!length(items)) return(p(if (gallery_mode() == "review") "本步骤没有可选的 PNG，请返回检查当前任务输出。"
      else "当前筛选下没有图片。可取消感兴趣筛选或切换分析步骤。"))
    order <- order(vapply(items, `[[`, numeric(1), "size"), decreasing = !identical(input$gallery_sort, "asc"))
    div(class = "bulk-gallery", lapply(items[order], function(x) {
      tags$button(type = "button", class = "bulk-gallery-item", `data-gallery-image` = x$id,
        `aria-pressed` = tolower(as.character(x$favorite)),
        tags$img(src = paste0("/", cache_prefix, "/", basename(x$path)), alt = x$name),
        tags$span(class = paste("gallery-star", if (x$favorite) "favorite"), HTML('<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m12 2 3 6 7 1-5 5 1 7-6-3-6 3 1-7-5-5 7-1z"/></svg>')),
        tags$span(paste(catalog$title[match(x$tool, catalog$id)], x$name, paste0(round(x$size / 1024), " KB"))))
    }))
  })
  observeEvent(input$gallery_image, {
    items <- gallery(); item <- items[[input$gallery_image]]; req(item, bulk_active())
    if (gallery_mode() == "review") {
      item$favorite <- !item$favorite; items[[item$id]] <- item; gallery(items)
    } else {
      field <- gallery_panel(); req(field %in% active_fields(), selected() == "figure_layout")
      updateCheckboxInput(session, "panel_auto_favorites", value = FALSE)
      path_cache[[field]] <- item$path
      upload_paths[[field]] <- NULL
      session$sendCustomMessage("upload-state", list(key = field, name = item$name))
      updateTextInput(session, paste0("path_", field), value = item$path)
      removeModal(); showNotification(paste("已添加", item$name))
    }
  })
  observeEvent(input$bulk_pick_panel, {
    req(in_bulk_step(), selected() == "figure_layout", input$bulk_pick_panel %in% active_fields())
    show_bulk_gallery("pick", input$bulk_pick_panel)
  })
  observeEvent(bulk_active(), {
    if (!bulk_active()) {
      save_bulk_progress(); clear_bulk_cache(); bulk(NULL)
      rm(list = ls(bulk_jobs), envir = bulk_jobs)
    }
  }, ignoreInit = TRUE)
  observeEvent(input$platform_project, {
    if (identical(input$platform_project, "biomethod") && bulk_active()) bulk_active(FALSE)
  })
  session$onSessionEnded(function() {
    if (isTRUE(isolate(save_bulk_progress()))) clear_bulk_cache()
    removeResourcePath(cache_prefix)
  })
  observeEvent(input$ppi_cache_image, {
    req(bulk_active(), bulk_step() == "network")
    value <- input$ppi_cache_image
    if (!is.character(value) || length(value) != 1L || nchar(value) > 20000000L || !startsWith(value, "data:image/png;base64,")) return()
    bytes <- base64enc::base64decode(sub("^data:image/png;base64,", "", value))
    if (length(bytes) < 8 || !identical(as.integer(bytes[1:8]), c(137L,80L,78L,71L,13L,10L,26L,10L))) return()
    key <- paste0("ppi-", format(Sys.time(), "%H%M%OS6")); key <- gsub("[^a-zA-Z0-9-]", "", key)
    path <- file.path(cache_dir, paste0(key, ".png")); writeBin(bytes, path)
    items <- gallery(); items[[key]] <- list(id = key, tool = "network", step = bulk_key(), name = "ppi_edited.png", path = path,
      size = length(bytes), favorite = TRUE); gallery(items)
    showNotification("PPI 精细编辑图片已加入本次流程缓存。")
  })
  output$download_bulk_all <- downloadHandler(
    filename = function() paste0(basename(project_folder()), "_", format(Sys.time(), "%Y%m%d%H%M%S", tz = "Asia/Shanghai"), ".zip"),
    content = function(file) {
      tb_bulk_archive(req(bulk()), as.list(bulk_jobs), gallery(), file)
    })

  bulk_jobs <- new.env(parent = emptyenv())
  save_bulk_progress <- function() {
    tryCatch({
      isolate(tb_flow_save(app_root, bulk(), as.list(bulk_jobs), gallery()))
      TRUE
    }, error = function(e) {
      showNotification(paste("流程保存失败：", conditionMessage(e)), type = "error", duration = NULL)
      FALSE
    })
  }
  observeEvent(list(bulk(), gallery()), save_bulk_progress(), ignoreInit = TRUE)
  observeEvent(input$bulk_resume, tryCatch({
    if (!is.null(job()) && job()$process$is_alive()) stop("请等待当前任务完成。")
    saved <- tb_flow_load(app_root)
    if (is.null(saved)) stop("没有可恢复的进度。")
    clear_bulk_cache(); rm(list = ls(bulk_jobs), envir = bulk_jobs)
    for (key in names(saved$jobs)) if (dir.exists(saved$jobs[[key]]$directory))
      bulk_jobs[[key]] <- tb_restored_job(saved$jobs[[key]])
    items <- saved$gallery
    for (key in names(items)) {
      target <- file.path(cache_dir, paste0(key, ".png"))
      if (!file.copy(items[[key]]$path, target, overwrite = TRUE)) stop("流程图片缺失：", items[[key]]$name)
      items[[key]]$path <- target
    }
    gallery(items)
    for (key in names(saved$jobs)) if (identical(tb_read_status(saved$jobs[[key]]$directory)$status, "completed"))
      cache_collect(saved$jobs[[key]]$directory, key)
    open_bulk_step(saved$flow)
    showNotification("已恢复上次流程、参数和选图。")
  }, error = function(e) showNotification(conditionMessage(e), type = "error")))

  bulk_setup_ui <- function() {
    div(class = "workspace tool-workspace",
      div(class = "tool-header", guide_heading("Bulk RNA-seq 自动化分析", "bulk")),
      p(paste(unname(tb_bulk_steps), collapse = " → ")),
      div(class = "tool-layout",
        div(class = "configuration-column",
          div(class = "panel", section_title("01", "分析输入", "计数表记录每个基因在各样本中测到的原始数量，分组表说明样本属于哪个条件。两张表中的样本名应完全一致，也可勾选示例由系统提供。"),
            example_switch(),
            p("完整 RNA-seq 流程请导入 Count 和分组。自定义其他工具时可先选择流程，再在相应步骤上传实际需要的文件。"),
            uiOutput("input_controls")),
          div(class = "panel", section_title("02", "物种与比较", "选择数据对应的人或小鼠，再明确实验组与对照组。后续差异、通路和网络步骤沿用这一比较方向，正的变化值表示实验组更高。"),
            selectInput("species", "物种", tb_species_choices),
            group_mode_ui("bulk", defaults$params),
            actionButton("refresh_groups", "读取当前分组", class = "small-button"),
            textOutput("group_summary"),
            tags$details(tags$summary("共享模型参数"), div(class = "two-columns",
              num("bulk_min_count", "Count 下限", defaults$params$min_count, 0),
              num("bulk_min_samples", "最少样本数", defaults$params$min_samples, 1),
              selectInput("bulk_fit_type", "离散度拟合", c("Parametric" = "parametric", "Local" = "local", "Mean" = "mean")),
              checkboxInput("bulk_batch", "纳入技术批次"),
              textInput("bulk_covariates", "需额外考虑的分组表列名（逗号分隔）")))),
          div(class = "panel",
            selectInput("bulk_palette", "本次流程科研配色（必选）", c("请选择…" = "", stats::setNames(names(tb_palettes()), names(tb_palettes())))),
            help_note("全部步骤默认沿用此配色，仍可单独调整字号、点大小等样式。")),
          if (!is.null(tb_flow_load(app_root))) actionButton("bulk_resume", "恢复上次自动化分析", class = "secondary-button"),
          actionButton("bulk_start", "选择分析流程", class = "primary-button")),
        div(class = "configuration-column",
          div(class = "panel", section_title("03", "通路与互作", "通路分析需要基因集，网络分析需要参考互作。可以选择公共库或自备文件；各步骤运行前还能审核来源、调整筛选和绘图参数。"),
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
    if (in_bulk_step()) {
      key <- bulk_key()
      flow <- bulk(); nodes <- tb_flow_nodes(flow)
      invalid <- vapply(nodes[seq.int(flow$step, length(nodes))], `[[`, character(1), "id")
      for (id in invalid) {
        flow$approved[[id]] <- NULL
        if (exists(id, bulk_jobs, inherits = FALSE)) rm(list = id, envir = bulk_jobs)
      }
      old <- gallery(); remove <- vapply(old, function(x) x$step %in% invalid, logical(1))
      for (x in old[remove]) if (file.exists(x$path)) unlink(x$path)
      gallery(old[!remove])
      flow$furthest <- flow$step
      flow$stage_params[[key]] <- spec$params
      flow$stage_inputs[[key]] <- spec$inputs
      for (field in intersect(c("counts", "groups", "deg"), names(spec$inputs))) {
        path <- spec$inputs[[field]]
        if (nzchar(path) && file.exists(path)) flow$inputs[[field]] <- path
      }
      flow$stage_styles[[key]] <- spec$style
      bulk(flow)
      bulk_jobs[[key]] <- current
      flow <- bulk()
      shared <- c("species", "control", "treatment", "min_count", "min_samples", "alpha", "fit_type", "use_batch", "covariates", "group_mode", "group_subset")
      for (key in intersect(shared, parameter_ids())) flow$params[[key]] <- spec$params[[key]]
      bulk(flow)
      save_bulk_progress()
    }
    sync_pins()
    history_tick(history_tick() + 1L)
    invisible(current)
  }

  open_bulk_step <- function(flow) {
    current <- job()
    node <- tb_flow_nodes(flow)[[flow$step]]
    step <- node$tool
    saved <- bulk_jobs[[node$id]]
    if (!is.null(current) && current$process$is_alive() && !identical(current$directory, saved$directory)) {
      showNotification("请先等待当前任务完成，或取消后再返回流程。", type = "warning")
      return(invisible(NULL))
    }
    bulk(flow)
    bulk_active(TRUE)
    choose_tool(step)
    restore_job(saved)
    if (!is.null(saved)) {
      request <- readRDS(file.path(saved$directory, "request.rds"))
      session$onFlushed(function() {
        for (id in intersect(names(request$params), c(isolate(parameter_ids()), if (step == "figure_layout") "panel_count"))) session$sendInputMessage(id, list(value = request$params[[id]]))
        if (step == "go") updateCheckboxGroupInput(session, "go_ontology_multi", selected = request$params$go_ontology)
        style_ids <- unique(c(names(do.call(c, unname(tb_style_schema(step)))), "formats", "gradient"))
        for (id in intersect(names(request$style), style_ids)) session$sendInputMessage(paste0("style_", id), list(value = request$style[[id]]))
      }, once = TRUE)
    }
    invisible(NULL)
  }

  observeEvent(input$bulk_start, {
    if (selected() != "bulk" || (!is.null(job()) && job()$process$is_alive())) return()
    tryCatch({
      palette <- tb_palettes()[[input$bulk_palette %or% ""]]
      if (is.null(palette)) stop("请先选择本次流程的科研配色。")
      palette$gradient <- paste(palette$colors %or% unlist(palette[c("low", "mid", "high")]), collapse = ";")
      fields <- active_fields()
      paths <- stats::setNames(lapply(fields, read_input), fields)
      has_groups <- nzchar(paths$groups %or% "") && file.exists(paths$groups)
      groups <- if (has_groups) unique(tb_read_groups(paths$groups)$condition) else c("Control", "Treatment")
      mode <- if (has_groups) input$group_mode %or% "pair" else "pair"
      subset <- input$group_subset %or% character()
      included <- if (length(subset) && mode != "pair") intersect(groups, subset) else groups
      if (length(included) < 2L) stop("至少纳入两个组。")
      contrast <- switch(mode, pair = if (has_groups) c(input$control, input$treatment) else c("Control", "Treatment"),
        reference = c(input$control, setdiff(included, input$control)[1L]), all_pairs = included[1:2])
      if (length(contrast) != 2L || anyDuplicated(contrast) || !all(contrast %in% included))
        stop("请先读取分组表，并选择两个不同的组。")
      ids <- c(go = trimws(input$bulk_go), kegg = trimws(input$bulk_kegg),
        gsea = trimws(input$bulk_gsea), gsva = trimws(input$bulk_gsva))
      if (length(tb_parse_terms(ids[["gsea"]])) > 1L) stop("GSEA 曲线只接受一个条目 ID。")
      synthetic <- example_checked() && example_dataset() == "synthetic"
      custom <- isTRUE(input$bulk_custom)
      if (custom && (!file.exists(paths$gmt) || !nzchar(trimws(input$bulk_gmt_version))))
        stop("自建注释需要上传 GMT 并填写来源与版本。")
      preset <- if (example_checked()) example_preset()
      species <- preset$species %or% input$species
      parameters <- list(species = species, control = contrast[1L], treatment = contrast[2L],
        group_mode = mode, group_subset = subset,
        min_count = input$bulk_min_count, min_samples = input$bulk_min_samples, fit_type = input$bulk_fit_type,
        use_batch = isTRUE(input$bulk_batch), covariates = input$bulk_covariates %or% "",
        database_version = if (synthetic) "biometa synthetic example" else input$bulk_gmt_version,
        gmt_id_type = if (synthetic) "gene_id" else input$bulk_gmt_id)
      flow <- list(id = basename(tempfile("flow-")), style = palette, palette_name = input$bulk_palette, step = 1L, furthest = 1L, nodes = flow_plan(), stage_params = list(), inputs = paths, params = parameters, terms = ids,
        custom = custom, synthetic = synthetic, approved = list(), skipped = list(),
        project_name = basename(project_folder()))
      flow_draft(flow)
      showModal(modalDialog(title = "选择本次分析流程", size = "l",
        radioButtons("flow_plan_mode", "流程方案", c("默认完整流程" = "default", "自定义 / 本地预设" = "custom"), selected = if (is.null(tb_read_settings(app_root)$workflow_preset)) "default" else "custom"),
        selectInput("flow_add_tool", "添加工作站已有分析", stats::setNames(catalog$id, catalog$title)),
        actionButton("flow_add", "添加步骤"), uiOutput("flow_plan_editor"),
        checkboxInput("flow_save_preset", "保存为下次自定义预设（保留在本机设置中）", FALSE),
        footer = tagList(modalButton("返回"), actionButton("flow_plan_start", "确认流程，进入第一步"))))
    }, error = function(e) showNotification(conditionMessage(e), type = "error", duration = 15))
  })

  output$flow_plan_editor <- renderUI({
    nodes <- if (identical(input$flow_plan_mode, "default")) tb_flow_nodes() else flow_plan()
    if (!length(nodes)) return(p("尚未选择步骤，请从上方添加本次需要的分析。"))
    tags$ol(class = "flow-plan-editor", lapply(seq_along(nodes), function(i) {
      node <- nodes[[i]]
      tags$li(`data-flow-index` = i, tags$button(type = "button", draggable = "true", `data-flow-drag` = i,
        `aria-label` = "拖动调整步骤", class = "flow-handle", HTML('<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 6h16M4 12h16M4 18h16"/></svg>')),
        span(paste(i, catalog$title[match(node$tool, catalog$id)])),
        tags$button(type = "button", `data-flow-remove` = i, "删除"))
    }))
  })
  observeEvent(input$flow_add, {
    req(input$flow_add_tool %in% catalog$id)
    nodes <- if (identical(input$flow_plan_mode, "default")) tb_flow_nodes() else flow_plan()
    tools <- vapply(nodes, `[[`, character(1), "tool")
    flow_plan(tb_flow_nodes_from_tools(c(tools, input$flow_add_tool)))
    updateRadioButtons(session, "flow_plan_mode", selected = "custom")
  })
  observeEvent(input$flow_remove, {
    i <- as.integer(input$flow_remove); nodes <- if (identical(input$flow_plan_mode, "default")) tb_flow_nodes() else flow_plan()
    if (!is.na(i) && i >= 1L && i <= length(nodes)) flow_plan(nodes[-i])
    updateRadioButtons(session, "flow_plan_mode", selected = "custom")
  })
  observeEvent(input$flow_reorder, {
    order <- as.integer(unlist(input$flow_reorder)); nodes <- if (identical(input$flow_plan_mode, "default")) tb_flow_nodes() else flow_plan()
    if (length(order) == length(nodes) && setequal(order, seq_along(nodes))) flow_plan(nodes[order])
    updateRadioButtons(session, "flow_plan_mode", selected = "custom")
  })
  observeEvent(input$flow_plan_start, tryCatch({
    nodes <- if (identical(input$flow_plan_mode, "default")) tb_flow_nodes() else flow_plan()
    tb_flow_validate(nodes, catalog$id)
    flow <- req(flow_draft()); flow$nodes <- nodes
    if (isTRUE(input$flow_save_preset)) {
      cfg <- tb_read_settings(app_root); cfg$workflow_preset <- nodes; tb_save_settings(app_root, cfg)
    }
    tb_flow_forget(app_root)
    clear_bulk_cache(); rm(list = ls(bulk_jobs), envir = bulk_jobs)
    flow_plan(nodes); flow_draft(NULL); removeModal(); open_bulk_step(flow)
    save_bulk_progress()
  }, error = function(e) showNotification(conditionMessage(e), type = "error")))

  output$bulk_progress <- renderUI({
    flow <- req(bulk())
    step <- req(bulk_step())
    current <- job()
    match_job <- !is.null(current) && identical(current$directory, bulk_jobs[[bulk_key()]]$directory)
    complete <- match_job && identical(result()$status, "completed")
    div(class = "panel bulk-progress",
      tags$ol(lapply(seq_along(tb_flow_nodes(flow)), function(i) {
        node <- tb_flow_nodes(flow)[[i]]
        tags$li(class = if (i == flow$step) "current" else if (!is.null(flow$approved[[node$id]])) "approved",
          tags$button(type = "button", `data-bulk-jump` = node$id,
            disabled = if (i > (flow$furthest %or% flow$step)) "disabled",
            `aria-current` = if (i == flow$step) "step", catalog$title[match(node$tool, catalog$id)]))
      })),
      if (step == "figure_layout") p("可从本次流程缓存挑选图片，也可以拖拽或浏览本地图片。设置序号样式后点击运行组图。")
      else if (step == "network" && is.null(current)) p("请补交本地互作 Edge 表，再运行本步。"),
      if (step == "pca" && !complete && (is.null(current) || !current$process$is_alive()))
        actionButton("bulk_back_setup", "返回输入设置", class = "secondary-button"),
      if (complete && flow$step < length(tb_flow_nodes(flow))) actionButton("bulk_next", "下一步 · 挑选图片", class = "primary-button"),
      if (flow$step == length(tb_flow_nodes(flow)) && complete) downloadButton("download_bulk_all", "下载全流程结果"),
      if (flow$step == length(tb_flow_nodes(flow)) && complete) actionButton("bulk_new", "新建 Bulk 流程", class = "secondary-button"))
  })

  advance_bulk <- function() {
    flow <- req(bulk()); step <- bulk_step(); key <- bulk_key()
    current <- req(job())
    req(identical(current$directory, bulk_jobs[[key]]$directory), identical(result()$status, "completed"))
    flow$approved[[key]] <- current$directory
    if (step == "deg") flow$params[c("padj", "log2fc", "direction")] <- last_spec()$params[c("padj", "log2fc", "direction")]
    if (flow$step < length(tb_flow_nodes(flow))) {
      flow$step <- flow$step + 1L
      flow$furthest <- max(flow$furthest %or% 1L, flow$step)
      open_bulk_step(flow)
    }
  }
  observeEvent(input$bulk_jump, {
    flow <- req(bulk())
    nodes <- tb_flow_nodes(flow)
    index <- match(input$bulk_jump, vapply(nodes, `[[`, character(1), "id"))
    if (is.na(index) || index > (flow$furthest %or% flow$step)) return()
    if (!is.null(job()) && job()$process$is_alive()) return(showNotification("请先完成或取消当前任务。", type = "warning"))
    flow$step <- index; open_bulk_step(flow)
  })
  observeEvent(input$bulk_next, {
    cache_collect(req(visible_job())$directory, bulk_key())
    show_bulk_gallery("review")
  })
  observeEvent(input$bulk_gallery_continue, { removeModal(); advance_bulk() })
  reset_bulk <- function() {
    tb_flow_forget(app_root)
    clear_bulk_cache()
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
    req(bulk()$step == length(tb_flow_nodes(bulk())), identical(result()$status, "completed"))
    reset_bulk()
  })

  for (key in tb_panel_fields(12)) local({
    field <- key
    output[[paste0("panel_thumb_", field)]] <- renderImage({
      req(selected() == "figure_layout")
      path <- read_input(field)
      req(nzchar(path), file.exists(path))
      extension <- tolower(tools::file_ext(path))
      if (extension %in% c("tif", "tiff")) {
        image <- magick::image_resize(magick::image_read(path)[1], "120x120")
        path <- tempfile(fileext = ".png"); magick::image_write(image, path)
      }
      list(src = path, alt = basename(path), width = "90px", height = "90px")
    }, deleteFile = FALSE)
  })
  observeEvent(input$figure_order, {
    req(selected() == "figure_layout")
    fields <- active_fields(); order <- unlist(input$figure_order, use.names = FALSE)
    if (length(order) != length(fields) || !setequal(order, fields)) return()
    paths <- stats::setNames(lapply(fields, read_input), fields)
    uploads <- stats::setNames(lapply(fields, function(x) upload_paths[[x]]), fields)
    weights <- stats::setNames(lapply(fields, function(x) input[[paste0("weight_", x)]] %or% 100), fields)
    updateCheckboxInput(session, "panel_auto_favorites", value = FALSE)
    for (i in seq_along(fields)) {
      field <- fields[i]; from <- order[i]
      path_cache[[field]] <- paths[[from]]; upload_paths[[field]] <- uploads[[from]]
      updateTextInput(session, paste0("path_", field), value = paths[[from]])
      updateSliderInput(session, paste0("weight_", field), value = weights[[from]])
      cached <- Filter(function(x) identical(x$path, paths[[from]]), gallery())
      session$sendCustomMessage("upload-state", list(key = field,
        name = uploads[[from]]$name %or% if (length(cached)) cached[[1L]]$name
          else if (nzchar(paths[[from]])) basename(paths[[from]]) else ""))
    }
  })
  observeEvent(input$panel_count, {
    if (selected() == "figure_layout" && isTRUE(input$panel_auto_favorites) &&
        !is.na(auto_panel_count()) && !identical(as.integer(input$panel_count), as.integer(auto_panel_count())))
      updateCheckboxInput(session, "panel_auto_favorites", value = FALSE)
  })
  observeEvent(list(input$panel_auto_favorites, gallery()), {
    req(selected() == "figure_layout", bulk_active(), isTRUE(input$panel_auto_favorites))
    items <- Filter(function(x) isTRUE(x$favorite), gallery())
    if (!length(items)) return(showNotification("还没有标星的图片，请先从本次流程中挑选。", type = "warning"))
    keys <- vapply(tb_flow_nodes(bulk()), `[[`, character(1), "id")
    items <- items[order(vapply(items, function(x) match(x$step, keys), integer(1)))]
    if (length(items) > 12L) showNotification("单次组图最多 12 张，已按流程顺序填入前 12 张标星图片。", type = "warning")
    items <- head(items, 12L)
    auto_panel_count(length(items))
    updateNumericInput(session, "panel_count", value = length(items))
    for (i in seq_along(items)) path_cache[[tb_panel_fields(length(items))[i]]] <- items[[i]]$path
    session$onFlushed(function() {
      for (i in seq_along(items)) {
        field <- tb_panel_fields(length(items))[i]
        upload_paths[[field]] <- NULL
        updateTextInput(session, paste0("path_", field), value = items[[i]]$path)
        session$sendCustomMessage("upload-state", list(key = field, name = items[[i]]$name))
      }
    }, once = TRUE)
  }, ignoreInit = TRUE)

  figure_input <- function(name) {
    read_input(name)
  }


  output$ora_metric_controls <- renderUI({
    req(selected() %in% c("go", "kegg"))
    base <- if (in_bulk_step()) tb_bulk_spec(bulk(), selected(), defaults) else NULL
    path <- if (!is.null(base) && !"deg" %in% active_fields()) base$inputs$deg %or% "" else read_input("deg")
    data <- if (nzchar(path) && file.exists(path)) tb_read_preview(path, n = 25) else NULL
    initial <- base$params %or% defaults$params
    columns <- if (is.null(data)) unique(unlist(tb_metric_aliases)) else names(data)[vapply(data, function(x) {
      values <- suppressWarnings(as.numeric(x))
      any(is.finite(values)) && !any(is.na(values) & !is.na(x) & nzchar(trimws(as.character(x))))
    }, logical(1))]
    columns <- setdiff(columns, c("gene_id", "gene_name", "ENTREZID", "GeneID"))
    pick <- function(id, kind) {
      previous <- isolate(input[[id]]) %or% initial[[id]]
      if (nzchar(previous) && previous %in% columns) return(previous)
      known <- intersect(tb_metric_aliases[[kind]], columns)
      if (length(known)) known[1L] else ""
    }
    div(class = "ora-metric-controls",
      h4("候选基因筛选"),
      p(if (is.null(data)) "使用前置差异分析的结果列；上传 DEG 后会显示该文件的实际数值列。"
        else paste("已读取 DEG 的实际列：", paste(names(data), collapse = "、"))),
      selectInput("ora_filter_mode", "筛选依据",
        c("自动按可用列组合" = "auto", "显著性与变化幅度" = "both", "仅显著性" = "probability", "仅变化幅度" = "effect"),
        selected = initial$ora_filter_mode),
      selectInput("ora_p_column", "显著性列 · 原始 P / Adjusted P / FDR", c("自动识别" = "", stats::setNames(columns, columns)),
        selected = pick("ora_p_column", "probability")),
      numericInput("padj", "所选显著性列上限", initial$padj, min = .000001, max = 1, step = .01),
      selectInput("ora_effect_column", "变化幅度列 · logFC", c("自动识别" = "", stats::setNames(columns, columns)),
        selected = pick("ora_effect_column", "effect")),
      numericInput("log2fc", "变化幅度绝对值下限", initial$log2fc, min = 0, step = .1),
      selectInput("direction", "候选基因方向", c("全部" = "all", "上调" = "up", "下调" = "down"), selected = initial$direction),
      help_note("只按显著性时不要求 logFC；只按变化幅度时不要求显著性列。上调或下调仍需要 logFC。显著性筛选时，背景优先用有效原始 P 值，没有时使用所选显著性列；仅变化模式用有效变化值。再与注释成员匹配。"))
  })
  output$pathway_mapping_controls <- renderUI({
    req(selected() %in% tb_pathway_tools)
    base <- if (in_bulk_step()) tb_bulk_spec(bulk(), selected(), defaults) else NULL
    mapping_path <- function(key) {
      if (!is.null(base) && !key %in% active_fields()) return(base$inputs[[key]] %or% "")
      read_input(key)
    }
    path <- mapping_path(if (selected() == "gsva") "matrix" else "deg")
    if (!nzchar(path) || !file.exists(path)) path <- mapping_path("counts")
    columns <- if (length(path) && file.exists(path)) tryCatch(names(tb_read_preview(path, n = 1)), error = function(e) character()) else character()
    tags$details(tags$summary("基因编号与名称映射"),
      p("稳定编号优先决定基因身份。历史别名和未证实的名称差异会记录警告；名称明确指向另一个稳定编号时中止。请先核对映射报告与原注释；确认编号可信后，可主动选择仅使用编号。该选择不修改原始文件，仍检查编号格式、物种和多重映射。"),
      selectInput("gene_id_column", "编号列", c("自动识别" = "", stats::setNames(columns, columns)),
        selected = isolate(input$gene_id_column) %or% ""),
      selectInput("gene_name_column", "基因名称映射列", c("自动识别" = "", "仅使用编号（确认后不使用名称校验）" = "__id_only__", stats::setNames(columns, columns)),
        selected = isolate(input$gene_name_column) %or% ""))
  })
  observeEvent(input$go_select_all, updateCheckboxGroupInput(session, "go_ontology_multi", selected = tb_go_ontologies("ALL")))

  collect_spec <- function() {
    req(selected() != "home")
    parameters <- if (in_bulk_step()) tb_bulk_spec(bulk(), selected(), defaults)$params else defaults$params
    for (name in intersect(names(parameters), c(parameter_ids(), if (selected() == "figure_layout") "panel_count"))) {
      value <- input[[name]]
      if (!is.null(value)) parameters[[name]] <- value
    }
    if (selected() == "go") parameters$go_ontology <- if (parameters$go_output_scope == "single")
      input$go_ontology_multi %or% character() else c("BP", "CC", "MF")
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
    style <- if (in_bulk_step()) tb_bulk_spec(bulk(), selected(), defaults)$style else defaults$style
    for (name in names(do.call(c, unname(tb_style_schema(selected()))))) {
      value <- input[[paste0("style_", name)]]
      if (!is.null(value)) style[[name]] <- value
    }
    style$gradient <- input$style_gradient %or% style$gradient %or% ""
    style$formats <- if (selected() == "deg") defaults$style$formats else input$style_formats %or% style$formats
    fields <- active_fields()
    inputs <- stats::setNames(lapply(fields, if (selected() == "figure_layout") figure_input else read_input), fields)
    preset <- if (example_checked()) example_preset()
    if (!is.null(preset)) parameters$species <- preset$species
    if ("gmt" %in% fields && example_checked("gmt") && nzchar(example_path("gmt")) &&
        (identical(parameters$pathway_source, "custom") || identical(parameters$immune_source, "custom"))) {
      parameters$database_version <- "biometa synthetic example"
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
      project_name = basename(project_folder()),
      input_names = stats::setNames(input_names, fields))
    if (in_bulk_step() && selected() == "figure_layout") {
      flow <- bulk()
      spec$bulk_review <- list(approved_jobs = lapply(flow$approved, basename), skipped = flow$skipped)
    }
    if (in_bulk_step() && selected() != "figure_layout") {
      base <- tb_bulk_spec(bulk(), selected(), defaults)
      fixed <- c("ppi_require_edges", "ppi_reference", "downstream_input")
      spec$params[fixed] <- base$params[fixed]
      if (selected() == "heatmap" && spec$params$group_mode != "pair") spec$params$heatmap_mode <- "deg"
      for (key in names(spec$inputs)) if (!nzchar(spec$inputs[[key]] %or% "")) spec$inputs[[key]] <- base$inputs[[key]] %or% ""
      spec$inputs <- utils::modifyList(base$inputs, spec$inputs)
      spec$style$formats <- unique(c(spec$style$formats, "png"))
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
          if (in_bulk_step()) { cache_collect(current$directory, bulk_key()); save_bulk_progress() }
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
  observe({
    current <- job()
    state <- result()
    busy <- !is.null(current) && !is.null(state) && state$status %in% c("queued", "running")
    session$sendCustomMessage("analysis-state", list(busy = busy))
  })
  output$analysis_steps <- renderUI({
    state <- visible_result()
    status <- state$status %or% "idle"
    active <- if (status == "completed") 4L else if (status %in% c("queued", "running")) 3L else 1L
    tags$ol(class = "analysis-steps", lapply(seq_len(4), function(i)
      tags$li(class = if (i == active) "current" else if (i < active) "done" else "",
        `aria-current` = if (i == active) "step", c("输入数据", "分析参数", "执行分析", "结果导出")[i])))
  })
  output$job_status <- renderUI({
    state <- visible_result()
    if (is.null(state)) return(div(class = "status-card status-idle", span(class = "status-dot"),
      div(strong("待运行"), `data-help` = "先提供当前工具需要的文件，再确认分组、比较方向和筛选条件，最后点击运行。完成后可查看图片与数据表；仅改颜色或字号时使用重新绘图。")))
    labels <- c(queued = "排队中", running = "正在计算", completed = "任务完成", failed = "运行失败", cancelled = "已取消")
    div(class = paste("status-card", paste0("status-", state$status)), `data-job-id` = visible_job()$id, span(class = "status-dot"),
      div(strong(labels[[state$status]] %or% state$status),
          if (!is.null(state$error) && nzchar(state$error)) tags$pre(class = "task-error", state$error)
          else p(paste(state$summary %or% "计算状态与日志实时更新。", collapse = " · ")),
          if (state$status == "failed" && grepl("BW-M02", state$error %or% "", fixed = TRUE))
            actionButton("review_mapping_conflicts", "查看冲突与编号运行选项", class = "secondary-button"),
          if (state$status %in% c("queued", "running", "completed")) {
            progress <- max(0, min(100, as.numeric(state$progress %or% 0)))
            tagList(div(class = "execution-progress", role = "progressbar", `aria-label` = "后台分析进度",
              `aria-valuenow` = progress, `aria-valuemin` = 0, `aria-valuemax` = 100,
              span(style = paste0("width:", progress, "%"))),
              span(class = "execution-percent", paste0(progress, "% · 后台阶段进度")))
          }),
      if (state$status %in% c("queued", "running")) actionButton("cancel_job", "取消", class = "small-button"))
  })
  observeEvent(input$review_mapping_conflicts, {
    req(visible_result()$status == "failed")
    path <- file.path(visible_job()$directory, "outputs/public_gene_mapping.csv")
    req(file.exists(path))
    rows <- read.csv(path, colClasses = "character", check.names = FALSE)
    rows <- rows[rows$conflict_reason == "confirmed_cross_gene", , drop = FALSE]
    columns <- intersect(c("input_id", "input_symbol", "database_symbol", "resolved_id", "symbol_resolved_ids", "symbol_ensembl_ids"), names(rows))
    showModal(modalDialog(title = "核对基因身份", size = "l",
      p("当前数据库将下列名称指向不同基因。请根据原始注释核实，不能仅因这些基因不显著就忽略。确认稳定编号可信后，可以不使用辅助名称列；原始文件保持原样，物种、格式与多重映射仍检查。"),
      div(style = "overflow-x:auto", tags$table(class = "table", tags$thead(tags$tr(lapply(columns, tags$th))),
        tags$tbody(lapply(seq_len(nrow(rows)), function(i) tags$tr(lapply(columns, function(key) tags$td(rows[[key]][i]))))))),
      footer = tagList(modalButton("保留严格校验"), actionButton("accept_primary_ids", "确认仅使用稳定编号", class = "primary-button"))))
  })
  observeEvent(input$accept_primary_ids, {
    req(visible_result()$status == "failed", grepl("BW-M02", visible_result()$error, fixed = TRUE))
    updateSelectInput(session, "gene_name_column", selected = "__id_only__")
    removeModal()
    showNotification("已选择仅使用编号。请确认当前输入文件与参数，再点击运行当前工具。", duration = 12)
  })
  output$mapping_quality <- renderUI({
    state <- visible_result(); current <- visible_job()
    if (is.null(state) || is.null(current)) return(NULL)
    path <- file.path(current$directory, "outputs/mapping_quality.json")
    if (!file.exists(path)) return(NULL)
    data <- tryCatch(jsonlite::read_json(path, simplifyVector = TRUE), error = function(e) NULL)
    if (is.null(data)) return(NULL)
    fields <- c(input_genes = "输入基因", mapped_genes = "成功映射", unmapped_genes = "未映射（含多重映射）",
      alias_or_name_updates = "别名或名称差异", confirmed_conflicts = "确认冲突", annotated_genes = "具有所选库注释",
      candidate_genes = "按阈值选中", final_universe_genes = "最终富集背景", final_enrichment_genes = "最终参与富集")
    tags$details(class = "mapping-quality", tags$summary(paste0("基因映射质量 · ", data$mapped_genes, "/", data$input_genes,
      "（", round(100 * data$mapped_fraction, 1), "%）")),
      p(paste(data$species, data$source, data$version, "·", data$mode %or% "映射检查")),
      tags$dl(lapply(intersect(names(fields), names(data)), function(key) tagList(tags$dt(fields[[key]]), tags$dd(data[[key]])))),
      p("名称差异与未映射已逐行记录于 public_gene_mapping.csv。名称未被证实错误不代表历史名称已获证实；最终统计以稳定编号和所选筛选规则为准。"))
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
    if (selected() == "go") images <- images[order(!grepl("go_BP_CC_MF_", basename(images), fixed = TRUE))]
    names <- if (selected() == "gsea") tb_gsea_image_labels(images) else basename(images)
    if (selected() == "go") {
      combined <- grepl("go_BP_CC_MF_", basename(images), fixed = TRUE)
      names[combined] <- paste("GO · BP / CC / MF 合并 ·",
        ifelse(grepl("barplot", names[combined]), "柱形图", "气泡图"))
    }
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
    if (!length(network)) return(div(class = "preview-empty", h4("等待网络结果"), `data-help` = "网络计算完成后，这里会显示基因或蛋白之间的连接。可拖动节点、滚轮缩放或切换布局；点击精细编辑可打开独立窗口继续筛选和排版。", tabindex = "0"))
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
      tb_output_name(image, selected())
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
      help_note("为便于浏览，界面最多显示前 200 行，这不表示分析只用了这些行。下载所选文件或整个结果包可以取得完整数据，保留表头便于后续复核。"))
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
    filename = function() tb_output_name(req(input$download_file_choice), selected()),
    content = function(file) {
      req(input$download_file_choice %in% completed_files())
      file.copy(input$download_file_choice, file, overwrite = TRUE)
    })
  output$download_zip <- downloadHandler(
    filename = function() tb_archive_name(req(visible_job())$directory, basename(project_folder())),
    content = function(file) {
      req(visible_result()$status == "completed")
      tb_zip_results(visible_job()$directory, file)
    }, contentType = "application/zip")
  output$download_recipe <- downloadHandler(
    filename = function() paste0("reproduce-", last_spec()$tool, ".R"),
    content = function(file) {
      req(visible_job(), last_spec())
      tb_write_reproduce(tb_job_request(req(visible_job())$directory), file, app_root)
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
          filename = function() tb_archive_name(path, basename(project_folder())),
          content = function(file) { req(dir.exists(path)); tb_zip_outputs(path, file) },
          contentType = "application/zip")
        downloadLink(key, "快速导出", class = "small-button")
      }
      failed <- identical(runs$status[i], "failed")
      diagnostic <- if (failed) {
        key <- paste0(if (modal) "history_debug_" else "recent_debug_", gsub("-", "_", runs$id[i]))
        output[[key]] <- downloadHandler(
          filename = function() sub("[.]zip$", "_debug.zip", tb_archive_name(path, basename(project_folder()))),
          content = function(file) tb_zip_diagnostics(path, file, app_root), contentType = "application/zip")
        downloadLink(key, "导出日志", class = "small-button diagnostic-export", title = "包含本任务输入、参数、样式、完整日志与脚本；可供本地排查。")
      } else tags$button(type = "button", class = "small-button diagnostic-disabled", disabled = "disabled",
        title = "仅失败任务提供诊断包", "导出日志")
      div(class = "history-item", div(strong(if (is.na(title)) runs$tool[i] else title),
          tags$small(runs$created[i], " · ", runs$id[i])),
        span(class = paste("history-status", paste0("history-", runs$status[i])), runs$status[i]),
        div(class = "history-actions",
          tags$button(type = "button", class = "small-button", `data-run` = path, "查看"),
          quick,
          diagnostic,
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

attr(ui, "http_methods_supported") <- c("GET", "POST", "PUT", "DELETE", "PATCH")
shinyApp(ui, server, uiPattern = ".*")
