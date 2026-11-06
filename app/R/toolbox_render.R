tb_open_device <- function(path, format, width, height, dpi, background = "white") {
  if (format == "png") grDevices::png(path, width = width, height = height, units = "in", res = dpi, bg = background)
  else if (format == "svg") svglite::svglite(path, width = width, height = height, bg = background)
  else if (format == "tiff") grDevices::tiff(path, width = width, height = height, units = "in", res = dpi, compression = "lzw", bg = background)
  else if (format == "pdf") grDevices::pdf(path, width = width, height = height, bg = background)
  else stop("未知图像格式：", format)
}

tb_pca_supplement <- function(bundle, spec, output, engine, style) {
  # 同一 PCA 结果派生负荷图和 3D 图，不重新拟合；只有存在 PC3 时输出三维视图。
  loadings <- as.data.frame(bundle$extras$pca$rotation)
  loadings$gene_id <- rownames(loadings)
  loadings$contribution <- loadings$PC1^2 + loadings$PC2^2
  loadings <- loadings[order(loadings$contribution, decreasing = TRUE), , drop = FALSE]
  engine$write_table(loadings, file.path(output, "loading_plot_data.csv"))
  plot <- ggplot2::ggplot(loadings, ggplot2::aes(PC1, PC2)) +
    ggplot2::geom_hline(yintercept = 0, color = "grey85") +
    ggplot2::geom_vline(xintercept = 0, color = "grey85") +
    ggplot2::geom_point(color = style$group_a, alpha = style$point_alpha, size = style$point_size, shape = as.integer(style$point_shape)) +
    ggplot2::labs(x = "PC1 loading", y = "PC2 loading") +
    engine$.plot_theme(style)
  if (spec$params$labels) plot <- plot + ggrepel::geom_text_repel(
    data = head(loadings, 20), ggplot2::aes(label = gene_id), size = style$label_size, seed = 1)
  engine$.save_ggplot_bundle(plot, file.path(output, "pca_loadings"), style)
  if (!"PC3" %in% names(bundle$data)) return(invisible(NULL))
  engine$require_packages("scatterplot3d")
  tb_pca_3d(bundle$data, bundle$extras$variance, style, engine, file.path(output, "pca_3d"))
}

tb_pca_3d <- function(data, variance, style, engine, output) {
  axes <- c("PC1", "PC2", "PC3")
  groups <- factor(data$condition)
  labels <- levels(groups)
  colors <- engine$.group_palette(labels, style$group_colors, style$palette)
  regions <- list()
  if (isTRUE(style$pca_ellipse_3d)) {
    regions <- lapply(split(data, groups), function(group) {
      region <- engine$.pca_region(group[axes], style$pca_confidence, style$pca_region_type)
      if (is.null(region))
        message("三维 PCA 区域跳过分组：", group$condition[1L], "（样本不足或协方差退化）")
      region
    })
    regions <- Filter(Negate(is.null), regions)
  }
  bounds <- lapply(regions, function(region) {
    half_width <- sqrt(rowSums(region$axes^2))
    rbind(region$center - half_width, region$center + half_width)
  })
  extent <- do.call(rbind, c(list(as.matrix(data[axes])), bounds))
  limits <- lapply(seq_along(axes), function(i) range(extent[, i], finite = TRUE))
  limits <- lapply(limits, function(x) if (diff(x) == 0) x + c(-.5, .5) else x)
  dir.create(output, showWarnings = FALSE)
  for (format in style$formats) {
    tb_open_device(file.path(output, paste0("figure.", format)), format,
      style$width, style$height, style$dpi, style$background)
    tryCatch({
      legend <- tb_pca_legend_layout(labels, style)
      draw <- scatterplot3d::scatterplot3d(data$PC1, data$PC2, data$PC3, type = "n", col.grid = "#D5DDE0", col.axis = "#627278",
        xlim = limits[[1L]], ylim = limits[[2L]], zlim = limits[[3L]],
        mar = c(4, 3, 1, 3) * min(1, style$width / 4, style$height / 4), angle = style$pca_3d_angle,
        xlab = sprintf("PC1 (%.1f%%)", variance[1L]), ylab = sprintf("PC2 (%.1f%%)", variance[2L]),
        zlab = sprintf("PC3 (%.1f%%)", variance[3L]))
      for (name in names(regions)) {
        region <- regions[[name]]
        projection <- tb_pca_surface_projection(region, draw$xyz.convert)
        fill <- engine$.pca_region_fill(colors[[name]], style)
        if (!is.na(fill) && style$pca_region_alpha > 0) tb_shade_pca_surface(region, projection, fill)
        graphics::polygon(projection$outline, col = NA,
          border = grDevices::adjustcolor(colors[[name]], .58), lwd = .85)
      }
      draw$points3d(as.matrix(data[axes]), col = grDevices::adjustcolor(colors[as.character(groups)], style$point_alpha),
        pch = as.integer(style$point_shape), cex = style$point_size / 2)
      if (!is.null(legend)) legend(colors)
    }, finally = grDevices::dev.off())
  }
  invisible(NULL)
}

