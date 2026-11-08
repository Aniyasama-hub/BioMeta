# One entry per line preserves pathway names containing spaces. Tables may be
# one column (one item per row) or one row (one pathway per column).
tb_read_items <- function(text = "", path = "", one_row = FALSE) {
  items <- trimws(unlist(strsplit(text %||% "", "[\r\n]+")))
  if (nzchar(path %||% "")) {
    extension <- tolower(tools::file_ext(path))
    table <- if (extension == "xlsx") as.data.frame(readxl::read_excel(path, col_names = FALSE)) else
      utils::read.table(path, header = FALSE, sep = if (extension %in% c("txt", "tsv")) "\t" else ",",
        quote = '"', comment.char = "", fill = TRUE, stringsAsFactors = FALSE,
        colClasses = "character", fileEncoding = "UTF-8-BOM")
    if (!one_row && ncol(table) != 1L) stop("请使用只有一列名称的表格。")
    if (one_row && ncol(table) > 1L && nrow(table) > 1L) stop("通路名称表请使用单列或单行。")
    values <- trimws(as.character(unlist(table, use.names = FALSE)))
    values <- values[!is.na(values) & !tolower(values) %in%
      c("gene", "gene_name", "genekey", "基因名", "pathway", "pathway_name", "通路名", "通路名称")]
    items <- c(items, values)
  }
  unique(items[!is.na(items) & nzchar(items)])
}

# Highlight requests never enter ORA/GSEA/GSVA selection or hypothesis testing.
tb_mark_pathway_targets <- function(pathways, spec, output, engine) {
  targets <- tb_pathway_input(spec)
  gsva <- spec$tool == "gsva"
  key <- if (gsva) "gsva" else "ora"
  table <- pathways[[key]]$results
  ids <- as.character(table[[if (gsva) "term_id" else "ID"]])
  labels <- as.character(table[[if (gsva) "description" else "Description"]])
  clean <- tb_pathway_key
  table$target_pathway <- clean(ids) %in% clean(targets) | clean(labels) %in% clean(targets)
  report <- lapply(targets, function(target) {
    hit <- which(clean(ids) == clean(target) | clean(labels) == clean(target))
    if (!length(hit)) return(data.frame(requested = target, term_id = NA_character_,
      description = NA_character_, in_results = FALSE))
    data.frame(requested = target, term_id = ids[hit], description = labels[hit], in_results = TRUE)
  })
  pathways$target_report <- if (length(report)) do.call(rbind, report) else data.frame(
    requested = character(), term_id = character(), description = character(), in_results = logical())
  pathways[[key]]$results <- table
  engine$write_table(table, file.path(output, if (gsva) "gsva_limma_results.csv" else "ora_results.csv"))
  pathways
}

tb_annotation_template <- function() data.frame(
  编号 = c("ENSMUSG00000000001", "ENSMUSG00000000001"),
  基因名 = c("Gnai3", "Gnai3"), 通路名 = c("目的通路 A", "目的通路 B"),
  是否纳入注释 = c("TRUE", "FALSE"), check.names = FALSE)

tb_read_annotation <- function(path) {
  data <- if (tolower(tools::file_ext(path)) == "xlsx")
    as.data.frame(readxl::read_excel(path, sheet = "GeneAnnotation")) else tb_read_preview(path, -1)
  aliases <- list(gene_id = c("编号", "gene_id"), gene_name = c("基因名", "gene_name", "GeneKey"),
    Pathway = c("通路名", "通路名称", "Pathway"), Use = c("是否纳入注释", "Use"))
  result <- lapply(aliases, function(keys) {
    found <- intersect(keys, names(data))
    if (length(found)) trimws(as.character(data[[found[1L]]])) else rep("", nrow(data))
  })
  result <- as.data.frame(result, stringsAsFactors = FALSE)
  if (!nrow(result)) stop("注释表为空。")
  if (any(!toupper(result$Use) %in% c("", "TRUE", "FALSE", "1", "0", "是", "否")))
    stop("是否纳入注释只能填写 TRUE/FALSE、1/0 或 是/否。")
  result$Use <- !toupper(result$Use) %in% c("FALSE", "0", "否")
  if (any(result$Use & (!nzchar(result$Pathway) | (!nzchar(result$gene_id) & !nzchar(result$gene_name)))))
    stop("纳入的记录必须填写通路名，以及基因编号或基因名。")
  result
}

