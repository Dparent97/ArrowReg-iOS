# ArrowReg iOS/Backend Repository

This repository contains the ArrowReg iOS application and its backend services.

## Changes

- Replaced synchronous `fs.*Sync` calls with `async/await` using `fs.promises`.
- Marked document management methods (`addDocument`, `removeDocument`, `listDocuments`, `getDocument`) as asynchronous and ensured errors propagate.
- Added basic evaluation tests for the local search service and document manager.

## Development

Run tests:

```bash
cd backend
npm test
```

## Update Plan

- [ ] Implement deterministic CFR chunking with pre-computed `bge-base`/`text-embedding-3-small` vectors.
- [ ] Add cosine and BM25 hybrid retrieval with top-k = 8 and strict citation formatting linking to eCFR.
- [ ] Expand evaluation suite with at least 10 curated queries and expected citations.
- [ ] Harden remote API client for JSON and SSE responses with token-based authentication and CORS support.

