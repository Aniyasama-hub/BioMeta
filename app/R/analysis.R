# 导入完整数据 → 基因表达QC → DESeq2模型 → 保留完整分析数据包。
import_dataset <- function(cfg, samples) {
  if (cfg$input$mode == "counts") {
    input <- read_table(cfg$input$counts)
    if (!all(c(cfg$input$gene_id_col, samples$source_sample_id) %in% names(input))) {
      stop("Count表缺少基因ID或样本列。")
    }
    ids <- input[[cfg$input$gene_id_col]]
    counts <- as.matrix(input[, samples$source_sample_id, drop = FALSE])
    colnames(counts) <- samples$sample_id
    storage.mode(counts) <- "numeric"
    if (anyNA(counts) || any(!is.finite(counts)) || any(counts < 0) ||
        any(counts != round(counts))) stop("counts模式只接受非负有限整数Count。")
    rownames(counts) <- ids
    gene_names <- if (cfg$input$gene_name_col %in% names(input)) {
      input[[cfg$input$gene_name_col]]
    } else ids
    genes <- data.frame(gene_id = ids, gene_name = gene_names)
    txi <- NULL
  } else {
    require_packages("tximport")
    map <- read_table(cfg$input$tx2gene)
    if (!all(c("transcript_id", "gene_id", "gene_name") %in% names(map))) {
      stop("tx2gene须含transcript_id/gene_id/gene_name。")
    }
    if (anyDuplicated(map$transcript_id)) stop("转录本ID不能重复映射。")
    reference <- jsonlite::read_json(cfg$input$reference_manifest, simplifyVector = TRUE)
    if (!identical(reference$species, cfg$project$species) ||
        !identical(reference$tx2gene_sha256,
                   digest::digest(file = cfg$input$tx2gene, algo = "sha256"))) {
      stop("参考物种或tx2gene校验值不匹配。")
    }
    run <- jsonlite::read_json(file.path(cfg$input$salmon_dir, "run_manifest.json"))
    fields <- c("species", "assembly", "release", "index_method", "transcriptome_sha256", "tx2gene_sha256")
    matches <- vapply(fields, function(name) identical(reference[[name]], run$reference[[name]]), logical(1))
    if (!identical(run$status, "completed") || !all(matches)) {
      stop("上游运行未完整成功，或所用参考与下游参考清单不一致。")
    }
    for (id in samples$sample_id) {
      log <- jsonlite::read_json(file.path(cfg$input$salmon_dir, id, "sample.json"))
      marker <- jsonlite::read_json(file.path(cfg$input$salmon_dir, id, "completed.json"))
      quant_sha <- digest::digest(file = file.path(cfg$input$salmon_dir, id, "salmon", "quant.sf"),
                                  algo = "sha256")
      if (!identical(log$status, "completed") ||
          !identical(log$sample_fingerprint, marker$sample_fingerprint) ||
          !identical(log$sample_fingerprint, run$samples[[id]]$sample_fingerprint) ||
          !identical(log$reference_sha256, run$index_sha256) ||
          !identical(quant_sha, marker$quant_sha256) ||
          !identical(quant_sha, log$quant_sha256) ||
          !identical(quant_sha, run$samples[[id]]$quant_sha256)) {
        stop("上游样本来源/完成标记不匹配：", id)
      }
    }
    files <- file.path(cfg$input$salmon_dir, samples$sample_id, "salmon", "quant.sf")
    names(files) <- samples$sample_id
    txi <- tximport::tximport(files, type = "salmon", tx2gene = map[, c("transcript_id", "gene_id")],
                              countsFromAbundance = "no")
    counts <- txi$counts
    genes <- unique(map[, c("gene_id", "gene_name")])
    if (anyDuplicated(genes$gene_id)) stop("一个gene_id映射多个名称，请先规范tx2gene。")
    genes <- genes[match(rownames(counts), genes$gene_id), , drop = FALSE]
  }
  if (anyNA(rownames(counts)) || any(!nzchar(rownames(counts))) ||
      anyDuplicated(rownames(counts))) stop("基因ID必须非空且唯一，不自动按Symbol合并。")
  if (!is.null(cfg$input$genes)) {
    genes <- read_table(cfg$input$genes)
    if (!all(c("gene_id", "gene_name") %in% names(genes)) || anyDuplicated(genes$gene_id)) {
      stop("genes表须含唯一gene_id和gene_name。")
    }
    genes <- genes[match(rownames(counts), genes$gene_id), , drop = FALSE]
    if (anyNA(genes$gene_id)) stop("genes表未覆盖Count基因ID。")
  }
  rownames(genes) <- genes$gene_id
  list(counts = counts, txi = txi, genes = genes)
}

