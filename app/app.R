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
options(shiny.maxRequestSize = 1024^3) # 单文件上传上限 1 GiB；较大文件使用本地路径。

catalog <- tb_tool_catalog()
defaults <- tb_default_settings(dirname(app_root))
`%or%` <- function(x, y) if (is.null(x) || !length(x)) y else x
tool_help <- list(
  pca = "对计数矩阵进行 DESeq2/VST 转换，选择高变基因后计算 PCA。中心化、是否标准化和基因数都会影响坐标。",
  deg = "使用原始整数 Count 拟合 DESeq2。正 log2FC 表示实验组相对对照组上调；FDR 与展示筛选阈值分别设置。",
  volcano = "按校正 P 值与 log2FC 阈值分类，输出火山图和入图数据。直接导入已有差异表时保持原始统计结果；比较组名称仅作说明，不会重新计算比较。留空差异表才使用 Count 模型。",
  heatmap = "从差异基因或高变基因中选取表达矩阵。逐行 Z-score 用于比较同一基因在样本间的变化，不表示基因间绝对表达量。",
  custom_heatmap = "沿用项目自定义基因热图，按目标列表绘制 Count 表达。默认 log₂(count + 1)，可切换 log CPM、VST 或不变换；匹配和重复处理沿用原脚本。",
  manual_heatmap = "使用项目原有手工通路注释热图流程。提供 pathway_annotation.xlsx，保留同一基因在多个通路中的重复展示及已确认样式。",
  go = "使用本机小鼠 GO 注释或固定版本的本地 GMT 做过度富集分析。背景来自实际受检且可映射的基因。",
  kegg = "使用已下载且明确版本的 KEGG GMT 做富集。请确认 GMT 的 ID 类型与项目一致；不会静默联网下载数据库。",
  gsea = "使用完整有效统计量排序做 GSEA，不先筛选显著差异基因。结果取决于排名、基因集和随机种子。",
  gsva = "对表达矩阵计算通路分数，再按分组建模。输入本地固定版本 GMT；通路分数不等于基因表达量。",
  network = "Node 与 Edge 分别上传。自动匹配 id、STRING_id 或 gene_id；支持 from/to、source/target。文件模式直接绘制已有网络，不重新拟合差异模型。",
  matrix_pca = "直接分析数值矩阵，不执行 RNA-seq 标准化。首列为行名、首行为样本名；样本按列排列。",
  matrix_heatmap = "直接绘制通用数值矩阵，可选择 log2 变换、行 Z-score、行列聚类及距离方法。",
  circos = "使用染色体长度、区域特征和区间连线绘制环形图。输入 Tab 分隔文件，单位统一为碱基 bp。"
)
input_meta <- list(
  counts = c("原始计数矩阵", "CSV；gene_id、gene_name 与原始样本列。Count 必须为非负整数。", ".csv,.tsv,.txt"),
  groups = c("样本分组表", "CSV；支持项目的 Sample/Group 或工作台的 sample_id/condition 表。", ".csv,.tsv,.txt"),
  targets = c("目标基因表", "CSV；GeneKey、可选 Pathway 和 Use。Count 热图按基因名或 ID 匹配，忽略大小写。", ".csv,.tsv,.txt"),
  annotation = c("手工通路注释", "Excel；使用当前项目 pathway_annotation.xlsx 的字段与工作表。", ".xlsx"),
  gmt = c("本地基因集", "GMT；每行：通路 ID、描述、基因列表，以 Tab 分隔。", ".gmt"),
  nodes = c("Node · 节点表", "CSV / TSV；id、STRING_id 或 gene_id；可附 label、gene_name、log2FC、group。", ".csv,.tsv,.txt"),
  edges = c("Edge · 连线表", "CSV / TSV；from,to 或 source,target；可附 score / combined_score。", ".csv,.tsv,.txt"),
  matrix = c("数值矩阵", "CSV / TSV；第一列为行标识，其他列为样本数值，不含额外注释列。", ".csv,.tsv,.txt"),
  deg = c("已有差异结果（可选）", "不填时从 Count 分析。支持项目差异结果列及工作台标准结果。", ".csv,.tsv,.txt"),
  chromosomes = c("染色体长度", "CSV / TSV，含表头 chr,length；长度单位 bp。", ".tsv,.txt,.csv"),
  features = c("区域特征（可选）", "CSV / TSV，含表头 chr,start,end,label；0 起点、半开区间。", ".tsv,.txt,.csv"),
  links = c("区间连线（可选）", "CSV / TSV，含表头 chr1,start1,end1,chr2,start2,end2。", ".tsv,.txt,.csv")
)
tool_inputs <- list(
  pca = c("counts", "groups"), deg = c("counts", "groups"),
  volcano = c("counts", "groups", "deg"), heatmap = c("counts", "groups"),
  custom_heatmap = c("counts", "groups", "targets"),
  manual_heatmap = c("counts", "groups", "annotation"),
  go = c("counts", "groups", "gmt"), kegg = c("counts", "groups", "gmt"),
  gsea = c("counts", "groups", "gmt"), gsva = c("counts", "groups", "gmt"),
  network = c("nodes", "edges"),
  matrix_pca = c("matrix", "groups"), matrix_heatmap = c("matrix", "groups"),
  circos = c("chromosomes", "features", "links")
)

