# Stable gene IDs determine identity. Symbols supply display and corroboration.
tb_mapping_query <- function(db, values, keytype, columns) {
  tryCatch({
    valid <- intersect(unique(values[!is.na(values) & nzchar(values)]), AnnotationDbi::keys(db, keytype = keytype))
    if (!length(valid)) return(as.data.frame(stats::setNames(rep(list(character()), length(unique(c(keytype, columns)))), unique(c(keytype, columns)))))
    suppressMessages(AnnotationDbi::select(db, valid, columns, keytype))
  }, error = function(e) tb_fail("BW-D02", paste("注释资源查询失败：", conditionMessage(e)),
    hint = "请检查所选物种的注释包和数据库文件是否可读；修复资源后重试。这不是基因身份冲突。", parent = e))
}

tb_gene_mapping <- function(genes, db, species = NULL, query = tb_mapping_query) {
  metadata <- AnnotationDbi::metadata(db)
  organism <- metadata$value[match("ORGANISM", metadata$name)]
  package <- if (identical(organism, "Mus musculus")) "org.Mm.eg.db" else "org.Hs.eg.db"
  version <- as.character(utils::packageVersion(package))
  ids <- trimws(as.character(genes$gene_id))
  names <- trimws(as.character(genes$gene_name %||% genes$gene_id))
  stable <- ids
  versioned <- grepl("^ENS[A-Z]*G[0-9]{11}[.][0-9]+$", ids)
  stable[versioned] <- sub("[.][0-9]+$", "", ids[versioned])
  ensembl <- grepl("^ENS[A-Z]*G[0-9]{11}$", stable)
  # An ENS prefix alone is not an ID namespace: legitimate symbols can share it.
  prefixed <- stable[grepl("^ENS", stable) & !ensembl]
  official_symbols <- query(db, prefixed, "SYMBOL", "ENTREZID")$SYMBOL
  looks_ensembl <- grepl("^ENS", stable) & !stable %in% official_symbols
  numeric <- grepl("^[0-9]+$", stable)
  expected <- if (identical(organism, "Mus musculus")) "^ENSMUSG" else "^ENSG"
  invalid <- looks_ensembl & !ensembl
  foreign <- ensembl & !grepl(expected, stable)
  duplicate_stable <- ensembl & (duplicated(stable) | duplicated(stable, fromLast = TRUE))
  if (!is.null(species) && !identical(organism, if (species == "mouse") "Mus musculus" else "Homo sapiens"))
    tb_fail("BW-M01", "所选物种与已加载的注释数据库不一致。", hint = "请选择正确物种并检查对应 org.*.eg.db 包。")

  ens <- query(db, stable[ensembl], "ENSEMBL", c("ENTREZID", "SYMBOL"))
  direct <- query(db, stable[numeric], "ENTREZID", c("ENTREZID", "SYMBOL"))
  symbols <- query(db, unique(c(stable[!ensembl & !numeric & !invalid], names)), "SYMBOL", c("ENTREZID", "ENSEMBL"))
  alias <- query(db, unique(c(stable[!ensembl & !numeric & !invalid], names)), "ALIAS", "ENTREZID")
  indexes <- new.env(parent = emptyenv())
  values <- function(table, key, value, input) {
    if (is.na(input) || !nzchar(input)) return(character())
    index <- paste(deparse(substitute(table)), key, value, sep = "/")
    if (!exists(index, indexes, inherits = FALSE)) {
      groups <- split(as.character(table[[value]]), table[[key]])
      indexes[[index]] <- lapply(groups, function(x) sort(unique(x[!is.na(x) & nzchar(x)])))
    }
    indexes[[index]][[input]] %||% character()
  }
  resolve <- lapply(seq_along(ids), function(i) {
    if (invalid[i] || foreign[i]) return(character())
    if (ensembl[i]) return(values(ens, "ENSEMBL", "ENTREZID", stable[i]))
    if (numeric[i]) return(values(direct, "ENTREZID", "ENTREZID", stable[i]))
    found <- values(symbols, "SYMBOL", "ENTREZID", stable[i])
    if (!length(found)) found <- values(alias, "ALIAS", "ENTREZID", stable[i])
    # Opaque feature IDs can use the explicitly supplied symbol; stable IDs never fall back.
    if (!length(found) && !is.na(names[i]) && names[i] != ids[i]) found <- values(symbols, "SYMBOL", "ENTREZID", names[i])
    found
  })
  resolved <- vapply(resolve, function(x) if (length(x) == 1L) x else NA_character_, character(1))
  detail <- query(db, unique(resolved[!is.na(resolved)]), "ENTREZID", c("SYMBOL", "ALIAS", "ENSEMBL"))
  database_symbol <- vapply(resolved, function(x) if (is.na(x)) "" else paste(values(detail, "ENTREZID", "SYMBOL", x), collapse = ";"), character(1), USE.NAMES = FALSE)
  aliases <- vapply(resolved, function(x) if (is.na(x)) "" else paste(values(detail, "ENTREZID", "ALIAS", x), collapse = ";"), character(1), USE.NAMES = FALSE)
  reason <- vapply(seq_along(ids), function(i) {
    if (invalid[i]) return("invalid_id_format")
    if (foreign[i]) return("species_mismatch")
    if (duplicate_stable[i]) return("duplicate_stable_id")
    if (length(resolve[[i]]) > 1L) return("ambiguous_id")
    if (is.na(resolved[i])) return("unmapped_id")
    if (is.na(names[i]) || !nzchar(names[i]) || names[i] %in% c(ids[i], stable[i], database_symbol[i])) return("matched")
    if (names[i] %in% values(detail, "ENTREZID", "ALIAS", resolved[i])) return("known_alias")
    other <- values(symbols, "SYMBOL", "ENTREZID", names[i])
    other_ensembl <- values(symbols, "SYMBOL", "ENSEMBL", names[i])
    symbol_primary <- !ensembl[i] && !numeric[i] && resolved[i] %in% values(symbols, "SYMBOL", "ENTREZID", stable[i])
    if (length(other) == 1L && other != resolved[i] && (numeric[i] || symbol_primary ||
        (ensembl[i] && length(other_ensembl) && !stable[i] %in% other_ensembl))) return("confirmed_cross_gene")
    "name_difference_unconfirmed"
  }, character(1))
  status <- ifelse(reason %in% c("invalid_id_format", "species_mismatch", "duplicate_stable_id", "confirmed_cross_gene"), "error",
    ifelse(reason %in% c("ambiguous_id", "unmapped_id"), "unmapped", ifelse(reason == "matched", "mapped", "warning")))
  data.frame(input_id = ids, normalized_id = stable, input_symbol = names, database_symbol = database_symbol,
    aliases = aliases, resolved_id = resolved, candidate_ids = vapply(resolve, paste, collapse = ";", character(1)),
    symbol_resolved_ids = vapply(names, function(x) paste(values(symbols, "SYMBOL", "ENTREZID", x), collapse = ";"), character(1), USE.NAMES = FALSE),
    symbol_ensembl_ids = vapply(names, function(x) paste(values(symbols, "SYMBOL", "ENSEMBL", x), collapse = ";"), character(1), USE.NAMES = FALSE),
    annotation_source = package, annotation_version = version, status = status, conflict_reason = reason,
    duplicated_symbol = !is.na(names) & (duplicated(names) | duplicated(names, fromLast = TRUE)),
    stringsAsFactors = FALSE)
}

