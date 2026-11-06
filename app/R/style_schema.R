# 每种图只暴露有实际渲染语义的选项；前端和输入校验使用同一份定义。
tb_style_schema <- function(tool) {
  number <- function(label, min = 0, max = 100, step = 1) list(type = "number", label = label, min = min, max = max, step = step)
  color <- function(label) list(type = "color", label = label)
  select <- function(label, choices) list(type = "select", label = label, choices = choices)
  text <- function(label, placeholder) list(type = "text", label = label, placeholder = placeholder)
  flag <- function(label) list(type = "flag", label = label)
  if (tool == "immune") tool <- "matrix_heatmap"
  if (tool == "deg") return(list())
  common <- list(
    width = number("画布宽 · 英寸", 2, 60, 0.5), height = number("画布高 · 英寸", 2, 60, 0.5),
    dpi = number("位图分辨率 · dpi", 72, 1200, 50), base_size = number("基础字号 · pt", 6, 48),
    font_family = select("图形字体", c("无衬线 Sans" = "sans", "衬线 Serif" = "serif", "等宽 Mono" = "mono")),
    background = color("画布背景"))
  legend <- list(legend_position = select("相对主图位置", c("右侧" = "right", "下方" = "bottom", "左侧" = "left", "上方" = "top", "隐藏" = "none")),
    legend_align = select("沿边对齐", c("起始（上／左）" = "start", "居中" = "center", "末端（下／右）" = "end")),
    legend_text_size = number("标签字号 · pt", 5, 30, 1), legend_title_size = number("标题字号 · pt", 5, 36, 1),
    legend_key_size = number("图例键 / 色条大小 · mm", 2, 14, .5), legend_gap = number("与主图间距 · mm", 0, 20, .5))
  pca_confidence <- list(pca_ellipse_2d = flag("绘制二维置信椭圆"), pca_ellipse_3d = flag("绘制三维置信椭球"),
    pca_region_type = select("区域含义", c("组均值置信区域" = "mean", "样本预测区域" = "prediction")),
    pca_confidence = number("置信或预测水平 · %", 80, 99.9, .1),
    pca_region_fill = select("区域填充", c("按组纯色" = "group", "统一纯色" = "solid", "仅轮廓" = "outline")),
    pca_region_color = color("统一填充色"),
    pca_region_alpha = number("填充不透明度（0–1）", 0, 1, .01))
  if (tool == "figure_layout") return(list(
    "纸张与画布" = c(list(panel_paper = select("组图纸张", c("A4", "A3", "A2", "自定义" = "custom")),
      panel_orientation = select("纸张方向", c("纵向" = "portrait", "横向" = "landscape"))),
      common[c("width", "height", "dpi", "background")]),
    "阅读顺序与主次" = list(panel_rows = text("每行图片数（留空自动）", "例如 3 / 1 / 3 / 2")),
    "序号" = list(panel_font_family = select("序号字体", c("Times New Roman" = "Times New Roman",
      "Arial" = "Arial", "Calibri" = "Calibri", "Cambria" = "Cambria", "Georgia" = "Georgia",
      "Courier New" = "Courier New", "系统无衬线" = "sans", "系统衬线" = "serif")),
      panel_sequence = select("序号格式", c("abc" = "abc", "123" = "numeric", "ⅠⅡⅢ" = "roman")),
      panel_fontface = select("字形", c("常规" = "plain", "粗体" = "bold", "斜体" = "italic", "粗斜体" = "bold.italic")),
      panel_label_size = number("序号字号 · pt", 6, 72), panel_label_color = color("序号颜色"))))
  scatter <- list(point_size = number("散点直径 · mm", 0.2, 16, 0.2),
    point_alpha = number("散点不透明度", 0.05, 1, 0.05), point_shape = select("散点形状", c("圆" = "16", "三角" = "17", "方" = "15", "菱形" = "18")),
    label_size = number("标签字号 · mm", 1, 10, 0.5), plot_theme = select("坐标版式", c("简洁轴线" = "classic", "细网格" = "minimal", "完整边框" = "bw")))
  heatmap <- list(low = color("低值色"), mid = color("中值色"), high = color("高值色"),
    z_limit = number("Z-score 色阶上限", 0.1, 20, 0.1), na_color = color("缺失值色"),
    cell_border = color("单元格边线"), cell_border_width = number("边线粗细", 0, 2, 0.1),
    row_font_size = number("基因 / 行名字号 · pt", 5, 36), column_font_size = number("样本 / 列名字号 · pt", 5, 36),
    column_rotation = number("列名旋转角度", 0, 90, 15), show_gene_names = flag("显示基因 / 行名"),
    heatmap_raster = flag("栅格化热图色块（适合大矩阵）"))
  if (tool %in% c("sankey", "venn", "kmeans", "beeswarm", "radar")) {
    fields <- switch(tool, kmeans = c("point_size", "point_alpha", "plot_theme"),
      beeswarm = c("point_size", "point_alpha", "plot_theme"), c("point_alpha", "label_size"))
    styles <- scatter[fields]
    if (tool == "radar") styles$line_width <- number("轮廓线宽 · mm", .2, 3, .1)
    return(list("画布与排版" = common, "当前图型" = styles, "图例" = legend))
  }
  specific <- switch(tool,
    pca = c(scatter, list(group_a = color("第一组颜色"), group_b = color("第二组颜色"), pca_3d_angle = number("三维观察角度", 10, 80, 5))),
    matrix_pca = c(scatter, list(group_a = color("第一组颜色"), group_b = color("第二组颜色"), pca_3d_angle = number("三维观察角度", 10, 80, 5))),
    volcano = c(scatter, list(up = color("上调基因"), down = color("下调基因"), neutral = color("不显著基因"),
      threshold_color = color("筛选阈值线"), threshold_width = number("阈值线宽 · mm", 0.1, 2, 0.1))),
    heatmap = heatmap, matrix_heatmap = heatmap, custom_heatmap = heatmap, manual_heatmap = heatmap,
    gsva = utils::modifyList(heatmap, list(show_gene_names = flag("显示通路名称"),
      row_font_size = number("通路名字号 · pt", 5, 36),
      term_wrap = number("通路名每行最多字符", 8, 120))),
    go = list(enrichment_kind = select("展示形式", c("气泡图" = "dot", "条形图" = "bar")),
      enrichment_orientation = select("条形方向", c("水平" = "horizontal", "竖直" = "vertical")),
      enrichment_low = color("低显著性颜色"), enrichment_high = color("高显著性颜色"),
      enrichment_size_min = number("气泡最小直径 · mm", 1, 10, 0.5), enrichment_size_max = number("气泡最大直径 · mm", 2, 20, 0.5),
      term_wrap = number("通路名称换行宽度 · 字符", 12, 100), point_alpha = number("图元不透明度", 0.1, 1, 0.05)),
    kegg = NULL,
    gsea = list(curve_color = color("富集曲线"), curve_width = number("曲线宽度 · mm", 0.3, 3, 0.1),
      positive_color = color("正排名统计量填色"), negative_color = color("负排名统计量填色"),
      rug_color = color("命中刻线"), rug_width = number("命中刻线宽度 · mm", 0.1, 1.5, 0.1)),
    network = list(network_color_by = select("节点着色", c("自动识别属性" = "auto", "log2FC" = "log2FC", "分组" = "group", "统一颜色" = "uniform")),
      network_node_color = color("统一节点色"), network_low = color("负 log2FC"), network_mid = color("零 log2FC"), network_high = color("正 log2FC"),
      node_size_min = number("最小节点直径 · mm", 1, 12, 0.5), node_size_max = number("最大节点直径 · mm", 2, 24, 0.5),
      network_edge_color = color("连线颜色"), network_edge_width = number("连线宽度 · mm", 0.1, 3, 0.1),
      network_edge_alpha = number("连线不透明度", 0.05, 1, 0.05), network_labels = flag("显示节点标签"),
      network_label_top = number("标签节点数 · 按 degree 排序", 0, 200), label_size = number("节点标签字号 · mm", 1, 10, 0.5)),
    circos = list(chromosome_color = color("染色体填色"), feature_color = color("基因区域填色"), link_color = color("区域连线填色"),
      link_alpha = number("连线不透明度", 0.05, 1, 0.05), start_degree = number("起始角度", 0, 360, 15),
      gap_degree = number("扇区间隔角度", 1, 20), track_height = number("染色体轨道相对高度", 0.04, 0.3, 0.01),
      circos_label_size = number("标签缩放", 0.3, 1.5, 0.1)), list())
  if (tool == "kegg") return(tb_style_schema("go"))
  sections <- list("画布与排版" = common, "当前图型" = specific)
  if (tool %in% c("pca", "matrix_pca")) sections$置信与预测区域 <- pca_confidence
  if (!tool %in% c("circos", "gsea")) sections$图例 <- legend
  sections
}

