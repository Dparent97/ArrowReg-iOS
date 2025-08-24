#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import readline from 'node:readline';

/**
 * Deterministically chunk CFR text by Title/Part/Subpart/Section and
 * precompute embeddings using bge-base and text-embedding-3-small.
 *
 * Usage: node scripts/preprocess-cfr.js <input-file> <title> <part>
 * The script outputs JSON to backend/src/services/rag-data/cfr-chunks.json
 */

import OpenAI from 'openai';

async function embedOpenAI(client, text) {
  try {
    const resp = await client.embeddings.create({
      model: 'text-embedding-3-small',
      input: text
    });
    return resp.data[0].embedding;
  } catch (e) {
    console.warn('OpenAI embedding failed, using zeros');
    return Array(3).fill(0);
  }
}

async function embedBGE(text) {
  try {
    const { pipeline } = await import('@xenova/transformers');
    const extractor = await pipeline('feature-extraction', 'Xenova/bge-base-en');
    const result = await extractor(text, { pooling: 'mean', normalize: true });
    return Array.from(result.data);
  } catch (e) {
    console.warn('bge-base embedding failed, using zeros');
    return Array(3).fill(0);
  }
}

function chunkLines(lines, title, part) {
  const chunks = [];
  let current = { subpart: '', section: '', text: '' };
  for (const line of lines) {
    const subpartMatch = line.match(/^Subpart\s+([A-Z0-9]+)\s+\—/i);
    if (subpartMatch) {
      if (current.section) chunks.push({ ...current });
      current = { subpart: subpartMatch[1], section: '', text: '' };
      continue;
    }
    const sectionMatch = line.match(/^\s*§\s*(\d+[\.\d]*)\.?\s*(.*)$/);
    if (sectionMatch) {
      if (current.section) chunks.push({ ...current });
      current.section = sectionMatch[1];
      current.text = sectionMatch[2] + '\n';
      continue;
    }
    if (current.section) current.text += line + '\n';
  }
  if (current.section) chunks.push({ ...current });
  return chunks.map((c, idx) => ({
    id: `${title}-${part}-${c.subpart || '0'}-${c.section}`,
    title, part, subpart: c.subpart || '', section: c.section,
    text: c.text.trim()
  }));
}

async function main() {
  const [input, title, part] = process.argv.slice(2);
  if (!input || !title || !part) {
    console.error('Usage: node preprocess-cfr.js <input-file> <title> <part>');
    process.exit(1);
  }
  const rl = readline.createInterface({ input: fs.createReadStream(input), crlfDelay: Infinity });
  const lines = [];
  for await (const line of rl) lines.push(line);
  const chunks = chunkLines(lines, title, part);
  const client = new OpenAI({ apiKey: process.env.OPENAI_API_KEY || '' });
  const out = [];
  for (const chunk of chunks) {
    const [bgeVec, openaiVec] = await Promise.all([
      embedBGE(chunk.text),
      embedOpenAI(client, chunk.text)
    ]);
    out.push({ ...chunk, bge: bgeVec, openai: openaiVec });
  }
  const outPath = path.join('backend', 'src', 'services', 'rag-data', 'cfr-chunks.json');
  fs.writeFileSync(outPath, JSON.stringify(out, null, 2));
  console.log(`Wrote ${out.length} chunks to ${outPath}`);
}

main().catch(e => { console.error(e); process.exit(1); });
