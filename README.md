# ArrowReg RAG Backend

This repository adds a local retrieval‑augmented generation (RAG) pipeline for CFR data.

## Preprocessing

```
node scripts/preprocess-cfr.js <cfr.txt> <title> <part>
```
The script chunks CFR text by Title/Part/Subpart/Section and writes JSON with metadata and
precomputed `bge-base` and `text-embedding-3-small` vectors to
`backend/src/services/rag-data/cfr-chunks.json`.

## Local Retrieval

`backend/src/services/rag.ts` exposes a search method combining cosine similarity and BM25
with `topK=8` results. Each result includes Title, Part, Subpart, Section and an eCFR link.
`backend/src/index.js` uses this service as a fallback when the remote OpenAI API is
unavailable.

## Tests

```
cd backend
npm test
```
The evaluation suite runs 10 sample queries against the local RAG store.

## Update Plan

1. Expand `cfr-chunks.json` with full CFR coverage using `scripts/preprocess-cfr.js`.
2. Replace mock embeddings with real model outputs once dependencies are available.
3. Integrate streaming SSE responses from the remote API and surface partial results.
4. Add more comprehensive benchmark queries and regression tests.
