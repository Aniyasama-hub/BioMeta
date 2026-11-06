ppi_graph <- function(nodes, edges) {
  igraph::graph_from_data_frame(edges[, c("from", "to"), drop = FALSE],
    directed = FALSE, vertices = data.frame(name = nodes$gene_id))
}

ppi_palettes <- function(base) {
  c(base, list(
    "青瓷 · Celadon" = list(low = "#2E665F", mid = "#EEF3E9", high = "#AE714C"),
    "海雾 · Marine" = list(low = "#325674", mid = "#EBF0F4", high = "#BB673C"),
    "暮紫 · Dusk" = list(low = "#5B4C80", mid = "#F4ECF5", high = "#A25763"),
    "石墨 · Graphite" = list(low = "#333942", mid = "#F2F2EF", high = "#B2792D")
  ))
}

ppi_hub_scores <- function(graph, weights) {
  n <- igraph::vcount(graph)
  degree <- igraph::degree(graph)
  neighbors <- igraph::adjacent_vertices(graph, igraph::V(graph))
  neighborhood <- vapply(neighbors, function(ids) {
    if (!length(ids)) return(c(ncc = 0, mnc = 0, dmnc = 0))
    subgraph <- igraph::induced_subgraph(graph, ids)
    groups <- igraph::components(subgraph)
    largest <- which(groups$csize == max(groups$csize))
    edges <- igraph::ends(subgraph, igraph::E(subgraph), names = FALSE)
    internal <- tabulate(groups$membership[edges[, 1]], nbins = groups$no)
    size <- groups$csize[largest[1]]
    c(ncc = mean(degree[as.integer(ids)]), mnc = size,
      dmnc = max(internal[largest]) / size^1.7)
  }, numeric(3))
  scores <- list(degree = degree, ncc = neighborhood[1, ], mnc = neighborhood[2, ],
    dmnc = neighborhood[3, ], clustering = igraph::transitivity(graph, type = "local", isolates = "zero"),
    pagerank = igraph::page_rank(graph, directed = FALSE, weights = weights)$vector,
    coreness = igraph::coreness(graph))
  # Global shortest-path measures use unit lengths. PPI confidence is a strength, not a distance.
  if (n <= 5000L && igraph::ecount(graph) <= 100000L) {
    scores$betweenness <- igraph::betweenness(graph, directed = FALSE)
    scores$harmonic <- igraph::harmonic_centrality(graph, mode = "all")
  }
  # A conservative degeneracy limit bounds the cost of exact maximal clique enumeration.
  if (n <= 2000L && max(scores$coreness) <= 12L) {
    mcc <- numeric(n)
    for (clique in igraph::max_cliques(graph, min = 2L)) {
      ids <- as.integer(clique)
      mcc[ids] <- mcc[ids] + factorial(length(ids) - 1L)
    }
    scores$mcc <- mcc
  }
  lapply(scores, function(value) as.list(unname(value)))
}

ppi_communities <- function(graph, edges, weights) {
  set.seed(1)
  methods <- list(components = igraph::components(graph)$membership)
  if (igraph::ecount(graph)) {
    methods$louvain <- igraph::membership(igraph::cluster_louvain(graph, weights = weights))
    methods$walktrap <- igraph::membership(igraph::cluster_walktrap(graph, weights = weights))
    methods$fast_greedy <- igraph::membership(igraph::cluster_fast_greedy(graph, weights = weights))
    methods$leiden <- igraph::membership(igraph::cluster_leiden(graph, objective_function = "modularity", weights = weights))
    methods$label_prop <- igraph::membership(igraph::cluster_label_prop(graph, weights = weights))
    methods$infomap <- igraph::membership(igraph::cluster_infomap(graph, e.weights = weights))
  }
  ids <- igraph::V(graph)$name
  from <- match(edges$from, ids)
  to <- match(edges$to, ids)
  lapply(methods, function(value) {
    membership <- match(value, unique(value))
    sizes <- tabulate(membership)
    same <- membership[from] == membership[to]
    counts <- tabulate(membership[from[same]], nbins = length(sizes))
    list(membership = as.list(membership), summary = data.frame(
      cluster = seq_along(sizes), size = sizes, edges = counts,
      density = ifelse(sizes > 1L, counts / choose(sizes, 2), 0)))
  })
}
