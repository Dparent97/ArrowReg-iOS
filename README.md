# ArrowReg-iOS

This repository contains the ArrowReg iOS client and accompanying backend services.

## Testing

The backend includes an evaluation test suite that issues ten predefined queries
against the hybrid retrieval service and verifies that expected citations appear
in the correct order.

Run the tests from the `backend` directory:

```bash
npm test
```

This runs `node --test tests/eval.test.js`.

