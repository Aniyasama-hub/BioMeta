# Isolated selected-R process. Latest means compatible with this R/Bioconductor release.
args <- commandArgs(trailingOnly = TRUE)
mode <- args[1]; report <- args[2]; lib <- args[3]
options(timeout = 90, repos = c(CRAN = "https://cloud.r-project.org"))
if (nzchar(lib)) { dir.create(lib, recursive = TRUE, showWarnings = FALSE); .libPaths(c(lib, .libPaths())) }
if (!requireNamespace("BiocManager", quietly = TRUE)) stop("请先为所选 R 安装 BiocManager。")
repos <- BiocManager::repositories()
script_file <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1])
app_root <- dirname(dirname(normalizePath(script_file, winslash = "/")))
source(file.path(app_root, "R", "toolbox.R"), encoding = "UTF-8")
required <- tb_dependency_report()$package
if (mode == "update") {
  wanted <- args[-(1:3)]
  if (identical(wanted, "__all__")) {
    available_before <- available.packages(repos = repos)
    current_before <- installed.packages()
    current_before <- current_before[!duplicated(current_before[, "Package"]) & (is.na(current_before[, "Priority"]) | current_before[, "Priority"] != "base"), , drop = FALSE]
    wanted <- current_before[, "Package"][vapply(seq_len(nrow(current_before)), function(i) {
      name <- current_before[i, "Package"]
      name %in% rownames(available_before) && utils::compareVersion(current_before[i, "Version"], available_before[name, "Version"]) < 0L
    }, logical(1))]
    wanted <- union(wanted, intersect(setdiff(required, current_before[, "Package"]), rownames(available_before)))
  }
  if (length(wanted)) BiocManager::install(wanted, lib = lib, ask = FALSE, update = FALSE)
}
available <- available.packages(repos = repos)
if (!nrow(available)) stop("未能读取仓库索引，请检查网络和仓库地址后重试。")
installed <- installed.packages()
installed <- installed[!duplicated(installed[, "Package"]), , drop = FALSE]
installed <- installed[is.na(installed[, "Priority"]) | installed[, "Priority"] != "base", , drop = FALSE]
rows <- lapply(seq_len(nrow(installed)), function(i) {
  name <- installed[i, "Package"]
  latest <- if (name %in% rownames(available)) available[name, "Version"] else NA_character_
  desc <- packageDescription(name, lib.loc = installed[i, "LibPath"])
  url <- if (name %in% rownames(available)) paste0(available[name, "Repository"], "/", name, "_", latest, ".tar.gz") else ""
  if (!is.null(desc$URL)) url <- trimws(strsplit(desc$URL, "[,\n]")[[1]][1])
  data.frame(package = name, current = installed[i, "Version"], latest = latest,
    description = if (is.null(desc$Title)) name else desc$Title, url = url,
    outdated = !is.na(latest) && utils::compareVersion(installed[i, "Version"], latest) < 0L)
})
# Base packages are managed by the R installation; recommended packages are checked too.
result <- do.call(rbind, rows)
missing <- setdiff(required, result$package)
if (length(missing)) for (name in missing) {
  latest <- if (name %in% rownames(available)) available[name, "Version"] else NA_character_
  result <- rbind(result, data.frame(package = name, current = "未安装", latest = latest,
    description = "工作站功能依赖", url = paste0("https://bioconductor.org/packages/", name), outdated = !is.na(latest)))
}
attr(result, "R_version") <- as.character(getRversion())
saveRDS(result, report)
if (mode == "update" && any(result$outdated[result$package %in% wanted])) stop("部分包仍未达到仓库版本，请查看安装日志。")