tb_legend_defaults <- function() list(legend_position = "right", legend_align = "center",
  legend_text_size = 10, legend_title_size = 11, legend_key_size = 4, legend_gap = 3,
  pca_ellipse_2d = FALSE, pca_ellipse_3d = FALSE, pca_confidence = 95,
  pca_region_type = "mean", pca_region_fill = "group", pca_region_color = "#527C91", pca_region_alpha = .18)

tb_style_defaults <- function() c(tb_legend_defaults(), list(line_width = .8, gradient = "", panel_sequence = "abc", panel_fontface = "bold",
  panel_paper = "custom", panel_orientation = "portrait", panel_rows = "", panel_weights = "",
  panel_font_family = "Times New Roman", panel_label_size = 20, panel_label_color = "#242424",
  font_family = "sans", background = "#FFFFFF", plot_theme = "classic", point_shape = "16",
  group_a = "#426C87", group_b = "#B8523E", threshold_color = "#847D72", threshold_width = 0.5,
  na_color = "#E1DDD3", cell_border = "#FFFFFF", cell_border_width = 0.3,
  row_font_size = 11, column_font_size = 10, column_rotation = 45, show_gene_names = TRUE, heatmap_raster = FALSE,
  enrichment_kind = "dot", enrichment_orientation = "horizontal", enrichment_low = "#B9C8BB", enrichment_high = "#B44A37",
  enrichment_size_min = 3, enrichment_size_max = 9, term_wrap = 38,
  curve_color = "#A44032", curve_width = 0.9, positive_color = "#B8523E", negative_color = "#426C87", rug_color = "#292F2D", rug_width = 0.3,
  network_color_by = "auto", network_node_color = "#426C87", network_low = "#426C87", network_mid = "#EAE5D9", network_high = "#B8523E",
  node_size_min = 3, node_size_max = 10, network_edge_color = "#A39F95", network_edge_width = 0.5, network_edge_alpha = 0.55,
  network_labels = TRUE, network_label_top = 30, chromosome_color = "#426C87", feature_color = "#BE6542", link_color = "#B8523E",
  link_alpha = 0.45, start_degree = 90, gap_degree = 4, track_height = 0.11, circos_label_size = 0.7, pca_3d_angle = 40))
