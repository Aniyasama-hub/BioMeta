const field = id => document.getElementById(id);
const data = JSON.parse(field('network-data').textContent);
data.elements.filter(element => element.group === 'nodes').forEach(element => {
  element.data.visibleLabel = element.data.displayLabel || '';
});
const cy = cytoscape({
  container: field('cy'), elements: data.elements, layout: {name: 'preset', padding: 30},
  style: [
    {selector: 'node', style: {
      'background-color': 'data(color)', width: 'data(size)', height: 'data(size)',
      label: 'data(visibleLabel)', 'font-size': 12, 'min-zoomed-font-size': 0,
      color: '#292f2b', 'text-valign': 'bottom',
      'text-margin-y': 5, 'border-width': 1, 'border-color': '#faf8f2'
    }},
    {selector: 'edge', style: {'line-color': data.edgeColor, width: data.edgeWidth,
      opacity: data.edgeAlpha, 'curve-style': 'bezier'}},
    {selector: 'node:selected', style: {'border-width': 3, 'border-color': '#bd4d35'}},
    {selector: '.filtered-out', style: {display: 'none'}}
  ]
});

let background = data.background;
let visible = cy.elements();
const initialLabelMode = cy.nodes().every(node => Boolean(node.data('displayLabel'))) ? 'all' : 'initial';
let labelMode = initialLabelMode;
const renderLabels = () => {
  cy.batch(() => cy.nodes().forEach(node => {
    const value = labelMode === 'all' ? node.data('label') :
      labelMode === 'initial' ? node.data('displayLabel') : '';
    node.data('visibleLabel', value || '');
  }));
  field('labels').textContent = labelMode === 'all' ? '隐藏全部标签' : '显示全部标签';
  field('labels').setAttribute('aria-pressed', String(labelMode === 'all'));
};
renderLabels();
document.querySelector('.edit-link')?.addEventListener('click', event => {
  const popup = window.open(event.currentTarget.href, '_blank', 'popup,width=1440,height=900');
  if (!popup) return;
  popup.opener = null;
  event.preventDefault();
});
const fit = () => { if (visible.nodes().length) cy.fit(visible, 30); };
field('resize').onclick = () => {
  if (!field('size-form').reportValidity()) return;
  field('cy').style.width = field('canvas-width').value + 'px';
  field('cy').style.height = field('canvas-height').value + 'px';
  cy.resize();
  fit();
};
field('fit').onclick = fit;
field('layout').onchange = () => {
  const name = field('layout').value;
  if (name === 'preset' || !visible.nodes().length) return;
  visible.layout({name, padding: 30, animate: false}).run();
  spacing = 100;
  field('spacing').value = 100;
  field('spacing-value').value = 100;
};
field('labels').onclick = () => {
  labelMode = labelMode === 'all' ? 'none' : 'all';
  renderLabels();
};
// Scale node coordinates around the visible nodes' centroid, keeping camera zoom fixed.
let spacing = 100;
const setSpacing = percent => {
  const nodes = visible.nodes();
  if (nodes.length) {
    const center = nodes.reduce((sum, node) => ({
      x: sum.x + node.position('x') / nodes.length,
      y: sum.y + node.position('y') / nodes.length
    }), {x: 0, y: 0});
    const ratio = percent / spacing;
    cy.batch(() => cy.nodes().positions(node => ({
      x: center.x + (node.position('x') - center.x) * ratio,
      y: center.y + (node.position('y') - center.y) * ratio
    })));
  }
  spacing = percent;
  field('spacing').value = percent;
  field('spacing-value').value = percent;
};
field('spacing').step = 'any';
field('spacing').oninput = () => setSpacing(Number(field('spacing').value));
field('spacing-form').onsubmit = event => {
  event.preventDefault();
  setSpacing(Number(field('spacing-value').value));
};
const styleItem = (name, {shape, colors} = {}) => {
  const item = document.createElement('span');
  item.className = 'style-item';
  item.textContent = name;
  if (shape) {
    const icon = document.createElement('span');
    icon.className = 'shape ' + shape;
    icon.setAttribute('aria-hidden', 'true');
    item.append(icon);
  }
  for (const color of colors || []) {
    const chip = document.createElement('span');
    chip.className = 'chip';
    chip.style.backgroundColor = color;
    chip.title = color;
    item.append(chip);
  }
  return item;
};
const styleMenu = (id, entries, onSelect, unselected) => {
  const menu = field(id + '-menu');
  const summary = menu.querySelector('summary');
  const current = field(id + '-current');
  const options = field(id + '-options');
  const set = key => {
    const option = entries[key] || unselected;
    current.replaceChildren(styleItem(option.name, option));
    for (const button of options.children) {
      button.setAttribute('aria-pressed', String(button.value === key));
    }
  };
  for (const [key, entry] of Object.entries(entries)) {
    const button = document.createElement('button');
    button.type = 'button';
    button.value = key;
    button.append(styleItem(entry.name, entry));
    button.onclick = () => {
      set(key);
      onSelect(key);
      menu.open = false;
      summary.focus();
    };
    options.append(button);
  }
  menu.addEventListener('focusout', event => {
    if (!menu.contains(event.relatedTarget)) menu.open = false;
  });
  menu.addEventListener('keydown', event => {
    if (event.key === 'Escape' && menu.open) {
      menu.open = false;
      summary.focus();
      event.preventDefault();
    }
  });
  return set;
};
const scopedNodes = () => field('style-scope').value === 'selected' ?
  visible.nodes(':selected') : visible.nodes();
