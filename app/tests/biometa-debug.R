# Public identifiers / synthetic statistics by default. Optional real DEG path is explicit.
root <- normalizePath("app", winslash = "/")
for (file in c("toolbox", "toolbox_analysis", "public_pathways", "workbench_settings", "settings_tools"))
  source(file.path(root, "R", paste0(file, ".R")), encoding = "UTF-8")
out <- file.path(root, "tests/_pathway-review/mapping-debug")
dir.create(out, recursive = TRUE, showWarnings = FALSE)
db <- getExportedValue("org.Mm.eg.db", "org.Mm.eg.db")
human <- getExportedValue("org.Hs.eg.db", "org.Hs.eg.db")
symbol <- tb_gene_mapping(data.frame(gene_id = "ENSA", gene_name = "ENSA"), human, "human")
stopifnot(symbol$status == "mapped", symbol$resolved_id == "2029")
five <- data.frame(gene_id = c("ENSMUSG00000062382", "ENSMUSG00000073538", "ENSMUSG00000098055", "ENSMUSG00000056592", "ENSMUSG00000111713"),
  gene_name = c("Ftl1-ps1", "E330020D12Rik", "Gm26947", "Zfp658", "Gm20234"))
report <- tb_gene_mapping(five, db, "mouse")
stopifnot(!any(report$status == "error"), !anyNA(report$resolved_id), report$conflict_reason[4] == "known_alias")
write.csv(report, file.path(out, "five_gene_diagnostics.csv"), row.names = FALSE)
bare <- five; bare$gene_name <- bare$gene_id
stopifnot(identical(tb_entrez_ids(bare, db), report$resolved_id))
versioned <- bare; versioned$gene_id <- paste0(versioned$gene_id, ".1"); versioned$gene_name <- versioned$gene_id
stopifnot(identical(tb_entrez_ids(versioned, db), report$resolved_id))
duplicate <- data.frame(gene_id = paste0(bare$gene_id[1], c(".1", ".2")))
duplicate$gene_name <- duplicate$gene_id
error <- tryCatch(tb_entrez_ids(duplicate, db), error = identity)
stopifnot(inherits(error, "bioworkbench_error"), error$code == "BW-M01")
different <- data.frame(gene_id = "ENSMUSG00000030695", gene_name = "Gapdh")
error <- tryCatch(tb_entrez_ids(different, db), error = identity)
stopifnot(inherits(error, "bioworkbench_error"), error$code == "BW-M02")
error <- tryCatch(tb_entrez_ids(data.frame(gene_id = "434624", gene_name = "Ftl1-ps1"), db), error = identity)
stopifnot(inherits(error, "bioworkbench_error"), error$code == "BW-M02")
error <- tryCatch(tb_entrez_ids(data.frame(gene_id = "Aldoa", gene_name = "Gapdh"), db), error = identity)
stopifnot(inherits(error, "bioworkbench_error"), error$code == "BW-M02")
same <- five[1:2, ]; same$gene_name <- "Shared display name"
stopifnot(length(unique(tb_entrez_ids(same, db))) == 2L)
edge <- data.frame(gene_id = c("ENSMUSG99999999999", "ENSMUSG00000062382"), gene_name = c("Aldoa", "Ftl1-ps1"))
edge <- tb_gene_mapping(edge, db, "mouse")
stopifnot(is.na(edge$resolved_id[1]), !is.na(edge$resolved_id[2]))
noncoding <- suppressMessages(AnnotationDbi::select(db, "Neat1", "ENSEMBL", "SYMBOL"))
noncoding <- noncoding[!is.na(noncoding$ENSEMBL), ][1, ]
stopifnot(!is.na(tb_entrez_ids(data.frame(gene_id = noncoding$ENSEMBL, gene_name = "Neat1"), db)))
for (id in c("ENSG00000141510", "ENSMUSG_bad")) {
  error <- tryCatch(tb_entrez_ids(data.frame(gene_id = id, gene_name = id), db), error = identity)
  stopifnot(inherits(error, "bioworkbench_error"), error$code == "BW-M01")
}
error <- tryCatch(tb_mapping_query(db, "1", "unavailable_keytype", "ENTREZID"), error = identity)
stopifnot(inherits(error, "bioworkbench_error"), error$code == "BW-D02")
closed <- AnnotationDbi::loadDb(AnnotationDbi::dbfile(db))
DBI::dbDisconnect(AnnotationDbi::dbconn(closed))
error <- tryCatch(tb_mapping_query(closed, five$gene_id, "ENSEMBL", "ENTREZID"), error = identity)
stopifnot(inherits(error, "bioworkbench_error"), error$code == "BW-D02", DBI::dbIsValid(AnnotationDbi::dbconn(db)))
engine <- tb_engine(root)
ranked <- data.frame(gene_id = c("A", "B", "C"), gene_name = c("A", "B", "C"), stat = c(3, -2, 1), pvalue = c(NA, .2, .01), padj = c(NA, 1, .03))
stopifnot(length(engine$.make_ranked_stats(ranked, ranked, "gene_id")) == 3L)
cat("PASS aliases, primary-ID identity, true conflict, shared symbol, pseudogene, noncoding, unmapped, species, format, query failure and full-stat GSEA\n")

