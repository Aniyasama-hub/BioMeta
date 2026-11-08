# Public references are downloaded without sending expression, gene IDs or sample data.
tb_public_table <- function(source, species, root, fetch = utils::download.file) {
  if (!source %in% c("kegg", "reactome")) stop("未知公共注释来源。")
  organism <- if (species == "human") "hsa" else "mmu"
  cache <- file.path(root, "results", "toolbox", "references")
  dir.create(cache, recursive = TRUE, showWarnings = FALSE)
  path <- file.path(cache, paste0(source, "-", organism, ".rds"))
  if (file.exists(path)) return(readRDS(path))
  read_remote <- function(url, ...) {
    local <- tempfile()
    on.exit(unlink(local))
    previous <- options(timeout = max(getOption("timeout"), 180))
    on.exit(options(previous), add = TRUE)
    status <- tryCatch(fetch(url, local, mode = "wb", quiet = TRUE),
      error = function(e) stop("公共注释库下载失败：", url, "。", conditionMessage(e), call. = FALSE))
    if (!identical(as.integer(status), 0L)) stop("公共注释库下载失败：", url)
    utils::read.delim(local, header = FALSE, colClasses = "character", quote = "", ...)
  }
  if (source == "kegg") {
    urls <- paste0("https://rest.kegg.jp/", c("link/pathway/", "list/pathway/"), organism)
    links <- read_remote(urls[1], col.names = c("gene", "term"))
    names <- read_remote(urls[2], col.names = c("term", "label"))
    links$gene <- sub(paste0("^", organism, ":"), "", links$gene)
    links$term <- sub("^path:", "", links$term)
    names$term <- sub("^path:", "", names$term)
    table <- merge(links, names, by = "term")
  } else {
    urls <- "https://reactome.org/download/current/NCBI2Reactome_All_Levels.txt"
    all <- read_remote(urls, col.names = c("gene", "term", "url", "label", "evidence", "species"))
    taxon <- if (species == "human") "Homo sapiens" else "Mus musculus"
    table <- all[all$species == taxon, c("term", "gene", "label")]
  }
  table <- unique(table[grepl("^[0-9]+$", table$gene) & nzchar(table$term) & nzchar(table$label), ])
  if (!nrow(table)) stop("公共注释未返回该物种的有效通路。")
  result <- list(table = table, urls = urls, retrieved = format(Sys.time(), tz = "UTC", usetz = TRUE))
  temp <- tempfile(tmpdir = cache)
  on.exit(unlink(temp), add = TRUE)
  saveRDS(result, temp)
  if (!file.rename(temp, path) && !file.exists(path)) stop("无法保存公共注释缓存。")
  result
}

tb_public_pathways <- function(cfg, spec, genes, root, directory, engine, terms = NULL) {
  source <- spec$params$pathway_source
  species <- spec$params$species
  package <- if (species == "human") "org.Hs.eg.db" else "org.Mm.eg.db"
  engine$require_packages(c(package, "AnnotationDbi"))
  db <- getExportedValue(package, package)
  report <- tb_gene_mapping(genes, db, species)
  ids <- report$resolved_id
  # Keep the original export columns for downstream readers.
  report$gene_id <- report$input_id; report$input_name <- report$input_symbol
  report$entrez_id <- ids; report$gene_name <- report$database_symbol
  engine$write_table(report, file.path(directory, "outputs", "public_gene_mapping.csv"))
  quality <- list(input_genes = nrow(report), mapped_genes = sum(!is.na(ids)),
    mapped_fraction = mean(!is.na(ids)), unmapped_genes = sum(is.na(ids)),
    alias_or_name_updates = sum(report$conflict_reason %in% c("known_alias", "name_difference_unconfirmed")),
    confirmed_conflicts = sum(report$conflict_reason == "confirmed_cross_gene"),
    ambiguous_genes = sum(report$conflict_reason == "ambiguous_id"),
    duplicated_symbol_genes = sum(report$duplicated_symbol), species = species,
    source = package, version = as.character(utils::packageVersion(package)),
    source_metadata = AnnotationDbi::metadata(db), annotation_source = source,
    policy = "stable_id_first; known_alias_or_unconfirmed_name_difference_warn; confirmed_cross_gene_error; ambiguous_id_unmapped")
  quality_path <- file.path(directory, "outputs", "mapping_quality.json")
  engine$write_manifest(quality, quality_path)
  tb_check_gene_mapping(report)
  map <- unique(data.frame(gene = ids, gene_id = genes$gene_id))
  map <- map[!is.na(map$gene), ]
  if (!nrow(map)) tb_fail("BW-M03", "没有成功映射的基因，无法分析。", hint = "请核对物种和编号类型；查看 public_gene_mapping.csv 中的未映射原因。")
  if (source == "go") {
    engine$require_packages("GO.db")
    table <- suppressMessages(AnnotationDbi::select(db, unique(map$gene),
      c("GOALL", "ONTOLOGYALL"), "ENTREZID"))
    ontologies <- tb_go_ontologies(spec$params$go_ontology)
    table <- table[!is.na(table$GOALL) & table$ONTOLOGYALL %in% ontologies, ]
    if (!nrow(table)) tb_fail("BW-M03", "该物种与 GO 类别没有可匹配的注释。", hint = "请核对输入物种、编号类型和所选 GO 分类。")
    names <- suppressMessages(AnnotationDbi::mapIds(getExportedValue("GO.db", "GO.db"),
      unique(table$GOALL), "TERM", "GOID"))
    table <- data.frame(gene = table$ENTREZID, term = table$GOALL,
      label = unname(names[table$GOALL]), ontology = table$ONTOLOGYALL)
    reference <- list(table = table, urls = "https://geneontology.org/",
      retrieved = paste("GO.db", utils::packageVersion("GO.db")))
  } else reference <- tb_public_table(source, species, root)
  table <- reference$table
  if (!is.null(terms)) table <- table[table$term %in% terms, ]
  hits <- merge(table, map, by = "gene")
  quality$annotated_genes <- length(unique(hits$gene_id))
  quality$mapped_without_annotation <- length(setdiff(map$gene_id, hits$gene_id))
  engine$write_manifest(quality, quality_path)
  if (quality$mapped_without_annotation > 0L) message("Warning [BW-MW03] ", quality$mapped_without_annotation,
    " 个已映射输入基因没有当前来源/分类的注释；清单与摘要已保留。")
  if (!nrow(hits)) tb_fail("BW-M03", "公共基因集与有效输入没有交集，无法分析。", hint = "请核对物种、注释来源和编号类型。")
  labels <- stats::setNames(hits$label[!duplicated(hits$term)], unique(hits$term))
  sets <- split(hits$gene_id, hits$term)
  gmt <- file.path(directory, "outputs", "public_annotation.gmt")
  writeLines(vapply(names(sets), function(id) {
    label <- labels[[id]]
    paste(c(id, if (is.na(label)) id else label, unique(sets[[id]])), collapse = "\t")
  }, character(1)), gmt, useBytes = TRUE)
  if (source == "go" && spec$tool == "go") {
    types <- unique(hits[c("term", "ontology")])
    cfg$pathways$go_term_ontology <- stats::setNames(types$ontology, types$term)
  }
  cfg$pathways$gmt <- gmt
  cfg$pathways$gmt_id_type <- "gene_id"
  cfg$pathways$database_label <- paste(toupper(source), species)
  cfg$pathways$database_version <- paste(reference$retrieved, package, utils::packageVersion(package))
  cfg$pathways$reference_urls <- reference$urls
  cfg$pathways$reference_sha256 <- digest::digest(file = gmt, algo = "sha256")
  cfg$pathways$annotation_packages <- stats::setNames(
    lapply(c(package, "AnnotationDbi", if (source == "go") "GO.db"), function(x) as.character(utils::packageVersion(x))),
    c(package, "AnnotationDbi", if (source == "go") "GO.db"))
  if (source == "go") cfg$pathways$annotation_metadata <- AnnotationDbi::metadata(db)
  cfg
}

