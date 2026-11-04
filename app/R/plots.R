.presentation_defaults <- function() list(
  font_family = "sans", background = "#FFFFFF", plot_theme = "classic", point_shape = "16",
  group_a = "#426C87", group_b = "#B8523E", threshold_color = "#847D72", threshold_width = 0.5,
  na_color = "#E1DDD3", cell_border = "#FFFFFF", cell_border_width = 0.3,
  row_font_size = 11, column_font_size = 10, column_rotation = 45, show_gene_names = TRUE, heatmap_raster = FALSE,
  enrichment_kind = "dot", enrichment_low = "#B9C8BB", enrichment_high = "#B44A37",
  enrichment_size_min = 3, enrichment_size_max = 9, term_wrap = 38,
  curve_color = "#A44032", curve_width = 0.9, positive_color = "#B8523E", negative_color = "#426C87", rug_color = "#292F2D", rug_width = 0.3,
  network_color_by = "auto", network_node_color = "#426C87", network_low = "#426C87", network_mid = "#EAE5D9", network_high = "#B8523E",
  node_size_min = 3, node_size_max = 10, network_edge_color = "#A39F95", network_edge_width = 0.5, network_edge_alpha = 0.55,
  network_labels = TRUE, network_label_top = 30, chromosome_color = "#426C87", feature_color = "#BE6542", link_color = "#B8523E",
  link_alpha = 0.45, start_degree = 90, gap_degree = 4, track_height = 0.11, circos_label_size = 0.7, pca_3d_angle = 40)


# 纯绘图模块：仅接收准备好的数据，不执行筛选、标准化或聚类。

# 空值回退函数，避免依赖其他模块或全局对象。
`%||%` <- function(x, y) if (is.null(x)) y else x

# 固定莫兰迪色板；分类水平按出现顺序循环使用，确保配色可复现。
.morandi_palette <- c("#7897B8", "#D99A9F", "#A9B8A5", "#B4A6BC", "#D8C5A5", "#9FB8B6", "#C7B5A8", "#ADB2BE")

# 为分类水平匹配用户颜色，并用固定莫兰迪色板补齐未指定水平。
.group_palette <- function(levels, supplied = NULL, palette = .morandi_palette) {
  colors <- supplied %||% character()
  missing <- setdiff(levels, names(colors))
  if (length(missing)) {
    generated <- rep(palette, length.out = length(missing))
    names(generated) <- missing
    colors <- c(colors, generated)
  }
  colors[levels]
}

# 样式默认值；可通过 render_bundle() 的 style 参数覆盖。
.default_plot_style <- function() {
  list(
    width = 10, height = 8, dpi = 300, base_size = 14,
    point_size = 2, point_alpha = 0.8, label_size = 3,
    colors = c(Up = "#D99A9F", Down = "#7897B8", Not_significant = "#ADB2BE"),
    group_colors = NULL, palette = .morandi_palette,
    low = "#7897B8", mid = "#E8DFD2", high = "#D99A9F",
    z_limit = 2, formats = c("png", "svg", "tiff", "pdf"),
    legend_position = "right", show_gene_names = TRUE, show_sample_labels = TRUE
  )
}

# 合并设置并规范颜色输入，避免 list 传入 ggplot/ComplexHeatmap 后类型不兼容。
.resolve_plot_style <- function(style) {
  result <- utils::modifyList(utils::modifyList(.default_plot_style(), .presentation_defaults()), style %||% list())
  result$formats <- tolower(result$formats)
  allowed_formats <- c("png", "svg", "tiff", "pdf")
  if (!length(result$formats) || !all(result$formats %in% allowed_formats)) {
    stop("style$formats 仅支持 png、svg、tiff、pdf。", call. = FALSE)
  }
  result$colors <- unlist(result$colors, use.names = TRUE)
  if (!is.null(result$group_colors)) {
    result$group_colors <- unlist(result$group_colors, use.names = TRUE)
  }
  result$palette <- unlist(result$palette, use.names = FALSE)
  if (!length(result$palette)) stop("style$palette 不能为空。", call. = FALSE)
  sides <- c("left", "right", "top", "bottom")
  if (length(result$legend_position) != 1L || !result$legend_position %in% sides) {
    stop("style$legend_position 仅支持 left、right、top、bottom。", call. = FALSE)
  }
  result
}