run <- function(spec, expected = "completed") {
  job <- tb_launch_job(spec, root); job$process$wait()
  state <- tb_read_job(job$directory)
  if (!identical(state$status, expected)) stop(state$error %||% state$summary)
  job
}
args <- commandArgs(trailingOnly = TRUE)
jobs <- list()
if (length(args)) {
  original <- normalizePath(args[1], winslash = "/", mustWork = TRUE)
  d <- read.csv(original, check.names = FALSE)
  mapped <- tb_gene_mapping(d, db, "mouse")
  stopifnot(any(mapped$conflict_reason == "ambiguous_id"), all(is.na(mapped$resolved_id[mapped$conflict_reason == "ambiguous_id"])))
  write.csv(mapped[mapped$conflict_reason == "confirmed_cross_gene", ], file.path(out, "confirmed_conflicts.csv"), row.names = FALSE)
  significant <- d[as.logical(d$Significant), ]
  stopifnot(nrow(d) == 18531L, nrow(significant) == 486L, !anyDuplicated(d$gene_id))
  # This checks mapping order only. A significant-only file is NOT a valid full ORA universe.
  sig_map <- tb_gene_mapping(significant, db, "mouse"); tb_check_gene_mapping(sig_map)
  bare <- d; bare$gene_name <- NULL
  bare_path <- file.path(out, "ensembl_only.csv"); write.csv(bare, bare_path, row.names = FALSE)
  spec <- list(tool = "go", inputs = list(deg = original), params = list(species = "mouse", pathway_source = "go",
    ora_filter_mode = "both", ora_p_column = "padj", ora_effect_column = "log2FC", padj = .05, log2fc = 1,
    go_output_scope = "both", pathway_top = 5), style = list(formats = "png", width = 9, height = 8, dpi = 96, enrichment_kind = "both"))
  jobs$strict_original <- run(spec, "failed")
  stopifnot(grepl("BW-M02", tb_read_status(jobs$strict_original$directory)$error))
  spec$inputs$deg <- bare_path
  jobs$id_only <- run(spec)
  files <- list.files(file.path(jobs$id_only$directory, "outputs"), recursive = TRUE)
  stopifnot(sum(grepl("[.]png$", files)) == 8L, all(vapply(c("go_BP/", "go_CC/", "go_MF/", "go_BP_CC_MF/"), function(x) any(startsWith(files, x)), logical(1))))
  spec$inputs$deg <- original; spec$params$gene_name_column <- "__id_only__"
  jobs$explicit_primary_id <- run(spec)
  a <- read.csv(file.path(jobs$id_only$directory, "outputs/ora_results.csv"))
  b <- read.csv(file.path(jobs$explicit_primary_id$directory, "outputs/ora_results.csv"))
  stopifnot(isTRUE(all.equal(a, b, check.attributes = FALSE)))
  archive <- file.path(out, "strict_failed_diagnostics.zip")
  tb_zip_diagnostics(jobs$strict_original$directory, archive, root)
  names <- zip::zip_list(archive)$filename
  stopifnot(all(vapply(c("task/inputs/deg.csv", "task/parameters.json", "task/job.log", "task/error_details.json", "task/sessionInfo.txt", "task/execution_source/R/gene_mapping.R", "diagnostic_manifest.csv"), function(x) x %in% names, logical(1))))
  stopifnot(inherits(try(tb_zip_diagnostics(jobs$id_only$directory, tempfile(fileext = ".zip"), root), silent = TRUE), "try-error"))
  quality <- jsonlite::read_json(file.path(jobs$id_only$directory, "outputs/mapping_quality.json"))
  stopifnot(quality$input_genes == nrow(d), quality$final_universe_genes > quality$final_enrichment_genes)
  cat("PASS original strict conflict preserved; 486-significant mapping; true original ID-only GO BP/CC/MF; equivalent explicit-ID choice; full failed-task diagnostic ZIP; success ZIP denial\n")
}
if (length(jobs)) jsonlite::write_json(lapply(jobs, function(x) x$directory), file.path(out, "jobs.json"), auto_unbox = TRUE, pretty = TRUE)
