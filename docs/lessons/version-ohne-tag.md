---
titel: Im flachen Klon heißt der Build nur nach dem Commit – build.sh holt Verlauf und Tags selbst nach
bereich: build
datum: 2026-10-29
pruefung: manuell: `build/main/VERSION.txt` beginnt mit `version=v…`
---

**Was passiert ist:** Meldung #24. `tools/build.sh build/main` schrieb `version=bda0bbb` statt `v1.7.1-92-gbda0bbb`, obwohl die Tags auf GitHub liegen. Der Session-Klon war flach (`git rev-parse --is-shallow-repository` → `true`, nur 37 Commits); `git describe --tags` fand den Tag `v1.7.1` nicht unter den Vorfahren. Kurz danach lag auf dem PC auch ein Build einer anderen Session mit `version=b33491c`. Im Menü und in Meldungen steht dann keine lesbare Version.

**Ursache:** Die Umgebung klont mit begrenzter Tiefe. `git fetch --tags` allein hilft nicht, die Tag-Commits fehlen in der Geschichte.

**Regel:**
- `tools/build.sh` ruft bei einem flachen Klon `git fetch --unshallow --tags` auf und warnt, wenn das nicht geht.
- Vor dem Übertragen nach `build/main` die erste Zeile von `VERSION.txt` ansehen.
