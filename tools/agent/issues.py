#!/usr/bin/env python3
"""Work with the in-game issues ("Meldungen") from an agent session.

Issues live in <data>/issues/<nnnn>-<slug>/ (see game/src/core/issue_store.gd). The game writes
issue.json + attachments once; afterwards both the player (in the game) and agents only APPEND to
verlauf.jsonl. The status is the "status" of the last thread entry that has one.

Agents claim an issue by creating claims/<n>/ atomically (mkdir); a claim is active until it is
released or its heartbeat is older than 6 hours. Nothing is ever deleted.

Where are the issues?  --dir, else $TT_ISSUES, else the first that exists of:
  $HOME/mnt/Tiefbau Tycoon/userdata/issues      (device shell on Jonathan's PC)
  <repo>/userdata/issues                          (portable data next to the repo)
  ~/.local/share/godot/app_userdata/Baustellen Manager/issues   (Linux, non-portable)

Usage (examples):
  issues.py list                     open issues, newest first, with claims
  issues.py next                     what to work on next (priority, unclaimed) + busy areas
  issues.py show 12                  everything about #12 (text, context, files, thread)
  issues.py claim 12 --session S --branch fix/12-kipper --areas site,vehicles
  issues.py heartbeat 12 --session S
  issues.py plan 12 --session S --text "Ursache …, Plan …"
  issues.py ask 12 --session S --text "Welcher Kipper?"          -> status Rückfrage
  issues.py fix 12 --session S --build "build/issue-12" --text "…" -> status bitte prüfen
  issues.py release 12 --session S --note "abgegeben"
  issues.py claims                   all active claims and their areas
  issues.py create --title "…" --text "…" --area verkehr --type fehler --session S
Exit codes: 0 ok, 2 claimed by someone else, 3 lost a claim race, 4 not found.
"""
import argparse, datetime, json, os, re, shutil, sys, time
from pathlib import Path

STALE_S = 6 * 3600
PRIO_ORDER = {"blockiert": 0, "hoch": 1, "normal": 2, "niedrig": 3}
AREAS = ["verkehr", "baustelle", "fahrzeuge", "karte", "oberflaeche", "grafik", "leistung", "wirtschaft", "sonstiges",
         "werkzeuge"]  # game/src/core/issue_store.gd AREAS (+ werkzeuge for repo/tooling work)
STATUS_TEXT = {"offen": "offen", "in_arbeit": "in Arbeit", "rueckfrage": "Rückfrage", "bitte_pruefen": "bitte prüfen",
               "erledigt": "erledigt", "abgelehnt": "abgelehnt"}


def find_dir(arg):
    if arg:
        return Path(arg)
    if os.environ.get("TT_ISSUES"):
        return Path(os.environ["TT_ISSUES"])
    here = Path(__file__).resolve().parents[2]
    cands = [Path.home() / "mnt" / "Tiefbau Tycoon" / "userdata" / "issues", here / "userdata" / "issues",
             Path.home() / ".local/share/godot/app_userdata/Baustellen Manager/issues"]
    for c in cands:
        if c.is_dir():
            return c
    for c in cands:  # no issue yet: the data folder exists, issues/ is created on the first write
        if c.parent.is_dir():
            return c
    sys.exit("Kein Issue-Ordner gefunden (--dir oder TT_ISSUES setzen)")


def now_iso():
    return datetime.datetime.now().astimezone().isoformat(timespec="seconds")


def read_json(p):
    try:
        return json.loads(Path(p).read_text(encoding="utf-8"))
    except Exception:
        return {}


def thread(folder):
    p = folder / "verlauf.jsonl"
    out = []
    if p.exists():
        for line in p.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line:
                try:
                    out.append(json.loads(line))
                except Exception:
                    pass
    return out


def status_of(th):
    st = "offen"
    for e in th:
        if "status" in e:
            st = e["status"]
    return st


def append(folder, entry):
    entry = {"t": now_iso(), **entry}
    with open(folder / "verlauf.jsonl", "a", encoding="utf-8") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")


def claims(folder):
    cdir = folder / "claims"
    if not cdir.is_dir():
        return []
    gens = sorted(int(d.name) for d in cdir.iterdir() if d.is_dir() and d.name.isdigit())
    return [(g, read_json(cdir / str(g) / "owner.json")) for g in gens]


