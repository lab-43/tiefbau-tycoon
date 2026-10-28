---
titel: In flachen Session-Klonen Refs beim Fetch und Lease ausdrücklich nennen
bereich: werkzeuge
datum: 2026-10-28
pruefung: manuell: merge.sh in einem Klon mit --depth 1 (Sandbox mit leerem Bare-Repo)
---

**Was passiert ist:** Neue Sessions klonen das Repo mit `git clone --depth 1`, also nur mit dem Branch main. Dabei fielen zwei Dinge auf:
- `git push --force-with-lease origin HEAD:<branch>` lehnte mit „stale info“ ab, weil es keine Remote-Tracking-Ref für den eigenen Branch gab. Deshalb hätte `merge.sh` den rebasten Branch nicht aktualisiert, und im CI-Weg wäre es mit „Branch-Push ging auch nicht“ abgebrochen.
- `git fetch origin <branch>` füllt dort nur FETCH_HEAD. `merge.sh --wait` hätte deshalb nie gesehen, dass die CI zusammengeführt hat.

**Regel:**
- Fetch mit voller Refspec: `git fetch origin "+refs/heads/X:refs/remotes/origin/X"`.
- Lease mit ausdrücklicher Erwartung: `--force-with-lease=refs/heads/X:<sha von ls-remote>`. `merge.sh` macht beides (`fetch_refs`, `push_branch`).
- Git-Abläufe in einer Sandbox mit flachem Klon testen, nicht nur mit vollem Klon.