# Explanation is attached to its local control after Shiny renders dynamic inputs.
help_note <- function(text) tags$span(class = "context-note", `data-note` = text, hidden = "hidden")
icon_mark <- function(text) span(class = "tool-mark", text)
section_title <- function(number, title, hint = NULL) {
  div(class = "section-heading", span(class = "step-index", number),
      div(h3(title, `data-help` = hint, tabindex = if (!is.null(hint)) "0")))
}
file_control <- function(name, value = NULL) {
  meta <- input_meta[[name]]
  div(class = "file-control", `data-help` = meta[2], textInput(paste0("path_", name), meta[1],
      value = value %or% defaults$inputs[[name]] %or% "", placeholder = "本机路径 / 上传文件"),
      div(class = "upload-line", fileInput(paste0("upload_", name), NULL,
          buttonLabel = "选择文件", placeholder = "使用本地路径", accept = meta[3])))
}
num <- function(name, label, default, min = 0, max = NA, step = 1) {
  numericInput(name, label, value = defaults$params[[name]] %or% default,
               min = min, max = max, step = step)
}
check <- function(name, label, default = FALSE) {
  checkboxInput(name, label, defaults$params[[name]] %or% default)
}

ui <- fluidPage(
  tags$head(tags$title("生信工作台 · BioWorkbench"),
    tags$meta(name = "viewport", content = "width=device-width, initial-scale=1"),
    tags$link(rel = "stylesheet", href = "toolbox.css"),
    tags$link(rel = "stylesheet", href = "studio.css"),
    tags$script(src = "toolbox.js")),
  div(class = "app-shell",
    tags$aside(class = "sidebar",
      div(class = "brand", div(class = "brand-symbol", "B"),
        div(strong("图谱工作室"), tags$small("BIOWORKBENCH"))),
      div(class = "sidebar-project", span(class = "live-dot"), "本地项目",
          strong(basename(dirname(app_root)))),
      textInput("tool_search", NULL, placeholder = "搜索工具 / PCA / 热图…"),
      actionButton("show_home", "工具总览", class = "home-button"),
      uiOutput("tool_navigation"),
      div(class = "sidebar-bottom", `data-help` = "数据与分析结果保存在本机。",
          actionLink("show_environment", "查看运行环境"))),
    tags$main(class = "main-shell",
      div(class = "topbar", div(span(class = "breadcrumb", "项目工作空间"),
          span(class = "topbar-divider", "/"), textOutput("breadcrumb_tool", inline = TRUE)),
        div(class = "topbar-right", span(class = "local-badge", `data-help` = "服务仅监听 127.0.0.1；分析结果保存在本机。", tabindex = "0", "本机"),
            actionButton("refresh_history", "任务记录", class = "quiet-button"))),
      uiOutput("workspace"),
      div(class = "app-footer", "图谱工作室")))
)

