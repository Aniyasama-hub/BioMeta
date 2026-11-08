(() => {
  const config = JSON.parse(document.getElementById('figure-config').textContent);
  const canvas = document.getElementById('figure');
  const ctx = canvas.getContext('2d');
  const mode = document.getElementById('kind');
  const status = document.getElementById('status');
  const selected = new Set();
  const previewScale = Math.min(1, 1600 / Math.max(config.width, config.height));
  canvas.width = Math.max(1, Math.round(config.width * previewScale));
  canvas.height = Math.max(1, Math.round(config.height * previewScale));
  const family =
    { sans: 'sans-serif', serif: 'serif', mono: 'monospace' }[config.font] ||
    JSON.stringify(config.font) + ', serif';
  const font =
    (config.face === 'plain' ? '' : config.face.replace('bold.italic', 'italic bold') + ' ') +
    config.fontSize * previewScale +
    'px ' +
    family;
  const assets = config.panels.map((panel) => {
    const image = new Image();
    const loaded = new Promise((resolve, reject) => {
      image.onload = resolve;
      image.onerror = reject;
    });
    image.src = 'figure-assets/' + panel.file;
    return { image, loaded };
  });
  let objects;
  const undoStack = [],
    redoStack = [];
  const snapshot = () => objects.map((o) => ({ ...o }));
  const historyButtons = () => {
    document.getElementById('undo').disabled = !undoStack.length;
    document.getElementById('redo').disabled = !redoStack.length;
  };
  const checkpoint = () => {
    undoStack.push(snapshot());
    if (undoStack.length > 100) undoStack.shift();
    redoStack.length = 0;
    historyButtons();
  };
  const historyMove = (from, to) => {
    if (!from.length || !objects) return;
    to.push(snapshot());
    objects = from.pop();
    selected.clear();
    draw();
    historyButtons();
  };
  const reset = () => {
    ctx.font = font;
    objects = config.panels.flatMap((p, i) => [
      {
        id: 'image' + i,
        type: 'image',
        image: assets[i].image,
        x: p.x * canvas.width,
        y: p.y * canvas.height,
        w: p.width * canvas.width,
        h: p.height * canvas.height,
      },
      {
        id: 'label' + i,
        type: 'label',
        text: p.label,
        x: p.label_x * canvas.width,
        y: p.label_y * canvas.height,
        w: ctx.measureText(p.label).width,
        h: config.fontSize * previewScale * 1.25,
      },
    ]);
    selected.clear();
  };
  const draw = (guides = true, ctx = canvas.getContext('2d')) => {
    ctx.fillStyle = config.background;
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.font = font;
    ctx.textBaseline = 'top';
    ctx.fillStyle = config.color;
    for (const object of objects.filter((o) => o.type === 'image'))
      ctx.drawImage(object.image, object.x, object.y, object.w, object.h);
    for (const object of objects.filter((o) => o.type === 'label'))
      ctx.fillText(object.text, object.x, object.y);
    if (!guides) return;
    ctx.strokeStyle = '#16845e';
    ctx.lineWidth = Math.max(1, canvas.width / 750);
    ctx.setLineDash([ctx.lineWidth * 5, ctx.lineWidth * 3]);
    for (const object of objects.filter((o) => selected.has(o.id)))
      ctx.strokeRect(object.x, object.y, object.w, object.h);
    ctx.setLineDash([]);
  };
  const available = () => objects.filter((o) => mode.value === 'all' || o.type === mode.value);
  const chosen = () => objects.filter((o) => selected.has(o.id));
  const point = (event) => {
    const box = canvas.getBoundingClientRect();
    return {
      x: ((event.clientX - box.left) * canvas.width) / box.width,
      y: ((event.clientY - box.top) * canvas.height) / box.height,
    };
  };
  const place = (o, x, y) => {
    o.x = Math.max(0, Math.min(x, canvas.width - o.w));
    o.y = Math.max(0, Math.min(y, canvas.height - o.h));
  };
  let drag = null;
  canvas.addEventListener('pointerdown', (event) => {
    if (!objects) return;
    const p = point(event);
    const hit = available()
      .sort((a, b) => Number(b.type === 'label') - Number(a.type === 'label'))
      .find((o) => p.x >= o.x && p.x <= o.x + o.w && p.y >= o.y && p.y <= o.y + o.h);
    if (!event.shiftKey && (!hit || !selected.has(hit.id))) selected.clear();
    if (hit) {
      if (event.shiftKey && selected.has(hit.id)) selected.delete(hit.id);
      else selected.add(hit.id);
    }
    if (hit && selected.has(hit.id)) {
      canvas.setPointerCapture(event.pointerId);
      drag = { p, items: chosen().map((o) => ({ o, x: o.x, y: o.y })) };
    }
    canvas.focus();
    draw();
  });
  canvas.addEventListener('pointermove', (event) => {
    if (!drag) return;
    if (!objects) return;
    const p = point(event);
    if (!drag.saved && (p.x !== drag.p.x || p.y !== drag.p.y)) {
      checkpoint();
      drag.saved = true;
    }
    drag.items.forEach((item) => place(item.o, item.x + p.x - drag.p.x, item.y + p.y - drag.p.y));
    draw();
  });
  for (const type of ['pointerup', 'pointercancel', 'lostpointercapture'])
    canvas.addEventListener(type, () => {
      drag = null;
    });
  canvas.addEventListener('keydown', (event) => {
    const directions = {
      ArrowUp: [0, -1],
      ArrowDown: [0, 1],
      ArrowLeft: [-1, 0],
      ArrowRight: [1, 0],
    };
    const delta = directions[event.key];
    if (!delta || !selected.size) return;
    event.preventDefault();
    const step = ((event.shiftKey ? 10 : 1) * canvas.width) / canvas.clientWidth;
    checkpoint();
    chosen().forEach((o) => place(o, o.x + step * delta[0], o.y + step * delta[1]));
    draw();
  });
  mode.onchange = () => {
    selected.clear();
    draw();
  };
  document.getElementById('select-all').onclick = () => {
    selected.clear();
    available().forEach((o) => selected.add(o.id));
    draw();
  };
  document.querySelectorAll('[data-align]').forEach((button) => {
    button.onclick = () => {
      const items = chosen();
      if (!items.length) return;
      checkpoint();
      const centerX = items.reduce((sum, o) => sum + o.x + o.w / 2, 0) / items.length;
      const centerY = items.reduce((sum, o) => sum + o.y + o.h / 2, 0) / items.length;
      for (const o of items) {
        if (button.dataset.align === 'vertical') place(o, centerX - o.w / 2, o.y);
        else if (button.dataset.align === 'horizontal') place(o, o.x, centerY - o.h / 2);
        else {
          const x = button.dataset.align === 'mirror-y' ? o.x : canvas.width - o.x - o.w;
          const y = button.dataset.align === 'mirror-x' ? o.y : canvas.height - o.y - o.h;
          place(o, x, y);
        }
      }
      draw();
    };
  });
  document.getElementById('reset').onclick = () => {
    checkpoint();
    reset();
    draw();
  };
  // 浏览器 PNG 默认的分辨率元数据可能与纸张设置不同。
  const setPngDpi = async (blob) => {
    if (!config.dpi) return blob;
    const chunk = new Uint8Array(21);
    const view = new DataView(chunk.buffer);
    view.setUint32(0, 9);
    chunk.set([112, 72, 89, 115], 4); // pHYs
    const perMeter = Math.round(config.dpi / 0.0254);
    view.setUint32(8, perMeter);
    view.setUint32(12, perMeter);
    chunk[16] = 1;
    let crc = -1;
    for (const byte of chunk.subarray(4, 17)) {
      crc ^= byte;
      for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ (crc & 1 ? 0xedb88320 : 0);
    }
    view.setUint32(17, ~crc);
    let offset = 33; // PNG 签名与 IHDR 之后
    while (offset + 12 <= blob.size) {
      const header = new DataView(await blob.slice(offset, offset + 8).arrayBuffer());
      const length = header.getUint32(0);
      const type = header.getUint32(4);
      if (type === 0x70485973)
        return new Blob([blob.slice(0, offset), chunk, blob.slice(offset + length + 12)], {
          type: 'image/png',
        });
      if (type === 0x49444154) break;
      offset += length + 12;
    }
    return new Blob([blob.slice(0, 33), chunk, blob.slice(33)], { type: 'image/png' });
  };
  document.getElementById('export').onclick = () => {
    const target = document.createElement('canvas');
    target.width = config.width;
    target.height = config.height;
    try {
      const output = target.getContext('2d');
      output.scale(config.width / canvas.width, config.height / canvas.height);
      draw(false, output);
      target.toBlob(async (blob) => {
        target.width = target.height = 1;
        if (!blob) {
          status.textContent = '浏览器无法生成 PNG，请降低画布尺寸或分辨率。';
          return;
        }
        const url = URL.createObjectURL(await setPngDpi(blob));
        const link = document.createElement('a');
        link.href = url;
        link.download = 'figure-layout-edited.png';
        link.click();
        setTimeout(() => URL.revokeObjectURL(url), 10000);
      }, 'image/png');
    } catch {
      status.textContent = '浏览器无法分配导出画布，请降低画布尺寸或分辨率。';
    }
  };
  document.getElementById('undo').onclick = () => historyMove(undoStack, redoStack);
  document.getElementById('redo').onclick = () => historyMove(redoStack, undoStack);
  document.addEventListener('keydown', (event) => {
    if (!(event.ctrlKey || event.metaKey) || /INPUT|TEXTAREA|SELECT/.test(event.target.tagName))
      return;
    const key = event.key.toLowerCase();
    if (key === 'z' || key === 'y') {
      event.preventDefault();
      if (key === 'y' || event.shiftKey) historyMove(redoStack, undoStack);
      else historyMove(undoStack, redoStack);
    }
  });
  const controls = Array.from(document.querySelectorAll('header button, header select'));
  controls.forEach((control) => {
    control.disabled = true;
  });
  Promise.all(assets.map((asset) => asset.loaded))
    .then(() => {
      reset();
      draw();
      controls.forEach((control) => {
        control.disabled = false;
      });
      historyButtons();
      canvas.dataset.ready = 'true';
    })
    .catch(() => {
      status.textContent = '图片资源无法加载。请保留 HTML 和 figure-assets 目录。';
    });
})();
