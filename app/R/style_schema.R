# 每种图只暴露有实际渲染语义的选项；前端和输入校验使用同一份定义。
tb_style_schema <- function(tool) {
  number <- function(label, min = 0, max = 100, step = 1) list(type = "number", label = label, min = min, max = max, step = step)
  color <- function(label) list(type = "color", label = label)
  select <- function(label, choices) list(type = "select", label = label, choices = choices)
  flag <- function(label) list(type = "flag", label = label)
  if (tool == "deg") return(list())
  common <- list(
    width = number("画布宽 · 英寸", 2, 60, 0.5), height = number("画布高 · 英寸", 2, 60, 0.5),
    dpi = number("位图分辨率 · dpi", 72, 1200, 50), base_size = number("基础字号 · pt", 6, 48),
    font_family = select("图形字体", c("无衬线 Sans" = "sans", "衬线 Serif" = "serif", "等宽 Mono" = "mono")),
    background = color("画布背景"), legend_position = select("图例位置", c("右" = "right", "下" = "bottom", "左" = "left", "上" = "top")))
  scatter <- list(point_size = number("散点直径 · mm", 0.2, 16, 0.2),
    point_alpha = number("散点不透明度", 0.05, 1, 0.05), point_shape = select("散点形状", c("圆" = "16", "三角" = "17", "方" = "15", "菱形" = "18")),
    label_size = number("标签字号 · mm", 1, 10, 0.5), plot_theme = select("坐标版式", c("简洁轴线" = "classic", "细网格" = "minimal", "完整边框" = "bw")))
  heatmap <- list(low = color("低值色"), mid = color("中值色"), high = color("高值色"),
    z_limit = number("Z-score 色阶上限", 0.1, 20, 0.1), na_color = color("缺失值色"),
    cell_border = color("单元格边线"), cell_border_width = number("边线粗细", 0, 2, 0.1),
    row_font_size = number("基因 / 行名字号 · pt", 5, 36), column_font_size = number("样本 / 列名字号 · pt", 5, 36),
    column_rotation = number("列名旋转角度", 0, 90, 15), show_gene_names = flag("显示基因 / 行名"),
    heatmap_raster = flag("栅格化热图色块（适合大矩阵）"))
  specific <- switch(tool,
    pca = c(scatter, list(group_a = color("第一组颜色"), group_b = color("第二组颜色"), pca_3d_angle = number("三维观察角度", 10, 80, 5))),
    matrix_pca = c(scatter, list(group_a = color("第一组颜色"), group_b = color("第二组颜色"), pca_3d_angle = number("三维观察角度", 10, 80, 5))),
    volcano = c(scatter, list(up = color("上调基因"), down = color("下调基因"), neutral = color("不显著基因"),
      threshold_color = color("筛选阈值线"), threshold_width = number("阈值线宽 · mm", 0.1, 2, 0.1))),
    heatmap = heatmap, matrix_heatmap = heatmap, custom_heatmap = heatmap, manual_heatmap = heatmap, gsva = heatmap,
    go = list(enrichment_kind = select("展示形式", c("气泡图" = "dot", "条形图" = "bar")),
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
  if (tool %in% c("circos", "gsea")) common$legend_position <- NULL
  list("画布与排版" = common, "当前图型" = specific)
}

tb_style_defaults <- function() list(
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
