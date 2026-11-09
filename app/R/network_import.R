# Node/edge 文件模式独立于 RNA-seq 模型，可使用任意一致的蛋白或基因 ID。
tb_import_network <- function(spec, output) {
  if (!requireNamespace("igraph", quietly = TRUE)) stop("PPI 网络需要 igraph。")
  nodes <- tb_read_preview(spec$inputs$nodes, n = -1)
  edges <- tb_read_preview(spec$inputs$edges, n = -1)
  find_column <- function(data, candidates, required = TRUE) {
    hit <- match(tolower(candidates), tolower(names(data)))
    hit <- hit[!is.na(hit)]
    if (!length(hit)) {
      if (required) stop("找不到字段：", paste(candidates, collapse = " / "))
      return(NULL)
    }
    names(data)[hit[1]]
  }
  source_field <- find_column(edges, c("from", "source", "source_id", "node1", "protein1"))
  target_field <- find_column(edges, c("to", "target", "target_id", "node2", "protein2"))
  endpoint_ids <- unique(trimws(c(as.character(edges[[source_field]]), as.character(edges[[target_field]]))))
  candidates <- intersect(c("id", "STRING_id", "gene_id", "name", "node", "protein_id"), names(nodes))
  if (!length(candidates)) candidates <- find_column(nodes, c("id", "STRING_id", "gene_id", "name", "node", "protein_id"))
  covered <- candidates[vapply(candidates, function(column) all(endpoint_ids %in% trimws(as.character(nodes[[column]]))), logical(1))]
  id <- if (length(covered)) covered[1] else candidates[1]
  if (id != "gene_id" && "gene_id" %in% names(nodes)) nodes$input_gene_id <- nodes$gene_id
  nodes$gene_id <- trimws(as.character(nodes[[id]]))
  if (!nrow(nodes) || anyNA(nodes$gene_id) || any(!nzchar(nodes$gene_id)) || anyDuplicated(nodes$gene_id)) {
    tb_fail("BW-I03", "Node ID 必须非空且唯一。", spec$inputs$nodes, "请补全 ID 并处理重复记录。")
  }
  label <- find_column(nodes, c("label", "gene_name", "symbol", "display_name"), FALSE)
  nodes$label <- if (is.null(label)) nodes$gene_id else as.character(nodes[[label]])
  nodes$label[is.na(nodes$label) | !nzchar(nodes$label)] <- nodes$gene_id[is.na(nodes$label) | !nzchar(nodes$label)]
  nodes$gene_name <- nodes$label
  fc <- find_column(nodes, c("log2FoldChange", "log2FC", "logFC"), FALSE)
  nodes$log2FoldChange <- if (is.null(fc)) NA_real_ else suppressWarnings(as.numeric(nodes[[fc]]))
  if (!is.null(fc) && any(!is.na(nodes[[fc]]) & !is.finite(nodes$log2FoldChange))) tb_fail("BW-I03", "Node log2FC 含非有限数值。", spec$inputs$nodes)
  group <- find_column(nodes, c("group", "class", "module", "cluster"), FALSE)
  nodes$group <- if (is.null(group)) "Nodes" else as.character(nodes[[group]])
  nodes$group[is.na(nodes$group) | !nzchar(nodes$group)] <- "Unassigned"
  source <- find_column(edges, c("from", "source", "source_id", "node1", "protein1"))
  target <- find_column(edges, c("to", "target", "target_id", "node2", "protein2"))
  score <- find_column(edges, c("score", "weight", "combined_score", "confidence"), FALSE)
  edges$from <- trimws(as.character(edges[[source]]))
  edges$to <- trimws(as.character(edges[[target]]))
  edges$score <- if (is.null(score)) rep(1, nrow(edges)) else suppressWarnings(as.numeric(edges[[score]]))
  if (anyNA(edges$from) || anyNA(edges$to) || any(!nzchar(edges$from)) || any(!nzchar(edges$to))) tb_fail("BW-I03", "Edge 端点不能空缺。", spec$inputs$edges)
  scale <- spec$params$network_score_scale
  if (scale == "auto") scale <- if (!is.null(score) && tolower(score) == "combined_score") "thousand" else "unit"
  if (scale == "thousand" && !is.null(score)) edges$score <- edges$score / 1000
  if (any(!is.finite(edges$score)) || any(edges$score < 0 | edges$score > 1)) {
    tb_fail("BW-I03", "边权重须在 0–1。", spec$inputs$edges, "若为 STRING 0–1000 分数，请选择相应分数单位。")
  }
  missing <- setdiff(unique(c(edges$from, edges$to)), nodes$gene_id)
  if (length(missing)) stop("Edge 中的 ID 未出现在 Node：", paste(head(missing, 12), collapse = ", "))
  self <- edges$from == edges$to
  filtered <- edges$score < spec$params$ppi_score
  excluded <- edges[self | filtered, , drop = FALSE]
  excluded$reason <- ifelse(self[self | filtered], "self_loop", "below_score")
  edges <- edges[!self & !filtered, , drop = FALSE]
  edges <- edges[order(edges$score, decreasing = TRUE), , drop = FALSE]
  key <- vapply(seq_len(nrow(edges)), function(i) paste(sort(c(edges$from[i], edges$to[i])), collapse = "\r"), character(1))
  edges <- edges[!duplicated(key), , drop = FALSE]
  edges <- edges[, c("from", "to", "score", setdiff(names(edges), c("from", "to", "score"))), drop = FALSE]
  graph <- igraph::graph_from_data_frame(edges[, c("from", "to", "score")], directed = FALSE,
                                          vertices = data.frame(name = nodes$gene_id))
  set.seed(1)
  coordinates <- if (nrow(nodes) == 1L) matrix(c(0, 0), ncol = 2) else if (!nrow(edges)) {
    igraph::layout_in_circle(graph)
  } else switch(spec$params$network_layout,
      fr = igraph::layout_with_fr(graph), kk = igraph::layout_with_kk(graph),
      circle = igraph::layout_in_circle(graph), grid = igraph::layout_on_grid(graph), stop("未知网络布局。"))
  order <- match(nodes$gene_id, igraph::V(graph)$name)
  nodes$x <- coordinates[order, 1]
  nodes$y <- coordinates[order, 2]
  nodes$degree <- unname(igraph::degree(graph)[nodes$gene_id])
  utils::write.csv(nodes, file.path(output, "ppi_nodes.csv"), row.names = FALSE, na = "")
  utils::write.csv(edges, file.path(output, "ppi_edges.csv"), row.names = FALSE)
  utils::write.csv(excluded, file.path(output, "excluded_edges.csv"), row.names = FALSE)
  list(type = "network", data = nodes, extras = list(edges = edges,
       score_source = if (is.null(score)) "unweighted_edges_assigned_1" else score,
       score_scale = scale, node_id_column = id, layout = spec$params$network_layout))
}

