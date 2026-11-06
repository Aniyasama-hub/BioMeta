# Regenerate deterministic, fully synthetic examples. Run from app/examples.
set.seed(42)
genes <- sprintf("g%03d", 1:160)
samples <- paste0("S", 1:6)
counts <- matrix(rnbinom(960, mu = 200, size = 40), nrow = 160, dimnames = list(NULL, samples))
counts[1:30, 4:6] <- counts[1:30, 4:6] * 6
counts[31:60, 1:3] <- counts[31:60, 1:3] * 6
save <- function(x, name) write.csv(x, paste0("demo_", name, ".csv"), row.names = FALSE)
save(data.frame(gene_id = genes, gene_name = genes, counts), "counts")
save(data.frame(Sample = samples, Group = rep(c("Control", "Treatment"), each = 3)), "groups")
save(data.frame(GeneKey = genes[1:20], Use = TRUE), "targets")
fold_change <- c(rep(2.6, 30), rep(-2.6, 30), rnorm(100, 0, .2))
save(data.frame(gene_id = genes, gene_name = genes, log2FoldChange = fold_change, stat = fold_change / .35,
  padj = c(runif(60, 0, .005), runif(100, .2, 1))), "deg")
save(data.frame(gene_id = genes, log2(1 + counts)), "expression")
save(data.frame(from = genes[1:25], to = genes[2:26], score = .9), "model_edges")
writeLines(vapply(0:7, function(i) paste(c(paste0("DEMO_", i + 1), paste("Synthetic set", i + 1),
  genes[(1:20) + i*20]), collapse = "\t"), character(1)), "demo_sets.gmt")
save(data.frame(source = c("A","A","B","C"), target = c("I","II","II","III"), value = c(4,2,6,3)), "sankey")
save(data.frame(set = rep(c("A","B","C"), each = 7), item = c(1:7, 4:10, 7:13)), "venn")
save(data.frame(id = paste0("X", 1:30), x = rnorm(30, rep(c(-3,0,3), each = 10), .4),
  y = rnorm(30, rep(c(0,4,0), each = 10), .4)), "kmeans")
save(data.frame(group = rep(c("A","B","C"), each = 16), value = rlnorm(48, rep(c(.3,.7,1.1), each = 16), .25)), "beeswarm")
save(data.frame(id = c("A","B","C"), metric_1 = c(.8,.5,.6), metric_2 = c(.3,.7,.9),
  metric_3 = c(.9,.5,.6), metric_4 = c(.7,.8,.3)), "radar")
