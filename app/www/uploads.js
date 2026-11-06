(() => {
  const zone = element => element.closest('.upload-zone');
  const input = area => area.querySelector('input[type=file]');
  const row = area => area.querySelector('.upload-file-row');
  const name = area => area.querySelector('.upload-filename');
  const remove = area => area.querySelector('.upload-remove');
  const feedback = (area, message, error = false) => {
    const status = area.querySelector('.upload-feedback');
    status.textContent = message;
    status.toggleAttribute('data-error', error);
  };
  const busy = (area, value) => {
    area.classList.toggle('is-uploading', value);
    remove(area).disabled = value;
    area.querySelector('.upload-drop').disabled = value;
  };
  const finish = (area, filename, error) => {
    busy(area, false);
    name(area).textContent = filename || '';
    row(area).hidden = !filename;
    area.classList.toggle('is-complete', Boolean(filename));
    feedback(area, error || (filename ? '已上传 · 100%' : ''), Boolean(error));
  };
  document.addEventListener('click', event => {
    const area = zone(event.target);
    if (!area) return;
    if (event.target.closest('.upload-drop')) input(area).click();
    if (event.target.closest('.upload-remove')) {
      input(area).value = '';
      input(area).removeAttribute('data-restore');
      area.dataset.saved = '';
      finish(area, '');
      Shiny.setInputValue('remove_upload_' + area.dataset.key, Date.now(), {priority:'event'});
    }
  });
  document.addEventListener('change', event => {
    const area = zone(event.target);
    if (!area || event.target !== input(area) || !event.target.files.length) return;
    const [file] = event.target.files;
    const valid = event.target.files.length === 1 &&
      event.target.accept.split(',').some(ext => file.name.toLowerCase().endsWith(ext.trim())) &&
      file.size <= Number(area.dataset.limit);
    if (!valid) {
      event.stopImmediatePropagation();
      event.target.value = '';
      feedback(area, '请选择一个符合类型要求且不超过 1 GiB 的文件。', true);
      return;
    }
    area.classList.remove('is-complete');
    busy(area, true);
    row(area).hidden = false;
    name(area).textContent = file.name;
    feedback(area, '正在上传 · 0%');
  }, true);
  document.addEventListener('dragover', event => {
    const area = zone(event.target);
    if (!area || !event.dataTransfer.types.includes('Files')) return;
    event.preventDefault();
    event.dataTransfer.dropEffect = area.classList.contains('is-uploading') ? 'none' : 'copy';
    area.classList.add('is-dragging');
  });
  document.addEventListener('dragleave', event => {
    const area = zone(event.target);
    if (area && !area.contains(event.relatedTarget)) area.classList.remove('is-dragging');
  });
  document.addEventListener('drop', event => {
    const area = zone(event.target);
    if (!area || !event.dataTransfer.files.length) return;
    event.preventDefault();
    event.stopPropagation();
    area.classList.remove('is-dragging');
    if (area.classList.contains('is-uploading')) return;
    input(area).files = event.dataTransfer.files;
    input(area).dispatchEvent(new Event('change', {bubbles:true}));
  }, true);
  document.addEventListener('DOMContentLoaded', () => {
    Shiny.addCustomMessageHandler('upload-state', state => {
      const area = document.querySelector('.upload-zone[data-key="' + state.key + '"]');
      if (!area) return;
      if (!state.error) area.dataset.saved = state.name;
      finish(area, area.dataset.saved, state.error);
    });
    const initialize = () => document.querySelectorAll('.upload-zone:not([data-ready])').forEach(area => {
      area.dataset.ready = 'true';
      area.dataset.saved = name(area).textContent;
      if (area.dataset.saved) finish(area, area.dataset.saved);
      const bar = area.querySelector('.progress-bar');
      new MutationObserver(() => {
        if (!area.classList.contains('is-uploading')) return;
        if (bar.classList.contains('progress-bar-danger')) {
          finish(area, area.dataset.saved, '上传失败，请重新选择文件。');
        } else {
          feedback(area, '正在上传 · ' + (bar.style.width || '0%'));
        }
      }).observe(bar, {attributes:true, attributeFilter:['style','class']});
    });
    initialize();
    new MutationObserver(initialize).observe(document.body, {childList:true, subtree:true});
  });
})();