server <- function(input, output, session) {
  selected <- reactiveVal("home")
  job <- reactiveVal(NULL)
  result <- reactiveVal(NULL)
  last_spec <- reactiveVal(NULL)
  history_tick <- reactiveVal(0L)
  environment_open <- reactiveVal(FALSE)
  group_choices <- reactiveVal(unique(c(defaults$params$control, defaults$params$treatment)))
  groups_message <- reactiveVal("")
  upload_paths <- reactiveValues()
  path_cache <- reactiveValues()
  style_cache <- reactiveValues()
  resource_paths <- character()
  for (name in names(input_meta)) local({
    key <- name
    observeEvent(input[[paste0("path_", key)]], {
      path_cache[[key]] <- input[[paste0("path_", key)]]
    }, ignoreNULL = TRUE)
  })

  choose_tool <- function(id) {
    previous <- isolate(selected())
    if (previous != "home") {
      fields <- names(do.call(c, unname(tb_style_schema(previous))))
      saved <- list()
      for (field in c(fields, "formats")) {
        value <- isolate(input[[paste0("style_", field)]])
        if (!is.null(value)) saved[[field]] <- value
      }
      style_cache[[previous]] <- saved
    }
    selected(id)
  }
  observeEvent(input$show_home, choose_tool("home"))
  observeEvent(input$tool_id, {
    if (input$tool_id %in% catalog$id) choose_tool(input$tool_id)
  })
  observeEvent(input$show_environment, {
    environment_open(TRUE)
    showModal(modalDialog(title = "本地运行环境", size = "l", easyClose = TRUE,
       p(paste("R", getRversion(), "·", R.home())),
       p("这里只检查依赖是否安装，不安装软件包，也不执行分析。"),
       tableOutput("dependency_table"), footer = modalButton("关闭")))
  })
  output$dependency_table <- renderTable({
    req(environment_open())
    tb_dependency_report()
  }, striped = TRUE, bordered = FALSE)

  for (name in names(input_meta)) local({
    key <- name
    observeEvent(input[[paste0("upload_", key)]], {
      uploaded <- input[[paste0("upload_", key)]]
      req(uploaded)
      directory <- file.path(tempdir(), paste0("bioworkbench-", session$token))
      dir.create(directory, recursive = TRUE, showWarnings = FALSE)
      filename <- paste0(key, "-", basename(uploaded$name))
      destination <- file.path(directory, filename)
      if (!file.copy(uploaded$datapath, destination, overwrite = TRUE)) {
        showNotification("无法保存上传文件，请使用本地完整路径。", type = "error")
        return()
      }
      upload_paths[[key]] <- destination
      updateTextInput(session, paste0("path_", key), value = destination)
    }, ignoreNULL = TRUE)
  })

  read_input <- function(name) {
    path <- input[[paste0("path_", name)]] %or% defaults$inputs[[name]] %or% ""
    trimws(path)
  }
  refresh_groups <- function() {
    tryCatch({
      path <- read_input("groups")
      if (!file.exists(path)) stop("分组表不存在。")
      separator <- if (grepl("[.](tsv|txt)$", path, ignore.case = TRUE)) "\t" else ","
      groups <- utils::read.table(path, header = TRUE, sep = separator, nrows = 10000,
        check.names = FALSE, stringsAsFactors = FALSE, fileEncoding = "UTF-8-BOM",
        comment.char = "", quote = "\"")
      field <- intersect(c("Group", "condition", "group", "Condition"), names(groups))[1]
      if (is.na(field)) stop("需要 Group 或 condition 分组列。")
      choices <- unique(as.character(groups[[field]]))
      choices <- choices[!is.na(choices) & nzchar(choices)]
      if (length(choices) < 2) stop("至少需要两个分组。")
      group_choices(choices)
      previous_control <- isolate(input$control) %or% defaults$params$control
      previous_treatment <- isolate(input$treatment) %or% defaults$params$treatment
      updateSelectInput(session, "control", choices = choices,
        selected = if (previous_control %in% choices) previous_control else choices[1])
      updateSelectInput(session, "treatment", choices = choices,
        selected = if (previous_treatment %in% choices) previous_treatment else choices[2])
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
    if (!nzchar(search)) return(catalog)
    catalog[grepl(search, tolower(paste(catalog$title, catalog$id,
      catalog$category, catalog$description)), fixed = TRUE), , drop = FALSE]
  })
  output$tool_navigation <- renderUI({
    tools <- filtered_catalog()
    tagList(lapply(unique(tools$category), function(category) {
      members <- tools[tools$category == category, , drop = FALSE]
      div(class = "nav-category", div(class = "category-label", category),
        lapply(seq_len(nrow(members)), function(i) {
          tags$button(type = "button", class = paste("tool-nav", if (selected() == members$id[i]) "active"),
            `data-tool` = members$id[i], span(class = "nav-dot"), members$title[i])
        }))
    }))
  })
  output$breadcrumb_tool <- renderText({
    if (selected() == "home") "工具总览" else catalog$title[match(selected(), catalog$id)]
  })

  output$workspace <- renderUI({
    if (selected() == "home") {
      return(div(class = "workspace home-workspace",
        div(class = "home-hero",
          div(class = "hero-composition", div(h1("表达 · 通路", tags$br(), span("与基因的关联。"))),
            div(class = "hero-art", `aria-hidden` = "true", div(class = "art-orbit orbit-one"), div(class = "art-orbit orbit-two"),
                div(class = "art-axis"), span(class = "art-node n1"), span(class = "art-node n2"), span(class = "art-node n3"),
                span(class = "art-node n4"), span(class = "art-caption", "EXPRESSION / PATHWAY / NETWORK")))),
        div(class = "home-section-title", h2("工具"), span(paste(nrow(catalog), "项"))),
        uiOutput("tool_cards"),
        div(class = "history-section", div(class = "home-section-title", h2("最近任务")), uiOutput("history_list"))))
    }
    tool <- catalog[match(selected(), catalog$id), , drop = FALSE]
    div(class = "workspace tool-workspace",
      div(class = "tool-header", div(div(class = "eyebrow", tool$category),
        h1(tool$title, `data-help` = tool$description, tabindex = "0"))),
      div(class = "tool-layout",
        div(class = "configuration-column",
          div(class = "panel", section_title("01", "数据输入", "使用本机路径或选择文件上传"),
              uiOutput("input_controls")),
          div(class = "panel", section_title("02", "分析参数", tool_help[[selected()]]),
              uiOutput("parameter_controls")),
          if (selected() != "deg") div(class = "panel", tags$details(tags$summary("图形样式与导出",
              `data-help` = "调整当前图型的样式；重新运行后保存为新的任务。画布单位为英寸，DPI 仅影响位图。", tabindex = "0"),
              div(class = "details-content", uiOutput("style_controls")))),
          div(class = "run-bar", actionButton("validate_inputs", "检查输入", class = "secondary-button"),
              actionButton("run_tool", "运行当前工具", class = "primary-button")),
          help_note("只有点击运行才执行计算。调整样式后重新运行会保留新的任务记录。")),
        div(class = "results-column", uiOutput("job_status"),
          div(class = "panel result-panel", div(class = "result-heading", h3("结果工作区"),
              uiOutput("result_badge")),
            tabsetPanel(id = "result_tab", type = "tabs",
              tabPanel("图形预览", uiOutput("preview_panel")),
              if (selected() == "network") tabPanel("交互网络", uiOutput("interactive_network")),
              tabPanel("数据表", uiOutput("data_selector"), tableOutput("data_preview")),
              tabPanel("运行日志", tags$pre(class = "job-log", textOutput("job_log"))),
              tabPanel("输出文件", uiOutput("file_list"))),
            uiOutput("download_actions")))))
  })
  output$tool_cards <- renderUI({
    tools <- filtered_catalog()
    if (!nrow(tools)) return(div(class = "empty-small", "没有匹配的工具，请换一个关键词。"))
    div(class = "tool-card-grid", lapply(seq_len(nrow(tools)), function(i) {
      marks <- c(pca = "PC", deg = "DE", volcano = "FC", heatmap = "HM", custom_heatmap = "GN",
        manual_heatmap = "MP", go = "GO", kegg = "KG", gsea = "GS", gsva = "GV", network = "PI",
        matrix_pca = "MX", matrix_heatmap = "MT", circos = "CI")
      tags$button(type = "button", class = "tool-card", `data-tool` = tools$id[i], `data-help` = tools$description[i],
        div(class = "card-topline", icon_mark(marks[[tools$id[i]]] %or% "R"),
            span(class = "card-category", tools$category[i])),
        h3(tools$title[i]), span(class = "card-link", "↗", `aria-hidden` = "true"))
    }))
  })
  output$input_controls <- renderUI({
    req(selected() != "home")
    fields <- tool_inputs[[selected()]]
    if (selected() == "network") fields <- if ((input$network_mode %or% "files") == "files") c("nodes", "edges") else c("counts", "groups", "edges")
    tagList(lapply(fields, function(name) {
      file_control(name, isolate(path_cache[[name]]))
    }), if (selected() == "go") help_note("GMT 留空时使用本机小鼠 GO 注释。"),
      if (selected() %in% c("matrix_pca", "matrix_heatmap"))
        help_note("分组表默认不参与通用矩阵绘图；需要分组注释时，勾选下方“使用分组表”。"))
  })

  output$parameter_controls <- renderUI({
    id <- selected()
    req(id != "home")
    matrix_tool <- id %in% c("matrix_pca", "matrix_heatmap", "circos")
    network_files <- id == "network" && (input$network_mode %or% "files") == "files"
    basic <- if (!matrix_tool && !network_files) tagList(
      div(class = "two-columns", selectInput("control", "对照组 · 分母", group_choices(),
        selected = defaults$params$control), selectInput("treatment", "实验组 · 分子", group_choices(),
        selected = defaults$params$treatment)),
      div(class = "group-refresh", actionButton("refresh_groups", "读取当前分组", class = "small-button"),
          textOutput("group_summary", inline = TRUE)),
      tags$details(tags$summary("模型与低表达过滤"), div(class = "details-content two-columns",
        num("min_count", "Count 下限", 10, 0), num("min_samples", "至少达到下限的样本数", 3, 1),
        num("alpha", "模型独立过滤 FDR", 0.05, 0.000001, 1, 0.01),
        selectInput("fit_type", "离散度拟合", c("Parametric" = "parametric", "Local" = "local", "Mean" = "mean"),
          selected = defaults$params$fit_type %or% "parametric"),
        check("use_batch", "将技术批次纳入模型"),
        textInput("covariates", "分类协变量（逗号分隔）", defaults$params$covariates %or% "")),
        help_note("批次需在工作台格式分组表中明确填写；与分组完全混杂时直接报错。")))
    selection <- if (id %in% c("deg", "volcano", "heatmap", "go", "kegg") || (id == "network" && !network_files)) tagList(
      div(class = "two-columns", num("padj", "筛选 FDR 上限", 0.05, 0.000001, 1, 0.01),
          num("log2fc", "|log₂FC| 下限", 1, 0, NA, 0.1)),
      selectInput("direction", "差异方向", c("全部" = "all", "上调" = "up", "下调" = "down"),
                  selected = defaults$params$direction %or% "all"))
    specific <- switch(id,
      pca = tagList(num("pca_top", "参与 PCA 的高变基因数", 500, 2), check("pca_scale", "PCA 前按基因标准化"),
                   check("labels", "显示样本标签")),
      deg = help_note("比较方向：实验组 / 对照组；输出全部统计量及差异筛选表。"),
      volcano = tagList(check("labels", "标注显著基因"),
                         help_note("已有差异结果优先；留空时从计数矩阵拟合。")),
      heatmap = selectInput("heatmap_mode", "候选基因", c("差异基因" = "deg", "高变基因" = "variable"),
                           selected = defaults$params$heatmap_mode %or% "deg"),
      custom_heatmap = tagList(selectInput("custom_transform", "Count 表达变换",
        c("log₂(count + 1)" = "log2", "log CPM" = "log_cpm", "VST" = "vst", "不变换" = "none"),
        selected = defaults$params$custom_transform %or% "log2"),
        help_note("沿用项目自定义基因流程和重复基因处理，默认逐行 Z-score。")),
      manual_heatmap = help_note("手工通路热图保留项目脚本的参数与已确认版式；通用样式项未必覆盖该流程全部设置。"),
      go = selectInput("go_ontology", "GO 分类", c("生物过程 · BP" = "BP", "细胞组分 · CC" = "CC",
                         "分子功能 · MF" = "MF"), selected = defaults$params$go_ontology %or% "BP"),
      network = tagList(
        selectInput("network_mode", "数据来源", c("Node + Edge 文件" = "files", "Count 模型中筛选 DEG + 本地边表" = "deg"), selected = input$network_mode %or% "files"),
        selectInput("network_layout", "静态导出布局", c("力导向 FR" = "fr", "Kamada–Kawai" = "kk", "圆形" = "circle", "网格" = "grid"), selected = defaults$params$network_layout %or% "fr"),
        if (network_files) selectInput("network_score_scale", "Edge 分数单位", c("按字段名识别（combined_score ÷ 1000）" = "auto", "已是 0–1" = "unit", "STRING 0–1000" = "thousand"), selected = defaults$params$network_score_scale %or% "auto"),
        num("ppi_score", "标准化置信分数下限（0–1）", 0.7, 0, 1, 0.05),
        help_note("Node / Edge ID 自动按覆盖关系匹配，孤立节点保留；未知端点会明确报错。")),
      matrix_pca = tagList(check("matrix_use_groups", "使用分组表（可选）", FALSE),
                           check("pca_scale", "PCA 前按特征标准化", TRUE), check("labels", "显示样本标签"),
                           help_note("矩阵按特征为行、样本为列排列。")),
      matrix_heatmap = tagList(check("matrix_use_groups", "使用分组表（可选）", FALSE),
                selectInput("matrix_transform", "矩阵变换", c("不变换" = "none", "log₂(x + 伪计数)" = "log2"),
                selected = defaults$params$matrix_transform %or% "none"),
                num("log_pseudocount", "log₂ 伪计数", 1, 0.000001, NA, 0.1)),
      circos = help_note("长度与区域起止必须使用相同单位。跨染色体连线的端点须存在于长度表。"))
    heatmap_options <- if (id %in% c("heatmap", "custom_heatmap", "matrix_heatmap", "gsva")) tagList(
      num("heatmap_top", "最多显示基因 / 通路数", 50, 1),
      check("row_scale", "逐行 Z-score", TRUE),
      div(class = "two-columns", check("cluster_rows", "聚类行", TRUE),
          check("cluster_columns", "聚类列", FALSE)),
      div(class = "two-columns", selectInput("distance", "距离", c("Pearson (1 − r)" = "pearson", "欧氏距离" = "euclidean"),
          selected = defaults$params$distance %or% "pearson"),
        selectInput("linkage", "聚类连接方法", c("Complete" = "complete", "Average" = "average", "Ward.D2" = "ward.D2"),
          selected = defaults$params$linkage %or% "complete")),
      help_note("Ward.D2 仅搭配欧氏距离。色阶截断只影响显示，原始数值保留。"))
    pathway_options <- if (id %in% c("go", "kegg", "gsea", "gsva")) tagList(
      selectInput("gmt_id_type", "GMT 基因标识", c("Gene Symbol" = "SYMBOL", "稳定 gene_id" = "gene_id"),
        selected = defaults$params$gmt_id_type %or% "SYMBOL"),
      textInput("database_version", "本地数据库版本 / 来源标记",
        value = defaults$params$database_version %or% "", placeholder = "如 MSigDB 版本或下载日期"),
      div(class = "two-columns", num("min_set_size", "最小基因集大小", 10, 1),
          num("max_set_size", "最大基因集大小", 500, 1)),
      num("pathway_top", "最多显示通路数", 15, 1),
      if (id == "gsea") textInput("pathway_id", "指定曲线通路 ID（可选）",
        defaults$params$pathway_id %or% "", placeholder = "留空按结果选择"),
      help_note("GO 使用内置注释时记录包版本。使用 GMT 时请填写其实际来源版本。"))
    tagList(basic, selection, specific, heatmap_options, pathway_options)
  })
  output$group_summary <- renderText(groups_message())
  output$style_controls <- renderUI({
    req(selected() != "home")
    schema <- tb_style_schema(selected())
    if (!length(schema)) return(help_note("差异分析输出统计表，本工具没有图形样式。图像设置请在火山图或热图中调整。"))
    style <- utils::modifyList(defaults$style, isolate(style_cache[[selected()]] %or% list()))
    render_field <- function(name, definition) {
      id <- paste0("style_", name)
      value <- style[[name]]
      control <- switch(definition$type,
        number = numericInput(id, definition$label, value, min = definition$min, max = definition$max, step = definition$step),
        color = div(class = "color-control", tags$span(class = "color-swatch", style = paste0("background:", value)), textInput(id, definition$label, value)),
        select = selectInput(id, definition$label, definition$choices, selected = value),
        flag = checkboxInput(id, definition$label, value))
      condition <- if (name %in% c("enrichment_size_min", "enrichment_size_max")) "input.style_enrichment_kind === 'dot'" else if (name %in% c("network_low", "network_mid", "network_high")) "input.style_network_color_by === 'auto' || input.style_network_color_by === 'log2FC'" else if (name == "network_node_color") "input.style_network_color_by !== 'log2FC'" else if ((name == "network_label_top" || (selected() == "network" && name == "label_size"))) "input.style_network_labels" else NULL
      if (is.null(condition)) control else conditionalPanel(condition, control)
    }
    tagList(lapply(names(schema), function(group) tags$fieldset(class = "style-group",
      tags$legend(group), div(class = "two-columns", lapply(names(schema[[group]]), function(name) render_field(name, schema[[group]][[name]]))))),
      checkboxGroupInput("style_formats", "导出格式", c("PNG" = "png", "SVG" = "svg", "TIFF" = "tiff", "PDF" = "pdf"),
        selected = style$formats, inline = TRUE))
  })

  collect_spec <- function() {
    req(selected() != "home")
    parameters <- defaults$params
    for (name in names(parameters)) {
      value <- input[[name]]
      if (!is.null(value)) parameters[[name]] <- value
    }
    style <- defaults$style
    for (name in names(do.call(c, unname(tb_style_schema(selected()))))) {
      value <- input[[paste0("style_", name)]]
      if (!is.null(value)) style[[name]] <- value
    }
    style$formats <- if (selected() == "deg") defaults$style$formats else input$style_formats %or% character()
    inputs <- lapply(names(input_meta), read_input)
    names(inputs) <- names(input_meta)
    # 只提交当前工具的输入；隐藏的其他工具上传路径不会影响本次任务。
    fields <- tool_inputs[[selected()]]
    if (selected() == "network" && parameters$network_mode == "deg") fields <- c("counts", "groups", "edges")
    inputs <- inputs[fields]
    list(tool = selected(), inputs = inputs, params = parameters, style = style)
  }
  observeEvent(input$validate_inputs, {
    tryCatch({
      checks <- tb_validate_inputs(collect_spec(), app_root)
      body <- p(paste(checks, collapse = "\n"))
      if (is.data.frame(checks)) {
        output$checks_table <- renderTable(checks, striped = TRUE)
        body <- tableOutput("checks_table")
      }
      showModal(modalDialog(title = "输入检查", body,
        p("检查不会执行 DESeq2、富集或绘图。"), easyClose = TRUE, footer = modalButton("关闭")))
    }, error = function(e) showNotification(conditionMessage(e), type = "error", duration = 12))
  })
  observeEvent(input$run_tool, {
    current <- job()
    if (!is.null(current) && current$process$is_alive()) {
      showNotification("已有任务正在运行，请等待完成或先取消。", type = "warning")
      return()
    }
    tryCatch({
      spec <- collect_spec()
      next_job <- tb_launch_job(spec, app_root)
      next_job$tool <- spec$tool
      job(next_job)
      saved_request <- file.path(next_job$directory, "request.rds")
      last_spec(if (file.exists(saved_request)) readRDS(saved_request) else spec)
      result(tb_read_job(next_job$directory))
      history_tick(history_tick() + 1L)
      updateTabsetPanel(session, "result_tab", selected = "运行日志")
      showNotification("任务已提交，正在独立 R 进程中运行。", type = "message")
    }, error = function(e) showNotification(conditionMessage(e), type = "error", duration = 15))
  })
  observe({
    invalidateLater(1000, session)
    current <- job()
    if (is.null(current)) return()
    state <- tb_read_job(current$directory)
    if (state$status %in% c("queued", "running") && !current$process$is_alive()) {
      state$status <- "failed"
      state$error <- state$error %or% "分析进程已结束，但没有完成记录。请查看运行日志。"
    }
    previous <- isolate(result())
    if (!identical(previous, state)) {
      result(state)
      if (state$status == "completed" && !identical(previous$status, "completed")) {
        updateTabsetPanel(session, "result_tab", selected = "图形预览")
        history_tick(isolate(history_tick()) + 1L)
        showNotification("任务完成，结果与作图数据已保存。", type = "message")
      }
    }
  })
  observeEvent(input$cancel_job, {
    req(job())
    tryCatch({
      tb_stop_job(job())
      result(tb_read_job(job()$directory))
      history_tick(history_tick() + 1L)
    }, error = function(e) showNotification(conditionMessage(e), type = "error"))
  })
  output$job_status <- renderUI({
    state <- result()
    if (is.null(state)) return(div(class = "status-card status-idle", span(class = "status-dot"),
      div(strong("待运行"), `data-help` = "配置参数后点击运行。")))
    labels <- c(queued = "排队中", running = "正在计算", completed = "任务完成", failed = "运行失败", cancelled = "已取消")
    div(class = paste("status-card", paste0("status-", state$status)), span(class = "status-dot"),
      div(strong(labels[[state$status]] %or% state$status),
          p(if (!is.null(state$error) && nzchar(state$error)) state$error else paste(state$summary %or% "计算状态与日志实时更新。", collapse = " · "))),
      if (state$status %in% c("queued", "running")) actionButton("cancel_job", "取消", class = "small-button"))
  })
  output$result_badge <- renderUI({
    state <- result()
    if (is.null(state)) span(class = "result-tag", "尚无结果") else {
      tool <- catalog$title[match(job()$tool, catalog$id)]
      span(class = "result-tag", tool, " · ", length(state$files %or% character()), " 个文件")
    }
  })
  completed_files <- reactive({
    state <- result()
    if (is.null(state) || state$status != "completed") return(character())
    files <- state$files %or% character()
    files[file.exists(files) & !dir.exists(files)]
  })
  output$preview_panel <- renderUI({
    images <- completed_files()[grepl("[.]png$", completed_files(), ignore.case = TRUE)]
    if (!length(images)) {
      state <- result()
      return(div(class = "preview-empty", div(class = "empty-chart", span(), span(), span(), span()),
        h4(if (!is.null(state) && state$status == "completed") "此任务没有 PNG 预览" else "等待结果"),
        help_note(if (!is.null(state) && state$status == "completed") "差异分析请查看数据表；绘图预览需启用 PNG 导出。" else "配置参数并运行后显示结果。")))
    }
    tagList(selectInput("preview_file", "图形", stats::setNames(images, basename(images))),
      imageOutput("preview_image", height = "auto"))
  })
  output$interactive_network <- renderUI({
    files <- completed_files()
    network <- files[basename(files) == "network.html"]
    if (!length(network)) return(div(class = "preview-empty", h4("等待网络结果"), `data-help` = "任务完成后可拖动节点、缩放和切换布局。", tabindex = "0"))
    prefix <- paste0("network-", substr(session$token, 1, 12), "-", basename(job()$directory))
    addResourcePath(prefix, dirname(network[1]))
    if (!prefix %in% resource_paths) resource_paths <<- c(resource_paths, prefix)
    tags$iframe(src = paste0(prefix, "/network.html"), title = "PPI interactive network", class = "network-frame")
  })
  output$preview_image <- renderImage({
    req(input$preview_file, input$preview_file %in% completed_files())
    list(src = input$preview_file, contentType = "image/png", alt = basename(input$preview_file), width = "100%")
  }, deleteFile = FALSE)
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
    state <- result()
    if (is.null(state)) return("暂无日志。")
    paste(state$log %or% "等待日志…", collapse = "\n")
  })
  output$file_list <- renderUI({
    files <- completed_files()
    if (!length(files)) return(div(class = "empty-small", "当前没有已完成的输出文件。"))
    tagList(div(class = "output-directory", job()$directory %or% ""),
      selectInput("download_file_choice", "选择下载文件", stats::setNames(files, basename(files))),
      downloadButton("download_file", "下载所选文件", class = "secondary-button"),
      tags$ul(class = "output-files", lapply(files, function(file) tags$li(span(basename(file)),
          tags$small(format(file.info(file)$size, big.mark = ","), " bytes")))))
  })
  output$download_actions <- renderUI({
    if (!length(completed_files())) return(NULL)
    div(class = "download-actions", downloadButton("download_zip", "下载结果包", class = "primary-button"),
      downloadButton("download_recipe", "复现 R 脚本", class = "secondary-button"))
  })
  output$download_file <- downloadHandler(
    filename = function() basename(input$download_file_choice),
    content = function(file) {
      req(input$download_file_choice %in% completed_files())
      file.copy(input$download_file_choice, file, overwrite = TRUE)
    })
  output$download_zip <- downloadHandler(
    filename = function() paste0("BioWorkbench-", job()$id, ".zip"),
    content = function(file) {
      req(result()$status == "completed")
      tb_zip_results(job()$directory, file)
    }, contentType = "application/zip")
  output$download_recipe <- downloadHandler(
    filename = function() paste0("reproduce-", last_spec()$tool, ".R"),
    content = function(file) {
      req(last_spec())
      tb_write_reproduce(last_spec(), file, app_root)
    })

  observeEvent(input$refresh_history, {
    history_tick(history_tick() + 1L)
    showModal(modalDialog(title = "任务记录", size = "l", uiOutput("history_modal"),
      easyClose = TRUE, footer = modalButton("关闭")))
  })
  history <- reactive({
    history_tick()
    tb_list_runs(app_root)
  })
  history_ui <- function() {
    runs <- history()
    if (is.null(runs) || !nrow(runs)) return(div(class = "history-empty", span(class = "history-icon", "↗"),
      div(strong("暂无任务"))))
    tags$div(class = "history-list", lapply(seq_len(min(nrow(runs), 10)), function(i) {
      title <- catalog$title[match(runs$tool[i], catalog$id)]
      div(class = "history-item", div(strong(title %or% runs$tool[i]),
          tags$small(runs$created[i], " · ", runs$id[i])),
          span(class = paste("history-status", paste0("history-", runs$status[i])), runs$status[i]),
          tags$button(type = "button", class = "small-button", `data-run` = runs$directory[i], "查看"))
    }))
  }
  output$history_list <- renderUI(history_ui())
  output$history_modal <- renderUI(history_ui())
  observeEvent(input$history_run, {
    # 只允许从服务端生成的任务记录选择路径。
    runs <- history()
    req(input$history_run %in% runs$directory)
    directory <- input$history_run
    state <- tb_read_job(directory)
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
    job(restored)
    request <- file.path(directory, "request.rds")
    last_spec(if (file.exists(request)) readRDS(request) else NULL)
    result(state)
    if (row$tool %in% catalog$id) selected(row$tool)
    removeModal()
  })
  session$onSessionEnded(function() {
    for (prefix in resource_paths) removeResourcePath(prefix)
    # 浏览器断开后任务由服务注册表保持；关闭启动器会结束服务及其子进程。
    invisible(NULL)
  })
}

shinyApp(ui, server)