analyze_dataset <- function(cfg, samples, output_dir, fingerprint) {
  require_packages(c("DESeq2", "SummarizedExperiment"))
  set.seed(cfg$analysis$seed)
  design <- make_design(samples, cfg)
  samples <- design$samples
  imported <- import_dataset(cfg, samples)
  counts <- imported$counts
  if (any(colSums(counts) <= 0)) stop("存在零文库样本。")
  # 定量流程保持完整矩阵；模型低表达过滤另存，不覆盖原始矩阵。
  keep <- rowSums(counts >= cfg$analysis$min_count) >= cfg$analysis$min_samples
  if (sum(keep) < 2) stop("低表达过滤后基因不足。")
  if (is.null(imported$txi)) {
    dds <- DESeq2::DESeqDataSetFromMatrix(
      countData = counts[keep, , drop = FALSE], colData = samples, design = design$formula
    )
  } else {
    txi <- lapply(imported$txi, function(x) {
      if (is.matrix(x)) x[keep, , drop = FALSE] else x
    })
    dds <- DESeq2::DESeqDataSetFromTximport(txi, colData = samples, design = design$formula)
  }
  dds <- DESeq2::DESeq(dds, fitType = cfg$analysis$fit_type,
                      sfType = cfg$analysis$size_factor_type, parallel = FALSE)
  contrast <- c("condition", cfg$contrast$numerator, cfg$contrast$denominator)
  results <- DESeq2::results(dds, contrast = contrast, alpha = cfg$analysis$alpha,
                             independentFiltering = cfg$analysis$independent_filtering,
                             cooksCutoff = cfg$analysis$cooks_cutoff)
  deg <- data.frame(gene_id = rownames(results), as.data.frame(results), row.names = NULL)
  deg$gene_name <- imported$genes[deg$gene_id, "gene_name"]
  # 收缩估计单独保存；默认不改变DEG阈值所用原始log2FC。
  if (cfg$analysis$shrink == "normal") {
    shrunken <- DESeq2::lfcShrink(dds, contrast = contrast, res = results, type = "normal")
    deg$log2FC_shrunken <- shrunken$log2FoldChange
  } else if (cfg$analysis$shrink != "none") stop("shrink只支持none/normal。")
  deg$result_status <- ifelse(is.na(deg$pvalue), "pvalue_NA_outlier_or_unestimable",
                              ifelse(is.na(deg$padj), "padj_NA_independent_filter", "tested"))
  # varianceStabilizingTransformation在少基因数据上也适用；避免vst的nsub限制。
  transformed <- DESeq2::varianceStabilizingTransformation(dds, blind = cfg$analysis$vst_blind)
  vst <- SummarizedExperiment::assay(transformed)
  vst_batch <- NULL
  if (cfg$analysis$batch_visualization) {
    require_packages("limma")
    if (nlevels(samples$batch) < 2) stop("去批次展示需要至少两个技术批次。")
    preserved <- stats::reformulate(unique(c(cfg$analysis$covariates, "condition")))
    full <- stats::model.matrix(stats::reformulate(unique(c(cfg$analysis$covariates, "batch", "condition"))), samples)
    if (qr(full)$rank < ncol(full)) stop("去批次展示设计不满秩，不能区分批次与生物效应。")
    vst_batch <- limma::removeBatchEffect(
      vst, batch = samples$batch, design = stats::model.matrix(preserved, samples)
    )
  }
  result <- list(
    schema_version = "1.0", species = cfg$project$species, fingerprint = fingerprint,
    counts = counts, genes = imported$genes, samples = samples,
    model_genes = rownames(vst), deg = deg, vst = vst, vst_batch = vst_batch,
    normalized_counts = DESeq2::counts(dds, normalized = TRUE), dds = dds,
    config = cfg
  )
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  write_table(data.frame(gene_id = rownames(counts), counts, check.names = FALSE),
              file.path(output_dir, "counts_complete.csv"))
  write_table(imported$genes, file.path(output_dir, "genes.csv"))
  write_table(samples, file.path(output_dir, "samples.csv"))
  write_table(data.frame(gene_id = rownames(counts), retained_for_model = keep),
              file.path(output_dir, "gene_filter_report.csv"))
  write_table(deg, file.path(output_dir, "deg_all.csv"))
  for (name in c("vst", "normalized_counts", "vst_batch")) {
    matrix <- result[[name]]
    if (!is.null(matrix)) write_table(data.frame(gene_id = rownames(matrix), matrix,
                                                check.names = FALSE),
                                     file.path(output_dir, paste0(name, ".csv")))
  }
  # 表达层QC不等同于测序QC；Salmon estimated counts总量也不冒充原始reads。
  qc <- data.frame(sample_id = samples$sample_id, condition = samples$condition,
                   batch = samples$batch, count_sum = colSums(counts),
                   detected_genes = colSums(counts > 0),
                   input_units = if (is.null(imported$txi)) "integer_counts" else "estimated_counts")
  write_table(qc, file.path(output_dir, "expression_qc.csv"))
  write_table(data.frame(sample_id = rownames(stats::cor(vst)), stats::cor(vst),
                         check.names = FALSE), file.path(output_dir, "sample_correlations.csv"))
  saveRDS(result, file.path(output_dir, "analysis.rds"))
  result
}