def active_claim(folder):
    cl = claims(folder)
    if not cl:
        return None
    g, owner = cl[-1]
    if not owner:
        # mkdir done, owner.json not written yet (or unreadable): treat a fresh claim as taken
        try:
            age = time.time() - (folder / "claims" / str(g)).stat().st_mtime
        except OSError:
            age = 1e9
        return (g, {"session": "?", "branch": "?", "areas": [], "heartbeat_unix": time.time()}) if age < 120 else None
    if owner.get("released") or time.time() - owner.get("heartbeat_unix", 0) > STALE_S:
        return None
    return g, owner


def issues(root):
    out = []
    for d in sorted(root.iterdir()) if root.is_dir() else []:
        meta = read_json(d / "issue.json")
        if not meta:
            continue
        th = thread(d)
        ac = active_claim(d)
        out.append({"id": meta.get("id", 0), "folder": d, "meta": meta, "thread": th, "status": status_of(th),
                    "claim": ac[1] if ac else None})
    out.sort(key=lambda x: -x["id"])
    return out


def get(root, ident):
    ident = str(ident).lstrip("#")
    for it in issues(root):
        if str(it["id"]) == ident or it["folder"].name.startswith(ident):
            return it
    sys.exit(4)


def line(it):
    m = it["meta"]
    cl = it["claim"]
    return "#%-4d %-13s %-9s %-11s %-12s %s%s" % (
        it["id"], STATUS_TEXT.get(it["status"], it["status"]), m.get("priority", ""), m.get("area", ""),
        m.get("type", ""), m.get("title", ""), ("   [%s, %s]" % (cl.get("session"), ",".join(cl.get("areas", [])))) if cl else "")


def cmd_list(a, root):
    n = 0
    for it in issues(root):
        if not a.all and it["status"] in ("erledigt", "abgelehnt"):
            continue
        if a.status and it["status"] != a.status:
            continue
        print(line(it))
        n += 1
    if n == 0:
        print("Keine offenen Meldungen%s." % ("" if not a.all else " (auch keine erledigten)"))


def cmd_next(a, root):
    busy = [it for it in issues(root) if it["claim"]]
    if busy:
        print("Gerade in Arbeit (Bereiche meiden oder abstimmen):")
        for it in busy:
            print("  " + line(it))
    cand = [it for it in issues(root) if not it["claim"] and it["status"] == "offen"]
    cand.sort(key=lambda it: (PRIO_ORDER.get(it["meta"].get("priority", "normal"), 2), it["id"]))
    print("Vorschlag (Priorität, dann älteste zuerst):")
    for it in cand[:8]:
        print("  " + line(it))
    if not cand:
        print("  – nichts offen –")


def cmd_show(a, root):
    it = get(root, a.id)
    m, folder = it["meta"], it["folder"]
    if a.json:
        print(json.dumps({**m, "status": it["status"], "thread": it["thread"], "folder": str(folder)}, ensure_ascii=False, indent=1))
        return
    print(line(it))
    print("Ordner:", folder)
    print("Gemeldet: %s · Build %s · Herkunft %s" % (m.get("created"), (m.get("build") or {}).get("version") or "-", m.get("origin")))
    if (m.get("map") or {}).get("id"):
        print("Karte: %s (%s)" % (m["map"].get("name"), m["map"].get("id")))
    print("\n" + (m.get("text") or "(kein Text)") + "\n")
    if m.get("pins"):
        print("Stellen:", "; ".join("%d %s (x %.1f z %.1f)" % (i + 1, p.get("label"), p["x"], p["z"]) for i, p in enumerate(m["pins"])))
    if m.get("selection"):
        s = m["selection"]
        print("Auswahl:", s.get("kind"), s.get("name", s.get("title", "")), s.get("status", ""))
    if m.get("context"):
        print("Kontext:", json.dumps(m["context"], ensure_ascii=False)[:600])
    print("System:", json.dumps(m.get("system", {}), ensure_ascii=False))
    print("Dateien:", ", ".join(m.get("files", [])))
    print("\nVerlauf:")
    for e in it["thread"]:
        st = (" -> " + e["status"]) if "status" in e else ""
        print("  %s %s %s%s: %s" % (e.get("t", "")[:16], e.get("by", ""), e.get("kind", ""), st, e.get("text", "")))
        if e.get("files"):
            print("      Dateien:", ", ".join(e["files"]))


