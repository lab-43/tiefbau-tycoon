---
titel: Keine privaten Daten im Repo oder in Anfragen
bereich: ablauf
datum: 2026-10-28
pruefung: lint:keine-mail
---

**Regel:**
- Jonathans E-Mail-Adresse steht nirgends im Repo und geht an keinen Dienst. Das gilt auch für User-Agent-Header, Commit-Autoren und Testdaten.
- Commits laufen unter einer neutralen Agent-Identität (siehe `tools/setup_env.sh`).
- Erlaubt ist nur `noreply@anthropic.com` in den Co-Authored-By-Zeilen.
