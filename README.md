# ArrowReg-iOS

This repository contains the ArrowReg iOS application and its Cloudflare Worker backend.

## Backend Streaming Utilities

The backend now exposes shared Server-Sent Events (SSE) helpers in `src/utils/sse.js`.  These helpers simplify creating event streams, sending events, and closing the stream.  Handlers such as `handleLocalStreamSearch` and `handleStreamingSearch` use these helpers to deliver streaming search results consistently.

## iOS Swipe Navigation

The iOS client now uses a UIKit-backed `UIPageViewController` to render multi-turn conversations. This change restores reliable horizontal swipe gestures even when the page view is nested inside other SwiftUI scroll views.

## Development

```bash
cd backend
npm install
npm run dev
```

## Update Plan

- [x] Integrate UIKit-based page view to restore swipe gestures in conversation view.
- [ ] Implement deterministic CFR chunking with precomputed embeddings.
- [ ] Add hybrid cosine/BM25 search with top-k=8 results and strict citations.
- [ ] Provide evaluation tests over 10 benchmark queries.
- [ ] Harden remote API client with JSON + SSE, CORS configuration, and token authentication.

