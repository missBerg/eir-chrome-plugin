# Eir Stories Rust Backend

This is the fast backend track for `Eir Stories`.

What it does:

- runs an Axum service on `http://localhost:4181`
- stores app data in SQLite at `../storage/stories-rust.db`
- exposes real stateful APIs for:
  - auth and sessions
  - stories
  - profiles
  - comments
  - follows
  - messages
- serves the existing frontend scaffold at `/site/`

Important note:

- Rust helps keep the app lean under load.
- SQLite is still a local-development choice, not the final answer for heavy social traffic.
- If the target is serious write volume, move this same service shape to Postgres next.

Run it:

```bash
cd /Users/birger/Community/eir-chrome-plugin/eir-stories/rust-backend
cargo run
```
