tb_string_reference <- function(root, species) {
  taxon <- if (species == "human") "9606" else "10090"
  parts <- c("protein.info", "protein.physical.links")
  files <- paste(taxon, parts, "v12.0.txt.gz", sep = ".")
  list(paths = file.path(root, "results", "toolbox", "references", files),
    urls = paste0("https://stringdb-downloads.org/download/", parts, ".v12.0/", files))
}

tb_string_edges <- function(analysis, cfg, spec, root, output, engine) {
  species <- spec$params$species
  reference <- tb_string_reference(root, species)
  if (!all(file.exists(reference$paths))) stop("本机缺少该物种的 STRING 参考，请上传互作 Edge 表。")
  selected <- analysis$deg[engine$selection_mask(analysis$deg, cfg$selection), , drop = FALSE]
  if (!nrow(selected)) stop("当前阈值下没有差异基因可用于 PPI。")
  genes <- unique(selected[c("gene_id", "gene_name")])
  info <- utils::read.delim(reference$paths[1L], check.names = FALSE, quote = "")
  symbols <- as.character(genes$gene_name)
  unresolved <- !symbols %in% info$preferred_name
  if (any(unresolved)) {
    package <- if (species == "human") "org.Hs.eg.db" else "org.Mm.eg.db"
    engine$require_packages(c(package, "AnnotationDbi"))
    db <- getExportedValue(package, package)
    ids <- tb_entrez_ids(genes[unresolved, ], db)
    keys <- unique(ids[!is.na(ids)])
    if (length(keys)) {
      mapped <- suppressMessages(AnnotationDbi::mapIds(db, keys, "SYMBOL", "ENTREZID", multiVals = "asNA"))
      symbols[unresolved] <- unname(mapped[ids])
    }
  }
  protein <- as.character(info[[1L]])
  matches <- merge(data.frame(protein = protein, symbol = info$preferred_name),
    data.frame(symbol = symbols[!is.na(symbols)], gene_id = genes$gene_id[!is.na(symbols)]), by = "symbol")
  direct <- match(sub("[.][0-9]+$", "", genes$gene_id), sub("^[0-9]+[.]", "", protein))
  prefixed <- match(genes$gene_id, protein)
  direct[!is.na(prefixed)] <- prefixed[!is.na(prefixed)]
  direct_rows <- !is.na(direct)
  map <- unique(rbind(matches[c("protein", "gene_id")],
    data.frame(protein = protein[direct[direct_rows]], gene_id = genes$gene_id[direct_rows])))
  ambiguous <- duplicated(map$protein) | duplicated(map$protein, fromLast = TRUE)
  map <- map[!ambiguous, , drop = FALSE]
  if (!nrow(map)) stop("差异基因与 STRING 标识没有匹配，请检查物种和基因 ID，或上传 Edge 表。")
  lookup <- stats::setNames(map$gene_id, map$protein)
  edges <- utils::read.table(reference$paths[2L], header = TRUE,
    colClasses = c("character", "character", "integer"))
  keep <- edges$protein1 %in% map$protein & edges$protein2 %in% map$protein
  path <- file.path(output, "ppi_reference_edges.csv")
  utils::write.csv(data.frame(from = unname(lookup[edges$protein1[keep]]),
    to = unname(lookup[edges$protein2[keep]]), score = edges$combined_score[keep] / 1000),
    path, row.names = FALSE)
  engine$write_manifest(list(database = "STRING physical links", version = "12.0", species = species,
    urls = reference$urls, sha256 = engine$file_fingerprint(reference$paths),
    mapped_genes = length(unique(map$gene_id)), selected_genes = nrow(genes)),
    file.path(output, "ppi_reference_source.json"))
  path
}
