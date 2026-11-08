# Public mouse IDs and synthetic statistics. No personal input or RNA-seq model.
root <- normalizePath("app", winslash = "/")
source(file.path(root, "R/toolbox.R"), encoding = "UTF-8")
out <- file.path(root, "tests/_pathway-review/mapping-debug")
db <- getExportedValue("org.Mm.eg.db", "org.Mm.eg.db")
ids <- head(AnnotationDbi::keys(db, keytype = "ENTREZID"), 350)
symbols <- unname(suppressMessages(AnnotationDbi::mapIds(db, ids, "SYMBOL", "ENTREZID", multiVals = "asNA")))
set.seed(42)
d <- data.frame(gene_id = ids, gene_name = symbols, log2FoldChange = rep(c(2, -2), 175),
  stat = rnorm(350), pvalue = rep(c(NA, .8), 175), padj = 1)
d$padj[1:80] <- .001
input <- file.path(out, "public_mouse_synthetic.csv"); write.csv(d, input, row.names = FALSE)
run <- function(spec) {
  job <- tb_launch_job(spec, root); job$process$wait()
  state <- tb_read_job(job$directory)
  if (state$status != "completed") stop(state$error %||% state$summary)
  job
}
spec <- list(tool = "kegg", inputs = list(deg = input), params = list(species = "mouse", pathway_source = "kegg",
  ora_filter_mode = "both", padj = .05, log2fc = 1, ora_fdr = 1, min_set_size = 2, kegg_maps = "off", pathway_top = 2),
  style = list(formats = "png", width = 7, height = 5, dpi = 96))
kegg <- run(spec)
quality <- jsonlite::read_json(file.path(kegg$directory, "outputs/mapping_quality.json"))
stopifnot(quality$input_genes == 350, quality$candidate_genes == 40, quality$mode == "ORA")
spec$tool <- "gsea"; spec$params$pathway_source <- "go"; spec$params$go_ontology <- "BP"
# An impossible ORA threshold must not prefilter GSEA's full signed ranking.
spec$params$log2fc <- 999
gsea <- run(spec)
ranks <- read.csv(file.path(gsea$directory, "outputs/gsea_ranked_stats.csv"), colClasses = c(rank_id = "character"))
stopifnot(nrow(ranks) == 350, setequal(ranks$rank_id, d$gene_id),
  isTRUE(all.equal(ranks$stat, d$stat[match(ranks$rank_id, d$gene_id)])))
quality <- jsonlite::read_json(file.path(gsea$directory, "outputs/mapping_quality.json"))
stopifnot(quality$mode == "GSEA", quality$valid_ranked_genes == 350)
jsonlite::write_json(list(kegg = kegg$directory, gsea = gsea$directory), file.path(out, "public-jobs.json"), auto_unbox = TRUE, pretty = TRUE)
cat("PASS actual public mouse KEGG ORA and GO GSEA; full finite stat list retains NA P values and ignores ORA thresholds\n")
