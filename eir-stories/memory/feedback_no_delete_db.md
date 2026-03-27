---
name: Do not delete the database
description: Never delete the SQLite database file — use migrations or upserts instead
type: feedback
---

Do not delete the stories-rust.db database file to re-seed data.

**Why:** The user has existing data in the database (user-created stories, accounts, etc.) that would be lost.

**How to apply:** When adding new seed data, use SQL inserts/upserts directly or modify the seed logic to handle incremental additions without wiping existing data.
