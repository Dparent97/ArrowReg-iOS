import test from 'node:test';
import assert from 'node:assert/strict';
import LocalSearchService from '../src/services/local-search.js';

const service = new LocalSearchService();

// helper to run search once service initialized
async function queryTop(query) {
  const results = await service.search(query, { maxResults: 8 });
  return results;
}

test.before(async () => {
  await service.initialize();
});

const cases = [
  {
    name: 'vessel inspection',
    query: 'vessel inspection',
    expect: {
      documentId: 'abs_part7',
      sectionId: 'abs_part7_2',
      source: 'ABS Part 7'
    }
  },
  {
    name: 'stability tests passenger vessels',
    query: 'stability tests passenger vessels',
    expect: {
      documentId: 'cfr46',
      sectionId: 'cfr46_2',
      source: '46 CFR'
    }
  },
  {
    name: 'navigation rules for mariners',
    query: 'navigation rules for mariners',
    expect: {
      documentId: 'cfr33',
      sectionId: 'cfr33_1',
      source: '33 CFR'
    }
  },
  {
    name: 'bridge lighting',
    query: 'bridge lighting',
    expect: {
      documentId: 'cfr33',
      sectionId: 'cfr33_2',
      source: '33 CFR'
    }
  },
  {
    name: 'survey after construction',
    query: 'survey after construction',
    expect: {
      documentId: 'abs_part7',
      sectionId: 'abs_part7_1',
      source: 'ABS Part 7'
    }
  },
  {
    name: 'hull inspection damage assessment',
    query: 'hull inspection damage assessment',
    expect: {
      documentId: 'abs_part7',
      sectionId: 'abs_part7_2',
      source: 'ABS Part 7'
    }
  },
  {
    name: 'inspection requirements after construction',
    query: 'inspection requirements after construction',
    expect: {
      documentId: 'abs_part7',
      sectionId: 'abs_part7_1',
      source: 'ABS Part 7'
    }
  },
  {
    name: 'mariners collision prevention',
    query: 'mariners collision prevention',
    expect: {
      documentId: 'cfr33',
      sectionId: 'cfr33_1',
      source: '33 CFR'
    }
  },
  {
    name: 'passenger vessel stability requirements',
    query: 'passenger vessel stability requirements',
    expect: {
      documentId: 'cfr46',
      sectionId: 'cfr46_2',
      source: '46 CFR'
    }
  },
  {
    name: 'bridge lights navigable waters',
    query: 'bridge lights navigable waters',
    expect: {
      documentId: 'cfr33',
      sectionId: 'cfr33_2',
      source: '33 CFR'
    }
  }
];

for (const testCase of cases) {
  test(`query: ${testCase.name}`, async () => {
    const results = await queryTop(testCase.query);
    assert.ok(Array.isArray(results));
    assert.ok(results.length > 0);
    const top = results[0];

    // ensure CFR chunking by checking sectionId format
    assert.equal(top.documentId, testCase.expect.documentId);
    assert.equal(top.sectionId, testCase.expect.sectionId);

    // citation formatting via source displayName
    assert.match(top.source.displayName, new RegExp(testCase.expect.source, 'i'));

    // hybrid ranking - ensure top result appears in top-k
    assert.ok(results.find(r => r.sectionId === testCase.expect.sectionId));
    assert.ok(results.length <= 8);
  });
}
