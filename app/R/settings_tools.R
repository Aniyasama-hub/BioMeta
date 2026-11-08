# A selected R must not inherit another R installation's library search path.
tb_runtime_env <- function() {
  env <- Sys.getenv()
  env[!names(env) %in% c("R_HOME", "R_LIBS", "R_LIBS_USER", "R_LIBS_SITE")]
}

# Native selection is local-only and returns a path, never uploaded program contents.
tb_pick_local <- function(root, kind) {
  if (.Platform$OS.type != "windows") stop("当前原生选择器仅适用于 Windows。")
  value <- processx::run("powershell.exe", c("-NoProfile", "-STA", "-ExecutionPolicy", "Bypass", "-File",
    file.path(root, "tools", "pick-local.ps1"), "-Kind", kind),
    timeout = 180000, encoding = "UTF-8", windows_hide_window = TRUE, error_on_status = TRUE)
  trimws(value$stdout)
}
tb_find_runtimes <- function(kind, root, configured = "", discover = NULL) {
  if (is.null(discover)) {
    current <- if (kind == "R") file.path(R.home("bin"), "Rscript.exe") else ""
    result <- processx::run("powershell.exe", c("-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
      file.path(root, "tools", "find-runtimes.ps1"), "-Kind", kind,
      if (nzchar(configured)) c("-Configured", configured), if (nzchar(current)) c("-Current", current)),
      timeout = 60000, encoding = "UTF-8", windows_hide_window = TRUE)
    discover <- jsonlite::fromJSON(result$stdout)
  }
  if (!is.data.frame(discover) || !nrow(discover)) stop("未找到 ", kind, "。已检查 PATH、注册表、常见安装位置和虚拟环境；也可浏览或手动指定自定义位置。")
  rows <- lapply(seq_len(nrow(discover)), function(i) {
    path <- normalizePath(discover$path[i], winslash = "/", mustWork = TRUE)
    probe <- tryCatch({
      result <- if (kind == "RStudio") list(status = 0L, stdout = discover$file_version[i] %||% "") else
        processx::run(path, if (kind == "R") c("--vanilla", "-e", "cat(as.character(getRversion()))") else "--version",
          timeout = 10000, error_on_status = FALSE, stderr_to_stdout = TRUE, env = tb_runtime_env(), windows_hide_window = TRUE)
      if (result$status != 0L) stop("无法执行版本查询")
      if (kind == "RStudio" && !nzchar(trimws(result$stdout))) "已发现（文件未记录版本）" else trimws(result$stdout)
    }, error = function(e) paste("不可用：", conditionMessage(e)))
    data.frame(path = path, version = probe, source = discover$source[i], available = !startsWith(probe, "不可用"))
  })
  unique(do.call(rbind, rows))
}
tb_package_job <- function(root, mode, report, packages = character(), lib = "") {
  cfg <- tb_read_settings(root)
  r <- if (nzchar(cfg$rscript)) cfg$rscript else file.path(R.home("bin"), "Rscript.exe")
  processx::process$new(r, c("--vanilla", file.path(root, "tools", "package-manager.R"),
    mode, report, lib, packages), stdout = paste0(report, ".log"), stderr = "2>&1",
    windows_hide_window = TRUE, cleanup = FALSE, env = tb_runtime_env())
}

# Compact presentation only: source dataset documents remain unchanged.
tb_example_document <- function(file) {
  lines <- readLines(file, encoding = "UTF-8", warn = FALSE)
  result <- character(); buffer <- character()
  flush <- function() { if (length(buffer)) { result <<- c(result, paste(buffer, collapse = "；"), ""); buffer <<- character() } }
  for (line in lines) {
    if (grepl("^\\|", line)) {
      if (grepl("^[| :–-]+$", line)) next
      buffer <- c(buffer, trimws(gsub("[|]", " · ", sub("[|]$", "", sub("^[|]", "", line)))))
    } else if (grepl("^[-*] +|^[0-9]+[.] +", line)) {
      buffer <- c(buffer, sub("^([-*]|[0-9]+[.]) +", "", line))
    } else if (!nzchar(trimws(line))) {
      if (!length(buffer)) result <- c(result, "")
    } else {
      flush(); result <- c(result, line)
    }
  }
  flush()
  htmltools::HTML(markdown::mark(text = paste(result, collapse = "\n"), template = FALSE, options = "-embed_resources"))
}

tb_package_purpose <- c(
  shiny = "工作站界面与交互",
  processx = "独立启动和管理分析脚本",
  jsonlite = "读写配置与接口数据",
  digest = "记录输入文件指纹",
  zip = "打包下载结果",
  rlang = "错误信息与参数处理",
  markdown = "渲染教程与说明",
  DESeq2 = "原始计数差异表达建模",
  SummarizedExperiment = "组织表达矩阵与样本信息",
  ggplot2 = "科研图形绘制",
  ggrepel = "避免图上标签重叠",
  scatterplot3d = "三维 PCA 视图",
  ComplexHeatmap = "表达和通路热图",
  circlize = "基因组环形图",
  svglite = "导出 SVG 矢量图",
  readxl = "读取 Excel 注释文件",
  clusterProfiler = "候选基因功能富集检验",
  org.Hs.eg.db = "人基因编号与名称注释",
  org.Mm.eg.db = "小鼠基因编号与名称注释",
  GO.db = "GO 条目与分类说明",
  AnnotationDbi = "查询基因注释与编号对应",
  fgsea = "完整基因排序的 GSEA",
  BiocParallel = "管理分析并行计算",
  GSVA = "逐样本通路活性评分",
  limma = "线性模型和通路评分比较",
  igraph = "网络结构和节点分析",
  patchwork = "组合多区域科研图",
  ggbeeswarm = "分组蜜蜂图",
  magick = "图片裁白、缩放和组图",
  png = "读取 PNG 图片"
)

tb_package_url <- function(names) {
  bioc <- c("DESeq2", "SummarizedExperiment", "ComplexHeatmap", "clusterProfiler", "org.Hs.eg.db", "org.Mm.eg.db", "GO.db", "AnnotationDbi", "fgsea", "BiocParallel", "GSVA", "limma")
  ifelse(names %in% bioc, paste0("https://bioconductor.org/packages/", names), paste0("https://cran.r-project.org/package=", names))
}
