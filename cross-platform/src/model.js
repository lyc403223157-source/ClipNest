export const STORAGE_KEY = 'clipnest-data-v2';

export function createInitialData() {
  return [
    { id: 'recent', type: 'recent', name: '最近', color: '#0a84ff', items: [] },
    { id: 'favorites', type: 'custom', name: '常用', color: '#30a46c', items: [] }
  ];
}

export function loadStoredData(raw) {
  if (!raw) return createInitialData();
  try {
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) return createInitialData();
    const tags = parsed.filter((tag) => tag && Array.isArray(tag.items));
    if (!tags.some((tag) => tag.type === 'recent')) tags.unshift(createInitialData()[0]);
    return tags;
  } catch {
    return createInitialData();
  }
}

export function titleForContent(content) {
  const text = String(content ?? '').trim();
  try {
    const url = new URL(text);
    if (!['http:', 'https:'].includes(url.protocol)) throw new Error('not a web URL');
    return `${url.hostname}${url.pathname === '/' ? '' : ` / ${url.pathname.slice(1).split('/')[0]}`}`.slice(0, 48);
  } catch {
    return text.replace(/\s*\n\s*/g, ' ↵ ').slice(0, 48) || '未命名内容';
  }
}

export function upsertRecent(tags, content, now = Date.now()) {
  const text = String(content ?? '').trim();
  if (!text) return tags;
  const recent = tags.find((tag) => tag.type === 'recent');
  if (!recent) return tags;
  recent.items = recent.items.filter((item) => item.content !== text);
  recent.items.unshift({ id: `recent-${now}`, title: titleForContent(text), content: text });
  return tags;
}

export function addClipboardItem(tag, content, now = Date.now()) {
  const text = String(content ?? '').trim();
  if (!tag || !text) return { added: false, index: -1 };
  const existing = tag.items.findIndex((item) => item.content === text);
  if (existing >= 0) return { added: false, index: existing };
  tag.items.push({ id: `item-${now}`, title: titleForContent(text), content: text });
  return { added: true, index: tag.items.length - 1 };
}

