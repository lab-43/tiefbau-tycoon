---
titel: Bringt eine andere Session neue Modelle, die privaten Assets vom PC neu holen und importieren – sonst scheitern fremde Szenarien und der Build passt nicht zum Daten-pck
bereich: build
datum: 2026-10-29
pruefung: manuell: vor Zusammenführen und Build `ls game/assets/consim` mit `private/assets.tar` auf dem PC vergleichen, `daten=` in build/main/VERSION.txt mit dem eigenen daten.hash
---

**Was passiert ist:** Beim Zusammenführen von #22 schlug das Szenario `fahrzeuge` fehl („tractor_nooteboom: 15 Lichtmarker an der Oberfläche, weitester 0,264 m“). Mein Arbeitsordner hatte die Assets vom Sitzungsbeginn. Inzwischen hatte #24 neue Modelle (R 938, S 550, Nooteboom, Bäume, Kipper mit Kran) in `private/assets.tar` gelegt und das Daten-pck auf dem PC erneuert (`daten=3a512aa3d18ac46b`). Nach dem Auspacken des neuen Archivs kam zunächst „Failed loading resource … trailer_nooteboom.glb“, erst `godot --headless --path game --import` behob das. Danach war `fahrzeuge` grün.

**Ursache:** Private Assets liegen nicht im Git. Ein Rebase bringt den Code einer anderen Session, aber nicht ihre Modelle. Der Code erwartet sie dann.

**Regel:**
- Taucht nach einem Rebase ein Szenario einer anderen Session auf, das mit Modellen arbeitet, oder ändert sich `daten=` in `build/main/VERSION.txt` auf dem PC: `private/assets.tar` neu holen (`device_stage_files`), in jeden eigenen Arbeitsordner auspacken, dann `godot --headless --path game --import`.
- Vor dem Build für `build/main` den Daten-Hash vergleichen (Befehl in `tools/build.sh`). Nur wenn er gleich ist, reicht es, das Code-pck zu übertragen.
- Mehrere Arbeitsordner (git worktree) brauchen eine eigene Kopie der Assets, keinen Symlink. Git sieht einen Symlink nicht als ignorierten Ordner (`.gitignore` mit `/` am Ende greift nicht). Mit Symlinks fehlten im Test außerdem die Verkehrsmodelle (Skriptfehler in `traffic_models.gd`, Ursache nicht weiter untersucht).
