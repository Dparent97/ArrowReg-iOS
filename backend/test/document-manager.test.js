import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { DocumentManager } from '../src/handlers/document-management.js';

async function createManager() {
  const tmpDir = await fs.promises.mkdtemp(path.join(os.tmpdir(), 'docs-'));
  const manager = new DocumentManager();
  manager.documentsPath = tmpDir;
  return { manager, tmpDir };
}

test('add, list, and get document', async () => {
  const { manager } = await createManager();
  const content = '# Title\n\n' + 'content '.repeat(50);
  const buffer = Buffer.from(content, 'utf8');
  const result = await manager.addDocument(buffer, 'test.md', 'custom');
  assert.ok(result.success);

  const list = await manager.listDocuments();
  assert.equal(list.totalCount, 1);

  const doc = await manager.getDocument(result.documentId);
  assert.equal(doc.metadata.id, result.documentId);
  assert.ok(doc.content.includes('Title'));
});
