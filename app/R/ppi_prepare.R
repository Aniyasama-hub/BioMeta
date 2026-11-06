# 只使用本地 STRING 风格边表，并为显著差异基因生成可复现布局坐标。
.run_ppi <- function(deg, cfg, output_dir) {
  edges_path <- cfg$pathways$ppi_edges
  if (is.null(edges_path) || !file.exists(edges_path)) stop("启用 PPI 时需提供本地 cfg$pathways$ppi_edges CSV。", call. = FALSE)
  edges <- read_table(edges_path)
  field <- function(options) {
    index <- match(options, tolower(names(edges)))
    index <- index[!is.na(index)]
    if (!length(index)) stop("互作参考边表缺少字段：", paste(options, collapse = " / "))
    names(edges)[index[1L]]
  }
  from <- field(c("from", "source", "source_id", "node1", "protein1"))
  to <- field(c("to", "target", "target_id", "node2", "protein2"))
  score <- field(c("score", "combined_score", "confidence", "weight"))
  scale <- cfg$pathways$ppi_score_scale %||% "auto"
  divisor <- if (scale == "thousand" || (scale == "auto" && tolower(score) == "combined_score")) 1000 else 1
  edges <- data.frame(from = trimws(as.character(edges[[from]])), to = trimws(as.character(edges[[to]])),
    score = suppressWarnings(as.numeric(edges[[score]])) / divisor)
  if (anyNA(edges$from) || anyNA(edges$to) || any(!nzchar(edges$from)) || any(!nzchar(edges$to)))
    stop("互作参考边表的端点 ID 不能为空。")
  if (any(!is.finite(edges$score) | edges$score < 0 | edges$score > 1)) {
    stop("PPI score 必须是 [0,1] 内的有限数值。", call. = FALSE)
  }
  edges <- edges[edges$score >= cfg$pathways$ppi_score & edges$from != edges$to, , drop = FALSE]
  # 同一无向边重复出现时保留最高置信度，避免结果取决于输入行顺序。
  edges <- edges[order(edges$score, decreasing = TRUE), , drop = FALSE]
  edge_key <- vapply(seq_len(nrow(edges)), function(i) paste(sort(c(edges$from[[i]], edges$to[[i]])), collapse = "\r"), character(1))
  edges <- edges[!duplicated(edge_key), , drop = FALSE]
  selected <- deg[selection_mask(deg, cfg$selection), , drop = FALSE]
  selected <- selected[!duplicated(selected$gene_id), , drop = FALSE]
  ids <- unique(as.character(selected$gene_id))
  edges <- edges[edges$from %in% ids & edges$to %in% ids, , drop = FALSE]
  if (isTRUE(cfg$pathways$ppi_require_edges) && !nrow(edges))
    stop("当前差异阈值与置信分数下没有匹配的互作边，请检查基因 ID 或调整筛选条件。")
  nodes <- merge(data.frame(gene_id = ids), selected[c("gene_id", "gene_name", "log2FoldChange", "padj")], by = "gene_id", all.x = TRUE, sort = FALSE)
  if (nrow(nodes)) {
    graph <- igraph::graph_from_data_frame(edges[c("from", "to", "score")], directed = FALSE, vertices = data.frame(name = nodes$gene_id))
    degree <- igraph::degree(graph)
    if (nrow(nodes) == 1L) {
      coordinates <- matrix(c(0, 0), nrow = 1L)
    } else {
      set.seed(cfg$pathways$seed)
      coordinates <- switch(cfg$pathways$ppi_layout %||% "fr", fr = igraph::layout_with_fr(graph),
        kk = igraph::layout_with_kk(graph), circle = igraph::layout_in_circle(graph),
        grid = igraph::layout_on_grid(graph), stop("未知网络布局。"))
    }
    vertex_names <- igraph::V(graph)$name
    nodes <- nodes[match(vertex_names, nodes$gene_id), , drop = FALSE]
    nodes$x <- coordinates[match(nodes$gene_id, vertex_names), 1]
    nodes$y <- coordinates[match(nodes$gene_id, vertex_names), 2]
    nodes$degree <- unname(degree[match(nodes$gene_id, names(degree))])
    nodes$label <- ifelse(is.na(nodes$gene_name) | nodes$gene_name == "", nodes$gene_id, nodes$gene_name)
  } else {
    nodes$x <- numeric()
    nodes$y <- numeric()
    nodes$degree <- integer()
    nodes$label <- character()
  }
  .write_pathway_table(nodes, file.path(output_dir, "ppi_nodes.csv"))
  .write_pathway_table(edges, file.path(output_dir, "ppi_edges.csv"))
  saveRDS(list(nodes = nodes, edges = edges), file.path(output_dir, "ppi_network.rds"))
  list(nodes = nodes, edges = edges)
}

# Standalone entry point. A sourced copy only defines the preparation functions.
if (sys.nframe() == 0L) {
  script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])
  root <- dirname(dirname(normalizePath(script, winslash = "/", mustWork = TRUE)))
  source(file.path(root, "R", "toolbox.R"), encoding = "UTF-8")
  args <- commandArgs(TRUE)
  if (length(args) < 3L || !args[1L] %in% c("human", "mouse") || !args[2L] %in% c("deg", "count")) {
    stop("用法：Rscript ppi_prepare.R human|mouse deg DEG.csv [Edge.csv]\n",
      "或 Rscript ppi_prepare.R human|mouse count Count.csv Group.csv Control Treatment [Edge.csv]")
  }
  count <- args[2L] == "count"
  required <- if (count) 6L else 3L
  if (length(args) < required) stop("缺少 Count、分组表或比较组。")
  if (length(args) > required + 1L) stop("输入参数过多。")
  paths <- if (count) list(counts = args[3L], groups = args[4L]) else list(deg = args[3L])
  paths$edges <- args[if (count) 7L else 4L]
  if (is.na(paths$edges)) paths$edges <- ""
  params <- list(species = args[1L], network_mode = if (count) "deg" else "results",
    ppi_reference = TRUE, ppi_require_edges = TRUE, ppi_tables_only = TRUE)
  if (count) {
    params$control <- args[5L]
    params$treatment <- args[6L]
  }
  job <- tb_launch_job(list(tool = "network", inputs = paths, params = params,
    style = list(formats = "png")), root)
  job$process$wait()
  result <- tb_read_job(job$directory)
  if (result$status != "completed") stop(result$error %||% result$summary)
  cat(file.path(job$directory, "outputs", c("ppi_nodes.csv", "ppi_edges.csv")), sep = "\n")
}