def cmd_claim(a, root):
    it = get(root, a.id)
    folder = it["folder"]
    ac = active_claim(folder)
    if ac and ac[1].get("session") != a.session:
        print("Schon in Arbeit bei %s (Branch %s, Herzschlag vor %d min)" % (
            ac[1].get("session"), ac[1].get("branch"), (time.time() - ac[1].get("heartbeat_unix", 0)) / 60))
        sys.exit(2)
    mine = [x for x in (a.areas or "").split(",") if x]
    for other in issues(root):
        c = other["claim"]
        if c and other["id"] != it["id"] and c.get("session") != a.session and set(mine) & set(c.get("areas", [])):
            print("WARNUNG: Bereich %s wird auch in #%d bearbeitet (%s, Branch %s) – klein committen, oft zusammenführen"
                  % (",".join(sorted(set(mine) & set(c.get("areas", [])))), other["id"], c.get("session"), c.get("branch")))
    gens = [g for g, _ in claims(folder)]
    nxt = (max(gens) + 1) if gens else 1
    try:
        os.makedirs(folder / "claims", exist_ok=True)
        os.mkdir(folder / "claims" / str(nxt))
    except FileExistsError:
        print("Jemand anderes war schneller.")
        sys.exit(3)
    owner = {"session": a.session, "branch": a.branch or "", "areas": [x for x in (a.areas or "").split(",") if x],
             "started": now_iso(), "heartbeat_unix": time.time(), "released": False}
    (folder / "claims" / str(nxt) / "owner.json").write_text(json.dumps(owner, ensure_ascii=False, indent=1), encoding="utf-8")
    append(folder, {"by": "agent:" + a.session, "kind": "status", "status": "in_arbeit",
                    "text": "Übernommen (Branch %s, Bereiche: %s)" % (a.branch or "-", a.areas or "-")})
    print("OK: #%d gehört jetzt %s" % (it["id"], a.session))


def _own_claim(folder, session):
    ac = active_claim(folder)
    if not ac or ac[1].get("session") != session:
        return None
    return ac


def cmd_heartbeat(a, root):
    it = get(root, a.id)
    ac = _own_claim(it["folder"], a.session)
    if not ac:
        sys.exit("Keine aktive Übernahme von %s für #%d" % (a.session, it["id"]))
    g, owner = ac
    owner["heartbeat_unix"] = time.time()
    (it["folder"] / "claims" / str(g) / "owner.json").write_text(json.dumps(owner, ensure_ascii=False, indent=1), encoding="utf-8")
    print("OK")


def cmd_release(a, root):
    it = get(root, a.id)
    ac = _own_claim(it["folder"], a.session)
    if ac:
        g, owner = ac
        owner["released"] = True
        owner["released_at"] = now_iso()
        (it["folder"] / "claims" / str(g) / "owner.json").write_text(json.dumps(owner, ensure_ascii=False, indent=1), encoding="utf-8")
    entry = {"by": "agent:" + a.session, "kind": "comment", "text": a.note or "Arbeit abgegeben"}
    if it["status"] == "in_arbeit":
        entry["status"] = "offen"
    append(it["folder"], entry)
    print("OK")


def _entry(a, root, kind, status=None, extra=None):
    it = get(root, a.id)
    e = {"by": "agent:" + a.session, "kind": kind, "text": a.text}
    if status:
        e["status"] = status
    if extra:
        e.update(extra)
    files = []
    for f in getattr(a, "file", None) or []:
        src = Path(f)
        dst = it["folder"] / src.name
        if src.resolve() != dst.resolve():
            k = 1
            while dst.exists():  # never overwrite the player's attachments (bild_1.png …)
                dst = it["folder"] / ("agent_%d_%s" % (k, src.name))
                k += 1
            shutil.copyfile(src, dst)
        files.append(dst.name)
    if files:
        e["files"] = files
    append(it["folder"], e)
    print("OK: #%d %s%s" % (it["id"], kind, (" -> " + status) if status else ""))


