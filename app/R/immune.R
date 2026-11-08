tb_immune_sources <- c("免疫细胞标志 · MSigDB" = "cell", "免疫状态 · MSigDB" = "state",
  "疾病相关签名 · MSigDB" = "disease", "免疫过程 · GO BP" = "go",
  "免疫通路 · KEGG" = "kegg", "上传自建 GMT" = "custom")

tb_immune_reference <- function(root, species, source) {
  human <- species == "human"
  taxon <- if (human) "Hs" else "Mm"
  collection <- switch(source, cell = if (human) "c8.all" else "m8.all",
    state = if (human) "c7.all" else "m7.all", disease = if (human) "c7.all" else "m2.cgp")
  release <- paste0("2025.1.", taxon)
  file <- paste0(collection, ".v", release, ".symbols.gmt")
  list(path = file.path(root, "results", "toolbox", "references", file), version = release,
    url = paste0("https://data.broadinstitute.org/gsea-msigdb/msigdb/release/", release, "/", file))
}

tb_immune_choices <- function(root, species, source) {
  if (source == "go") return(c("免疫应答" = "GO:0006955", "炎症反应" = "GO:0006954",
    "适应性免疫应答" = "GO:0002250", "先天免疫应答" = "GO:0045087",
    "细胞因子产生" = "GO:0001816", "干扰素 β 应答" = "GO:0035456", "抗病毒防御" = "GO:0051607"))
  if (source == "kegg") return(stats::setNames(
    paste0(if (species == "human") "hsa" else "mmu", c("04620", "04650", "04660", "04662", "04060", "04630")),
    c("Toll 样受体", "NK 细胞介导的细胞毒性", "T 细胞受体", "B 细胞受体", "细胞因子与受体互作", "JAK–STAT")))
  if (source == "custom") return(character())
  path <- tb_immune_reference(root, species, source)$path
  if (!file.exists(path)) return(character())
  ids <- sub("\t.*", "", readLines(path, warn = FALSE))
  pattern <- switch(source, cell = "MACROPHAGE|MONOCYTE|NEUTROPHIL|DENDRITIC|LYMPHOCYTE|B_CELL|T_CELL|NK_CELL|CD4|CD8",
    disease = "LUPUS|ARTHRIT|DIABET|COLITIS|ASTHMA|SEPSIS|PSORIASIS|TUMOR", ".")
  unique(ids[grepl(pattern, ids)])
}

tb_immune_markers <- function(spec, genes, root, output, engine) {
  source <- spec$params$immune_source
  species <- spec$params$species
  terms <- unique(as.character(spec$params$immune_terms))
  read_sets <- function(path) {
    gmt <- engine$.read_local_gmt(path)
    split(gmt$term2gene$gene, gmt$term2gene$term_id)
  }
  match_symbols <- FALSE
  if (source == "custom") {
    markers <- read_sets(spec$inputs$gmt)
    reference <- list(version = spec$params$database_version,
      sha256 = digest::digest(file = spec$inputs$gmt, algo = "sha256"))
  } else {
    choices <- unname(tb_immune_choices(root, species, source))
    if (!length(terms) || length(terms) > 40L || !all(terms %in% choices))
      stop("请选择当前物种和来源中的 1–40 个预设基因集。")
    if (source %in% c("go", "kegg")) {
      spec$params$pathway_source <- source
      spec$params$go_ontology <- "BP"
      cfg <- tb_public_pathways(list(pathways = list()), spec,
        data.frame(gene_id = genes, gene_name = genes), root, dirname(output), engine,
        terms = terms)$pathways
      markers <- read_sets(cfg$gmt)
      reference <- list(version = cfg$database_version, url = cfg$reference_urls, sha256 = cfg$reference_sha256)
    } else {
      preset <- tb_immune_reference(root, species, source)
      lines <- readLines(preset$path, warn = FALSE)
      rows <- strsplit(lines[sub("\t.*", "", lines) %in% terms], "\t", fixed = TRUE)
      markers <- stats::setNames(lapply(rows, function(row) unique(row[-c(1, 2)])),
        vapply(rows, `[`, character(1), 1L))
      reference <- list(version = preset$version, url = preset$url,
        sha256 = digest::digest(file = preset$path, algo = "sha256"))
      match_symbols <- TRUE
    }
    markers <- stats::setNames(lapply(terms, function(term) markers[[term]] %||% character()), terms)
  }
  symbols <- genes
  if (match_symbols) {
    package <- if (species == "human") "org.Hs.eg.db" else "org.Mm.eg.db"
    engine$require_packages(c(package, "AnnotationDbi"))
    db <- getExportedValue(package, package)
    ids <- tb_entrez_ids(data.frame(gene_id = genes, gene_name = genes), db)
    if (any(!is.na(ids))) {
      mapped <- suppressMessages(AnnotationDbi::mapIds(db, unique(stats::na.omit(ids)), "SYMBOL", "ENTREZID", multiVals = "asNA"))
      symbols <- unname(mapped[ids])
    }
  }
  reference <- c(list(source = source, species = species, terms = names(markers)), reference)
  engine$write_manifest(reference, file.path(output, "immune_reference.json"))
  list(markers = markers, matched = lapply(markers, function(set) genes[genes %in% set | symbols %in% set]))
}


# 按样本计算基因集的 ssGSEA 分数；自建 GMT 按输入 ID 精确匹配。
tb_immune_bundle <- function(spec, engine, output, root) {
  engine$require_packages(c("GSVA", "BiocParallel"))
  expression <- tb_read_matrix(spec$inputs$matrix, list(matrix_transform = "none"))
  if (anyDuplicated(colnames(expression)) || any(!nzchar(colnames(expression)))) {
    stop("表达矩阵样本名必须非空且唯一。")
  }
  minimum <- spec$params$immune_min_genes
  if (!is.finite(minimum) || minimum < 2 || minimum != as.integer(minimum)) {
    stop("最少匹配基因数须为至少 2 的整数。")
  }
  sets <- tb_immune_markers(spec, rownames(expression), root, output, engine)
  markers <- sets$markers
  matched <- sets$matched
  keep <- lengths(matched) >= minimum & lengths(matched) < nrow(expression)
  utils::write.csv(data.frame(signature = names(markers), supplied = lengths(markers),
    matched = lengths(matched), used = keep), file.path(output, "immune_marker_coverage.csv"), row.names = FALSE)
  if (!any(keep)) stop("没有满足覆盖要求的标志基因集，请检查物种、基因 ID 和最小匹配数。")
  # 关闭跨样本范围归一化，保留每个样本的 ssGSEA 原始分数。
  param <- GSVA::ssgseaParam(expression, matched[keep], minSize = minimum, normalize = FALSE)
  scores <- GSVA::gsva(param, verbose = FALSE, BPPARAM = BiocParallel::SerialParam())
  utils::write.csv(data.frame(signature = rownames(scores), scores, check.names = FALSE),
    file.path(output, "immune_scores.csv"), row.names = FALSE)
  matched_table <- stack(matched[keep])
  names(matched_table) <- c("gene_id", "signature")
  utils::write.csv(matched_table, file.path(output, "immune_matched_markers.csv"), row.names = FALSE)
  list(type = "heatmap", data = scores,
    extras = list(matrix_units = "ssGSEA score", row_labels = rownames(scores),
      clustering = list(cluster_rows = TRUE, cluster_columns = TRUE, distance = "euclidean", linkage = "complete", column_cluster_mode = "global"),
      row_order = seq_len(nrow(scores)), column_order = seq_len(ncol(scores))))
}
