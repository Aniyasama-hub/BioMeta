tb_plot_general <- function(bundle, style, engine) {
  d <- bundle$data
  palette <- function(x) engine$.group_palette(unique(as.character(x)), palette = style$palette)
  theme <- engine$.plot_theme(style)
  if (bundle$type == "beeswarm") {
    engine$require_packages("ggbeeswarm")
    plot <- ggplot2::ggplot(d, ggplot2::aes(group, value, color = group))
    if (bundle$extras$box) plot <- plot + ggplot2::geom_boxplot(outlier.shape = NA, width = .25, alpha = .12)
    plot <- plot + ggbeeswarm::geom_beeswarm(size = style$point_size, alpha = style$point_alpha) +
      ggplot2::scale_color_manual(values = palette(d$group)) + ggplot2::labs(x = NULL, y = "Value", color = NULL)
    if (bundle$extras$log) plot <- plot + ggplot2::scale_y_log10()
    return(plot + theme)
  }
  if (bundle$type == "kmeans") {
    return(ggplot2::ggplot(d, ggplot2::aes(PC1, PC2, color = cluster)) +
      ggplot2::geom_point(size = style$point_size, alpha = style$point_alpha) +
      ggplot2::scale_color_manual(values = palette(d$cluster)) + ggplot2::labs(color = "Cluster") + theme)
  }
  if (bundle$type == "sankey") {
    x <- seq(0, 1, length.out = 60)
    t <- x^2 * (3 - 2*x)
    ribbons <- do.call(rbind, lapply(seq_len(nrow(d)), function(i) {
      y <- (1-t)*d$source_y[i] + t*d$target_y[i]
      data.frame(x = c(x, rev(x)), y = c(y, rev(y + d$value[i])), source = d$source[i], edge = i)
    }))
    nodes <- rbind(
      transform(stats::aggregate(cbind(lo = d$source_y, hi = d$source_y + d$value), list(label = d$source), mean), x = 0),
      transform(stats::aggregate(cbind(lo = d$target_y, hi = d$target_y + d$value), list(label = d$target), mean), x = 1))
    return(ggplot2::ggplot(ribbons, ggplot2::aes(x, y, fill = source, group = edge)) +
      ggplot2::geom_polygon(alpha = style$point_alpha) + ggplot2::scale_fill_manual(values = palette(d$source)) +
      ggplot2::geom_text(data = nodes, ggplot2::aes(x, (lo+hi)/2, label = label, hjust = 1-x),
        inherit.aes = FALSE, size = style$label_size, nudge_x = 0) +
      ggplot2::scale_x_continuous(expand = ggplot2::expansion(mult = .2)) + theme +
      ggplot2::theme(axis.title = ggplot2::element_blank(), axis.text = ggplot2::element_blank(),
        axis.ticks = ggplot2::element_blank(), axis.line = ggplot2::element_blank()))
  }
  if (bundle$type == "venn") {
    labels <- bundle$extras$sets
    centers <- data.frame(x = c(-.55, .55, 0)[seq_along(labels)], y = c(.25, .25, -.62)[seq_along(labels)], set = labels)
    angles <- seq(0, 2*pi, length.out = 120)
    circles <- do.call(rbind, lapply(seq_along(labels), function(i)
      data.frame(x = centers$x[i]+cos(angles), y = centers$y[i]+sin(angles), set = labels[i])))
    coordinates <- if (length(labels) == 2L) data.frame(x = c(-.95,.95,0), y = .25) else
      data.frame(x = c(-.96,.96,0,0,-.55,.55,0), y = c(.50,.50,.76,-1.26,-.45,-.45,-.14))
    coordinates$count <- bundle$extras$counts
    return(ggplot2::ggplot(circles, ggplot2::aes(x, y, fill = set)) +
      ggplot2::geom_polygon(alpha = min(style$point_alpha, .5), color = "grey45") +
      ggplot2::geom_text(data = coordinates, ggplot2::aes(x, y, label = count), inherit.aes = FALSE, size = style$label_size) +
      ggplot2::scale_fill_manual(values = palette(labels)) + ggplot2::coord_equal() +
      ggplot2::labs(fill = NULL) + theme + ggplot2::theme(axis.title = ggplot2::element_blank(),
        axis.text = ggplot2::element_blank(), axis.ticks = ggplot2::element_blank(), axis.line = ggplot2::element_blank()))
  }
  axes <- unique(d[c("metric", "theta")])
  guides <- do.call(rbind, lapply(seq(.25, 1, .25), function(radius)
    data.frame(x = radius*cos(axes$theta), y = radius*sin(axes$theta), ring = radius)))
  ggplot2::ggplot(d, ggplot2::aes(x, y, group = profile, color = profile)) +
    ggplot2::geom_polygon(data = guides, ggplot2::aes(x, y, group = ring), inherit.aes = FALSE, fill = NA, color = "grey75") +
    ggplot2::geom_segment(data = axes, ggplot2::aes(x = 0, y = 0, xend = cos(theta), yend = sin(theta)),
      inherit.aes = FALSE, color = "grey80") +
    ggplot2::geom_polygon(fill = NA, linewidth = style$line_width, alpha = style$point_alpha) +
    ggplot2::geom_text(data = axes, ggplot2::aes(1.13*cos(theta), 1.13*sin(theta), label = metric),
      inherit.aes = FALSE, size = style$label_size) +
    ggplot2::scale_color_manual(values = palette(d$profile)) + ggplot2::coord_equal() +
    ggplot2::labs(color = NULL) + theme + ggplot2::theme(axis.title = ggplot2::element_blank(),
      axis.text = ggplot2::element_blank(), axis.ticks = ggplot2::element_blank(), axis.line = ggplot2::element_blank())
}
