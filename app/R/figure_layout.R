tb_white_crop <- function(image, width, height, tolerance) {
  cutoff <- as.raw(ceiling(255 * (1 - tolerance / 100)))
  # 分条扫描，将 RGB 和占用掩码限制在约 100 万像素。
  strip_height <- max(1L, floor(1e6 / width))
  bounds <- c(width, height, 0L, 0L)
  for (offset in seq.int(0L, height - 1L, by = strip_height)) {
    rows <- min(strip_height, height - offset)
    strip <- magick::image_crop(image, sprintf("%dx%d+0+%d", width, rows, offset), repage = TRUE)
    rgb <- magick::image_data(strip, channels = "rgb")
    occupied <- rgb[1L, , , drop = FALSE] < cutoff | rgb[2L, , , drop = FALSE] < cutoff |
      rgb[3L, , , drop = FALSE] < cutoff
    dim(occupied) <- c(width, rows)
    x <- which(rowSums(occupied) > 0L)
    y <- which(colSums(occupied) > 0L) + offset
    if (length(x)) bounds <- c(min(bounds[1L], x), min(bounds[2L], y), max(bounds[3L], x), max(bounds[4L], y))
  }
  if (!bounds[3L]) return(c(0L, 0L, width, height))
  c(bounds[1:2] - 1L, bounds[3:4] - bounds[1:2] + 1L)
}

tb_prepare_figure <- function(spec) {
  if (!requireNamespace("magick", quietly = TRUE)) stop("图片排版需要 R 包 magick。")
  p <- spec$params
  keys <- tb_panel_fields(p$panel_count)
  columns <- p$panel_columns
  tolerance <- p$panel_trim
  if (!is.finite(columns) || columns != floor(columns) || columns < 0 || columns > length(keys))
    stop("列数须为 0（自动）或不超过图片数量的正整数。")
  if (!is.finite(tolerance) || tolerance < 0 || tolerance > 20) stop("裁白容差须在 0–20% 内。")
  images <- lapply(keys, function(key) tb_with_input(spec$inputs[[key]], {
    image <- magick::image_read(spec$inputs[[key]])
    info <- magick::image_info(image)
    if (nrow(info) != 1L || !info$format %in% c("PNG", "JPEG", "TIFF") ||
        as.double(info$width) * info$height > 1e8) stop("请上传单帧 PNG、JPEG 或 TIFF，且单图不超过 1 亿像素。")
    image <- magick::image_background(image, "white", flatten = TRUE)
    crop <- tb_white_crop(image, info$width, info$height, tolerance)
    image <- magick::image_crop(image, sprintf("%dx%d+%d+%d", crop[3], crop[4], crop[1], crop[2]), repage = TRUE)
    list(png = magick::image_write(image, format = "png"), crop = crop,
      original_width = info$width, original_height = info$height)
  }, code = "BW-I05"))
  list(type = "figure_layout", images = images,
       fixed_columns = if (columns > 0L) columns)
}

tb_figure_positions <- function(bundle, style) {
  style <- tb_figure_paper(style)
  n <- length(bundle$images)
  opt <- tb_figure_layout_options(style, n)
  paper_ratio <- style$width / style$height
  aspects <- vapply(bundle$images, function(image) image$crop[3L] / image$crop[4L], numeric(1))
  margin <- .025
  gx <- .022
  gy <- .016
  label_band <- 1.45 * style$panel_label_size / (72 * style$height)
  tags <- switch(style$panel_sequence, abc = letters[seq_len(n)], numeric = as.character(seq_len(n)),
    roman = intToUtf8(0x2160 + seq_len(n) - 1L, multiple = TRUE))

  row_geometry <- function(ids) {
    ratio <- aspects[ids]
    weights <- pmax(.85, pmin(1.25, (stats::median(ratio) / ratio)^.3))
    if (length(opt$weights)) weights <- weights * opt$weights[ids]
    width <- 1 - 2 * margin - (length(ids) - 1) * gx
    height <- weights * width * paper_ratio / sum(ratio * weights)
    list(height = height, width = height * ratio / paper_ratio, max_height = max(height))
  }

  counts <- opt$rows
  if (!length(counts) && !is.null(bundle$fixed_columns)) {
    counts <- lengths(split(seq_len(n), (seq_len(n) - 1L) %/% bundle$fixed_columns))
  }
  if (!length(counts)) {
    # 只比较连续面板的分行方案，保持原上传顺序。
    target <- min(.49, .8 / sqrt(n))
    costs <- c(rep(Inf, n), 0)
    next_row <- integer(n)
    for (i in rev(seq_len(n))) {
      for (k in seq_len(min(4L, n - i + 1L))) {
        ids <- seq.int(i, length.out = k)
        height <- row_geometry(ids)$max_height
        penalty <- if (k > 1L && any(aspects[ids] > 2.8)) .9 else 0
        score <- log(height / target)^2 + .12 + penalty + costs[i + k]
        if (score < costs[i]) {
          costs[i] <- score
          next_row[i] <- k
        }
      }
    }
    i <- 1L
    while (i <= n) {
      counts <- c(counts, next_row[i])
      i <- i + next_row[i]
    }
  }

  rows <- split(seq_len(n), rep(seq_along(counts), counts))
  geometry <- lapply(rows, row_geometry)
  heights <- unname(vapply(geometry, function(row) row$max_height, numeric(1)))
  available <- 1 - 2 * margin - (length(rows) - 1) * gy - length(rows) * label_band
  if (available <= 0) stop("纸张高度不足以容纳各行序号，请减小字号或减少行数。")
  row_heights <- heights * min(1, available / sum(heights))
  tops <- margin + (available - sum(row_heights)) / 2 +
    c(0, head(cumsum(row_heights + gy + label_band), -1L))
  panels <- lapply(seq_along(rows), function(row) {
    ids <- rows[[row]]
    target <- geometry[[row]]$width
    capacity <- row_heights[row] * aspects[ids] / paper_ratio
    widths <- pmin(target, capacity)
    # Redistribute width from height-limited panels to neighbors with room.
    spare <- capacity - widths
    if (sum(spare) > 0) widths <- widths + spare * min(1, (sum(target) - sum(widths)) / sum(spare))
    image_heights <- widths * paper_ratio / aspects[ids]
    left <- (1 - sum(widths) - (length(ids) - 1) * gx) / 2
    x <- left + c(0, head(cumsum(widths + gx), -1L))
    crops <- t(vapply(bundle$images[ids], function(image) as.numeric(image$crop), numeric(4L)))
    data.frame(panel = ids, row = row, file = sprintf("panel_%02d.png", ids), label = tags[ids],
      x = x, y = tops[row] + label_band + (row_heights[row] - image_heights) / 2,
      width = widths, height = image_heights, label_x = x, label_y = tops[row],
      crop_x = crops[, 1L], crop_y = crops[, 2L], crop_width = crops[, 3L], crop_height = crops[, 4L])
  })
  do.call(rbind, panels)
}


