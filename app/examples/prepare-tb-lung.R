# Build local demonstration inputs from the supplied GEO-derived directories.
args <- commandArgs(TRUE)
stopifnot(length(args) == 2L)
# 至少 3 个样本计数达到 10；显著性用于独立过滤，完整表仍保留全部受检基因。
min_count <- 10L
min_samples <- 3L
alpha <- .05
fit_type <- "parametric"
source_root <- args[1]
target_root <- args[2]
directories <- sort(list.dirs(source_root, recursive = FALSE))
directories <- directories[grepl("^0[1-9]_", basename(directories))]
stopifnot(length(directories) == 9L)
contrasts <- list(c("Normal","TB"), c("Healthy parenchyma","Granuloma"), c("Media","M. tuberculosis"),
  c("TB-IH","TB-preDM"), c("Control","Active_TB"), c("cntl / naive","ltbi / naive"),
  c("B6 / minus","Sp140 KO / minus"), c("B6","Apoe"), c("Uninfected","HN878"))
read_tsv <- function(path) read.delim(path, check.names = FALSE, stringsAsFactors = FALSE)
write_tsv <- function(x, file) write.table(x, file, sep = "\t", quote = FALSE, row.names = FALSE)
clean <- function(path, samples) {
  table <- read_tsv(path)
  ids <- trimws(as.character(table[[1]]))
  stopifnot(all(samples %in% names(table)), !anyDuplicated(names(table)))
  values <- as.matrix(table[, samples, drop = FALSE])
  keep <- !is.na(ids) & nzchar(ids) & rowSums(!is.finite(values)) == 0L & rowSums(values != 0, na.rm = TRUE) > 0L
  # 只删除同一 ID 且所有样本数值完全相同的重复记录；不同表达的同名基因保留。
  stable_ids <- make.unique(ids, sep = "__")
  duplicate <- duplicated(data.frame(gene_id = ids, values, check.names = FALSE))
  retained <- keep & !duplicate
  rownames(values) <- stable_ids
  list(values = values[retained, , drop = FALSE], symbols = ids[retained],
    removed = sum(!keep), exact_duplicates = sum(keep & duplicate),
    duplicated = sum(duplicated(ids[retained])), unused_columns = ncol(table) - 1L - length(samples))
}
for (i in seq_along(directories)) {
  src <- directories[i]
  name <- basename(src)
  dest <- file.path(target_root, name)
  dir.create(dest, recursive = TRUE, showWarnings = FALSE)
  g <- read_tsv(file.path(src, "group.tsv"))
  stopifnot(!anyDuplicated(g$sample_id))
  keep <- !is.na(g$group) & nzchar(trimws(g$group))
  if (i == 3) keep <- keep & g$cell_type == "alveolar macrophage"
  if (i == 4) keep <- keep & g$timepoint == "Diagnosis"
  if (i == 5) keep <- keep & g$timepoint == "Baseline" & !(g$outlier_flag %in% "Yes")
  if (i == 8) {
    keep <- keep & g$cell_type == "AM" & g$treatment == "inf" & g$timepoint == 10
    g$group <- g$genotype
  }
  if (i == 9) keep <- keep & g$timepoint == "day26"
  original_n <- nrow(g)
  pair <- contrasts[[i]]
  g <- g[which(keep & g$group %in% pair), , drop = FALSE]
  paired <- i %in% c(2, 3)
  if (paired) {
    subjects <- intersect(g$subject_id[g$group == pair[1]], g$subject_id[g$group == pair[2]])
    g <- g[g$subject_id %in% subjects & !duplicated(g[c("subject_id","group")]), , drop = FALSE]
  }
  stopifnot(all(table(factor(g$group, levels = pair)) >= 2L))
  group <- data.frame(Sample = g$sample_id, Group = g$group)
  if (paired) group$subject_id <- g$subject_id
  if (i == 7) group$batch <- g$batch
  write_tsv(group, file.path(dest, "groups.tsv"))
  expression <- clean(file.path(src, "log2cpm.tsv.gz"), g$sample_id)
  write_tsv(data.frame(gene_id = rownames(expression$values), expression$values, check.names = FALSE),
    file.path(dest, "matrix.tsv"))
  variance <- apply(expression$values, 1L, var)
  targets <- rownames(expression$values)[head(order(variance, decreasing = TRUE), 20L)]
  write_tsv(data.frame(GeneKey = targets, Use = TRUE), file.path(dest, "targets.tsv"))
  group$condition <- factor(g$group, levels = pair)
  if (paired) group$subject_id <- factor(group$subject_id)
  if (i == 7) group$batch <- factor(group$batch)
  design <- if (paired) ~subject_id + condition else if (i == 7) ~batch + condition else ~condition
  count_file <- file.path(src, "counts.tsv.gz")
  if (file.exists(count_file)) {
    counts <- clean(count_file, g$sample_id)
    stopifnot(all(counts$values >= 0 & counts$values == floor(counts$values)))
    write_tsv(data.frame(gene_id = rownames(counts$values), gene_name = counts$symbols,
      counts$values, check.names = FALSE), file.path(dest, "counts.tsv"))
    dds <- DESeq2::DESeqDataSetFromMatrix(counts$values, group, design)
    dds <- DESeq2::DESeq(dds[rowSums(DESeq2::counts(dds) >= min_count) >= min_samples, ],
      fitType = fit_type, quiet = TRUE)
    fit <- as.data.frame(DESeq2::results(dds, contrast = c("condition", rev(pair)), alpha = alpha))
    ids <- rownames(fit)
    result <- data.frame(gene_id = ids, gene_name = counts$symbols[match(ids, rownames(counts$values))],
      fit, row.names = NULL)
    method <- "DESeq2（原始整数计数）"
  } else {
    fit <- limma::eBayes(limma::lmFit(expression$values, model.matrix(design, group)))
    t <- limma::topTable(fit, coef = ncol(fit$coefficients), number = Inf, sort.by = "none")
    ids <- rownames(t)
    result <- data.frame(gene_id = ids, gene_name = expression$symbols[match(ids, rownames(expression$values))],
      log2FoldChange = t$logFC, stat = t$t, pvalue = t$P.Value, padj = t$adj.P.Val)
    method <- "limma（log2 CPM，源数据没有原始整数 Count）"
  }
  audit <- data.frame(input = "matrix", removed_invalid_or_zero = expression$removed,
    removed_exact_duplicates = expression$exact_duplicates, omitted_columns = expression$unused_columns,
    retained_rows = nrow(expression$values))
  if (file.exists(count_file)) audit <- rbind(audit, data.frame(input = "counts",
    removed_invalid_or_zero = counts$removed, removed_exact_duplicates = counts$exact_duplicates,
    omitted_columns = counts$unused_columns, retained_rows = nrow(counts$values)))
  write.csv(audit, file.path(dest, "cleaning_summary.csv"), row.names = FALSE)
  write.csv(result, file.path(dest, "deg.csv"), row.names = FALSE, fileEncoding = "UTF-8")
  file.copy(file.path(src, "README.md"), file.path(dest, "README.md"), overwrite = TRUE)
  cat(sprintf("\n## 工作站默认示例\n\n- 比较：%s 相对 %s。\n- 方法：%s。\n- 样本：保留 %d/%d 个与示例比较相符的样本。\n- 表达矩阵：排除 %d 个空 ID、非有限值或全零行。保留 %d 个重复符号行，并用后缀区分。\n- 差异结果仅供流程演示。\n",
    pair[2], pair[1], method, nrow(g), original_n, expression$removed, expression$duplicated),
    file = file.path(dest, "README.md"), append = TRUE)
  cat(sprintf("\n- 低表达过滤：至少 %d 个样本 Count 达到 %d；模型显著性 %.2f，离散度拟合 %s（仅 Count 示例）。\n- 模型设计：%s。完整 DEG 保留未显著基因供 GSEA 排序使用。\n- 仅删除同 ID 且数值完全相同的重复行；其余重复符号保留。具体删除行数和省略列数见 cleaning_summary.csv。\n- 这里的 counts.tsv、groups.tsv、matrix.tsv、targets.tsv 和 deg.csv 是可直接用于工作站的整理文件；上方原始数据读入示例仅说明数据来源。\n",
    min_samples, min_count, alpha, fit_type, paste(deparse(design), collapse = " ")),
    file = file.path(dest, "README.md"), append = TRUE)
  jsonlite::write_json(list(species = if (i <= 5) "human" else "mouse", control = pair[1], treatment = pair[2],
    fit_type = fit_type, min_count = min_count, min_samples = min_samples, alpha = alpha,
    use_batch = i == 7, covariates = if (paired) "subject_id" else "", count = file.exists(count_file)),
    file.path(dest, "preset.json"), auto_unbox = TRUE)
  cat("PASS", name, nrow(g), nrow(result), method, "\n")
}
