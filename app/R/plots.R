.pathway_display_label <- function(x) {
  x <- gsub("(?i)\\[(?:BP|CC|MF|GO|KEGG|REACTOME|RECATOME)\\]", "", x, perl = TRUE)
  trimws(gsub("[[:space:]]+", " ", x))
}

.presentation_defaults <- function() list(
  font_family = "sans", background = "#FFFFFF", plot_theme = "classic", point_shape = "16",
  group_a = "#426C87", group_b = "#B8523E", threshold_color = "#847D72", threshold_width = 0.5,
  na_color = "#E1DDD3", cell_border = "#FFFFFF", cell_border_width = 0.3,
  row_font_size = 11, column_font_size = 10, column_rotation = 45, show_gene_names = TRUE, heatmap_raster = FALSE,
  heat_cell_width = 0, heat_cell_height = 0, show_row_tree = FALSE, show_column_tree = FALSE,
  reverse_rows = FALSE, reverse_columns = FALSE, enrichment_bar_width = .7, enrichment_bar_length = 90,
  target_label_color = "#C62828", target_point_color = "#F2C94C",
  pathway_target_color = "#C62828", pathway_target_fill = "transparent",
  gene_label_fill = "none", pathway_label_fill = "preset", pathway_font_size = 11,
  pathway_font_face = "plain", pathway_font_color = "#242424",
  enrichment_kind = "dot", enrichment_orientation = "horizontal", enrichment_low = "#B9C8BB", enrichment_high = "#B44A37",
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
  result <- utils::modifyList(utils::modifyList(c(.default_plot_style(), tb_legend_defaults()[-1L]), .presentation_defaults()), style %||% list())
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
  sides <- c("left", "right", "top", "bottom", "none")
  if (length(result$legend_position) != 1L || !result$legend_position %in% sides) {
    stop("style$legend_position 仅支持 left、right、top、bottom、none。", call. = FALSE)
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
  .draw_heatmap_legends(heatmap$plot, heatmap$legends, style)
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
  align <- .legend_alignment(style)
  justify <- if (style$legend_position %in% c("top", "bottom")) c(align, .5) else c(.5, 1-align)
  theme + ggplot2::theme(legend.position = style$legend_position, legend.justification = justify,
    legend.text = ggplot2::element_text(size = style$legend_text_size),
    legend.title = ggplot2::element_text(size = style$legend_title_size),
    legend.key.size = grid::unit(style$legend_key_size, "mm"),
    legend.box.spacing = grid::unit(style$legend_gap, "mm"),
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
  if (isTRUE(style$pca_ellipse_2d)) {
    theta <- seq(0, 2*pi, length.out = 121L)
    regions <- lapply(split(data, data$condition), function(group) {
      region <- .pca_region(group[c("PC1", "PC2")], style$pca_confidence, style$pca_region_type)
      if (is.null(region)) {
        message("二维 PCA 置信椭圆跳过分组：", group$condition[1L], "（样本不足或协方差退化）")
        return(NULL)
      }
      xy <- sweep(cbind(cos(theta), sin(theta)) %*% t(region$axes), 2L, region$center, "+")
      data.frame(PC1 = xy[, 1L], PC2 = xy[, 2L], condition = group$condition[1L])
    })
    ellipses <- do.call(rbind, regions)
    if (!is.null(ellipses)) {
      colors <- .group_palette(levels(data$condition), style$group_colors, style$palette)
      ellipses$fill <- vapply(as.character(ellipses$condition), function(group) .pca_region_fill(colors[[group]], style), character(1))
      region <- ggplot2::geom_polygon(data = ellipses, ggplot2::aes(group = condition),
        fill = ellipses$fill, linewidth = .55, show.legend = FALSE)
      # Paint behind the sample points.
      p$layers <- c(list(region), p$layers)
      p <- p + ggplot2::coord_fixed()
    }
  }
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
  if (is.null(plot_data$target)) plot_data$target <- FALSE
  targets <- plot_data[plot_data$target %in% TRUE, , drop = FALSE]
  if (nrow(targets)) p <- p + ggplot2::geom_point(data = targets, color = style$target_point_color,
    size = style$point_size, shape = as.integer(style$point_shape))
  labels <- plot_data[plot_data$label %in% TRUE & !plot_data$gene_id %in% targets$gene_id, , drop = FALSE]
  if (style$show_gene_names && nrow(labels)) {
    labels$plot_label <- ifelse(is.na(labels$gene_name) | labels$gene_name == "", labels$gene_id, labels$gene_name)
    p <- p + ggrepel::geom_text_repel(data = labels, ggplot2::aes(label = plot_label), size = style$label_size, show.legend = FALSE, seed = 1)
  }
  if (nrow(targets)) {
    targets$plot_label <- ifelse(is.na(targets$gene_name) | targets$gene_name == "", targets$gene_id, targets$gene_name)
    p <- p + ggrepel::geom_text_repel(data = targets, ggplot2::aes(label = plot_label),
      color = style$target_label_color, size = style$label_size, max.overlaps = Inf, seed = 1, show.legend = FALSE)
  }
  p
}

# 按已给顺序绘制热图；矩阵行名保留稳定 ID，row_labels 控制展示文本。
.heatmap_cell_extent <- function(mm, count) {
  if (!is.null(mm) && mm > 0) grid::unit.pmin(grid::unit(mm * count, "mm"), grid::unit(.8, "npc"))
}

.label_fill_colors <- function(mode, style, n) {
  if (is.null(mode) || mode == "none") return(rep("transparent", n))
  palette <- if (mode == "preset") style$palette else {
    preset <- tb_palettes()[[mode]]
    if (is.null(preset)) stop("背景填充预设不存在。")
    preset$colors %||% unlist(preset[c("low", "mid", "high")])
  }
  grDevices::adjustcolor(rep(palette, length.out = n), alpha.f = .22)
}

.filled_row_labels <- function(labels, colors, size, family, face = "plain", color = "#242424") {
  width <- ComplexHeatmap::max_text_width(labels, gp = grid::gpar(fontsize = size, fontfamily = family)) + grid::unit(4, "mm")
  ComplexHeatmap::AnnotationFunction(which = "row", n = length(labels), width = width,
    fun = function(index, k, n) {
      y <- (rev(seq_along(index)) - .5) / length(index)
      grid::grid.rect(x = .5, y = y, width = 1, height = 1 / length(index),
        gp = grid::gpar(fill = colors[index], col = NA))
      grid::grid.text(labels[index], x = grid::unit(2, "mm"), y = y, just = "left",
        gp = grid::gpar(fontsize = size, fontfamily = family, fontface = face,
          col = if (length(color) > 1L) color[index] else color))
    })
}

.plot_heatmap <- function(data, extras, style) {
  matrix_data <- as.matrix(data)
  if (style$heat_cell_height > 0) style$row_font_size <- min(style$row_font_size, style$heat_cell_height * 2.3)
  if (style$heat_cell_width > 0) style$column_font_size <- min(style$column_font_size, style$heat_cell_width * 2.3)
  if (!is.numeric(matrix_data)) stop("Heatmap data 必须是数值矩阵。", call. = FALSE)
  row_order <- extras$row_order %||% seq_len(nrow(matrix_data))
  column_order <- extras$column_order %||% seq_len(ncol(matrix_data))
  if (isTRUE(style$reverse_rows)) row_order <- rev(row_order)
  if (isTRUE(style$reverse_columns)) column_order <- rev(column_order)
  matrix_data <- matrix_data[row_order, column_order, drop = FALSE]
  clustering <- extras$clustering
  tree <- function(matrix) {
    fit <- stats::hclust(compute_distance(matrix, clustering$distance), method = clustering$linkage)
    # 按既定顺序旋转子树；使用最小位置，避免均值把不等长分支再次调换。
    stats::reorder(as.dendrogram(fit), seq_len(nrow(matrix)), agglo.FUN = min)
  }
  show_rows <- isTRUE(style$show_row_tree) && isTRUE(clustering$cluster_rows) && nrow(matrix_data) > 1L
  show_columns <- isTRUE(style$show_column_tree) && isTRUE(clustering$cluster_columns) && ncol(matrix_data) > 1L
  matrix_units <- extras$matrix_units %||% "row_zscore"
  if (identical(matrix_units, "row_zscore")) {
    breaks <- c(-style$z_limit, 0, style$z_limit)
  } else {
    value_range <- range(matrix_data, finite = TRUE)
    if (!all(is.finite(value_range))) stop("Heatmap 矩阵没有有限数值。", call. = FALSE)
    if (value_range[[1]] == value_range[[2]]) value_range <- value_range + c(-0.5, 0.5)
    breaks <- seq(value_range[[1]], value_range[[2]], length.out = 3)
  }
  colors <- tb_gradient_ramp(style, c(style$low, style$mid, style$high))
  palette <- circlize::colorRamp2(seq(breaks[1], tail(breaks, 1), length.out = length(colors)), colors)
  row_annotation <- extras$row_annotation
  column_annotation <- extras$sample_annotation
  left_ha <- NULL
  top_ha <- NULL
  column_split <- NULL
  column_titles <- NULL
  legends <- list(.heatmap_color_legend(switch(matrix_units, row_zscore = "Row z-score",
    "ssGSEA score" = "ssGSEA score", "Expression"), palette))
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
      legends <- c(legends, .heatmap_annotation_legends(annotation_colors))
      left_ha <- ComplexHeatmap::rowAnnotation(df = row_annotation, col = annotation_colors, show_annotation_name = TRUE)
      if ("Pathway" %in% keep && !identical(extras$pathway_cluster, FALSE)) {
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
    if ("batch" %in% keep && length(unique(column_annotation$batch)) < 2L) keep <- setdiff(keep, "batch")
    if (length(keep)) {
      column_annotation <- column_annotation[, keep, drop = FALSE]
      column_annotation <- .prepare_annotation(column_annotation, style$group_colors, style$palette)
      annotation_colors <- attr(column_annotation, "annotation_colors")
      if ("condition" %in% keep && !(show_columns && identical(clustering$column_cluster_mode, "global"))) {
        runs <- rle(as.character(column_annotation$condition))
        column_titles <- runs$values
        if (style$heat_cell_width > 0) {
          widths <- pmax(3L, floor(runs$lengths * style$heat_cell_width * 2.8346 / (style$column_font_size * .6)))
          column_titles <- vapply(seq_along(column_titles), function(i) {
            starts <- seq.int(1L, nchar(column_titles[i]), by = widths[i])
            paste(substring(column_titles[i], starts, starts + widths[i] - 1L), collapse = "\n")
          }, character(1))
        }
        column_split <- factor(rep(seq_along(runs$lengths), runs$lengths), levels = seq_along(runs$lengths))
      }
      if ("condition" %in% keep && is.null(column_split)) legends <- c(legends,
        .heatmap_annotation_legends(list("Group" = annotation_colors$condition)))
      if ("batch" %in% keep) legends <- c(legends,
        .heatmap_annotation_legends(list("Technical batch" = annotation_colors$batch)))
      top_ha <- ComplexHeatmap::HeatmapAnnotation(df = column_annotation, col = annotation_colors,
        show_annotation_name = FALSE, show_legend = FALSE)
    }
  }
  row_labels <- rownames(matrix_data)
  if (style$show_gene_names && !is.null(extras$row_labels)) {
    if (length(extras$row_labels) != nrow(data)) stop("extras$row_labels 长度需与热图行数一致。", call. = FALSE)
    row_labels <- as.character(extras$row_labels[row_order])
  }
  right_ha <- NULL
  target_rows <- (extras$row_targets %||% rep(FALSE, nrow(data)))[row_order] %in% TRUE
  row_colors <- ifelse(target_rows, style$pathway_target_color, "#242424")
  row_fills <- .label_fill_colors(style$gene_label_fill, style, length(row_labels))
  row_fills[target_rows] <- style$pathway_target_fill
  if (isTRUE(style$show_gene_names) && (!identical(style$gene_label_fill, "none") ||
      any(target_rows) && !identical(style$pathway_target_fill, "transparent"))) {
    right_ha <- ComplexHeatmap::rowAnnotation(Gene = .filled_row_labels(row_labels,
      row_fills, style$row_font_size, style$font_family, color = row_colors),
      show_annotation_name = FALSE)
  }
  if (!is.null(row_annotation) && "Pathway" %in% names(row_annotation)) {
    labels <- as.character(row_annotation$Pathway)
    levels <- unique(labels)
    wrapped <- vapply(levels, function(x) paste(strwrap(x, width = style$term_wrap), collapse = "\n"), character(1))
    fills <- .label_fill_colors(style$pathway_label_fill, style, length(levels))
    left_ha <- if (!is.null(row_split)) ComplexHeatmap::rowAnnotation(
      Pathway = ComplexHeatmap::anno_block(gp = grid::gpar(fill = fills, col = NA),
        labels = wrapped, labels_rot = 0,
        labels_gp = grid::gpar(fontsize = style$pathway_font_size, fontfamily = style$font_family,
          fontface = style$pathway_font_face, col = style$pathway_font_color),
        width = ComplexHeatmap::max_text_width(wrapped, gp = grid::gpar(fontsize = style$pathway_font_size,
          fontfamily = style$font_family, fontface = style$pathway_font_face)) + grid::unit(4, "mm")),
      show_annotation_name = FALSE) else ComplexHeatmap::rowAnnotation(
        Pathway = .filled_row_labels(wrapped[match(labels, levels)], fills[match(labels, levels)], style$pathway_font_size,
          style$font_family, style$pathway_font_face, style$pathway_font_color), show_annotation_name = FALSE)
  }
  heatmap <- ComplexHeatmap::Heatmap(
    matrix_data, name = "Expression", col = palette,
    cluster_rows = if (show_rows) tree else FALSE,
    cluster_columns = if (show_columns) tree else FALSE,
    row_dend_reorder = FALSE, column_dend_reorder = FALSE, cluster_row_slices = FALSE, row_split = row_split,
    width = .heatmap_cell_extent(style$heat_cell_width, ncol(matrix_data)),
    height = .heatmap_cell_extent(style$heat_cell_height, nrow(matrix_data)),
    column_split = column_split, column_title = column_titles, cluster_column_slices = FALSE,
    column_title_gp = grid::gpar(fontfamily = style$font_family, fontsize = style$column_font_size, fontface = "bold"),
    column_gap = grid::unit(1.2, "mm"),
    show_row_names = style$show_gene_names && is.null(right_ha), row_labels = row_labels,
    row_title = NULL, right_annotation = right_ha,
    show_column_names = style$show_sample_labels, column_names_rot = style$column_rotation,
    na_col = style$na_color, rect_gp = grid::gpar(col = style$cell_border, lwd = style$cell_border_width),
    use_raster = style$heatmap_raster, left_annotation = left_ha, top_annotation = top_ha,
    row_names_max_width = if (all(c("term_id", "description") %in% names(extras$statistics))) {
      ComplexHeatmap::max_text_width(row_labels,
        gp = grid::gpar(fontsize = style$row_font_size, fontfamily = style$font_family)) + grid::unit(2, "mm")
    } else grid::unit(6, "cm"),
    row_names_gp = grid::gpar(fontsize = style$row_font_size, fontfamily = style$font_family, col = row_colors),
    column_names_gp = grid::gpar(fontsize = style$column_font_size, fontfamily = style$font_family),
    show_heatmap_legend = FALSE
  )
  list(plot = heatmap, legends = legends)
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
.highlight_pathway_axis <- function(plot, labels, style, side) {
  if (!length(labels)) return(plot)
  if (grDevices::dev.cur() == 1L) {
    grDevices::pdf(NULL, width = style$width, height = style$height)
    on.exit(grDevices::dev.off(), add = TRUE)
  }
  table <- ggplot2::ggplotGrob(plot)
  decorate <- function(grob) {
    if (inherits(grob, "text")) {
      values <- as.character(grob$label)
      selected <- which(values %in% labels)
      if (!length(selected)) return(grob)
      colors <- rep(grob$gp$col %||% "#4D4D4D", length.out = length(values))
      colors[selected] <- style$pathway_target_color
      grob$gp$col <- colors
      if (identical(style$pathway_target_fill, "transparent")) return(grob)
      backgrounds <- lapply(selected, function(i) {
        x <- grob$x[rep(seq_along(grob$x), length.out = length(values))[i]]
        y <- grob$y[rep(seq_along(grob$y), length.out = length(values))[i]]
        hjust <- rep(grob$hjust %||% .5, length.out = length(values))[i]
        vjust <- rep(grob$vjust %||% .5, length.out = length(values))[i]
        measure <- grid::textGrob(values[i], gp = grid::gpar(fontsize = grob$gp$fontsize %||% style$base_size,
          fontfamily = style$font_family))
        width <- grid::grobWidth(measure); height <- grid::grobHeight(measure)
        grid::rectGrob(x = (.5 - hjust) * width, y = (.5 - vjust) * height,
          width = width + grid::unit(2, "mm"), height = height + grid::unit(1, "mm"),
          vp = grid::viewport(x = x, y = y, just = c("left", "bottom"), angle = grob$rot %||% 0),
          gp = grid::gpar(fill = style$pathway_target_fill, col = NA))
      })
      return(grid::grobTree(children = do.call(grid::gList, c(backgrounds, list(grob))), name = grob$name))
    }
    if (inherits(grob, "gtable")) grob$grobs <- lapply(grob$grobs, decorate)
    else if (inherits(grob, "gTree") && length(grob$children))
      grob$children <- do.call(grid::gList, lapply(grob$children, decorate))
    grob
  }
  positions <- grep(paste0("^axis-", side), table$layout$name)
  table$grobs[positions] <- lapply(table$grobs[positions], decorate)
  table
}

.plot_enrichment <- function(data, style, extras = list()) {
  required <- c("term_id", "description", "padj", "gene_ratio", "count", "source")
  if (!all(required %in% names(data))) stop("Enrichment data 缺少必要列。")
  data$minus_log10_padj <- -log10(pmax(data$padj, .Machine$double.xmin))
  vertical <- style$enrichment_kind == "bar" && style$enrichment_orientation == "vertical"
  levels <- unique(data$term_id)
  data$term_axis <- factor(data$term_id, levels = if (vertical) levels else rev(levels))
  data$description <- .pathway_display_label(data$description)
  terms <- unique(data[c("term_id", "description")])
  labels <- vapply(terms$description, function(x) paste(strwrap(x, width = style$term_wrap), collapse = "\n"), character(1))
  label_map <- stats::setNames(labels, terms$term_id)
  axes <- if (vertical) ggplot2::aes(x = term_axis, y = gene_ratio) else ggplot2::aes(x = gene_ratio, y = term_axis)
  p <- ggplot2::ggplot(data, axes)
  if (style$enrichment_kind == "bar") {
    p <- p + ggplot2::geom_col(ggplot2::aes(fill = minus_log10_padj), alpha = style$point_alpha, width = style$enrichment_bar_width) +
      ggplot2::scale_fill_gradientn(colours = tb_gradient_ramp(style, c(style$enrichment_low, style$enrichment_high)), name = "-log10 FDR")
    limits <- c(0, max(data$gene_ratio, 1e-6) * 100 / style$enrichment_bar_length)
    p <- p + if (vertical) ggplot2::coord_cartesian(ylim = limits) else ggplot2::coord_cartesian(xlim = limits)
  } else {
    p <- p + ggplot2::geom_point(ggplot2::aes(size = count, color = minus_log10_padj), alpha = style$point_alpha) +
      ggplot2::scale_size_continuous(range = c(style$enrichment_size_min, style$enrichment_size_max), name = "Gene count") +
      ggplot2::scale_color_gradientn(colours = tb_gradient_ramp(style, c(style$enrichment_low, style$enrichment_high)), name = "-log10 FDR")
  }
  p <- p + .plot_theme(style)
  if (isTRUE(extras$go_facets)) {
    data$ontology <- factor(data$ontology, levels = c("BP", "CC", "MF"))
    p$data <- data
    p <- p + if (vertical) ggplot2::facet_grid(cols = ggplot2::vars(ontology),
      scales = "free_x", space = "free_x", drop = FALSE) else
      ggplot2::facet_grid(rows = ggplot2::vars(ontology), scales = "free_y", space = "free_y", drop = FALSE)
    absent <- setdiff(c("BP", "CC", "MF"), unique(as.character(data$ontology)))
    if (length(absent)) p <- p + ggplot2::labs(caption = paste("无符合当前阈值的条目：", paste(absent, collapse = ", ")))
  }
  p <- if (vertical) p + ggplot2::scale_x_discrete(labels = label_map) +
    ggplot2::labs(x = NULL, y = "Gene ratio") + ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1)) else
    p + ggplot2::scale_y_discrete(labels = label_map) + ggplot2::labs(x = "Gene ratio", y = NULL)
  targets <- if ("target_pathway" %in% names(data)) data$term_id[data$target_pathway %in% TRUE] else character()
  .highlight_pathway_axis(p, unname(label_map[targets]), style, if (vertical) "b" else "l")
}

# GSEA 三联图按输入 rank 顺序展示 ES、命中位置和排序统计量。
.plot_gsea <- function(data, extras, style) {
  required <- c("rank", "running_es", "hit", "rank_score")
  if (!all(required %in% names(data))) stop("GSEA data 缺少必要列。")
  id <- extras$pathway_id %||% "GSEA"
  title <- paste(strwrap(.pathway_display_label(extras$pathway_name %||% id), width = max(18, floor(style$width * 6))), collapse = "\n")
  statistics <- sprintf("NES = %.3f  |  FDR = %.3g", as.numeric(extras$nes), as.numeric(extras$padj))
  if (!is.null(extras$pvalue)) statistics <- paste(statistics, sprintf("P = %.3g", extras$pvalue), sep = "  |  ")
  subtitle <- paste(paste(c(extras$database, id), collapse = " · "), statistics, sep = "\n")
  theme <- .plot_theme(style) + ggplot2::theme(legend.position = "none")
  p1 <- ggplot2::ggplot(data, ggplot2::aes(rank, running_es)) +
    ggplot2::geom_line(color = style$curve_color, linewidth = style$curve_width) +
    ggplot2::geom_hline(yintercept = 0, color = "grey75", linewidth = 0.3) +
    ggplot2::coord_cartesian(xlim = c(1, nrow(data))) + ggplot2::labs(x = NULL, y = "Running ES", title = title, subtitle = subtitle) + theme
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
      ggplot2::scale_color_gradientn(colours = tb_gradient_ramp(style, c(style$network_low, style$network_mid, style$network_high)),
        limits = c(-max(abs(data$log2FoldChange), .Machine$double.eps, na.rm = TRUE),
                    max(abs(data$log2FoldChange), .Machine$double.eps, na.rm = TRUE)), name = "log2FC")
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
# Keep stable pathway IDs in the score matrix and join descriptions only for display.
.gsva_pathway_labels <- function(ids, statistics, width) {
  labels <- .pathway_display_label(as.character(statistics$description[match(ids, statistics$term_id)]))
  missing <- is.na(labels) | !nzchar(labels) | grepl("^https?://", labels, ignore.case = TRUE)
  labels[missing] <- ids[missing]
  labels <- trimws(gsub("[[:space:]_]+", " ", labels))
  width <- max(1L, as.integer(width))
  vapply(labels, function(label) {
    lines <- strwrap(label, width = width + 1L)
    pieces <- lapply(lines, function(line) {
      starts <- seq.int(1L, nchar(line), by = width)
      substring(line, starts, starts + width - 1L)
    })
    paste(unlist(pieces, use.names = FALSE), collapse = "\n")
  }, character(1), USE.NAMES = FALSE)
}

render_bundle <- function(bundle, style = list(), output_dir = ".") {
  if (!is.list(bundle) || is.null(bundle$type) || (bundle$type != "gsea_collection" && is.null(bundle$data))) {
    stop("bundle 必须包含 type 与 data。", call. = FALSE)
  }
  style <- .resolve_plot_style(style)
  if (bundle$type == "gsea_collection") {
    paths <- lapply(names(bundle$curves), function(name)
      render_bundle(bundle$curves[[name]], style, file.path(output_dir, name)))
    return(unlist(paths, use.names = FALSE))
  }
  extras <- bundle$extras %||% list()
  if (bundle$type == "heatmap") {
    if (style$show_gene_names && all(c("term_id", "description") %in% names(extras$statistics))) {
      extras$row_labels <- .gsva_pathway_labels(rownames(bundle$data), extras$statistics, style$term_wrap)
      longest <- max(lengths(strsplit(extras$row_labels, "\n", fixed = TRUE)))
      if (longest > 1L) {
        # Give every heatmap row room for its label at the requested font size.
        style$height <- max(style$height, 1.5 + nrow(bundle$data) * longest * style$row_font_size * 1.2 / 72)
      }
    }
    heatmap <- .plot_heatmap(bundle$data, extras, style)
    return(.save_heatmap_bundle(heatmap, output_dir, style))
  }
  if (bundle$type == "volcano") {
    plot <- .plot_volcano(bundle$data, extras, style)
    vertical <- .save_ggplot_bundle(plot, file.path(output_dir, "vertical"), style)
    horizontal <- .save_ggplot_bundle(plot + ggplot2::coord_flip(), file.path(output_dir, "horizontal"), style)
    return(c(vertical, horizontal))
  }
  plot <- switch(
    bundle$type,
    pca = .plot_pca(bundle$data, extras, style),
    volcano = .plot_volcano(bundle$data, extras, style),
    enrichment = .plot_enrichment(bundle$data, style, extras),
    gsea = .plot_gsea(bundle$data, extras, style),
    network = .plot_network(bundle$data, extras, style),
    stop(sprintf("暂不支持的 bundle$type：%s", bundle$type), call. = FALSE)
  )
  .save_ggplot_bundle(plot, output_dir, style)
}

# Hotelling T² confidence region for a group mean in a fixed PCA projection.
.pca_region <- function(points, level, type = "mean") {
  points <- as.matrix(points)
  d <- ncol(points)
  n <- nrow(points)
  if (n <= d || any(!is.finite(points))) return(NULL)
  covariance <- eigen(stats::cov(points), symmetric = TRUE)
  if (min(covariance$values) <= max(covariance$values) * 1e-10) return(NULL)
  # The mean has covariance S/n. An independent future sample minus the mean uses (1 + 1/n) S.
  variance_multiplier <- if (type == "prediction") 1 + 1/n else 1/n
  radius <- sqrt(variance_multiplier * d * (n - 1) / (n - d) * stats::qf(level / 100, d, n - d))
  axes <- covariance$vectors %*% diag(sqrt(covariance$values) * radius, nrow = d)
  list(center = colMeans(points), axes = axes)
}

.pca_region_fill <- function(group_color, style) {
  if (style$pca_region_fill == "outline") return(NA_character_)
  color <- if (style$pca_region_fill == "solid") style$pca_region_color else group_color
  grDevices::adjustcolor(color, style$pca_region_alpha)
}

.legend_alignment <- function(style) unname(c(start = 0, center = .5, end = 1)[style$legend_align])

.heatmap_color_legend <- function(title, colors, at = NULL) list(title = title, col_fun = colors, at = at)

.heatmap_annotation_legends <- function(colors) {
  lapply(names(colors), function(name) list(title = name, colors = colors[[name]]))
}

.draw_heatmap_legends <- function(heatmap, legends, style, ...) {
  side <- style$legend_position
  if (side == "none" || !length(legends))
    return(ComplexHeatmap::draw(heatmap, show_heatmap_legend = FALSE, show_annotation_legend = FALSE,
      background = style$background, ...))
  horizontal <- side %in% c("top", "bottom")
  dimensions <- c(style$width, style$height) * 25.4
  make <- function(scale) {
    key <- style$legend_key_size * scale
    label_gp <- grid::gpar(fontsize = style$legend_text_size * scale, fontfamily = style$font_family)
    title_gp <- grid::gpar(fontsize = style$legend_title_size * scale, fontfamily = style$font_family, fontface = "bold")
    guides <- lapply(legends, function(item) {
      args <- list(title = item$title, labels_gp = label_gp, title_gp = title_gp)
      if (!is.null(item$col_fun)) {
        args <- c(args, list(col_fun = item$col_fun,
          direction = if (horizontal) "horizontal" else "vertical"))
        if (!is.null(item$at)) args$at <- item$at
        args[[if (horizontal) "legend_width" else "legend_height"]] <- grid::unit(max(key * 6, style$legend_text_size * scale * 2.1), "mm")
        args[[if (horizontal) "grid_height" else "grid_width"]] <- grid::unit(key * .7, "mm")
      } else {
        args <- c(args, list(labels = names(item$colors), legend_gp = grid::gpar(fill = unname(item$colors)),
          grid_width = grid::unit(key, "mm"), grid_height = grid::unit(key, "mm"),
          ncol = if (horizontal) min(4L, length(item$colors)) else 1L))
      }
      do.call(ComplexHeatmap::Legend, args)
    })
    do.call(ComplexHeatmap::packLegend, c(guides, list(direction = if (horizontal) "horizontal" else "vertical",
      max_width = grid::unit(dimensions[1L] * .92, "mm"), max_height = grid::unit(dimensions[2L] * .92, "mm"))))
  }
  measure <- function(guides) c(grid::convertWidth(grid::grobWidth(guides@grob), "mm", valueOnly = TRUE),
    grid::convertHeight(grid::grobHeight(guides@grob), "mm", valueOnly = TRUE))
  grid::grid.newpage()
  scale <- 1
  for (i in seq_len(5L)) {
    guides <- make(scale)
    size <- measure(guides)
    limit <- dimensions * if (horizontal) c(.92, .36) else c(.40, .92)
    factor <- min(1, limit / pmax(size, .01))
    if (factor >= .99) break
    scale <- scale * factor * .95
  }
  axis <- if (horizontal) 2L else 1L
  gap <- min(style$legend_gap + 4, dimensions[axis] * .12)
  space <- (size[axis] + gap) / dimensions[axis]
  if (space > .65) stop("图例尺寸超过画布可用空间，请减小字号或扩大画布。")
  x <- if (side == "left") space else 0
  y <- if (side == "bottom") space else 0
  grid::pushViewport(grid::viewport(x = x, y = y, width = if (horizontal) 1 else 1-space,
    height = if (horizontal) 1-space else 1, just = c("left", "bottom"), clip = "on"))
  result <- tryCatch(ComplexHeatmap::draw(heatmap, newpage = FALSE, show_heatmap_legend = FALSE,
    show_annotation_legend = FALSE, background = style$background, ...), finally = grid::upViewport())
  align <- .legend_alignment(style)
  gx <- if (horizontal) .04 + .92 * align else if (side == "left") space / 2 else 1 - space / 2
  gy <- if (!horizontal) .96 - .92 * align else if (side == "bottom") space / 2 else 1 - space / 2
  ComplexHeatmap::draw(guides, x = grid::unit(gx, "npc"), y = grid::unit(gy, "npc"),
    just = if (horizontal) c(c("left", "center", "right")[match(align, c(0,.5,1))], "center")
      else c("center", c("top", "center", "bottom")[match(align, c(0,.5,1))]))
  result
}