tb_pca_surface_projection <- function(region, project) {
  origin <- project(0, 0, 0)
  basis <- diag(3)
  unit <- project(basis[, 1L], basis[, 2L], basis[, 3L])
  view <- rbind(unit$x - origin$x, unit$y - origin$y)
  center <- do.call(project, as.list(unname(region$center)))
  map <- view %*% region$axes
  shape <- svd(map, nv = 3L)
  theta <- seq(0, 2*pi, length.out = 181L)
  outline <- cbind(cos(theta), sin(theta)) %*% diag(shape$d, nrow = 2L) %*% t(shape$u)
  list(center = c(center$x, center$y), outline = sweep(outline, 2L, c(center$x, center$y), "+"),
    view = view, map = map, shape = shape)
}

tb_shade_pca_surface <- function(region, projection, color) {
  unit_vector <- function(x) x / sqrt(sum(x^2))
  shape <- projection$shape
  half_width <- sqrt(rowSums(projection$map^2))
  # For every pixel cast an orthographic ray onto the near hemisphere of the unit sphere.
  size <- 400L
  x <- ((seq_len(size) - .5) / size * 2 - 1) * half_width[1L]
  y <- (1 - (seq_len(size) - .5) / size * 2) * half_width[2L]
  pixels <- as.matrix(expand.grid(x = x, y = y))
  screen <- sweep(pixels %*% shape$u, 2L, shape$d, "/")
  distance <- rowSums(screen^2)
  inside <- distance <= 1
  camera <- unit_vector(svd(projection$view, nv = 3L)$v[, 3L])
  if (camera[2L] > 0) camera <- -camera
  front <- shape$v[, 3L]
  if (sum((region$axes %*% front) * camera) < 0) front <- -front
  surface <- screen[inside, , drop = FALSE] %*% t(shape$v[, 1:2, drop = FALSE]) +
    outer(sqrt(1 - distance[inside]), front)
  normals <- surface %*% solve(region$axes)
  normals <- normals / sqrt(rowSums(normals^2))
  light <- unit_vector(camera - .52 * unit_vector(projection$view[1L, ]) +
    .62 * unit_vector(projection$view[2L, ]))
  diffuse <- pmax(0, drop(normals %*% light))
  highlight <- diffuse^12
  rgba <- grDevices::col2rgb(color, alpha = TRUE)[, 1L] / 255
  base <- pmin(.90, pmax(.09, rgba[1:3]))
  rgb <- outer(.38 + .62 * diffuse, base) + outer(.42 * highlight, 1 - base)
  pixels_color <- rep("#00000000", nrow(pixels))
  pixels_color[inside] <- grDevices::rgb(rgb[, 1L], rgb[, 2L], rgb[, 3L],
    alpha = rgba[4L])
  image <- as.raster(matrix(pixels_color, nrow = size, byrow = TRUE))
  bounds <- c(projection$center - half_width, projection$center + half_width)
  graphics::rasterImage(image, bounds[1L], bounds[2L], bounds[3L], bounds[4L], interpolate = TRUE)
}


