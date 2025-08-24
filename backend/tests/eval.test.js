import test from 'node:test';
import assert from 'node:assert/strict';
import LocalSearchService from '../src/services/local-search.js';

// Prepare a local search service with in-memory documents
const service = new LocalSearchService();

// Sample documents with multiple sections to evaluate retrieval ordering
const documents = [
  {
    id: 'doc1',
    title: 'Doc 1',
    content: `# Boat Safety
Boat safety ensures safe navigation and safety measures.
# Pollution Control
Regulations for pollution control.
# Emergency Signals
Procedures for emergency signals.
# Waste Disposal
Rules about waste disposal.
# Navigation Lights
Guidelines for navigation lights.`
  },
  {
    id: 'doc2',
    title: 'Doc 2',
    content: `# Life Jackets
Life jacket requirements for crew.
# Engine Maintenance
Engine maintenance standards.
# Crew Training
Crew training guidelines.
# Fuel Storage
Fuel storage safety and handling.
# Radio Operations
Protocols for radio operations.`
  }
];

for (const doc of documents) {
  const sections = service.parseMarkdownSections(doc.content, doc.id);
  service.documents.set(doc.id, {
    id: doc.id,
    title: doc.title,
    sections,
    fullContent: doc.content
  });
  service.indexDocument(doc.id, sections);
}
// Mark the service as initialized to avoid loading external files
service.initialized = true;

test('hybrid retrieval evaluation', async () => {
  const cases = [
    { query: 'safety', expected: ['Boat Safety', 'Fuel Storage'] },
    { query: 'pollution', expected: ['Pollution Control'] },
    { query: 'emergency', expected: ['Emergency Signals'] },
    { query: 'waste', expected: ['Waste Disposal'] },
    { query: 'navigation lights', expected: ['Navigation Lights'] },
    { query: 'life jacket', expected: ['Life Jackets'] },
    { query: 'engine', expected: ['Engine Maintenance'] },
    { query: 'crew training', expected: ['Crew Training'] },
    { query: 'fuel storage', expected: ['Fuel Storage'] },
    { query: 'radio operations', expected: ['Radio Operations'] }
  ];

  for (const { query, expected } of cases) {
    const results = await service.search(query, { maxResults: 8 });
    const titles = results.map(r => r.title);
    assert.deepStrictEqual(
      titles.slice(0, expected.length),
      expected,
      `Query "${query}" did not return expected citations in order`
    );
  }
});