tb_check_gene_mapping <- function(report) {
  for (reason in c("invalid_id_format", "species_mismatch", "duplicate_stable_id", "confirmed_cross_gene")) {
    bad <- report$conflict_reason == reason
    if (!any(bad)) next
    explanation <- switch(reason, invalid_id_format = "Ensembl 基因编号格式无效",
      species_mismatch = "Ensembl 编号与所选物种不匹配",
      duplicate_stable_id = "去掉版本后缀后，多个输入行对应同一个 Ensembl 稳定编号",
      confirmed_cross_gene = "编号和名称均有注释，但名称明确指向另一稳定基因编号")
    tb_fail(if (reason == "confirmed_cross_gene") "BW-M02" else "BW-M01",
      paste0(explanation, "（", sum(bad), " 个；示例：", paste(head(report$input_id[bad], 5L), collapse = ", "), "）。"),
      hint = "请核对物种及所选编号/名称列；查看 public_gene_mapping.csv 中的候选编号、别名和原因，按原注释来源核实后再运行。不要仅删除报错基因。")
  }
  warnings <- table(report$conflict_reason[!report$conflict_reason %in% "matched"])
  labels <- c(ambiguous_id = "一个编号对应多个基因", unmapped_id = "未映射编号", known_alias = "已知别名",
    name_difference_unconfirmed = "尚未证实冲突的名称差异")
  if (length(warnings)) message("Warning [BW-MW01] 映射检查：", paste(labels[names(warnings)], warnings, sep = "=", collapse = "; "),
    "；示例：", paste(head(report$input_id[report$conflict_reason != "matched"], 5L), collapse = ", "),
    "。稳定编号优先；未映射或多重映射不参与公共注释匹配。请查看逐行报告，核对原注释版本；不要按名称强行合并或静默删除。")
  if (any(report$duplicated_symbol)) message("Warning [BW-MW02] 多个输入 ID 共用名称；保留各输入 ID，不按名称合并。")
  invisible(report)
}

tb_entrez_ids <- function(genes, db) {
  report <- tb_gene_mapping(genes, db)
  tb_check_gene_mapping(report)
  report$resolved_id
}