tb_palettes <- function() {
  make <- function(low, mid, high) {
    list(low = low, mid = mid, high = high, group_a = low, group_b = high,
      up = high, down = low, neutral = mid, enrichment_low = mid, enrichment_high = high,
      curve_color = low, positive_color = high, negative_color = low,
      network_low = low, network_mid = mid, network_high = high, network_node_color = low,
      chromosome_color = low, feature_color = high, link_color = high)
  }
  list("静谧 · Quietude" = make("#5B6B70", "#EEE8DA", "#916958"),
       "归乡 · Homecoming" = make("#52664D", "#F3E1C7", "#A05C43"),
       "共生 · Symbiosis" = make("#35396B", "#E8EAD1", "#9E596C"),
       "赤潮 · Renegade" = make("#493653", "#F5E4DB", "#B8324E"))
}
tb_gradient_colors <- function(style, fallback) {
  value <- style$gradient
  if (is.null(value) || !length(value) || !nzchar(trimws(value))) return(fallback)
  tokens <- trimws(strsplit(value, ";", fixed = TRUE)[[1]])
  if (!length(tokens) || length(tokens) > 8L) stop("色尺支持 1–8 个颜色，使用分号分隔。")
  vapply(tokens, function(token) {
    if (grepl("^#[0-9A-Fa-f]{3}$", token)) {
      token <- paste0("#", paste(rep(strsplit(substring(token, 2), "")[[1]], each = 2), collapse = ""))
    }
    if (grepl("^rgb\\(\\s*[0-9]+\\s*,\\s*[0-9]+\\s*,\\s*[0-9]+\\s*\\)$", token, ignore.case = TRUE)) {
      rgb <- as.numeric(strsplit(gsub("(?i)rgb|[() ]", "", token, perl = TRUE), ",", fixed = TRUE)[[1]])
      if (any(rgb > 255)) stop("RGB 的各通道须在 0–255。")
      return(grDevices::rgb(rgb[1], rgb[2], rgb[3], maxColorValue = 255))
    }
    if (!grepl("^#[0-9A-Fa-f]{6}$", token)) stop("色尺颜色须为 HEX 或 rgb(红,绿,蓝)。")
    toupper(token)
  }, character(1), USE.NAMES = FALSE)
}

tb_gradient_ramp <- function(style, fallback) {
  colors <- tb_gradient_colors(style, fallback)
  if (length(colors) == 1L) rep(colors, 2L) else colors
}

tb_figure_paper <- function(style) {
  paper <- style$panel_paper
  if (is.null(paper) || identical(paper, "custom")) return(style)
  sizes <- list(A4 = c(210, 297), A3 = c(297, 420), A2 = c(420, 594))
  mm <- sizes[[paper]]
  if (is.null(mm)) stop("请选择 A4、A3、A2 或自定义纸张。")
  if (identical(style$panel_orientation, "landscape")) mm <- rev(mm)
  style$width <- mm[1L] / 25.4
  style$height <- mm[2L] / 25.4
  style
}

tb_figure_layout_options <- function(style, count) {
  tokens <- function(value) {
    if (is.null(value) || !length(value)) return(character())
    if (is.numeric(value)) return(value)
    if (!nzchar(trimws(value))) return(character())
    strsplit(trimws(value), "[ /,，、;；]+")[[1L]]
  }
  rows <- tokens(style$panel_rows)
  if (length(rows) && (!all(grepl("^[1-9][0-9]*$", rows)) ||
      sum(as.numeric(rows)) != count)) stop("每行图片数须为正整数，且总和应等于图片数量。")
  weights <- suppressWarnings(as.numeric(tokens(style$panel_weights)))
  if (length(weights) && (length(weights) != count || any(!is.finite(weights) | weights < .5 | weights > 2)))
    stop("每张图片的相对大小须在 50%–200% 之间。")
  list(rows = as.integer(rows), weights = weights)
}
