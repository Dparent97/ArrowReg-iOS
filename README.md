# ArrowReg-iOS

This repository contains the ArrowReg iOS application and its Cloudflare Worker backend.

## Recent Improvements

- Replaced SwiftUI `TabView` with a UIKit-backed paging view to restore reliable swipe gestures in the multi-turn conversation UI.
- Added a lightweight local RAG pipeline with deterministic CFR section chunking, precomputed embedding vectors, and a hybrid cosine/BM25 ranker.

## Backend Streaming Utilities

The backend now exposes shared Server-Sent Events (SSE) helpers in `src/utils/sse.js`.  These helpers simplify creating event streams, sending events, and closing the stream.  Handlers such as `handleLocalStreamSearch` and `handleStreamingSearch` use these helpers to deliver streaming search results consistently.

## Development

```bash
cd backend
npm install
npm run dev
```

## Update Plan

- [x] Implement deterministic CFR chunking with precomputed embeddings.
- [x] Add hybrid cosine/BM25 search with top-k=8 results and strict citations.
- [x] Provide evaluation tests over 10 benchmark queries.
- [x] Harden remote API client with JSON + SSE, CORS configuration, and token authentication.
- [ ] Expand citation coverage and integrate larger regulatory corpora.

