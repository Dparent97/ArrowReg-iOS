# ArrowReg-iOS

This repository contains the ArrowReg iOS application and supporting backend utilities.

## Recent Changes
- Centralized search history persistence in `SearchService`.
- `SearchViewModel` now observes the shared history published by `SearchService`.
- UI components update automatically when the shared history changes.

## Update Plan
- Extend local retrieval and ranking capabilities with deterministic CFR section chunking and precomputed bge-base/text-embedding-3-small vectors.
- Integrate cosine/BM25 hybrid search with top-k=8 results and strict eCFR citations.
- Add evaluation tests over 10 representative queries.
- Harden remote API client to handle JSON/SSE responses with CORS and token-based auth.