tb_pca_legend_layout <- function(labels, style) {
  side <- style$legend_position
  if (side == "none") return(NULL)
  horizontal <- side %in% c("top", "bottom")
  axis <- if (horizontal) style$width else style$height
  cross <- if (horizontal) style$height else style$width
  measure <- function(text, size) max(vapply(text, function(label) {
    grid::convertWidth(grid::grobWidth(grid::textGrob(label,
      gp = grid::gpar(fontfamily = style$font_family, fontsize = size))), "inches", valueOnly = TRUE)
  }, numeric(1)))
  size <- style$legend_text_size
  gap <- min(style$legend_gap / 25.4, cross * .10)
  key <- style$legend_key_size / 25.4
  span <- measure(labels, size) + key + .15
  if (horizontal) {
    cols <- max(1L, min(length(labels), floor(axis * .95 / span)))
    rows <- ceiling(length(labels) / cols)
    expected <- (rows + 1.5) * max(size / 72 * 1.45, key) + gap
    space <- min(cross * .40, expected)
    scale <- min(1, space / expected, axis * .95 / span)
    graphics::layout(matrix(if (side == "top") c(2L, 1L) else c(1L, 2L), ncol = 1L),
      heights = if (side == "top") c(space, cross-space) else c(cross-space, space))
  } else {
    rows <- max(1L, floor((axis-.3) / max(size / 72 * 1.45, key)))
    cols <- ceiling(length(labels) / rows)
    expected <- cols * span + gap
    space <- min(cross * .42, expected)
    scale <- min(1, space / expected)
    graphics::layout(matrix(if (side == "left") c(2L, 1L) else c(1L, 2L), nrow = 1L),
      widths = if (side == "left") c(space, cross-space) else c(cross-space, space))
  }
  function(colors) {
    graphics::par(mar = rep(0, 4), family = style$font_family, ps = size, xaxs = "i", yaxs = "i")
    graphics::plot.new()
    graphics::plot.window(c(0, 1), c(0, 1))
    position <- if (horizontal) c(start = "left", center = "center", end = "right") else
      c(start = "top", center = "center", end = "bottom")
    graphics::legend(unname(position[style$legend_align]), legend = labels, col = colors,
      pch = as.integer(style$point_shape), cex = scale, pt.cex = scale * style$legend_key_size / 4,
      ncol = cols, bty = "n", title = "Group", title.cex = scale * style$legend_title_size / size)
  }
}


tb_render_circos <- function(bundle, style, output) {
  chromosomes <- bundle$data
  features <- bundle$extras$features
  links <- bundle$extras$links
  draw <- function() {
    on.exit(circlize::circos.clear(), add = TRUE)
    circlize::circos.par(start.degree = style$start_degree, gap.degree = style$gap_degree)
    circlize::circos.initialize(chromosomes$chr, xlim = cbind(0, chromosomes$length))
    circlize::circos.trackPlotRegion(ylim = c(0, 1), bg.col = rep(style$chromosome_color, nrow(chromosomes)),
      track.height = style$track_height, panel.fun = function(x, y) {
        chr <- circlize::get.cell.meta.data("sector.index")
        center <- circlize::get.cell.meta.data("xcenter")
        circlize::circos.text(center, 0.5, chr, col = "white", cex = style$circos_label_size,
                               facing = "bending.inside", niceFacing = TRUE)
        circlize::circos.axis(labels.cex = 0.5)
      })
    if (!is.null(features)) {
      circlize::circos.genomicTrackPlotRegion(features[, c("chr", "start", "end", "label")], ylim = c(0, 1),
        track.height = 0.12, bg.border = NA, panel.fun = function(region, value, ...) {
          circlize::circos.genomicRect(region, ybottom = 0.2, ytop = 0.5, col = style$feature_color, border = NA)
          circlize::circos.genomicText(region, value, y = 0.8, labels.column = 1, cex = style$circos_label_size, niceFacing = TRUE)
        })
    }
    if (!is.null(links)) for (i in seq_len(nrow(links))) {
      circlize::circos.link(links$chr1[i], c(links$start1[i], links$end1[i]),
                             links$chr2[i], c(links$start2[i], links$end2[i]),
                             col = grDevices::adjustcolor(style$link_color, alpha.f = style$link_alpha), border = NA)
    }
  }
  for (format in style$formats) {
    path <- file.path(output, paste0("figure.", format))
    if (format == "png") grDevices::png(path, width = style$width, height = style$height, units = "in", res = style$dpi, bg = style$background)
    if (format == "svg") svglite::svglite(path, width = style$width, height = style$height, bg = style$background)
    if (format == "tiff") grDevices::tiff(path, width = style$width, height = style$height, units = "in", res = style$dpi, compression = "lzw", bg = style$background)
    if (format == "pdf") grDevices::pdf(path, width = style$width, height = style$height, bg = style$background)
    graphics::par(family = style$font_family, cex = style$base_size / 12)
    tryCatch(draw(), finally = grDevices::dev.off())
  }
}