const paletteColors = palette => palette ? [palette.low, palette.mid, palette.high] :
  [cy.nodes().first().data('color'), data.background, data.edgeColor];
const renderCustomPalette = colors => {
  const preview = field('palette-preview');
  preview.hidden = !colors.length;
  preview.replaceChildren(...colors.map((color, index) =>
    styleItem('第 ' + (index + 1) + ' 色', {colors: [color]})));
};
const applyPalette = key => {
  const palette = data.palettes[key];
  cy.nodes().removeStyle('background-color');
  if (palette) cy.nodes().style('background-color', palette.low);
  background = palette ? palette.mid : data.background;
  field('cy').style.background = background;
  field('edge-color').value = palette ? palette.high : initialEdgeColor;
  updateEdges();
  selectTheme(null);
  renderCustomPalette([]);
};
const paletteEntries = Object.fromEntries([['', null], ...Object.entries(data.palettes)]
  .map(([key, palette]) => [key, {name: key || '原始配色', colors: paletteColors(palette)}]));
const selectPalette = styleMenu('palette', paletteEntries, applyPalette, {name: '选择预设配色'});

const parseColor = value => {
  const hex = /^#?([0-9a-f]{6})$/i.exec(value.trim());
  if (hex) return '#' + hex[1].toLowerCase();
  const rgb = /^(?:rgb\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*\)|(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3}))$/i.exec(value.trim());
  if (!rgb) return null;
  const channels = rgb.slice(1).filter(channel => channel !== undefined).map(Number);
  return channels.every(channel => channel <= 255) ?
    '#' + channels.map(channel => channel.toString(16).padStart(2, '0')).join('') : null;
};
const addColor = () => {
  const container = field('custom-colors');
  const index = container.children.length;
  const defaults = ['#52664d', '#ae714c', '#325674', '#5b4c80'];
  const row = document.createElement('label');
  row.className = 'color-row';
  const picker = document.createElement('input');
  picker.type = 'color';
  picker.value = defaults[index % defaults.length];
  picker.setAttribute('aria-label', '第 ' + (index + 1) + ' 色取色器');
  const text = document.createElement('input');
  text.type = 'text';
  text.required = true;
  text.value = picker.value;
  text.placeholder = '#RRGGBB 或 R,G,B';
  text.setAttribute('aria-label', '第 ' + (index + 1) + ' 色 RGB 或十六进制');
  text.oninput = () => {
    const color = parseColor(text.value);
    text.setCustomValidity(color ? '' : '请输入 #RRGGBB 或 0–255 的 RGB 值。');
    if (color) picker.value = color;
  };
  picker.oninput = () => {
    text.value = picker.value;
    text.setCustomValidity('');
  };
  row.append('第 ' + (index + 1) + ' 色', picker, text);
  container.append(row);
};
field('palette-count').onchange = () => {
  const count = Number(field('palette-count').value);
  const container = field('custom-colors');
  while (container.children.length > count) container.lastElementChild.remove();
  while (container.children.length < count) addColor();
  field('add-color').hidden = count < 4;
  field('remove-color').hidden = count < 4;
};
field('add-color').onclick = addColor;
field('remove-color').onclick = () => {
  const colors = field('custom-colors');
  if (colors.children.length > 4) colors.lastElementChild.remove();
};
addColor();
field('custom-palette').onsubmit = event => {
  event.preventDefault();
  const nodes = scopedNodes();
  if (!nodes.length) {
    field('detail').textContent = '当前应用范围没有节点。';
    return;
  }
  const colors = Array.from(field('custom-colors').querySelectorAll('input[type=color]'), input => input.value);
  const {min, max} = nodes.reduce((range, node) => {
    const degree = node.data('degree');
    range.min = Math.min(range.min, degree);
    range.max = Math.max(range.max, degree);
    return range;
  }, {min: Infinity, max: -Infinity});
  cy.batch(() => nodes.forEach(node => {
    const fraction = max === min ? 0 : (node.data('degree') - min) / (max - min);
    const index = Math.min(colors.length - 1, Math.floor(fraction * colors.length));
    node.style('background-color', colors[index]);
  }));
  selectPalette(null);
  selectTheme(null);
  renderCustomPalette(colors);
};

