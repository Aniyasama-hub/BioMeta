# Public references are downloaded without sending expression, gene IDs or sample data.
tb_public_table <- function(source, species, root, fetch = utils::download.file) {
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

tb_entrez_ids <- function(genes, db) {
  ids <- as.character(genes$gene_id)
  lookup <- function(values, type) {
    keys <- intersect(unique(values), AnnotationDbi::keys(db, keytype = type))
    result <- if (type == "ENTREZID") stats::setNames(keys, keys) else if (length(keys)) {
      suppressMessages(AnnotationDbi::mapIds(db, keys, "ENTREZID", type, multiVals = "asNA"))
    } else stats::setNames(character(), character())
    unname(result[values])
  }
  entrez <- lookup(ids, "ENTREZID")
  missing <- is.na(entrez)
  entrez[missing] <- lookup(sub("[.][0-9]+$", "", ids[missing]), "ENSEMBL")
  missing <- is.na(entrez)
  entrez[missing] <- lookup(as.character(genes$gene_name[missing]), "SYMBOL")
  entrez
}

tb_public_pathways <- function(cfg, spec, genes, root, directory, engine, terms = NULL) {
  source <- spec$params$pathway_source
  species <- spec$params$species
  package <- if (species == "human") "org.Hs.eg.db" else "org.Mm.eg.db"
  engine$require_packages(c(package, "AnnotationDbi"))
  db <- getExportedValue(package, package)
  map <- unique(data.frame(gene = tb_entrez_ids(genes, db), gene_id = genes$gene_id))
  map <- map[!is.na(map$gene), ]
  if (!nrow(map)) stop("未识别该物种的基因 ID。请使用 Entrez、Ensembl 或物种对应的基因符号。")
  if (source == "go") {
    engine$require_packages("GO.db")
    table <- suppressMessages(AnnotationDbi::select(db, unique(map$gene),
      c("GOALL", "ONTOLOGYALL"), "ENTREZID"))
    ontologies <- tb_go_ontologies(spec$params$go_ontology)
    table <- table[!is.na(table$GOALL) & table$ONTOLOGYALL %in% ontologies, ]
    if (!nrow(table)) stop("该物种与 GO 类别没有可匹配的注释。")
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
  if (!nrow(hits)) stop("公共基因集与当前输入没有匹配。请核对物种和基因 ID。")
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
  cfg
}
