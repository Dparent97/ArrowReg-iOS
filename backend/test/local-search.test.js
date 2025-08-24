import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import LocalSearchService from '../src/services/local-search.js';

async function setupService() {
  const service = new LocalSearchService();
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'ls-'));
  const filePath = path.join(tmpDir, 'doc.md');
  fs.writeFileSync(filePath, `# Fire Safety\nFire detection systems are required.\n`);
  await service.loadDocument(filePath, 'doc1');
  service.initialized = true;
  return service;
}

test('stemming matches variations', async () => {
  const service = await setupService();
  const res1 = await service.search('fire');
  const res2 = await service.search('fires');
  assert.ok(res1.length > 0);
  assert.equal(res1[0].sectionId, res2[0].sectionId);
});

test('stop words do not affect results', async () => {
  const service = await setupService();
  const res1 = await service.search('fire detection');
  const res2 = await service.search('the fire detection');
  assert.equal(res1[0].sectionId, res2[0].sectionId);
});
