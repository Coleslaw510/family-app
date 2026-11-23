# SimpleFIN integration facts

These implementation constraints were checked against SimpleFIN's official protocol and Bridge developer guide on 2026-11-23.

- The user provides a base64-encoded Setup Token. The application decodes its URL and claims it with one HTTPS POST. The returned Access URL includes Basic Auth credentials and is a secret; it must be stored securely and never returned to the client.
- Claiming a token can return HTTP 403 when invalid, expired, or already claimed. SimpleFIN says the user should be notified that a failed/compromised token may expose transaction data and may need to be disabled.
- Fetch data using `GET /accounts`, Basic Auth, protocol `version=2`, and optional `start-date` / `end-date` Unix timestamps. A 403 from `/accounts` indicates revoked or invalid credentials; 402 indicates payment required.
- Transactions have IDs unique within an account, a posted Unix timestamp, a signed decimal-string amount, a description, and optional pending status. Positive amounts represent deposits; pending transactions are omitted unless explicitly requested.
- SimpleFIN Bridge intends daily updates, allows roughly 24 requests/day, limits one date-window request to 90 days, and recommends overlapping sync windows by about five days. Avoid high-frequency polling and deduplicate using both account identity and transaction ID.
- Require HTTPS and verify certificates. Never pass an Access URL to the iOS client or expose raw provider error text without sanitization.

## Sources

- [SimpleFIN Protocol](https://www.simplefin.org/protocol.html) — App Quickstart, token claim, GET `/accounts`, error codes, account/transaction fields, and security checklist.
- [SimpleFIN Bridge Developer Guide](https://beta-bridge.simplefin.org/info/developers) — setup-token workflow, Basic Auth usage, Bridge request limits, 90-day date range, and five-day overlap recommendation.