# ggplot 图统一使用英寸尺寸；svg 采用 svglite，tiff 使用 LZW 压缩。
.save_ggplot_bundle <- function(plot, output_dir, style) {
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  paths <- file.path(output_dir, paste0("figure.", style$formats))
  for (i in seq_along(style$formats)) {
    format <- style$formats[[i]]
    args <- list(
      filename = paths[[i]], plot = plot, width = style$width,
      height = style$height, units = "in", dpi = style$dpi, bg = style$background
    )
    if (format == "svg") args$device <- svglite::svglite
    if (format == "tiff") {
      args$device <- "tiff"
      args$compression <- "lzw"
    }
    do.call(ggplot2::ggsave, args)
  }
  paths
}

# 安全打开 grid 设备并绘制热图，on.exit 确保异常时关闭当前设备。
.draw_heatmap_file <- function(heatmap, path, format, style) {
  if (format == "png") grDevices::png(path, width = style$width, height = style$height, units = "in", res = style$dpi, bg = style$background)
  if (format == "svg") svglite::svglite(path, width = style$width, height = style$height, bg = style$background)
  if (format == "tiff") grDevices::tiff(path, width = style$width, height = style$height, units = "in", res = style$dpi, compression = "lzw", bg = style$background)
  if (format == "pdf") grDevices::pdf(path, width = style$width, height = style$height, bg = style$background, family = style$font_family)
  on.exit(grDevices::dev.off(), add = TRUE)
  ComplexHeatmap::draw(heatmap, heatmap_legend_side = style$legend_position, background = style$background)
}

# 导出 ComplexHeatmap 至要求的图像格式。
.save_heatmap_bundle <- function(heatmap, output_dir, style) {
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  paths <- file.path(output_dir, paste0("figure.", style$formats))
  for (i in seq_along(style$formats)) {
    .draw_heatmap_file(heatmap, paths[[i]], style$formats[[i]], style)
  }
  paths
}


.plot_theme <- function(style, void = FALSE) {
  theme <- if (void) ggplot2::theme_void(base_size = style$base_size, base_family = style$font_family) else {
    switch(style$plot_theme, minimal = ggplot2::theme_minimal, bw = ggplot2::theme_bw,
           ggplot2::theme_classic)(base_size = style$base_size, base_family = style$font_family)
  }
  theme + ggplot2::theme(legend.position = style$legend_position,
    plot.background = ggplot2::element_rect(fill = style$background, color = NA),
    panel.background = ggplot2::element_rect(fill = style$background, color = NA))
}

# PCA 图使用输入坐标和已计算的方差比例。
.plot_pca <- function(data, extras, style) {
  required <- c("sample_id", "condition", "PC1", "PC2")
  if (!all(required %in% names(data))) stop("PCA data 缺少必要列。", call. = FALSE)
  variance <- extras$variance
  if (length(variance) < 2) stop("PCA extras$variance 需包含 PC1、PC2 方差百分比。", call. = FALSE)
  data$condition <- as.factor(data$condition)
  p <- ggplot2::ggplot(data, ggplot2::aes(x = PC1, y = PC2, color = condition)) +
    ggplot2::geom_point(size = style$point_size, alpha = style$point_alpha, shape = as.integer(style$point_shape)) +
    ggplot2::labs(x = sprintf("PC1 (%.1f%%)", variance[[1]]), y = sprintf("PC2 (%.1f%%)", variance[[2]]), color = NULL) +
    .plot_theme(style)
  p <- p + ggplot2::scale_color_manual(values = .group_palette(levels(data$condition), style$group_colors, style$palette))
  if (style$show_sample_labels) {
    p <- p + ggrepel::geom_text_repel(
      ggplot2::aes(label = sample_id), size = style$label_size,
      seed = 1, show.legend = FALSE
    )
  }
  p
}

