---
titel: Keine privaten Daten im Repo oder in Anfragen
bereich: ablauf
datum: 2026-10-28
pruefung: lint:keine-mail
---

**Was passiert ist:** In `.git/config` des Arbeitsrepos stand eine repo-lokale Identität mit Jonathans privater Adresse. Die Commits waren sauber, weil sie mit `-c user.email=…` erstellt wurden. Ein normales `git commit` hätte die Adresse aber nach GitHub gebracht.

**Regel:**
- Jonathans E-Mail-Adresse steht nirgends im Repo und geht an keinen Dienst. Das gilt auch für User-Agent-Header, Commit-Autoren und Testdaten.
- Commits laufen unter einer neutralen Agent-Identität. `tools/setup_env.sh` entfernt private repo-lokale Adressen, und `lint.py --staged` (Pre-Commit) prüft den Autor.
- Erlaubt ist nur `noreply@anthropic.com` in den Co-Authored-By-Zeilen.