tb_render_legacy <- function(bundle, spec, output, engine) {
  context <- bundle$context
  style <- spec$style
  colors <- tb_gradient_ramp(style, c(style$low, style$mid, style$high))
  breaks <- seq(-style$z_limit, style$z_limit, length.out = length(colors))
  # Keep the prepared values unchanged and rebuild all graphical objects.
  list2env(list(out_path = output, output_dir = output, output_formats = style$formats,
    image_width = style$width, image_height = style$height, dpi = style$dpi,
    scale_limit = style$z_limit, heatmap_colors = colors, export_background = style$background,
    export_style = style, draw_heatmap_legends = engine$.draw_heatmap_legends,
    make_heatmap_color_legend = engine$.heatmap_color_legend, font_family = style$font_family,
    gene_font_size = style$row_font_size, row_font_size = style$row_font_size,
    sample_font_size = style$column_font_size, column_font_size = style$column_font_size,
    sample_name_rotation = style$column_rotation, column_name_rotation = style$column_rotation,
    show_gene_names = style$show_gene_names, gene_font_color = if (style$show_gene_names) "#222222" else "transparent",
    row_font_color = if (style$show_gene_names) "#222222" else "transparent",
    show_sample_names = spec$params$labels, show_column_names = spec$params$labels,
    na_color = style$na_color, cell_border_color = style$cell_border, cell_border_width = style$cell_border_width,
    use_raster = style$heatmap_raster, use_raster_heatmap = style$heatmap_raster), envir = context)
  if (spec$tool == "custom_heatmap") {
    draw <- function(fmt) {
      path <- file.path(out_path, paste0(output_prefix, "_Heatmap.", fmt))
      tb_open_device(path, fmt, image_width, image_height, dpi, export_background)
      on.exit(grDevices::dev.off(), add = TRUE)
      guides <- if (show_heatmap_legend) list(make_heatmap_color_legend(legend_title, col_fun)) else list()
      draw_heatmap_legends(ht, guides, export_style, column_title = plot_title,
        column_title_gp = grid::gpar(fontfamily = font_family, fontsize = title_font_size,
          fontface = title_font_face, col = title_font_color))
    }
    environment(draw) <- context
    context$draw_one <- draw
  } else {
    draw <- function(fmt) {
      path <- file.path(output_dir, paste0(project_name, "_Heatmap.", fmt))
      tb_open_device(path, fmt, image_width, image_height, dpi, export_background)
      on.exit(grDevices::dev.off(), add = TRUE)
      guides <- if (show_heatmap_legend) list(make_heatmap_color_legend("Relative expression", col_fun)) else list()
      draw_heatmap_legends(ht, guides, export_style)
    }
    environment(draw) <- context
    context$draw_file <- draw
  }
  for (expression in bundle$expressions) {
    name <- if (is.call(expression) && identical(expression[[1]], as.name("<-")) && is.symbol(expression[[2]]))
      as.character(expression[[2]]) else ""
    if (name == "col_fun") {
      context$col_fun <- circlize::colorRamp2(breaks, colors)
    } else if (!name %in% c("draw_one", "draw_file")) eval(expression, context)
  }
}

