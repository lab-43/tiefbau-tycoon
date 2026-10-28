#!/usr/bin/env python3
"""Project rules that came out of real mistakes (see docs/lessons/). Run before every commit:

    python3 tools/lint.py            # whole repo
    python3 tools/lint.py --staged   # additionally checks what is staged for the next commit

Each rule names the lesson it comes from. A line can opt out of a code rule with "# lint-ok: <reason>".
Exit code 1 if any ERROR was found (warnings do not fail).

Add a rule here whenever a lesson can be checked mechanically (skill "lernen").
"""
import re, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Never in Git (private use only: Construction Simulator / FS25 material and the extraction tools).
PRIVATE = [r"^game/assets/consim/", r"^game/assets/barriers/", r"^tools/consim_extract/", r"^tools/fs-i3d/",
           r"^docs/consim_assets.*\.png$", r"^private/", r"\.pck$", r"\.exe$", r"^userdata/", r"^build/"]
MAX_FILE_MB = 20
ALLOWED_MAIL = {"noreply@anthropic.com"}
MAIL_RE = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\.[A-Za-z0-9.-]*[a-z]{2,}")
LESSON_KEYS = ["titel", "bereich", "datum", "pruefung"]

problems = []  # (level, where, text, lesson)


def report(level, where, text, lesson):
    problems.append((level, where, text, lesson))


def git(*args):
    r = subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True, text=True)
    return [l for l in r.stdout.splitlines() if l.strip()] if r.returncode == 0 else None


def tracked_files():
    # tracked + untracked-but-not-ignored = everything "git add -A" would commit
    files = git("ls-files", "--cached", "--others", "--exclude-standard")
    if files is None:  # not a git checkout (e.g. a plain copy): lint what is there
        files = [str(p.relative_to(ROOT)) for p in ROOT.rglob("*") if p.is_file()
                 and not any(part.startswith(".") and part not in (".claude", ".github") for part in p.relative_to(ROOT).parts)]
    return files


def check_private(files, label):
    for f in files:
        for pat in PRIVATE:
            if re.search(pat, f):
                report("ERROR", f, f"privater/erzeugter Pfad ist {label} – gehört nicht ins Git", "privat-assets")
        if f.endswith("override.cfg"):
            report("ERROR", f, "override.cfg im Repo – Engine-Einstellungen mit Pfaden brechen auf anderen PCs", "kein-override-cfg")
        p = ROOT / f
        if p.is_file() and p.stat().st_size > MAX_FILE_MB * 1024 * 1024:
            report("ERROR", f, f"Datei größer als {MAX_FILE_MB} MB {label}", "privat-assets")


def check_modes():
    """Scripts that are called directly must be executable in git (fresh clones)."""
    for l in git("ls-files", "-s") or []:
        mode, _, _, path = l.split(None, 3)
        if (path.endswith(".sh") or path.startswith("tools/agent/") and path.endswith(".py")) and mode != "100755":
            report("ERROR", path, "nicht ausführbar im Git (git update-index --chmod=+x %s)" % path, "skripte-ausfuehrbar")


def check_author():
    """The next commit must not carry a private address (agent commits go to GitHub)."""
    ident = subprocess.run(["git", "-C", str(ROOT), "var", "GIT_AUTHOR_IDENT"], capture_output=True, text=True).stdout
    m = re.search(r"<([^>]*)>", ident)
    mail = m.group(1) if m else ""
    if mail and mail.lower() not in ALLOWED_MAIL and not mail.endswith("users.noreply.github.com"):
        report("ERROR", ".git/config", "Commit-Autor hat eine private Adresse – git config user.email noreply@anthropic.com",
               "keine-mail")


def check_gd(path, rel, lines):
    for i, line in enumerate(lines, 1):
        code = line.split("#", 1)[0] if not line.lstrip().startswith("#") else ""
        ok = "lint-ok" in line
        if ok:
            continue
        if re.search(r"use_threads\s*=\s*true", code):
            report("ERROR", f"{rel}:{i}", "HTTPRequest.use_threads = true blockiert beim Abbrechen den Hauptthread", "http-ohne-threads")
        if '"user://' in code and rel != "game/src/core/game.gd":
            report("ERROR", f"{rel}:{i}", "user:// direkt benutzt – Game.data_path() nehmen (portabler Modus)", "datenordner-portabel")
        if "set_anchors_preset(" in code:
            nxt = "".join(lines[i:i + 4])
            if "offset_" not in nxt:
                report("WARN", f"{rel}:{i}", "set_anchors_preset() lässt die Offsets stehen – set_anchors_and_offsets_preset() oder Offsets setzen", "ui-anker")
        if re.search(r"Program Files|steamapps", line):
            report("ERROR", f"{rel}:{i}", "Pfad in den Steam-Spielordner – dort wird nie geschrieben", "privat-assets")