# 火山图只显示输入数据标记的标签，不重新计算显著性筛选。
.plot_volcano <- function(data, extras, style) {
  required <- c("gene_id", "gene_name", "log2FoldChange", "padj", "minus_log10_padj", "regulation", "label")
  if (!all(required %in% names(data))) stop("Volcano data 缺少必要列。", call. = FALSE)
  data$regulation <- factor(data$regulation, levels = names(style$colors))
  plottable <- data$plottable %||% (is.finite(data$log2FoldChange) & is.finite(data$minus_log10_padj))
  plot_data <- data[!is.na(plottable) & plottable, , drop = FALSE]
  counts <- table(factor(plot_data$regulation, levels = names(style$colors)))
  legend_labels <- paste0(names(counts), " (n=", as.integer(counts), ")")
  p <- ggplot2::ggplot(plot_data, ggplot2::aes(x = log2FoldChange, y = minus_log10_padj, color = regulation)) +
    ggplot2::geom_point(size = style$point_size, alpha = style$point_alpha, shape = as.integer(style$point_shape), na.rm = TRUE) +
    ggplot2::scale_color_manual(values = style$colors, labels = legend_labels, drop = FALSE) +
    ggplot2::labs(x = "log2 fold change", y = "-log10 adjusted p-value", color = NULL) +
    .plot_theme(style)
  if (!is.null(extras$padj_cutoff)) p <- p + ggplot2::geom_hline(yintercept = -log10(extras$padj_cutoff), linetype = 2, color = style$threshold_color, linewidth = style$threshold_width)
  if (!is.null(extras$log2fc_cutoff)) p <- p + ggplot2::geom_vline(xintercept = c(-extras$log2fc_cutoff, extras$log2fc_cutoff), linetype = 2, color = style$threshold_color, linewidth = style$threshold_width)
  labels <- plot_data[plot_data$label %in% TRUE & !is.na(plot_data$label), , drop = FALSE]
  if (style$show_gene_names && nrow(labels)) {
    labels$plot_label <- ifelse(is.na(labels$gene_name) | labels$gene_name == "", labels$gene_id, labels$gene_name)
    p <- p + ggrepel::geom_text_repel(data = labels, ggplot2::aes(label = plot_label), size = style$label_size, show.legend = FALSE, seed = 1)
  }
  p
}

