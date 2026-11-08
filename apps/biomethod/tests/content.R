# Run from the BioWorkbench repository root; no analyses are executed.
root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
`%||%` <- function(x, y) if (is.null(x)) y else x
source(file.path(root, "apps/biomethod/R/service.R"), encoding = "UTF-8")
source(file.path(root, "shared/platform.R"), encoding = "UTF-8")
source(file.path(root, "app/R/toolbox.R"), encoding = "UTF-8")
manifest <- bm_manifest(root)
ids <- function(items) vapply(items, `[[`, character(1), "id")
article_ids <- ids(manifest$articles)
stopifnot(!anyDuplicated(article_ids))
script_ids <- ids(manifest$scripts)
reference_ids <- ids(manifest$references)
category_ids <- ids(manifest$categories)
stopifnot(!anyDuplicated(script_ids), !anyDuplicated(reference_ids))
projects <- platform_config(root)$projects
stopifnot(!anyDuplicated(ids(projects)), length(projects) >= 2L)
features <- jsonlite::read_json(file.path(root, "shared/feature-map.json"))
tool_ids <- c("home", "bulk", tb_tool_catalog()$id)
annotations <- bm_annotation_inventory(root)
annotation_ids <- ids(annotations)
stopifnot(setequal(annotation_ids, c("go", "kegg", "reactome")), !anyDuplicated(annotation_ids))
for (item in annotations) stopifnot(startsWith(item$homepage, "https://"), nzchar(item$source),
  nzchar(item$identifier), nzchar(item$version_policy), all(unlist(item$features) %in% tool_ids))
stopifnot(all(unlist(features) %in% article_ids), all(names(features) %in% tool_ids))
for (item in manifest$articles) {
  stopifnot(item$category %in% category_ids,
    item$article_type %in% c("concept", "technical"),
    all(unlist(item$technical_articles) %in% article_ids),
    all(unlist(item$annotation_libraries) %in% annotation_ids),
    all(unlist(item$scripts) %in% script_ids),
    all(unlist(item$references) %in% reference_ids),
    all(unlist(item$related) %in% article_ids),
    all(unlist(item$features) %in% tool_ids))
  article <- bm_article(root, item$id, manifest)
  stopifnot(nzchar(article$markdown), nzchar(article$html), nzchar(item$title_en))
  headings <- regmatches(article$html, gregexpr("(?s)<h2\\b[^>]*>.*?</h2>", article$html, perl = TRUE))[[1L]]
  headings <- trimws(gsub("<[^>]+>", "", headings))
  stopifnot(identical(unname(headings), c("定义解释", "分析原理", "分析操作", "适用范围", "参考与致谢")))
  if (item$id == "pca") stopifnot(nchar(article$markdown) > 12000L)
  stopifnot(grepl('<figure class="bm-process">', article$html, fixed = TRUE))
  lines <- strsplit(article$markdown, "\n", fixed = TRUE)[[1L]]
  starts <- which(lines == "```r")
  if (item$article_type == "concept") {
    stopifnot(length(starts) == 0L, length(item$scripts) == 0L,
      !grepl("app/R/|prepare_bundle|analyze_dataset|extract_degs", article$markdown))
    for (id in unlist(item$technical_articles))
      stopifnot(bm_find(manifest$articles, id)$article_type == "technical")
  } else {
    stopifnot(item$category == "scripts", length(starts) > 0L)
    for (start in starts) {
      end <- which(seq_along(lines) > start & lines == "```")[1L]
      block <- lines[seq.int(start + 1L, end - 1L)]
      parsed <- parse(text = block, keep.source = TRUE)
      tokens <- getParseData(parsed)
      commented <- unique(tokens$line1[tokens$token == "COMMENT"])
      stopifnot(all(which(nzchar(trimws(block))) %in% commented))
    }
  }
}
for (item in manifest$scripts) {
  source <- bm_script(root, item$id, manifest)
  stopifnot(nzchar(source$code), nchar(source$sha256) == 64L,
    source$end_line >= source$start_line,
    all(unlist(source$articles) %in% article_ids), length(item$parameters) > 0L)
}
for (item in manifest$references) {
  stopifnot(startsWith(item$url, "https://"), nzchar(item$title),
    all(unlist(item$articles) %in% article_ids))
}
stopifnot(is.null(bm_article(root, "not-registered")),
  is.null(bm_script(root, "not-registered")))
response <- bm_http(list(PATH_INFO = "/api/knowledge/articles/pca", REQUEST_METHOD = "POST"), root)
stopifnot(response$status == 405L)
stopifnot(length(bm_json(file.path(bm_root(root), "videos.json"))) == 0L)
for (path in c("app/app.R", "shared/platform.R", "apps/biomethod/R/service.R", "app/R/toolbox.R", "app/tools/dependencies.R")) {
  parse(file.path(root, path), encoding = "UTF-8")
}
cat(sprintf("PASS content graph: %d articles, %d scripts, %d references; R syntax and readonly handler\n",
  length(article_ids), length(script_ids), length(reference_ids)))

stopifnot("markdown" %in% tb_dependency_report()$package)

# Downloadable GMT must be readable by the actual workstation parser.
source(file.path(root, "app/R/pathways.R"), encoding = "UTF-8")
gmt <- .read_local_gmt(file.path(root, "apps/biomethod/www/examples/custom-format-example.gmt"))
stopifnot(nrow(gmt$term2name) == 2L, nrow(gmt$term2gene) == 5L,
  identical(sort(gmt$term2gene$gene[gmt$term2gene$term_id == "CUSTOM_REVIEWED_SET_V1"]),
    c("GENE_A", "GENE_B", "GENE_C")))
cat("PASS conceptual/code separation, per-line R comments, process diagrams and real GMT parser\n")

# Exercise the published GMT construction steps using only the format template.
check_gmt_tutorial <- function() {
  directory <- tempfile("biomethod-gmt-")
  dir.create(directory)
  previous <- setwd(directory)
  on.exit(setwd(previous), add = TRUE)
  file.copy(file.path(root, "apps/biomethod/www/examples/gene-set-members-template.csv"),
    "gene-set-members.csv")
  write.csv(data.frame(gene_id = c("GENE_A", "GENE_C")), "expression_genes.csv", row.names = FALSE)
  lines <- strsplit(bm_article(root, "gmt-code", manifest)$markdown, "\n", fixed = TRUE)[[1L]]
  environment <- new.env(parent = globalenv())
  for (start in which(lines == "```r")) {
    end <- which(seq_along(lines) > start & lines == "```")[1L]
    block <- lines[seq.int(start + 1L, end - 1L)]
    block <- block[!startsWith(block, "setwd(")]
    eval(parse(text = block), envir = environment)
  }
  result <- .read_local_gmt("my_sets_v1.gmt")
  report <- read.csv("gmt_matching_report.csv")
  stopifnot(nrow(result$term2gene) == 3L, nrow(result$term2name) == 2L,
    identical(report$original_size, c(2L, 1L)), identical(report$matched_size, c(1L, 1L)))
}
check_gmt_tutorial()
cat("PASS published CSV-to-GMT tutorial and matching report on the format template\n")