tb_annotated_heatmap <- function(spec, cfg, analysis, root, directory, engine) {
  output <- file.path(directory, "outputs")
  if (spec$params$linkage == "ward.D2" && spec$params$distance != "euclidean")
    stop("Ward.D2 聚类须搭配欧氏距离。")
  expression <- engine$choose_expression(analysis, cfg$selection)
  genes <- analysis$genes
  if (is.null(analysis$deg)) stop("通路注释热图需要完整 DEG 表。")
  if (identical(spec$params$annotation_mode, "auto")) {
    terms <- tb_pathway_input(spec, TRUE)
    if (!length(terms)) stop("请输入或上传目的通路名称 / ID，每行一项。")
    if (spec$params$annotation_source == "custom") {
      source <- spec$inputs$gmt
    } else {
      request <- spec; request$params$pathway_source <- spec$params$annotation_source
      request$params$go_ontology <- c("BP", "CC", "MF")
      public <- tb_public_pathways(cfg, request, genes, root, directory, engine)
      source <- public$pathways$gmt
      engine$write_manifest(public$pathways, file.path(output, "annotation_source.json"))
    }
    gmt <- engine$.read_local_gmt(source)
    sets <- split(gmt$term2gene$gene, gmt$term2gene$term_id)
    descriptions <- stats::setNames(gmt$term2name$description, gmt$term2name$term_id)
    records <- lapply(terms, function(term) {
      hits <- names(sets)[tb_pathway_key(names(sets)) == tb_pathway_key(term) |
        tb_pathway_key(descriptions[names(sets)]) == tb_pathway_key(term)]
      hits <- hits[!is.na(hits)]
      if (!length(hits)) stop("目的通路未精确匹配名称或 ID：", term,
        "。请使用所选库中的正式名称或稳定 ID。")
      do.call(rbind, lapply(hits, function(id) data.frame(gene_id = "", gene_name = sets[[id]],
        Pathway = descriptions[[id]], Use = TRUE, stringsAsFactors = FALSE)))
    })
    annotation <- unique(do.call(rbind, records))
  } else annotation <- tb_read_annotation(spec$inputs$annotation)

  # Stable identifiers take precedence; an explicit mismatch is reported rather
  # than silently falling back to a different gene with the same symbol.
  mapping <- lapply(seq_len(nrow(annotation)), function(i) {
    row <- annotation[i, ]
    candidates <- if (nzchar(row$gene_id)) which(genes$gene_id == row$gene_id) else
      which(genes$gene_name == row$gene_name | genes$gene_id == row$gene_name)
    if (!length(candidates)) return(data.frame(row, matched_id = NA_character_, status = "unmatched"))
    conflict <- nzchar(row$gene_id) && nzchar(row$gene_name) &&
      !row$gene_name %in% c(genes$gene_name[candidates], genes$gene_id[candidates])
    data.frame(row[rep(1L, length(candidates)), ], matched_id = genes$gene_id[candidates],
      status = if (!row$Use) "excluded" else if (conflict) "name_conflict" else if (length(candidates) > 1L) "ambiguous" else "matched")
  })
  report <- do.call(rbind, mapping)
  engine$write_table(report, file.path(output, "annotation_match_report.csv"))
  mapped <- report[report$Use & report$status == "matched", , drop = FALSE]
  mapped <- mapped[mapped$matched_id %in% rownames(expression), , drop = FALSE]
  joined <- merge(mapped, analysis$deg, by.x = "matched_id", by.y = "gene_id", suffixes = c("_input", ""), sort = FALSE)
  if (!nrow(joined)) stop("纳入的注释未匹配表达矩阵与 DEG，请查看匹配报告。")
  # A gene belonging to two pathways occurs in both blocks; never sum it twice.
  joined <- unique(joined)
  joined <- joined[order(match(joined$Pathway, unique(mapped$Pathway)), joined$padj,
    -abs(joined$log2FoldChange), joined$matched_id), , drop = FALSE]
  ids <- head(unique(joined$matched_id), spec$params$heatmap_top)
  joined <- joined[joined$matched_id %in% ids, , drop = FALSE]
  matrix <- expression[joined$matched_id, , drop = FALSE]
  keep <- apply(matrix, 1L, function(x) all(is.finite(x)) && stats::sd(x) > 0)
  joined <- joined[keep, , drop = FALSE]; matrix <- matrix[keep, , drop = FALSE]
  if (!nrow(matrix)) stop("匹配基因无可绘制的非恒定表达。")
  rownames(matrix) <- make.unique(paste(joined$matched_id, joined$Pathway, sep = " | "))
  engine$write_table(cbind(joined, as.data.frame(matrix, check.names = FALSE)), file.path(output, "annotated_expression.csv"))
  before <- matrix
  if (spec$params$row_scale) matrix <- t(scale(t(matrix)))
  selection <- cfg$selection
  order_rows <- function(ids) if (isTRUE(spec$params$cluster_rows) && length(ids) > 1L)
    ids[stats::hclust(engine$compute_distance(matrix[ids, , drop = FALSE], selection$distance), method = selection$linkage)$order] else ids
  order <- if (isTRUE(spec$params$pathway_cluster)) unlist(lapply(
    split(seq_len(nrow(matrix)), factor(joined$Pathway, levels = unique(joined$Pathway))), order_rows), use.names = FALSE)
    else order_rows(seq_len(nrow(matrix)))
  samples <- analysis$samples[colnames(matrix), c("condition", "batch"), drop = FALSE]
  list(type = "heatmap", data = matrix, extras = list(
    matrix_units = if (spec$params$row_scale) "row_zscore" else "Expression",
    row_order = order, column_order = engine$heatmap_column_plan(matrix, samples, selection),
    row_labels = genes$gene_name[match(joined$matched_id, genes$gene_id)],
    row_annotation = data.frame(Pathway = joined$Pathway), sample_annotation = samples,
    pathway_cluster = spec$params$pathway_cluster, expression_before_scale = before,
    clustering = selection[c("cluster_rows", "cluster_columns", "distance", "linkage", "column_cluster_mode")]))
}