# 按已给顺序绘制热图；矩阵行名保留稳定 ID，row_labels 控制展示文本。
.plot_heatmap <- function(data, extras, style) {
  matrix_data <- as.matrix(data)
  if (!is.numeric(matrix_data)) stop("Heatmap data 必须是数值矩阵。", call. = FALSE)
  row_order <- extras$row_order %||% seq_len(nrow(matrix_data))
  column_order <- extras$column_order %||% seq_len(ncol(matrix_data))
  matrix_data <- matrix_data[row_order, column_order, drop = FALSE]
  matrix_units <- extras$matrix_units %||% "row_zscore"
  if (identical(matrix_units, "row_zscore")) {
    breaks <- c(-style$z_limit, 0, style$z_limit)
  } else {
    value_range <- range(matrix_data, finite = TRUE)
    if (!all(is.finite(value_range))) stop("Heatmap 矩阵没有有限数值。", call. = FALSE)
    if (value_range[[1]] == value_range[[2]]) value_range <- value_range + c(-0.5, 0.5)
    breaks <- seq(value_range[[1]], value_range[[2]], length.out = 3)
  }
  palette <- circlize::colorRamp2(breaks, c(style$low, style$mid, style$high))
  row_annotation <- extras$row_annotation
  column_annotation <- extras$sample_annotation
  left_ha <- NULL
  top_ha <- NULL
  row_split <- NULL
  if (!is.null(row_annotation)) {
    if (nrow(row_annotation) != nrow(data)) stop("row_annotation 行数需与热图行数一致。", call. = FALSE)
    row_annotation <- row_annotation[row_order, , drop = FALSE]
    keep <- intersect(c("condition", "batch", "Pathway"), names(row_annotation))
    if (length(keep)) {
      row_annotation <- row_annotation[, keep, drop = FALSE]
      if ("Pathway" %in% names(row_annotation)) {
        row_annotation$Pathway <- as.character(row_annotation$Pathway)
        missing_pathway <- is.na(row_annotation$Pathway) | !nzchar(row_annotation$Pathway)
        row_annotation$Pathway[missing_pathway] <- "Unassigned"
      }
      row_annotation <- .prepare_annotation(row_annotation, style$group_colors, style$palette)
      annotation_colors <- attr(row_annotation, "annotation_colors")
      left_ha <- ComplexHeatmap::rowAnnotation(df = row_annotation, col = annotation_colors, show_annotation_name = TRUE)
      if ("Pathway" %in% keep) {
        pathway_order <- as.character(row_annotation$Pathway)
        ordered_groups <- unique(pathway_order)
        if (identical(as.character(rle(pathway_order)$values), ordered_groups)) {
          row_split <- factor(pathway_order, levels = ordered_groups)
        }
      }
    }
  }
  if (!is.null(column_annotation)) {
    if (nrow(column_annotation) != ncol(data)) stop("sample_annotation 行数需与热图列数一致。", call. = FALSE)
    column_annotation <- column_annotation[column_order, , drop = FALSE]
    keep <- intersect(c("condition", "batch"), names(column_annotation))
    if (length(keep)) {
      column_annotation <- column_annotation[, keep, drop = FALSE]
      column_annotation <- .prepare_annotation(column_annotation, style$group_colors, style$palette)
      annotation_colors <- attr(column_annotation, "annotation_colors")
      top_ha <- ComplexHeatmap::HeatmapAnnotation(df = column_annotation, col = annotation_colors, show_annotation_name = TRUE)
    }
  }
  row_labels <- rownames(matrix_data)
  if (style$show_gene_names && !is.null(extras$row_labels)) {
    if (length(extras$row_labels) != nrow(data)) stop("extras$row_labels 长度需与热图行数一致。", call. = FALSE)
    row_labels <- as.character(extras$row_labels[row_order])
  }
  ComplexHeatmap::Heatmap(
    matrix_data, name = "Expression", col = palette, cluster_rows = FALSE,
    cluster_columns = FALSE, cluster_row_slices = FALSE, row_split = row_split,
    show_row_names = style$show_gene_names, row_labels = row_labels,
    show_column_names = style$show_sample_labels, column_names_rot = style$column_rotation,
    na_col = style$na_color, rect_gp = grid::gpar(col = style$cell_border, lwd = style$cell_border_width),
    use_raster = style$heatmap_raster, left_annotation = left_ha, top_annotation = top_ha,
    row_names_gp = grid::gpar(fontsize = style$row_font_size, fontfamily = style$font_family),
    column_names_gp = grid::gpar(fontsize = style$column_font_size, fontfamily = style$font_family),
    heatmap_legend_param = list(title = if (matrix_units == "row_zscore") "Row z-score" else "Expression")
  )
}

# 为分类注释使用用户颜色，缺失类别按固定莫兰迪色板确定性补色。
.prepare_annotation <- function(annotation, group_colors, palette) {
  annotation[] <- lapply(annotation, function(x) if (is.character(x)) factor(x) else x)
  annotation_colors <- list()
  for (column in names(annotation)) {
    values <- annotation[[column]]
    if (is.factor(values) || is.character(values)) {
      levels_present <- unique(as.character(values))
      supplied <- group_colors
      matched <- supplied[names(supplied) %in% levels_present]
      if (length(matched) < length(levels_present)) {
        missing <- setdiff(levels_present, names(matched))
        generated <- rep(palette, length.out = length(missing))
        names(generated) <- missing
        matched <- c(matched, generated)
      }
      annotation_colors[[column]] <- matched
      annotation[[column]] <- factor(values, levels = levels_present)
    }
  }
  attr(annotation, "annotation_colors") <- annotation_colors
  annotation
}

