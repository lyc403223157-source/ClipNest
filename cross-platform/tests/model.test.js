import test from 'node:test';
import assert from 'node:assert/strict';
import {
  addClipboardItem,
  createInitialData,
  loadStoredData,
  titleForContent,
  upsertRecent
} from '../src/model.js';

test('starts with fixed recent and favorites tags', () => {
  const data = createInitialData();
  assert.equal(data[0].type, 'recent');
  assert.equal(data[0].name, '最近');
  assert.equal(data[1].name, '常用');
});

test('recent history is deduplicated and is not capped at five items', () => {
  const data = createInitialData();
  for (let index = 0; index < 8; index += 1) upsertRecent(data, `内容 ${index}`, index);
  assert.equal(data[0].items.length, 8);
  upsertRecent(data, '内容 2', 20);
  assert.equal(data[0].items.length, 8);
  assert.equal(data[0].items[0].content, '内容 2');
});

test('creates readable URL and multiline titles', () => {
  assert.equal(titleForContent('https://example.com/docs/start'), 'example.com / docs');
  assert.equal(titleForContent('第一行\n第二行'), '第一行 ↵ 第二行');
});

test('custom groups allow more than five items and reject duplicates', () => {
  const tag = createInitialData()[1];
  for (let index = 0; index < 7; index += 1) {
    assert.equal(addClipboardItem(tag, `回复 ${index}`, index).added, true);
  }
  assert.equal(tag.items.length, 7);
  const duplicate = addClipboardItem(tag, '回复 3', 99);
  assert.equal(duplicate.added, false);
  assert.equal(duplicate.index, 3);
});

test('invalid stored state falls back safely', () => {
  assert.equal(loadStoredData('{broken')[0].type, 'recent');
  assert.equal(loadStoredData('[]')[0].type, 'recent');
});

