import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import LocalSearchService from '../src/services/local-search.js';

// Helper to create temporary markdown file
function createTempDocument(content) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'local-search-'));
  const file = path.join(dir, 'doc.md');
  fs.writeFileSync(file, content);
  return { file, dir };
}

test('add and remove document updates search index', async () => {
  const service = new LocalSearchService();
  service.initialized = true; // skip automatic initialization

  const { file, dir } = createTempDocument('# Test Section\nThis is a test document.');
  await service.addDocument(file, 'doc1');

  let results = await service.search('test');
  assert.equal(results.length > 0, true);

  await service.removeDocument('doc1');
  results = await service.search('test');
  assert.equal(results.length, 0);
  fs.rmSync(dir, { recursive: true, force: true });
});
