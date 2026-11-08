const hubMode = () => field('analysis-kind').value === 'hub';
const updateMethods = () => {
  const choices = hubMode() ? data.scores : data.communities;
  field('algorithm').replaceChildren(
    ...Object.keys(choices).map((key) => new Option(ppiMethods[key][0], key)),
  );
  document.querySelectorAll('.community-option').forEach((control) => {
    control.hidden = hubMode();
    control.querySelector('input, select').disabled = hubMode();
  });
};
const updateHelpLink = () => {
  field('algorithm-help').href = 'ppi-algorithms.html#' + field('algorithm').value;
};
field('algorithm').onchange = updateHelpLink;
field('analysis-kind').onchange = () => {
  updateMethods();
  updateHelpLink();
};
field('analysis-kind').onchange();
const showSubset = (nodes, edges, title, rows) => {
  visible = nodes.union(edges);
  cy.batch(() => {
    cy.elements().addClass('filtered-out');
    visible.removeClass('filtered-out');
  });
  field('summary').textContent =
    title + ' · ' + nodes.length + ' 个节点 · ' + edges.length + ' 条边';
  field('clusters').replaceChildren(
    ...rows.map((text) => {
      const item = document.createElement('li');
      item.textContent = text;
      return item;
    }),
  );
  fit();
};
field('analysis-form').onsubmit = (event) => {
  event.preventDefault();
  const algorithm = field('algorithm').value;
  const title = ppiMethods[algorithm][0];
  const limit = Number(field('top-n').value);
  if (hubMode()) {
    const scores = data.scores[algorithm];
    const selected = Array.from(cy.nodes())
      .filter((node) => Number.isFinite(scores[node.data('index')]))
      .sort(
        (a, b) => scores[b.data('index')] - scores[a.data('index')] || a.id().localeCompare(b.id()),
      )
      .slice(0, limit);
    const ids = new Set(selected.map((node) => node.id()));
    const nodes = cy.nodes().filter((node) => ids.has(node.id()));
    const edges = cy
      .edges()
      .filter((edge) => ids.has(edge.source().id()) && ids.has(edge.target().id()));
    showSubset(
      nodes,
      edges,
      title,
      selected.map(
        (node) => node.data('label') + ' · ' + scores[node.data('index')].toPrecision(5),
      ),
    );
    return;
  }
  const method = data.communities[algorithm];
  const rank = field('ranking').value;
  const total = Number(field('total-nodes').value);
  const ranked = method.summary
    .filter((row) => row.size >= Number(field('min-size').value))
    .sort((a, b) => b[rank] - a[rank] || b.size - a.size || a.cluster - b.cluster);
  const chosen = total > 0 ? ranked : ranked.slice(0, limit);
  const ids = new Set(chosen.map((row) => row.cluster));
  const cluster = (node) => method.membership[node.data('index')];
  let nodes = cy.nodes().filter((node) => ids.has(cluster(node)));
  if (total > 0) {
    const top = Array.from(nodes)
      .sort((a, b) => b.degree() - a.degree() || a.id().localeCompare(b.id()))
      .slice(0, total);
    const retained = new Set(top.map((node) => node.id()));
    nodes = nodes.filter((node) => retained.has(node.id()));
  }
  const retainedIds = new Set(Array.from(nodes).map((node) => node.id()));
  const edges = cy
    .edges()
    .filter(
      (edge) =>
        retainedIds.has(edge.source().id()) &&
        retainedIds.has(edge.target().id()) &&
        cluster(edge.source()) === cluster(edge.target()),
    );
  showSubset(
    nodes,
    edges,
    title + ' · ' + chosen.length + ' 个群集',
    chosen.map(
      (row) =>
        '群集 ' +
        row.cluster +
        ' · 节点 ' +
        row.size +
        ' · 边 ' +
        row.edges +
        ' · 密度 ' +
        row.density.toFixed(3),
    ),
  );
};
field('clear-filter').onclick = () => showSubset(cy.nodes(), cy.edges(), '全部网络', []);