tb_render_figure <- function(bundle, style, root, output) {
  style <- tb_figure_paper(style)
  panels <- tb_figure_positions(bundle, style)
  assets <- file.path(output, "figure-assets")
  dir.create(assets, showWarnings = FALSE)
  for (i in seq_len(nrow(panels))) {
    panel <- panels[i, ]
    size <- pmax(1L, ceiling(c(panel$width * style$width, panel$height * style$height) * style$dpi))
    image <- magick::image_read(bundle$images[[i]]$png)
    image <- magick::image_resize(image, sprintf("%dx%d>", size[1L], size[2L]))
    magick::image_write(image, file.path(assets, panel$file), format = "png")
  }
  utils::write.csv(panels, file.path(output, "figure_panels.csv"), row.names = FALSE)
  draw <- function(format) {
    path <- file.path(output, paste0("figure.", format))
    if (format == "pdf") grDevices::cairo_pdf(path, width = style$width, height = style$height, bg = style$background)
    else if (format == "png") grDevices::png(path, width = style$width, height = style$height,
      units = "in", res = style$dpi, bg = style$background, type = "cairo")
    else if (format == "tiff") grDevices::tiff(path, width = style$width, height = style$height,
      units = "in", res = style$dpi, bg = style$background, type = "cairo", compression = "lzw")
    else tb_open_device(path, format, style$width,
      style$height, style$dpi, style$background)
    on.exit(grDevices::dev.off(), add = TRUE)
    grid::grid.newpage()
    for (i in seq_len(nrow(panels))) {
      panel <- panels[i, ]
      grid::grid.raster(png::readPNG(file.path(assets, panel$file), native = TRUE),
        x = panel$x, y = 1-panel$y, width = panel$width, height = panel$height,
        just = c("left", "top"), interpolate = TRUE)
      grid::grid.text(panel$label, x = panel$label_x, y = 1-panel$label_y, just = c("left", "top"),
        gp = grid::gpar(fontsize = style$panel_label_size, fontface = style$panel_fontface,
          fontfamily = style$panel_font_family, col = style$panel_label_color))
    }
  }
  for (format in style$formats) draw(format)
  config <- jsonlite::toJSON(list(panels = panels, width = round(style$width*style$dpi),
    height = round(style$height*style$dpi), dpi = style$dpi, background = style$background, font = style$panel_font_family,
    face = style$panel_fontface, color = style$panel_label_color,
    fontSize = style$panel_label_size * style$dpi / 72), auto_unbox = TRUE)
  template <- paste(readLines(file.path(root, "www", "figure-layout.html"), encoding = "UTF-8"), collapse = "\n")
  parts <- strsplit(template, "__FIGURE_CONFIG__", fixed = TRUE)[[1]]
  writeLines(paste0(parts[1], gsub("<", "\\u003c", config, fixed = TRUE), parts[2]),
    file.path(output, "figure-layout.html"), useBytes = TRUE)
  if (!file.copy(file.path(root, "www", "figure-layout.js"), output, overwrite = TRUE)) stop("无法保存排版编辑器。")
}
