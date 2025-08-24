import test from 'node:test';
import assert from 'node:assert';
import rag from '../src/services/rag.js';

const queries = [
  'fire detection systems on OSV',
  'oil discharge prohibitions',
  'lifesaving equipment requirements',
  'fire detection coverage',
  'oil discharge report',
  'survival craft requirements',
  'automatic fire alarm',
  'oily waste discharge regulations',
  'life rafts emergency equipment',
  'fire detection power supply'
];

test('rag returns results for common queries', async (t) => {
  for (const q of queries) {
    const results = await rag.search(q, 8);
    assert.ok(Array.isArray(results), 'results should be array');
    assert.ok(results.length > 0, 'should return at least one result');
    const top = results[0];
    assert.ok(top.title && top.part && top.section, 'result should include metadata');
    assert.ok(top.link.startsWith('https://www.ecfr.gov/current/'), 'should include eCFR link');
  }
});
