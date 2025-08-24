import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import LocalSearchService from '../local-search.js';

function setup() {
  const service = new LocalSearchService();
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ls-'));
  const file = path.join(dir, 'doc.md');
  fs.writeFileSync(
    file,
    `# Section One\nInspection procedures are outlined.\n\n# Section Two\nThese regulations cover safety equipment.\n`
  );
  return { service, file };
}

test('handles stemming for plural forms', async () => {
  const { service, file } = setup();
  await service.loadDocument(file, 'doc');
  service.initialized = true;
  const results = await service.search('inspections');
  assert.ok(results.length > 0);
  assert.ok(results[0].content.includes('Inspection'));
});

test('removes stop words in queries', async () => {
  const { service, file } = setup();
  await service.loadDocument(file, 'doc');
  service.initialized = true;
  const res1 = await service.search('safety equipment');
  const res2 = await service.search('the safety equipment');
  assert.strictEqual(res1[0].sectionId, res2[0].sectionId);
});

test('is case insensitive', async () => {
  const { service, file } = setup();
  await service.loadDocument(file, 'doc');
  service.initialized = true;
  const res1 = await service.search('INSPECTION');
  const res2 = await service.search('inspection');
  assert.strictEqual(res1[0].sectionId, res2[0].sectionId);
});