tb_render_request <- function(bundle, spec, root, directory, engine = tb_engine(root)) {
  output <- file.path(directory, "outputs")
  dir.create(output, recursive = TRUE, showWarnings = FALSE)
  tb_status_write(directory, "running", 85, "根据已准备的数据绘图。")
  style <- utils::modifyList(engine$.default_plot_style(), spec$style)
  style$colors <- c(Up = style$up, Down = style$down, Not_significant = style$neutral)
  style$show_sample_labels <- spec$params$labels
  style$palette <- tb_gradient_colors(style, c(style$group_a, style$group_b, "#A89046", "#697C61"))
  if (!is.null(style$gradient) && nzchar(trimws(style$gradient))) {
    colors <- style$palette
    low <- colors[1]
    high <- tail(colors, 1)
    mid <- grDevices::colorRampPalette(colors)(3)[2]
    style$colors <- c(Up = high, Down = low, Not_significant = mid)
    style$network_node_color <- low
    style$network_low <- low
    style$network_mid <- mid
    style$network_high <- high
    style$group_a <- low
    style$curve_color <- low
    style$positive_color <- high
    style$negative_color <- low
    style$chromosome_color <- low
    style$feature_color <- mid
    style$link_color <- high
  }
  if (bundle$type == "legacy_heatmap") {
    tb_render_legacy(bundle, spec, output, engine)
  } else if (bundle$type == "circos") {
    tb_render_circos(bundle, style, output)
  } else if (bundle$type == "figure_layout") {
    tb_render_figure(bundle, style, root, output)
  } else if (bundle$type %in% tb_general_tools) {
    engine$write_table(bundle$data, file.path(output, "plot_data.csv"))
    if (bundle$type == "venn") engine$write_table(
      data.frame(region = seq_along(bundle$extras$counts), count = bundle$extras$counts),
      file.path(output, "venn_regions.csv"))
    engine$.save_ggplot_bundle(tb_plot_general(bundle, style, engine), output, style)
  } else {
    engine$export_bundle(bundle, output)
    engine$render_bundle(bundle, style, output)
    if (bundle$type == "network") tb_write_interactive_network(bundle, style, root, output)
    if (bundle$type == "pca") tb_pca_supplement(bundle, spec, output, engine, style)
  }
}

tb_redraw_request <- function(spec, root, directory, previous_output = NULL) {
  previous <- spec$redraw_from
  if (file.exists(file.path(previous, "batch.rds"))) return(tb_redraw_comparisons(spec, root, directory))
  cache <- file.path(previous, "render.rds")
  if (!file.copy(cache, directory)) stop("无法复制已准备的绘图数据。")
  output <- file.path(directory, "outputs")
  dir.create(output)
  old <- previous_output %||% file.path(previous, "outputs")
  files <- list.files(old, recursive = TRUE)
  files <- files[!grepl("[.](png|svg|tiff|pdf|html|js)$", files, ignore.case = TRUE)]
  for (name in files) {
    target <- file.path(output, name)
    dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
    if (!file.copy(file.path(old, name), target)) stop("无法复制分析结果：", name)
  }
  tb_render_request(readRDS(file.path(directory, "render.rds")), spec, root, directory)
  manifest <- file.path(output, "manifest.json")
  if (file.exists(manifest)) {
    metadata <- jsonlite::read_json(manifest)
    metadata$style <- spec$style
    metadata$redrawn_from <- basename(previous)
    jsonlite::write_json(metadata, manifest, pretty = TRUE, auto_unbox = TRUE)
  }
  tb_write_reproduce(spec, file.path(directory, "reproduce.R"), root)
  tb_status_write(directory, "completed", 100, "已复用分析结果并重新绘图。")
}
