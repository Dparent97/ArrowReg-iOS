# ArrowReg-iOS

This repository contains the ArrowReg iOS application and its Cloudflare Worker backend.

## Data Flow Overview

1. The iOS app collects user queries in `SearchView` and forwards them through `SearchService`.
2. The Cloudflare Worker backend streams results back to the device over Server-Sent Events (SSE).
3. Responses are rendered inside SwiftUI views, which now use a UIKit-backed pager for smooth horizontal navigation between conversation turns.

## Backend Streaming Utilities

The backend now exposes shared Server-Sent Events (SSE) helpers in `src/utils/sse.js`.  These helpers simplify creating event streams, sending events, and closing the stream.  Handlers such as `handleLocalStreamSearch` and `handleStreamingSearch` use these helpers to deliver streaming search results consistently.

## Development

```bash
cd backend
npm install
npm run dev
```

## Update Plan

- [ ] Implement deterministic CFR chunking with precomputed embeddings.
- [ ] Add hybrid cosine/BM25 search with top-k=8 results and strict citations.
- [ ] Provide evaluation tests over 10 benchmark queries.
- [ ] Harden remote API client with JSON + SSE, CORS configuration, and token authentication.
- [x] Replace `TabView` with a UIKit-backed pager to restore reliable swipe gestures in conversation pages.