const canvasColor = document.createElement('canvas').getContext('2d');
canvasColor.fillStyle = data.edgeColor;
const initialEdgeColor = canvasColor.fillStyle;
const edgeMetric = {
  degree: edge => (edge.source().data('degree') + edge.target().data('degree')) / 2,
  score: edge => edge.data('score')
};
const edgeWidths = {arrow: 1.5, thin: 0.8, thick: 3, dashed: 1.5};
const updateEdges = () => {
  const mode = field('edge-style').value;
  field('edge-metric-label').hidden = mode !== 'scaled';
  const metric = edgeMetric[field('edge-metric').value];
  const max = mode === 'scaled' ? cy.edges().reduce((value, edge) => Math.max(value, metric(edge)), 0) : 0;
  const base = edgeWidths[mode] ?? data.edgeWidth;
  const multiplier = Number(field('edge-width').value);
  const color = field('edge-color').value;
  cy.batch(() => cy.edges().forEach(edge => {
    const width = mode === 'scaled' ? (max > 0 ? Math.max(0.5, 4 * metric(edge) / max) : 0.5) : base;
    edge.style({
      'line-style': ['dashed', 'scaled'].includes(mode) ? 'dashed' : 'solid',
      'target-arrow-shape': mode === 'arrow' ? 'triangle' : 'none',
      'target-arrow-color': color, 'line-color': color, width: width * multiplier,
      opacity: Number(field('edge-opacity').value) / 100
    });
  }));
};
field('edge-color').value = initialEdgeColor;
field('edge-opacity').value = data.edgeAlpha * 100;
field('edge-form').oninput = () => {
  if (field('edge-form').checkValidity()) {
    updateEdges();
    selectTheme(null);
  }
};
field('edge-form').onsubmit = event => event.preventDefault();

const nodeStyles = {
  ellipse: {name: '圆形', shape: 'ellipse'},
  rounded: {name: '圆角矩形', shape: 'round-rectangle'},
  triangle: {name: '三角形', shape: 'triangle'},
  diamond: {name: '菱形', shape: 'diamond'},
  hexagon: {name: '六边形', shape: 'hexagon'}
};
let nodeStyle = 'ellipse';
const setNodeStyle = style => {
  nodeStyle = style;
  selectNodeStyle(style);
};
const selectNodeStyle = styleMenu('node-style', nodeStyles, style => {
  nodeStyle = style;
});

