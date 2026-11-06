tb_prepare_general <- function(spec) {
  p <- spec$params
  data <- tb_read_preview(spec$inputs$matrix, n = -1)
  require_columns <- function(columns) {
    if (!nrow(data) || !all(columns %in% names(data))) stop("输入表需要列：", paste(columns, collapse = ", "))
  }
  text_values <- function(x) {
    x <- trimws(as.character(x))
    if (anyNA(x) || any(!nzchar(x))) stop("分组与标识不可为空。")
    x
  }
  numeric_values <- function(x) {
    x <- suppressWarnings(as.numeric(x))
    if (any(!is.finite(x))) stop("数值列必须为有限数值。")
    x
  }
  extras <- list()
  if (spec$tool == "sankey") {
    require_columns(c("source", "target", "value"))
    data <- data.frame(source = text_values(data$source), target = text_values(data$target),
      value = numeric_values(data$value))
    if (any(data$value <= 0)) stop("桑基流量须大于零。")
    data <- stats::aggregate(value ~ source + target, data, sum)
    edges <- function(key) {
      sizes <- tapply(data$value, key, sum)
      gap <- sum(sizes) * p$sankey_gap / max(1, length(sizes) - 1L)
      start <- cumsum(c(0, head(unname(sizes), -1) + gap))
      positions <- vapply(split(seq_len(nrow(data)), key), function(ids) length(ids), integer(1))
      lower <- numeric(nrow(data))
      for (i in seq_along(positions)) {
        ids <- which(key == names(sizes)[i])
        lower[ids] <- start[i] + cumsum(c(0, head(data$value[ids], -1)))
      }
      lower
    }
    data$source_y <- edges(data$source)
    data$target_y <- edges(data$target)
  } else if (spec$tool == "venn") {
    require_columns(c("set", "item"))
    sets <- split(text_values(data$item), text_values(data$set))
    if (!length(sets) %in% c(2L, 3L)) stop("韦恩图支持两个或三个集合。")
    items <- unique(unlist(sets, use.names = FALSE))
    mask <- Reduce(`+`, lapply(seq_along(sets), function(i) 2^(i - 1L) * (items %in% sets[[i]])))
    data <- data.frame(item = items, region = mask)
    extras$sets <- names(sets)
    extras$counts <- tabulate(mask, nbins = 2^length(sets) - 1L)
  } else if (spec$tool == "beeswarm") {
    require_columns(c("group", "value"))
    data <- data.frame(group = text_values(data$group), value = numeric_values(data$value))
    if (isTRUE(p$beeswarm_log) && any(data$value <= 0)) stop("对数轴要求所有值大于零。")
    extras$log <- isTRUE(p$beeswarm_log)
    extras$box <- isTRUE(p$beeswarm_box)
  } else {
    if (!nrow(data) || ncol(data) < 3L) stop("输入需含首列标识及至少两列数值。")
    ids <- text_values(data[[1]])
    if (anyDuplicated(ids) || anyDuplicated(names(data)[-1])) stop("标识和数值列名必须唯一。")
    values <- do.call(cbind, lapply(data[-1], numeric_values))
    colnames(values) <- names(data)[-1]
    if (spec$tool == "kmeans") {
      k <- p$kmeans_k
      if (!is.finite(k) || k != floor(k) || k < 2 || k >= nrow(values) ||
          k > nrow(unique(values))) stop("K 须至少为 2，小于行数，且不超过不同数据点数。")
      if (isTRUE(p$kmeans_scale)) {
        keep <- apply(values, 2, stats::sd) > 0
        values <- values[, keep, drop = FALSE]
        if (ncol(values) < 2) stop("至少需要两个非恒定数值列。")
        values <- scale(values)
      }
      set.seed(as.integer(p$kmeans_seed))
      groups <- stats::kmeans(values, centers = k, nstart = 25)
      projection <- stats::prcomp(values)$x
      data <- data.frame(item = ids, cluster = factor(groups$cluster), PC1 = projection[, 1], PC2 = projection[, 2])
      extras$centers <- groups$centers
    } else {
      if (ncol(values) < 3L) stop("雷达图至少需要三个数值指标。")
      original <- values
      if (isTRUE(p$radar_normalize)) {
        values <- apply(values, 2, function(x) if (diff(range(x)) == 0) rep(.5, length(x)) else (x - min(x)) / diff(range(x)))
        values <- matrix(values, nrow = length(ids))
      } else if (any(values < 0 | values > 1)) stop("关闭归一化时，各指标须位于 0–1。")
      theta <- pi/2 - 2*pi*seq.int(0, ncol(values)-1)/ncol(values)
      data <- data.frame(profile = rep(ids, each = length(theta)), metric = rep(colnames(original), length(ids)),
        original = c(t(original)), radius = c(t(values)), theta = rep(theta, length(ids)))
      data$x <- data$radius * cos(data$theta)
      data$y <- data$radius * sin(data$theta)
    }
  }
  list(type = spec$tool, data = data, extras = extras)
}
