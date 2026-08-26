import {
  STORAGE_KEY,
  addClipboardItem,
  loadStoredData,
  upsertRecent
} from './model.js';

const tauri = window.__TAURI__;
const invoke = tauri?.core?.invoke;
const currentWindow = tauri?.window?.getCurrentWindow?.();
const eventApi = tauri?.event;

const COLORS = ['#6957e8', '#29966f', '#e59b35', '#d75c87', '#3c8fc7'];

let data = loadData();
let pickerOpen = false;
let pickerTagIndex = 0;
let selectedItemIndex = 0;
let managerTagId = data.find((tag) => tag.type === 'custom')?.id || null;
let toastTimer;
const isMac = /mac/i.test(navigator.platform || navigator.userAgent);
const isWindows = /win/i.test(navigator.platform || navigator.userAgent);
const platformName = isMac ? 'macos' : (isWindows ? 'windows' : 'linux');
const quickHotkey = isMac ? 'Ctrl+V' : 'Alt+V';
const directPasteHotkey = isMac ? '⌘V' : 'Ctrl+V';

const $ = (selector) => document.querySelector(selector);
const tagAt = (index) => data[index] || data[0];
const activePickerTag = () => tagAt(pickerTagIndex);
const managerTag = () => data.find((tag) => tag.id === managerTagId);
const escapeHtml = (value) => String(value).replace(/[&<>"']/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[char]));

function loadData() {
  return loadStoredData(localStorage.getItem(STORAGE_KEY));
}

function saveData() { localStorage.setItem(STORAGE_KEY, JSON.stringify(data)); }

function showToast(message) {
  const toast = $('#toast');
  toast.textContent = message;
  toast.classList.add('visible');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => toast.classList.remove('visible'), 1800);
}

async function readClipboard() {
  try {
    if (invoke) return await invoke('read_clipboard');
    return await navigator.clipboard.readText();
  } catch { return ''; }
}

async function writeClipboard(content) {
  if (invoke) return invoke('write_clipboard', { text: content });
  return navigator.clipboard.writeText(content);
}

function recordRecent(content) {
  upsertRecent(data, content);
  saveData();
}

function renderOverview() {
  $('#tag-overview').innerHTML = data.map((tag) => {
    const slots = Array.from({ length: 5 }, (_, index) => `<i class="${index < tag.items.length ? 'filled' : ''}"></i>`).join('');
    const examples = tag.items.slice(0, 3).map((item) => `<div class="tag-example">${escapeHtml(item.title)}</div>`).join('');
    return `<article class="tag-card"><div class="tag-head"><i class="tag-dot" style="background:${tag.color}"></i><strong>${escapeHtml(tag.name)}</strong><span class="count">${tag.items.length}</span></div><div class="progress">${slots}</div>${examples || '<div class="tag-example">暂无内容</div>'}</article>`;
  }).join('');
}

function renderPicker() {
  const tag = activePickerTag();
  if (!tag) return;
  selectedItemIndex = Math.min(selectedItemIndex, Math.max(0, tag.items.length - 1));
  $('#picker-tabs').innerHTML = data.map((item, index) => `<button type="button" class="picker-tab ${index === pickerTagIndex ? 'active' : ''}" data-picker-tag="${index}">${escapeHtml(item.name)}<span>${item.items.length}</span></button>`).join('');
  $('#picker-items').innerHTML = tag.items.length ? tag.items.map((item, index) => `<button type="button" class="picker-item ${index === selectedItemIndex ? 'selected' : ''}" data-picker-item="${index}"><span><strong>${escapeHtml(item.title)}</strong><small>${escapeHtml(item.content.replace(/\s*\n\s*/g, ' ↵ '))}</small></span><span class="item-number">${index < 5 ? index + 1 : ''}</span></button>`).join('') : '<div class="empty">这个标签还没有内容</div>';
  $('#picker-hint').textContent = `${tag.name} · ${tag.items.length ? selectedItemIndex + 1 : 0} / ${tag.items.length}`;
  $('#add-clipboard').hidden = tag.type === 'recent';
}

function renderManager() {
  const customTags = data.filter((tag) => tag.type === 'custom');
  $('#manager-tags').innerHTML = customTags.map((tag) => `<button type="button" class="manager-tag ${tag.id === managerTagId ? 'active' : ''}" data-manager-tag="${tag.id}"><i class="tag-dot" style="background:${tag.color}"></i><span>${escapeHtml(tag.name)}</span><span class="count">${tag.items.length}</span></button>`).join('');
  const tag = managerTag();
  if (!tag) { $('#manager-items').innerHTML = '<div class="empty">还没有自定义标签</div>'; return; }
  const rows = tag.items.map((item) => `<div class="item-row" data-item-id="${item.id}"><i class="tag-dot" style="background:${tag.color}"></i><div><input data-field="title" value="${escapeHtml(item.title)}" aria-label="内容标题"><textarea rows="1" data-field="content" aria-label="内容">${escapeHtml(item.content)}</textarea></div><div class="row-actions"><button type="button" data-copy-manager="${item.id}" aria-label="复制">↗</button><button type="button" data-delete-item="${item.id}" aria-label="删除">×</button></div></div>`).join('');
  $('#manager-items').innerHTML = `<div class="manager-header"><div><h2>${escapeHtml(tag.name)}</h2><p class="muted">${tag.items.length} 条内容，修改会自动保存</p></div><button id="add-manager-item" class="primary-button" type="button">＋ 添加当前剪贴板</button></div><div class="item-list">${rows || '<div class="empty">这个标签还没有内容。</div>'}</div><div class="limit-note">快速面板固定显示五行，更多内容可滚动浏览。</div>`;
}

function renderAll() { renderOverview(); renderPicker(); renderManager(); }

async function showMainWindow() {
  if (currentWindow) { await currentWindow.show(); await currentWindow.setFocus(); }
}

async function hideMainWindow() {
  if (currentWindow) await currentWindow.hide();
}

async function setPickerWindowMode(picker) {
  if (!invoke) return;
  try { await invoke('set_picker_mode', { picker }); } catch { showToast('窗口模式切换失败，请重启 ClipNest'); }
}

async function openPicker() {
  const clipboard = await readClipboard();
  if (clipboard) recordRecent(clipboard);
  pickerTagIndex = 0;
  selectedItemIndex = 0;
  renderAll();
  pickerOpen = true;
  document.body.classList.add('picker-mode');
  $('#clipnest-app').hidden = true;
  $('#picker-overlay').hidden = false;
  await setPickerWindowMode(true);
  await showMainWindow();
  setTimeout(() => $('#picker-items .picker-item')?.focus(), 20);
}

async function closePicker({ restoreWindow = true } = {}) {
  pickerOpen = false;
  $('#picker-overlay').hidden = true;
  document.body.classList.remove('picker-mode');
  $('#clipnest-app').hidden = false;
  if (restoreWindow) await setPickerWindowMode(false);
}

async function pasteSelected() {
  const tag = activePickerTag();
  const item = tag?.items[selectedItemIndex];
  if (!item) return;
  await closePicker({ restoreWindow: false });
  await hideMainWindow();
  try {
    if (invoke) await invoke('paste_into_previous_app', { text: item.content });
    else await writeClipboard(item.content);
    showToast(`已粘贴「${item.title}」`);
  } catch (error) {
    await writeClipboard(item.content);
    showToast(`已复制到剪贴板，请按 ${directPasteHotkey} 粘贴`);
  }
}

async function addCurrentClipboard() {
  const tag = activePickerTag();
  if (!tag || tag.type === 'recent') return;
  const clipboard = (await readClipboard()).trim();
  if (!clipboard) return showToast('当前剪贴板为空');
  const result = addClipboardItem(tag, clipboard);
  if (!result.added) { selectedItemIndex = result.index; renderPicker(); return showToast('该内容已在此标签'); }
  saveData();
  selectedItemIndex = result.index;
  renderAll();
  showToast('已添加到当前标签');
}

async function createTag() {
  const name = window.prompt('输入标签名称');
  if (!name?.trim()) return;
  const id = `tag-${Date.now()}`;
  data.push({ id, type: 'custom', name: name.trim(), color: COLORS[data.length % COLORS.length], items: [] });
  managerTagId = id;
  saveData(); renderAll(); showToast('标签已创建');
}

function bindEvents() {
  $('#open-picker').addEventListener('click', openPicker);
  $('#simulate-paste').addEventListener('click', async () => { await writeClipboard($('#test-clipboard').value); await openPicker(); });
  $('#dismiss-picker').addEventListener('click', closePicker);
  $('#open-manager').addEventListener('click', async () => { await closePicker(); await showMainWindow(); $('#home-view').hidden = true; $('#manage-view').hidden = false; renderManager(); });
  $('#back-home').addEventListener('click', async () => { await setPickerWindowMode(false); $('#manage-view').hidden = true; $('#home-view').hidden = false; renderOverview(); });
  $('#new-tag').addEventListener('click', createTag);
  $('#add-clipboard').addEventListener('click', addCurrentClipboard);
  $('#permission-help').addEventListener('click', openAccessibilitySettings);
  $('#permission-note-action').addEventListener('click', openAccessibilitySettings);

  document.addEventListener('keydown', async (event) => {
    const isQuickHotkey = isMac
      ? event.ctrlKey && !event.metaKey && !event.altKey
      : event.altKey && !event.ctrlKey && !event.metaKey;
    if (isQuickHotkey && event.key.toLowerCase() === 'v') {
      event.preventDefault();
      if (pickerOpen) return pasteSelected();
      return openPicker();
    }
    if (!pickerOpen) return;
    if (event.key === 'Escape') return closePicker();
    if (event.key === 'ArrowLeft') { event.preventDefault(); pickerTagIndex = Math.max(0, pickerTagIndex - 1); selectedItemIndex = 0; return renderPicker(); }
    if (event.key === 'ArrowRight') { event.preventDefault(); pickerTagIndex = Math.min(data.length - 1, pickerTagIndex + 1); selectedItemIndex = 0; return renderPicker(); }
    if (event.key === 'ArrowUp') { event.preventDefault(); selectedItemIndex = Math.max(0, selectedItemIndex - 1); return renderPicker(); }
    if (event.key === 'ArrowDown') { event.preventDefault(); selectedItemIndex = Math.min(Math.max(0, activePickerTag().items.length - 1), selectedItemIndex + 1); return renderPicker(); }
    if (event.key === 'Enter') { event.preventDefault(); return pasteSelected(); }
    if (/^[1-5]$/.test(event.key)) {
      const index = Number(event.key) - 1;
      if (index < activePickerTag().items.length) { selectedItemIndex = index; return pasteSelected(); }
    }
  });

  document.addEventListener('click', async (event) => {
    const pickerTab = event.target.closest('[data-picker-tag]');
    if (pickerTab) { pickerTagIndex = Number(pickerTab.dataset.pickerTag); selectedItemIndex = 0; return renderPicker(); }
    const pickerItem = event.target.closest('[data-picker-item]');
    if (pickerItem) { selectedItemIndex = Number(pickerItem.dataset.pickerItem); return pasteSelected(); }
    const managerTagButton = event.target.closest('[data-manager-tag]');
    if (managerTagButton) { managerTagId = managerTagButton.dataset.managerTag; return renderManager(); }
    if (event.target.closest('#add-manager-item')) {
      const tag = managerTag();
      if (!tag) return;
      const clipboard = (await readClipboard()).trim();
      if (!clipboard) return showToast('当前剪贴板为空');
      const result = addClipboardItem(tag, clipboard);
      if (!result.added) return showToast('该内容已在此标签');
      saveData(); renderAll(); return showToast('已添加内容');
    }
    const copyButton = event.target.closest('[data-copy-manager]');
    if (copyButton) { const item = managerTag()?.items.find((entry) => entry.id === copyButton.dataset.copyManager); if (item) { await writeClipboard(item.content); showToast('已复制'); } return; }
    const deleteButton = event.target.closest('[data-delete-item]');
    if (deleteButton) { const tag = managerTag(); tag.items = tag.items.filter((item) => item.id !== deleteButton.dataset.deleteItem); saveData(); renderManager(); return showToast('已删除'); }
  });

  document.addEventListener('input', (event) => {
    const field = event.target.closest('[data-field]');
    if (!field) return;
    const row = field.closest('[data-item-id]');
    const item = managerTag()?.items.find((entry) => entry.id === row.dataset.itemId);
    if (item) { item[field.dataset.field] = field.value; saveData(); }
  });
}

async function openAccessibilitySettings() {
  if (!invoke) return showToast('请在 ClipNest 应用中打开此功能');
  try {
    await invoke('open_accessibility_settings');
    $('#hotkey-status').textContent = '请在系统设置中允许 ClipNest';
    $('#hotkey-status').style.color = '#9a6a00';
    $('#permission-note').hidden = false;
  } catch { showToast('无法打开系统设置，请手动打开“隐私与安全性 > 辅助功能”'); }
}

async function initNativeBridge() {
  document.body.dataset.platform = platformName;
  document.querySelectorAll('[data-hotkey]').forEach((element) => { element.textContent = quickHotkey; });
  document.querySelectorAll('[data-direct-paste-hotkey]').forEach((element) => { element.textContent = directPasteHotkey; });
  if (isMac) {
    $('#permission-help').hidden = false;
    $('#permission-note').hidden = false;
  }
  if (!eventApi?.listen) return;
  await eventApi.listen('paste-shortcut', async () => { if (pickerOpen) await pasteSelected(); else await openPicker(); });
  await eventApi.listen('keyboard-hook-started', () => { $('#hotkey-status').textContent = `${quickHotkey} 监听中`; $('#hotkey-status').style.color = ''; });
  await eventApi.listen('keyboard-hook-error', (event) => { $('#hotkey-status').textContent = isMac ? '需要辅助功能权限' : '快捷键不可用'; $('#hotkey-status').style.color = '#c64d53'; if (isMac) $('#permission-note').hidden = false; if (event.payload) console.warn('Keyboard hook error:', event.payload); });
}

window.addEventListener('DOMContentLoaded', async () => {
  bindEvents();
  renderAll();
  await initNativeBridge();
});

window.addEventListener('blur', async () => {
  if (!pickerOpen) return;
  await closePicker({ restoreWindow: false });
  await hideMainWindow();
});