GENERATED = ("build/", "userdata/", "private/", "game/.godot", "game/build_info.json", "game/assets/consim",
             "game/assets/barriers", "/tmp")


def check_refs(rel, lines, tracked):
    """Files a script uses via $ROOT/<path> must be in git, or a fresh clone breaks (lesson gitignore-anker)."""
    for i, line in enumerate(lines, 1):
        for m in re.finditer(r'\$ROOT/([A-Za-z0-9_./-]+)', line):
            path = m.group(1).rstrip("./")
            if not path or "$" in path or path.startswith(GENERATED) or "lint-ok" in line:
                continue
            if path not in tracked and not any(t.startswith(path + "/") for t in tracked):
                report("ERROR", f"{rel}:{i}", f"benutzt {path}, das nicht im Git ist (.gitignore?)", "gitignore-anker")


def check_sh(path, rel, lines):
    for i, line in enumerate(lines, 1):
        if "lint-ok" in line:
            continue
        m = re.search(r"pkill\s+-f\s+[\"']?([^\"'\s]+)", line)
        if m and "[" not in m.group(1):
            report("WARN", f"{rel}:{i}", "pkill -f ohne [x]-Muster trifft auch die eigene Shell", "pkill-muster")
        if re.search(r"Program Files \(x86\)/Steam|steamapps/common", line) and re.search(r"(>|cp |mv |rm |tee )", line):
            report("ERROR", f"{rel}:{i}", "Schreibzugriff auf den Steam-Spielordner", "privat-assets")


def check_text(rel, text):
    for m in MAIL_RE.finditer(text):
        mail = m.group(0)
        if mail.lower() in ALLOWED_MAIL or mail.endswith((".png", ".svg", ".glb", ".gd")):
            continue
        line = text.count("\n", 0, m.start()) + 1
        report("ERROR", f"{rel}:{line}", f"E-Mail-Adresse im Repo ({mail}) – private Adressen gehören nicht hierher", "keine-mail")


def check_yaml(rel, text):
    try:
        import yaml  # optional; CI runners and most sessions have PyYAML
    except ImportError:
        return
    try:
        yaml.safe_load(text)
    except yaml.YAMLError as e:
        report("ERROR", rel, "YAML kaputt: " + str(e).replace("\n", " ")[:160], "yaml-gueltig")


def check_lesson(rel, text):
    if not text.startswith("---"):
        report("ERROR", rel, "Lektion ohne Frontmatter (---)", "lernen")
        return
    head = text.split("---", 2)[1] if text.count("---") >= 2 else ""
    for k in LESSON_KEYS:
        if not re.search(rf"^{k}:\s*\S", head, re.M):
            report("ERROR", rel, f"Lektion ohne Feld '{k}'", "lernen")


def main():
    staged = "--staged" in sys.argv
    files = tracked_files()
    tracked = set(files)
    check_private(files, "im Git")
    check_modes()
    if staged:
        check_author()
        st = git("diff", "--cached", "--name-only", "--diff-filter=AM") or []
        check_private(st, "zum Commit vorgemerkt")
        files = sorted(set(files) | set(st))
    for rel in files:
        p = ROOT / rel
        if not p.is_file() or p.stat().st_size > 2_000_000:
            continue
        if p.suffix in (".gd", ".sh", ".py", ".md", ".cfg", ".json", ".yml", ".yaml", ".txt", ".cmd", ".tscn", ".godot"):
            try:
                text = p.read_text(encoding="utf-8")
            except UnicodeDecodeError:
                continue
            if not rel.startswith("game/test_fixtures/"):
                check_text(rel, text)
            lines = text.splitlines(keepends=True)
            if p.suffix == ".gd":
                check_gd(p, rel, lines)
            elif p.suffix == ".sh":
                check_sh(p, rel, lines)
                check_refs(rel, lines, tracked)
            if p.suffix in (".yml", ".yaml"):
                check_yaml(rel, text)
            if rel.startswith("docs/lessons/") and p.suffix == ".md" and p.name != "README.md":
                check_lesson(rel, text)
    errors = [x for x in problems if x[0] == "ERROR"]
    for level, where, text, lesson in sorted(problems, key=lambda x: (x[0] != "ERROR", x[1])):
        print(f"{level:5} {where}: {text}  [Lektion: {lesson}]")
    print(f"lint: {len(errors)} Fehler, {len(problems) - len(errors)} Warnungen")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
