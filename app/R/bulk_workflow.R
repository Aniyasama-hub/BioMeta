tb_bulk_steps <- c(pca = "PCA", deg = "差异表达", volcano = "火山图", heatmap = "热图",
  go = "GO", kegg = "KEGG", gsea = "GSEA", gsva = "GSVA", network = "PPI", figure_layout = "组图")

tb_bulk_source <- function(ids, custom = FALSE) {
  if (custom) return("custom")
  if (length(ids) && all(startsWith(ids, "GO:"))) return("go")
  if (length(ids) && all(grepl("^(hsa|mmu)[0-9]{5}$", ids))) return("kegg")
  "reactome"
}

tb_bulk_spec <- function(flow, tool, defaults, style = list()) {
  p <- utils::modifyList(defaults$params, flow$params)
  if (tool == "pca" && p$group_mode != "pair") p$group_mode <- "joint"
  p$network_mode <- "deg"
  p$ppi_require_edges <- TRUE
  p$ppi_reference <- TRUE
  if (tool %in% tb_pathway_tools) {
    terms <- flow$terms[[tool]]
    p$pathway_terms <- if (tool != "gsea") terms else ""
    p$pathway_id <- if (tool == "gsea") terms else ""
    p$pathway_source <- if (flow$synthetic || (tool %in% c("gsea", "gsva") && flow$custom)) "custom"
      else if (tool %in% c("go", "kegg")) tool else tb_bulk_source(tb_parse_terms(terms))
  }
  request <- list(tool = tool, inputs = flow$inputs, params = p, style = utils::modifyList(defaults$style, style))
  source <- flow$approved$deg
  if (!is.null(source) && tool %in% c("volcano", "heatmap", tb_pathway_tools, "network")) {
    if (p$group_mode == "pair") request <- tb_link_deg_outputs(request, file.path(source, "outputs"))
    else request$upstream_deg <- source
  }
  request
}

tb_bulk_figures <- function(flow) {
  choices <- lapply(names(tb_bulk_steps), function(id) {
    directory <- flow$approved[[id]]
    if (is.null(directory)) return(character())
    files <- tb_read_job(directory)$files
    files <- files[grepl("[.]png$", files, ignore.case = TRUE) & file.exists(files)]
    if (!length(files)) return(character())
    if (!length(files)) return(character())
    suffix <- sub(paste0(directory, "/outputs/"), "", files, fixed = TRUE)
    if (id == "gsea") suffix <- paste(dirname(suffix), "·", tb_gsea_image_labels(files))
    stats::setNames(files, paste(tb_bulk_steps[[id]], "·", suffix))
  })
  do.call(c, choices)
}
