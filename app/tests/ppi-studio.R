# Use a synthetic triangle with a leaf and an isolate to distinguish the metrics.
root <- normalizePath(commandArgs(trailingOnly = TRUE)[1], winslash = "/")
source(file.path(root, "R/toolbox.R"), encoding = "UTF-8")
source(file.path(root, "R/network_import.R"), encoding = "UTF-8")
source(file.path(root, "ppi-studio/metrics.R"), encoding = "UTF-8")
nodes <- data.frame(gene_id = LETTERS[1:5], label = c("alpha", NA, "gamma", "", "epsilon"),
  degree = c(3, 2, 2, 1, 0), x = c(0, 1, 0, -1, 2), y = c(0, 0, 1, 0, 1), log2FoldChange = NA_real_)
edges <- data.frame(from = c("A", "A", "B", "A"), to = c("B", "C", "C", "D"), score = .9)
g <- ppi_graph(nodes, edges)
scores <- lapply(ppi_hub_scores(g, edges$score), unlist)
stopifnot(isTRUE(all.equal(scores$ncc, c(5/3, 2.5, 2.5, 3, 0))),
  identical(as.numeric(scores$mnc), c(2, 2, 2, 1, 0)),
  isTRUE(all.equal(scores$dmnc[1], 1 / 2^1.7)),
  identical(scores$mcc, c(3, 2, 2, 1, 0)))
groups <- ppi_communities(g, edges, edges$score)
stopifnot(length(groups) == 7L, all(vapply(groups, function(method) sum(method$summary$size) == 5L, logical(1))))
empty <- ppi_graph(nodes, edges[FALSE, ])
stopifnot(all(unlist(ppi_hub_scores(empty, numeric())$mcc) == 0))
out <- file.path(root, "tests/_output/ppi-studio")
dir.create(out, recursive = TRUE, showWarnings = FALSE)
style <- tb_default_settings(dirname(root))$style
style$network_label_top <- 1L
tb_write_interactive_network(list(data = nodes, extras = list(edges = edges)), style, root, out)
basic <- paste(readLines(file.path(out, "network.html"), encoding = "UTF-8"), collapse = "\n")
advanced <- paste(readLines(file.path(out, "ppi-studio.html"), encoding = "UTF-8"), collapse = "\n")
stopifnot(grepl('href="ppi-studio.html"', basic, fixed = TRUE), !grepl("analysis-kind", basic),
          grepl("analysis-kind", advanced), grepl('"label":"B"', advanced, fixed = TRUE),
          file.exists(file.path(out, "ppi_hub_scores.csv")))
cat("PASS synthetic metrics, missing label fallback and separate PPI pages\n")