# Only public pathway IDs go to KEGG. Expression values and gene lists stay local.
tb_export_kegg_maps <- function(ids, directory, root, species, fetch = utils::download.file) {
  organism <- if (species == "human") "hsa" else "mmu"
  ids <- unique(ids[grepl(paste0("^", organism, "[0-9]{5}$"), ids)])
  target <- file.path(directory, "kegg_maps")
  cache <- file.path(root, "results", "toolbox", "references", "kegg-maps")
  dir.create(target, recursive = TRUE, showWarnings = FALSE)
  dir.create(cache, recursive = TRUE, showWarnings = FALSE)
  valid_png <- function(path) file.exists(path) && file.info(path)$size > 8 &&
    identical(as.integer(readBin(path, "raw", 8)), c(137L, 80L, 78L, 71L, 13L, 10L, 26L, 10L))
  previous <- options(timeout = max(30, getOption("timeout")))
  on.exit(options(previous), add = TRUE)
  rows <- lapply(ids, function(id) {
    message("KEGG 官网机制图：", id)
    url <- paste0("https://rest.kegg.jp/get/", id, "/image")
    cached <- file.path(cache, paste0(id, ".png"))
    error <- ""
    from_cache <- valid_png(cached)
    if (!from_cache) {
      temp <- tempfile(tmpdir = cache, fileext = ".png")
      error <- tryCatch({
        Sys.sleep(.35) # KEGG permits at most three API calls per second.
        status <- fetch(url, temp, mode = "wb", quiet = TRUE)
        if (!identical(as.integer(status), 0L) || !valid_png(temp)) stop("未返回有效 PNG。")
        if (!file.copy(temp, cached, overwrite = TRUE)) stop("无法写入机制图缓存。")
        ""
      }, error = function(e) conditionMessage(e))
      unlink(temp)
    }
    name <- paste0("kegg_", id, "_mechanism.png")
    success <- !nzchar(error) && file.copy(cached, file.path(target, name), overwrite = TRUE)
    if (!success && !nzchar(error)) error <- "机制图无法复制到结果目录。"
    data.frame(pathway_id = id, source_url = url,
      pathway_url = paste0("https://www.kegg.jp/pathway/", id),
      file = if (success) paste0("kegg_maps/", name) else "", status = if (success) "downloaded" else "failed",
      sha256 = if (success) digest::digest(file = cached, algo = "sha256") else "",
      from_cache = from_cache,
      retrieved_utc = if (success) format(file.info(cached)$mtime, tz = "UTC", usetz = TRUE) else "", error = error)
  })
  report <- if (length(rows)) do.call(rbind, rows) else data.frame(pathway_id = character(),
    source_url = character(), pathway_url = character(), file = character(), status = character(),
    sha256 = character(), from_cache = logical(), retrieved_utc = character(), error = character())
  utils::write.csv(report, file.path(directory, "kegg_map_downloads.csv"), row.names = FALSE)
  if (any(report$status == "failed")) warning("部分 KEGG 官网机制图下载失败；详情和官网链接已写入 kegg_map_downloads.csv。")
  report
}
