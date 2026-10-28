# Tiefbau Tycoon – Baustellen Manager

Privates Tiefbau-/Straßenbau-Tycoon-Spiel auf echten OpenStreetMap-Karten. Godot 4.5.1, GDScript.

**Nur privat:** Die Fahrzeug-, Maschinen- und Absperrmodelle stammen aus Construction Simulator und einem FS25-Mod. Sie sind **nicht** in diesem Repository (siehe `.gitignore`) und dürfen nicht weitergegeben werden.

## Spielen

`build/main/BaustellenManager.exe` starten (wird von den Agent-Sessions geliefert, nicht im Git).

- **Testversionen** zu Meldungen liegen in `build/issue-<nr>/`. Start mit `Starten.cmd`.
- **Spielstände, Karten, Meldungen und Protokolle** liegen gemeinsam in `userdata/`.
- **Probleme oder Wünsche:** im Spiel **F8** drücken. Die Meldung landet in `userdata/issues/`, Agenten arbeiten sie ab. Rückfragen und Testbitten erscheinen unter „Meldungen“.

## Einmalig: auf GitHub bringen

1. Auf GitHub ein **leeres, privates** Repository anlegen, z. B. `tiefbau-tycoon`. Ohne README, .gitignore oder Lizenz.
2. Im Ordner `Tiefbau Tycoon` (Git Bash oder Terminal):
   ```
   git remote add origin https://github.com/<dein-name>/tiefbau-tycoon.git
   git push -u origin main --tags
   ```
3. Neue Claude-Sessions mit diesem Repository starten. Für Meldungen, Assets und Builds muss die Session mit dem PC verknüpft sein; dafür muss die Claude-Desktop-App laufen.

## Entwickeln

Die Arbeit erledigen Claude-Sessions; Regeln und Abläufe stehen in `CLAUDE.md` und `.claude/skills/`. Kurz:

- **Neue Session:** `tools/setup_env.sh`, dann Assets vom PC holen (Skill `tycoon-dev`).
- **Prüfen:** `python3 tools/lint.py && tools/check.sh`
- **Testen:** `cd game && godot --headless --path . -- --autostart --fixture=utrecht --e2e=job`
- **Bauen:** `tools/build.sh build/out`

Lizenz der Kartendaten: © OpenStreetMap-Mitwirkende (ODbL). Schrift Inter (OFL), Icons Lucide (ISC).

### Optional: Lagebericht automatisch beim Sitzungsstart

Jede Session führt laut `CLAUDE.md` zuerst `bash tools/agent/session_start.sh` aus. Wer das erzwingen möchte, legt `.claude/settings.json` mit diesem Inhalt an:

```json
{
  "hooks": {
    "SessionStart": [
      { "hooks": [ { "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/tools/agent/session_start.sh\"", "timeout": 30 } ] }
    ]
  }
}
```

Die Agenten haben diese Datei absichtlich nicht selbst angelegt, weil sie ihre eigenen Einstellungen ändern würde.