// Global presets define node dimensions in px and edge opacity as a percentage.
const themes = {
  atlas: {
    name: '纸本图谱', colors: ['#2c665b', '#f5f0e3', '#ad6948'],
    node: 'ellipse', size: 27, label: '#253d35', font: 11, border: '#fff9eb',
    edge: 'thin', width: 1.2, opacity: 70
  },
  blueprint: {
    name: '深海蓝图', colors: ['#51cfc4', '#14243b', '#7496d5'],
    node: 'hexagon', size: 30, label: '#e6f3ff', font: 12, border: '#c6fcf3',
    edge: 'dashed', width: 1.5, opacity: 68
  },
  print: {
    name: '黑白版画', colors: ['#252525', '#fcfcf7', '#575757'],
    node: 'diamond', size: 20, label: '#202020', font: 10, border: '#ffffff',
    edge: 'thin', width: 0.9, opacity: 80
  },
  plum: {
    name: '暮紫珊瑚', colors: ['#77529e', '#f6edf3', '#c97066'],
    node: 'rounded', size: 34, label: '#4d3159', font: 12, border: '#fdf5f9',
    edge: 'thick', width: 2.6, opacity: 58
  }
};
const applyTheme = key => {
  const theme = themes[key];
  if (!theme) {
    field('reset-style').onclick();
    return;
  }
  const [fill, canvas, line] = theme.colors;
  setNodeStyle(theme.node);
  field('node-size').value = theme.size;
  field('node-color').value = fill;
  cy.nodes().style({
    shape: nodeStyles[theme.node].shape, width: theme.size, height: theme.size,
    'background-color': fill, 'border-color': theme.border,
    color: theme.label, 'font-size': theme.font
  });
  background = canvas;
  field('cy').style.background = background;
  field('edge-style').value = theme.edge;
  field('edge-width').value = theme.width / edgeWidths[theme.edge];
  field('edge-color').value = line;
  field('edge-opacity').value = theme.opacity;
  updateEdges();
  selectPalette(null);
  renderCustomPalette([]);
};
const selectTheme = styleMenu('theme', {'': {name: '任务原始样式'}, ...themes}, applyTheme,
  {name: '选择全局风格'});
field('node-form').onsubmit = event => event.preventDefault();
field('apply-style').onclick = () => {
  if (!field('node-form').reportValidity()) return;
  const nodes = scopedNodes();
  if (!nodes.length) {
    field('detail').textContent = '请先选择节点。';
    return;
  }
  const size = Number(field('node-size').value);
  nodes.style({shape: nodeStyles[nodeStyle].shape, width: size, height: size,
    'background-color': field('node-color').value});
  selectTheme(null);
};
field('reset-style').onclick = () => {
  cy.elements().removeStyle();
  selectPalette('');
  selectTheme('');
  setNodeStyle('ellipse');
  field('node-size').value = field('node-size').defaultValue;
  field('node-color').value = field('node-color').defaultValue;
  field('edge-style').value = '';
  field('edge-width').value = 1;
  field('edge-metric').value = 'degree';
  field('edge-metric-label').hidden = true;
  field('edge-color').value = initialEdgeColor;
  field('edge-opacity').value = data.edgeAlpha * 100;
  labelMode = initialLabelMode;
  renderLabels();
  background = data.background;
  field('cy').style.background = background;
  renderCustomPalette([]);
};
cy.on('tap', 'node', event => {
  const node = event.target.data();
  field('detail').textContent = node.label + ' · ' + node.id + ' · 度 ' + node.degree;
});
field('png').onclick = () => {
  if (!visible.nodes().length) return;
  const link = document.createElement('a');
  link.download = 'ppi-current-view.png';
  link.href = cy.png({bg: background, full: false, scale: 2});
  link.click();
};
field('cy').style.background = background;
setNodeStyle('ellipse');
selectPalette('');
selectTheme('');

const cachePng = document.getElementById('cache-png');
if (cachePng) cachePng.onclick = () => {
  const target = window.opener || (window.parent !== window ? window.parent : null);
  const payload = {type: 'ppi-cache-image', png: cy.png({bg: background, full: false, scale: 2})};
  if (target) target.postMessage(payload, location.origin);
  else if (ppiCacheChannel) ppiCacheChannel.postMessage(payload);
  else { field('detail').textContent = '当前浏览器不支持回传，请导出 PNG 后在主窗口上传。'; return; }
  field('detail').textContent = '已发送至工作站；请在主窗口确认缓存提示。';
};
window.addEventListener('message', event => {
  if (event.origin === location.origin && event.data?.type === 'ppi-cache-image' && window.parent !== window)
    window.parent.postMessage(event.data, location.origin);
});

// The advanced window intentionally has no opener. A job-scoped same-origin channel
// returns its image to the embedded editor without restoring window.opener.
const ppiCacheChannel = ['http:', 'https:'].includes(location.protocol) && typeof BroadcastChannel === 'function'
  ? new BroadcastChannel('ppi-cache:' + location.pathname.split('/')[1]) : null;
if (ppiCacheChannel) ppiCacheChannel.onmessage = event => {
  if (event.data?.type === 'ppi-cache-image' && window.parent !== window)
    window.parent.postMessage(event.data, location.origin);
};
window.addEventListener('pagehide', () => ppiCacheChannel?.close());
if (cachePng) {
  cachePng.disabled = false;
  cachePng.title = '将当前视图加入工作站本次流程的图片缓存';
}
