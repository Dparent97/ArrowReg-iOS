import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import LocalSearchService from '../src/services/local-search.js';

// Evaluation tests for LocalSearchService using 10 queries

async function setupTempDoc() {
  const tmpDir = await fs.promises.mkdtemp(path.join(os.tmpdir(), 'localsearch-'));
  const filePath = path.join(tmpDir, 'doc.md');
  const content = `# Section 1\nShips ensure safety at sea.\n\n# Section 2\nRegulations govern maritime operations.`;
  await fs.promises.writeFile(filePath, content, 'utf8');
  return { tmpDir, filePath };
}

test('local search returns results for queries', async () => {
  const { filePath } = await setupTempDoc();
  const service = new LocalSearchService();
  await service.addDocument(filePath, 'doc1');
  service.initialized = true;

  const queries = [
    'ships',
    'safety',
    'sea',
    'regulations',
    'maritime',
    'operations',
    'section',
    'govern',
    'ships safety',
    'nonexistent'
  ];

  for (const q of queries) {
    const results = await service.search(q, { maxResults: 5 });
    assert.ok(Array.isArray(results));
  }
});
