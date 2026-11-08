# Read-only knowledge service; never evaluates analysis scripts.
bm_root <- function(root) file.path(root, "content", "biomethod")
bm_json <- function(path) jsonlite::read_json(path, simplifyVector = FALSE)
bm_find <- function(items, id) {
  hits <- Filter(function(item) identical(item$id, id), items)
  if (length(hits) == 1L) hits[[1L]] else NULL
}
bm_manifest <- function(root) {
  catalog <- bm_json(file.path(bm_root(root), "catalog.json"))
  ids <- vapply(catalog$articles, `[[`, character(1), "id")
  if (anyDuplicated(ids) || any(!grepl("^[a-z0-9-]+$", ids))) stop("知识 ID 必须唯一且合法。")
  catalog$scripts <- bm_json(file.path(bm_root(root), "scripts.json"))
  catalog$references <- bm_json(file.path(bm_root(root), "references.json"))
  catalog
}
bm_article <- function(root, id, catalog = bm_manifest(root)) {
  item <- bm_find(catalog$articles, id)
  if (is.null(item)) return(NULL)
  if (!identical(item$file, paste0(item$id, ".md"))) stop("知识文件与 ID 不匹配。")
  text <- paste(readLines(file.path(bm_root(root), "articles", item$file), encoding = "UTF-8", warn = FALSE), collapse = "\n")
  item$markdown <- text
  item$html <- markdown::mark(text = text, options = c("latex_math", "-embed_resources", "-js_math", "-js_highlight"), format = "html", template = FALSE)
  if (length(item$annotation_libraries)) item$annotation_inventory <- Filter(function(x)
    x$id %in% unlist(item$annotation_libraries), bm_annotation_inventory(root))
  item
}

# Read-only, local inventory. No expression data, personal paths or network calls.
bm_annotation_inventory <- function(root) {
  libraries <- bm_json(file.path(root, "shared", "annotation-libraries.json"))
  lapply(libraries, function(item) {
    item$runtime_packages <- lapply(item$packages, function(package) {
      installed <- nzchar(system.file(package = package))
      list(name = package, version = if (installed) as.character(utils::packageVersion(package)) else "未安装")
    })
    item$local <- lapply(c(human = "hsa", mouse = "mmu"), function(organism) {
      if (item$id == "go") return(list(organism = organism, status = "按本机注释包生成本次输入的映射"))
      path <- file.path(root, "app", "results", "toolbox", "references", paste0(item$id, "-", organism, ".rds"))
      if (!file.exists(path)) return(list(organism = organism, status = "尚未缓存；首次分析按需下载"))
      cached <- tryCatch(readRDS(path), error = function(e) NULL)
      if (is.null(cached$table) || !all(c("term", "gene", "label") %in% names(cached$table)))
        return(list(organism = organism, status = "缓存结构不完整，请重新获取"))
      table <- cached$table
      expected <- if (item$id == "kegg") paste0("^", organism, "[0-9]{5}$")
        else if (organism == "hsa") "^R-HSA-[0-9]+$" else "^R-MMU-[0-9]+$"
      invalid <- sum(is.na(table$gene) | !grepl("^[0-9]+$", table$gene) |
        is.na(table$term) | !grepl(expected, table$term) | is.na(table$label) | !nzchar(table$label))
      list(organism = organism, status = if (invalid) "缓存含无效记录" else "缓存字段与物种编号检查通过",
        terms = length(unique(table$term)), genes = length(unique(table$gene)), links = nrow(table),
        invalid_records = invalid, duplicate_links = sum(duplicated(table[c("term", "gene")])),
        retrieved = cached$retrieved %||% "未记录", release = cached$release %||% "未记录发行号",
        sha256 = digest::digest(file = path, algo = "sha256"))
    })
    item
  })
}
bm_script <- function(root, id, catalog = bm_manifest(root)) {
  item <- bm_find(catalog$scripts, id)
  if (is.null(item)) return(NULL)
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  path <- normalizePath(file.path(root, item$path), winslash = "/", mustWork = TRUE)
  if (!startsWith(path, paste0(root, "/app/")) || tools::file_ext(path) != "R") stop("脚本必须来自工作站 R 文件白名单。")
  lines <- readLines(path, encoding = "UTF-8", warn = FALSE)
  start <- if (is.null(item$symbol)) 1L else which(startsWith(lines, paste0(item$symbol, " <- function")))[1L]
  if (is.na(start)) stop("映射函数不存在：", item$id)
  end <- min(length(lines), start + as.integer(item$max_lines) - 1L)
  item$start_line <- start
  item$end_line <- end
  item$code <- paste(lines[seq.int(start, end)], collapse = "\n")
  item$excerpt <- TRUE
  item$sha256 <- digest::digest(file = path, algo = "sha256")
  item
}
bm_response <- function(value, status = 200L) shiny::httpResponse(status, "application/json; charset=utf-8",
  jsonlite::toJSON(value, auto_unbox = TRUE, null = "null", na = "null"),
  headers = list("Cache-Control" = "no-store", "X-Content-Type-Options" = "nosniff"))
bm_http <- function(request, root) {
  path <- request$PATH_INFO
  if (!startsWith(path, "/api/knowledge/")) return(NULL)
  if (!identical(request$REQUEST_METHOD, "GET")) return(bm_response(list(error = "知识接口为只读接口。"), 405L))
  route <- sub("^/api/knowledge/", "", path)
  tryCatch({
    if (route == "annotations") return(bm_response(list(items = bm_annotation_inventory(root))))
    if (route == "videos/schema") return(bm_response(bm_json(file.path(bm_root(root), "video.schema.json"))))
    if (route == "videos") {
      videos <- bm_json(file.path(bm_root(root), "videos.json"))
      return(bm_response(list(items = Filter(function(v) identical(v$status, "published"), videos), capability = "metadata-only")))
    }
    catalog <- bm_manifest(root)
    if (route == "catalog") {
      query <- shiny::parseQueryString(request$QUERY_STRING %||% "")
      catalog$articles <- lapply(catalog$articles, function(item) {
        article <- bm_article(root, item$id, catalog)
        item$search_text <- paste(item$title, item$title_en, item$summary, paste(unlist(item$tags), collapse = " "), article$markdown)
        item
      })
      if (!is.null(query$q) && nzchar(trimws(query$q))) catalog$articles <- Filter(function(item)
        grepl(tolower(trimws(query$q)), tolower(item$search_text), fixed = TRUE), catalog$articles)
      if (!is.null(query$category)) catalog$articles <- Filter(function(item) identical(item$category, query$category), catalog$articles)
      return(bm_response(catalog))
    }
    if (route == "references") return(bm_response(list(items = catalog$references)))
    parts <- strsplit(route, "/", fixed = TRUE)[[1L]]
    if (length(parts) != 2L || !grepl("^[a-z0-9-]+$", parts[2L])) return(bm_response(list(error = "未找到知识资源。"), 404L))
    item <- switch(parts[1L], articles = bm_article(root, parts[2L], catalog), scripts = bm_script(root, parts[2L], catalog),
      references = bm_find(catalog$references, parts[2L]), NULL)
    if (is.null(item)) bm_response(list(error = "未找到知识资源。"), 404L) else bm_response(item)
  }, error = function(e) {
    message("BioMethod content error: ", conditionMessage(e))
    bm_response(list(error = "知识内容暂不可用，请检查内容清单与脚本映射。"), 500L)
  })
}
