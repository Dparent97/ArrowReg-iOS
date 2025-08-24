# ArrowReg iOS and Backend

This repository contains the ArrowReg iOS client and its Cloudflare Worker backend.

## Highlights

- **Secure token storage**: iOS client now stores authentication tokens in the Keychain and attaches them to outbound requests.
- **Robust streaming**: Search streaming gracefully handles authorization errors and treats JSON and SSE responses uniformly.
- **Production-ready backend**: CORS is restricted to configured origins and JWTs are verified using the [`jose`](https://github.com/panva/jose) library.

## Development

### Backend
1. Install dependencies:
   ```bash
   cd backend
   npm install
   ```
2. Provide environment variables:
   - `JWT_SECRET` – HMAC secret for token verification
   - `ALLOWED_ORIGINS` – comma-separated list of allowed origins (defaults to `https://arrowreg.app`)
3. Run the worker:
   ```bash
   npm run dev
   ```

### iOS
The iOS app automatically reads any saved auth token from the Keychain. To set a token at runtime:
```swift
KeychainHelper.shared.save("<token>")
```

## Testing
No automated test suite is bundled yet. Run `npm test` in the backend directory to verify future tests once added.

## Update Plan
- Fetch dependencies once network access is available to populate the `jose` package in `package-lock.json`.
- Expand test coverage, including evaluation queries for search.
- Implement local RAG pipeline and additional evaluation as described in project roadmap.