# Enrichment 气泡图以 term_id 作为唯一纵轴键并安全转换 padj=0。
.plot_enrichment <- function(data, style) {
  required <- c("term_id", "description", "padj", "gene_ratio", "count", "source")
  if (!all(required %in% names(data))) stop("Enrichment data 缺少必要列。")
  data$minus_log10_padj <- -log10(pmax(data$padj, .Machine$double.xmin))
  data$term_axis <- factor(data$term_id, levels = rev(unique(data$term_id)))
  terms <- unique(data[c("term_id", "description")])
  labels <- vapply(terms$description, function(x) paste(strwrap(x, width = style$term_wrap), collapse = "\n"), character(1))
  label_map <- stats::setNames(labels, terms$term_id)
  p <- ggplot2::ggplot(data, ggplot2::aes(x = gene_ratio, y = term_axis))
  if (style$enrichment_kind == "bar") {
    p <- p + ggplot2::geom_col(ggplot2::aes(fill = minus_log10_padj), alpha = style$point_alpha, width = 0.7) +
      ggplot2::scale_fill_gradient(low = style$enrichment_low, high = style$enrichment_high, name = "-log10 FDR")
  } else {
    p <- p + ggplot2::geom_point(ggplot2::aes(size = count, color = minus_log10_padj), alpha = style$point_alpha) +
      ggplot2::scale_size_continuous(range = c(style$enrichment_size_min, style$enrichment_size_max), name = "Gene count") +
      ggplot2::scale_color_gradient(low = style$enrichment_low, high = style$enrichment_high, name = "-log10 FDR")
  }
  p + ggplot2::scale_y_discrete(labels = label_map) + ggplot2::labs(x = "Gene ratio", y = NULL) + .plot_theme(style)
}

# GSEA 三联图按输入 rank 顺序展示 ES、命中位置和排序统计量。
.plot_gsea <- function(data, extras, style) {
  required <- c("rank", "running_es", "hit", "rank_score")
  if (!all(required %in% names(data))) stop("GSEA data 缺少必要列。")
  title <- sprintf("%s | NES = %.3f | FDR = %.3g", extras$pathway_id %||% "GSEA", as.numeric(extras$nes), as.numeric(extras$padj))
  theme <- .plot_theme(style) + ggplot2::theme(legend.position = "none")
  p1 <- ggplot2::ggplot(data, ggplot2::aes(rank, running_es)) +
    ggplot2::geom_line(color = style$curve_color, linewidth = style$curve_width) +
    ggplot2::geom_hline(yintercept = 0, color = "grey75", linewidth = 0.3) +
    ggplot2::coord_cartesian(xlim = c(1, nrow(data))) + ggplot2::labs(x = NULL, y = "Running ES", title = title) + theme
  hits <- data[data$hit %in% TRUE, , drop = FALSE]
  p2 <- ggplot2::ggplot(hits, ggplot2::aes(x = rank)) +
    ggplot2::geom_segment(ggplot2::aes(xend = rank, y = 0, yend = 1), color = style$rug_color, linewidth = style$rug_width) +
    ggplot2::coord_cartesian(xlim = c(1, nrow(data))) + ggplot2::labs(x = NULL, y = "Hits") + .plot_theme(style, void = TRUE)
  p3 <- ggplot2::ggplot(data, ggplot2::aes(rank, rank_score, fill = rank_score >= 0)) +
    ggplot2::geom_col(width = 1) + ggplot2::scale_fill_manual(values = c("TRUE" = style$positive_color, "FALSE" = style$negative_color), guide = "none") +
    ggplot2::coord_cartesian(xlim = c(1, nrow(data))) + ggplot2::labs(x = "Rank in ordered list", y = "Rank score") + theme
  patchwork::wrap_plots(p1, p2, p3, ncol = 1, heights = c(2, 0.4, 1))
}