tb_prepare_ppi_topology <- function(bundle, root) {
  methods <- new.env(parent = baseenv())
  sys.source(file.path(root, "ppi-studio", "metrics.R"), envir = methods)
  edges <- bundle$extras$edges
  graph <- methods$ppi_graph(bundle$data, edges)
  weights <- pmax(edges$score, .Machine$double.eps)
  list(communities = methods$ppi_communities(graph, edges, weights),
       scores = methods$ppi_hub_scores(graph, weights),
       palettes = methods$ppi_palettes(tb_palettes()))
}

tb_write_interactive_network <- function(bundle, style, root, output) {
  # 离线供应 Cytoscape.js；输入属性仅作为 JSON 数据，绝不当作脚本执行。
  nodes <- bundle$data
  if (!"group" %in% names(nodes)) nodes$group <- "Nodes"
  mode <- style$network_color_by
  if (mode == "auto") mode <- if (any(is.finite(nodes$log2FoldChange))) "log2FC" else if (length(unique(nodes$group)) > 1) "group" else "uniform"
  if (mode == "log2FC") {
    limit <- max(abs(nodes$log2FoldChange), na.rm = TRUE)
    if (!is.finite(limit) || limit == 0) limit <- 1
    ramp <- tb_gradient_ramp(style, c(style$network_low, style$network_mid, style$network_high))
    colors <- circlize::colorRamp2(seq(-limit, limit, length.out = length(ramp)), ramp)(ifelse(is.finite(nodes$log2FoldChange), nodes$log2FoldChange, 0))
  } else if (mode == "group") {
    groups <- unique(nodes$group)
    palette <- stats::setNames(rep(tb_gradient_colors(style,
      c(style$network_node_color, "#B8523E", "#A89046", "#697C61", "#8F6D86")), length.out = length(groups)), groups)
    colors <- palette[nodes$group]
  } else colors <- rep(style$network_node_color, nrow(nodes))
  rgb <- grDevices::col2rgb(colors)
  colors <- grDevices::rgb(rgb[1, ], rgb[2, ], rgb[3, ], maxColorValue = 255)
  degrees <- range(nodes$degree)
  size <- if (diff(degrees) == 0) rep(mean(c(style$node_size_min, style$node_size_max)), nrow(nodes)) else {
    style$node_size_min + (nodes$degree - degrees[1]) / diff(degrees) * (style$node_size_max - style$node_size_min)
  }
  labels <- trimws(as.character(nodes$label))
  missing <- is.na(labels) | !nzchar(labels)
  labels[missing] <- nodes$gene_id[missing]
  selected <- head(order(-nodes$degree, nodes$gene_id), style$network_label_top)
  node_elements <- lapply(seq_len(nrow(nodes)), function(i) list(
    group = "nodes", data = list(id = nodes$gene_id[i], label = labels[i], degree = nodes$degree[i], index = i - 1L,
      color = unname(colors[i]), size = unname(size[i] * 5), displayLabel = if (style$network_labels && i %in% selected) labels[i] else ""),
    position = list(x = nodes$x[i] * 100, y = nodes$y[i] * 100)))
  edges <- bundle$extras$edges
  prefix <- "__bw_edge_"
  while (any(startsWith(nodes$gene_id, prefix))) prefix <- paste0("_", prefix)
  edge_elements <- lapply(seq_len(nrow(edges)), function(i) list(group = "edges", data = list(
    id = paste0(prefix, i), source = edges$from[i], target = edges$to[i], score = edges$score[i])))
  studio <- file.path(root, "ppi-studio")
  topology <- bundle$extras$topology %||% tb_prepare_ppi_topology(bundle, root)
  communities <- topology$communities
  scores <- topology$scores
  membership <- do.call(rbind, lapply(names(communities), function(method) {
    data.frame(method = method, node = nodes$gene_id, cluster = unlist(communities[[method]]$membership))
  }))
  utils::write.csv(membership, file.path(output, "ppi_communities.csv"), row.names = FALSE)
  utils::write.csv(data.frame(node = nodes$gene_id, lapply(scores, unlist)),
    file.path(output, "ppi_hub_scores.csv"), row.names = FALSE)
  data <- list(elements = c(node_elements, edge_elements), palettes = topology$palettes,
    edgeColor = style$network_edge_color, edgeWidth = style$network_edge_width * 3,
    edgeAlpha = style$network_edge_alpha, background = style$background)
  vendor <- file.path(root, "www", "vendor")
  sources <- c(file.path(vendor, c("cytoscape.min.js", "CYTOSCAPE-LICENSE.txt")),
    file.path(studio, c("editor.js", "analysis.js", "methods.js", "algorithms.html")))
  targets <- file.path(output, c("cytoscape.min.js", "CYTOSCAPE-LICENSE.txt",
    "network-editor.js", "ppi-analysis.js", "ppi-methods.js", "ppi-algorithms.html"))
  if (!all(file.copy(sources, targets, overwrite = TRUE))) stop("缺少离线网络编辑资源。")
  read_text <- function(file) paste(readLines(file, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  render <- function(advanced) {
    payload <- if (advanced) c(data, list(communities = communities, scores = scores)) else data
    encoded <- jsonlite::toJSON(payload, auto_unbox = TRUE, na = "null")
    encoded <- gsub("<", "\\u003c", encoded, fixed = TRUE)
    html <- read_text(file.path(studio, "template.html"))
    replacements <- c(
      "__EDITOR_MODE__" = if (advanced) "advanced" else "basic",
      "__EDITOR_TITLE__" = if (advanced) "PPI Studio · 精细编辑" else "PPI 基础编辑",
      "__EDITOR_LINK__" = if (advanced) "" else '<a class="edit-link" href="ppi-studio.html" target="_blank" rel="noopener">精细编辑 ↗</a>',
      "__ADVANCED_TOOLS__" = if (advanced) read_text(file.path(studio, "advanced.html")) else "",
      "__ADVANCED_SCRIPTS__" = if (advanced) '<script src="ppi-methods.js"></script><script src="ppi-analysis.js"></script>' else ""
    )
    for (key in names(replacements)) html <- gsub(key, replacements[[key]], html, fixed = TRUE)
    parts <- strsplit(html, "__NETWORK_DATA__", fixed = TRUE)[[1]]
    writeLines(tb_localize_editor(paste0(parts[1], encoded, parts[2]), root),
      file.path(output, if (advanced) "ppi-studio.html" else "network.html"), useBytes = TRUE)
  }
  render(FALSE)
  render(TRUE)
}