def cmd_claims(a, root):
    any_ = False
    for it in issues(root):
        if it["claim"]:
            any_ = True
            c = it["claim"]
            print("#%-4d %-24s Branch %-28s Bereiche %-24s seit %s" % (it["id"], c.get("session"), c.get("branch"),
                  ",".join(c.get("areas", [])), c.get("started", "")[:16]))
    if not any_:
        print("Keine aktiven Übernahmen.")


def cmd_create(a, root):
    ids = [int(d.name.split("-")[0]) for d in root.iterdir() if d.is_dir() and d.name.split("-")[0].isdigit()] if root.is_dir() else []
    nid = (max(ids) + 1) if ids else 1
    slug = re.sub(r"[^a-z0-9]+", "-", a.title.lower().replace("ä", "ae").replace("ö", "oe").replace("ü", "ue").replace("ß", "ss")).strip("-")[:40]
    folder = root / ("%04d-%s" % (nid, slug))
    while True:
        try:
            os.makedirs(folder)
            break
        except FileExistsError:
            nid += 1
            folder = root / ("%04d-%s" % (nid, slug))
    meta = {"id": nid, "title": a.title, "text": a.text, "type": a.type, "area": a.area, "priority": a.priority,
            "origin": "agent", "created": now_iso(), "files": [], "pins": [], "camera": {}, "build": {}, "map": {}}
    (folder / "issue.json").write_text(json.dumps(meta, ensure_ascii=False, indent=1), encoding="utf-8")
    (folder / "beschreibung.md").write_text("# %s\n\n%s\n" % (a.title, a.text), encoding="utf-8")
    append(folder, {"by": "agent:" + a.session, "kind": "status", "status": "offen", "text": "Von einem Agenten angelegt"})
    print("OK: #%d %s" % (nid, folder))


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--dir")
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("list"); s.add_argument("--all", action="store_true"); s.add_argument("--status")
    sub.add_parser("next")
    sub.add_parser("claims")
    s = sub.add_parser("show"); s.add_argument("id"); s.add_argument("--json", action="store_true")
    s = sub.add_parser("claim"); s.add_argument("id"); s.add_argument("--session", required=True); s.add_argument("--branch"); s.add_argument("--areas")
    s = sub.add_parser("heartbeat"); s.add_argument("id"); s.add_argument("--session", required=True)
    s = sub.add_parser("release"); s.add_argument("id"); s.add_argument("--session", required=True); s.add_argument("--note")
    for name in ["comment", "plan", "ask"]:
        s = sub.add_parser(name); s.add_argument("id"); s.add_argument("--session", required=True); s.add_argument("--text", required=True)
        s.add_argument("--file", action="append")
    s = sub.add_parser("status"); s.add_argument("id"); s.add_argument("status", choices=list(STATUS_TEXT)); s.add_argument("--session", required=True); s.add_argument("--text", default="")
    s = sub.add_parser("fix"); s.add_argument("id"); s.add_argument("--session", required=True); s.add_argument("--build", required=True)
    s.add_argument("--text", required=True); s.add_argument("--commit", default=""); s.add_argument("--file", action="append")
    s = sub.add_parser("create"); s.add_argument("--title", required=True); s.add_argument("--text", default=""); s.add_argument("--session", required=True)
    s.add_argument("--area", default="sonstiges", choices=AREAS)
    s.add_argument("--type", default="aufgabe", choices=["fehler", "wunsch", "verbesserung", "aufgabe"])
    s.add_argument("--priority", default="normal", choices=list(PRIO_ORDER))
    a = p.parse_args()
    root = find_dir(a.dir)
    if a.cmd == "create":
        root.mkdir(parents=True, exist_ok=True)
    {"list": cmd_list, "next": cmd_next, "claims": cmd_claims, "show": cmd_show, "claim": cmd_claim,
     "heartbeat": cmd_heartbeat, "release": cmd_release, "create": cmd_create,
     "comment": lambda a, r: _entry(a, r, "comment"), "plan": lambda a, r: _entry(a, r, "plan"),
     "ask": lambda a, r: _entry(a, r, "question", "rueckfrage"),
     "status": lambda a, r: _entry(a, r, "status", a.status),
     "fix": lambda a, r: _entry(a, r, "fix", "bitte_pruefen", {"build": a.build, "commit": a.commit}),
     }[a.cmd](a, root)


if __name__ == "__main__":
    main()
