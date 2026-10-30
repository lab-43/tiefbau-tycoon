---
titel: Wird Geometrie gestaucht, kann eine Teilezahl 1 werden – „/ (n - 1)“ ergibt dann NaN, und eine NaN-Position legt den Ablauf still
bereich: baustelle
datum: 2026-10-30
pruefung: lint:teilen-durch-null-teile, e2e:platzieren (NaN-Suche bei Verkehr, Kolonne, Absperrteilen, Fahrzeugen)
---

**Was passiert ist:** Mit #33 staucht sich die Absperr-Vorlage an Kreuzungen. Die Verziehung vor der Grube war auf einer Hamburger Wohnstraße nur 0,5 m lang. `SiteLayout.items()` berechnete die Zahl der Leitbaken als `clampi(int(länge / 3) + 1, 0 if länge < 0.5 else 2, 5)`. Bei 0,49999 m wurde daraus 1, und `float(i) / (n_taper - 1)` war 0/0. Eine Leitbake bekam die Position (nan, nan). Der Arbeiter, der sie trug, lief dorthin und stand danach selbst auf NaN. Die Absperrung blieb bei 96 % stehen, und das Log füllte sich mit 365.000 Zeilen `Condition "!v.is_finite()" is true`.

**Ursache:** Die Formel stammt aus dem festen Schema, in dem die Verziehung immer 12 m lang war und `n_taper` immer 5. Erst die freie Platzierung machte Längen um 0 möglich. Ein Vergleich `< 0.5` an der Grenze reicht nicht, um `n = 1` auszuschließen.

**Regel:**
- Abstände über eine Zahl von Teilen immer mit `maxf(1, n - 1)` teilen oder `n` so festlegen, dass es nur 0 oder ≥ 2 sein kann. `tools/lint.py` warnt bei `/ (n - 1)`. Bleibt `n` sicher ≥ 2 (z. B. ein Raster), mit `# lint-ok` begründen.
- Lange e2e-Szenarien suchen NaN aktiv (`e2e_platzieren.gd`, `_nan_check`). Eine NaN-Position meldet Godot nur als Engine-Fehler, nicht als `SCRIPT ERROR`.
- Wer eine Vorlage stauchen lässt, testet die kürzeste erlaubte Form bis zum Ende, nicht nur die normale.