# 网络图使用输入节点坐标与边关系，不进行新的布局计算。
.plot_network <- function(data, extras, style) {
  if (!all(c("gene_id", "label", "x", "y", "degree", "log2FoldChange") %in% names(data))) stop("Network nodes 缺少必要列。")
  if (!"group" %in% names(data)) data$group <- "Nodes"
  edges <- extras$edges
  from <- match(edges$from, data$gene_id)
  to <- match(edges$to, data$gene_id)
  if (anyNA(from) || anyNA(to)) stop("网络边与节点不匹配。")
  edge_data <- data.frame(x = data$x[from], y = data$y[from], xend = data$x[to], yend = data$y[to])
  mode <- style$network_color_by
  if (mode == "auto") mode <- if (any(is.finite(data$log2FoldChange))) "log2FC" else if (length(unique(data$group)) > 1) "group" else "uniform"
  p <- ggplot2::ggplot() + ggplot2::geom_segment(data = edge_data,
      ggplot2::aes(x, y, xend = xend, yend = yend), color = style$network_edge_color,
      linewidth = style$network_edge_width, alpha = style$network_edge_alpha)
  if (mode == "log2FC") {
    if (!any(is.finite(data$log2FoldChange))) stop("Node 没有可用 log2FC，请改用统一颜色或分组着色。")
    p <- p + ggplot2::geom_point(data = data, ggplot2::aes(x, y, size = degree, color = log2FoldChange)) +
      ggplot2::scale_color_gradient2(low = style$network_low, mid = style$network_mid, high = style$network_high, midpoint = 0, name = "log2FC")
  } else if (mode == "group") {
    palette <- .group_palette(unique(data$group), palette = c(style$network_node_color, "#B8523E", "#A89046", "#697C61", "#8F6D86"))
    p <- p + ggplot2::geom_point(data = data, ggplot2::aes(x, y, size = degree, color = group)) + ggplot2::scale_color_manual(values = palette, name = "Group")
  } else p <- p + ggplot2::geom_point(data = data, ggplot2::aes(x, y, size = degree), color = style$network_node_color)
  p <- p + ggplot2::scale_size_continuous(range = c(style$node_size_min, style$node_size_max), name = "Degree") +
    ggplot2::labs(x = NULL, y = NULL) + .plot_theme(style, void = TRUE)
  if (style$network_labels && style$network_label_top > 0) {
    labels <- head(data[order(-data$degree, data$gene_id), , drop = FALSE], style$network_label_top)
    p <- p + ggrepel::geom_text_repel(data = labels, ggplot2::aes(x, y, label = label), size = style$label_size,
      family = style$font_family, max.overlaps = Inf, seed = 1)
  }
  p
}

# 按 bundle 类型调用绘图函数并返回导出文件路径。
render_bundle <- function(bundle, style = list(), output_dir = ".") {
  if (!is.list(bundle) || is.null(bundle$type) || is.null(bundle$data)) {
    stop("bundle 必须包含 type 与 data。", call. = FALSE)
  }
  style <- .resolve_plot_style(style)
  extras <- bundle$extras %||% list()
  if (bundle$type == "heatmap") {
    heatmap <- .plot_heatmap(bundle$data, extras, style)
    return(.save_heatmap_bundle(heatmap, output_dir, style))
  }
  plot <- switch(
    bundle$type,
    pca = .plot_pca(bundle$data, extras, style),
    volcano = .plot_volcano(bundle$data, extras, style),
    enrichment = .plot_enrichment(bundle$data, style),
    gsea = .plot_gsea(bundle$data, extras, style),
    network = .plot_network(bundle$data, extras, style),
    stop(sprintf("暂不支持的 bundle$type：%s", bundle$type), call. = FALSE)
  )
  .save_ggplot_bundle(plot, output_dir, style)
}
