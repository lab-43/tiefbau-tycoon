#!/usr/bin/env python3
"""Work with the in-game issues ("Meldungen") from an agent session. Runs with Python >= 3.8
(Jonathan's PC shell has 3.10). Run it in the device shell on the PC: only there are claims atomic.

Issues live in <data>/issues/<nnnn>-<slug>/ (see game/src/core/issue_store.gd). The game writes
issue.json + attachments once; afterwards both the player (in the game) and agents only APPEND to
verlauf.jsonl. The status is the "status" of the last thread entry that has one.

Claims (who works on an issue) and locks (e.g. "build-main") use the same scheme, nothing is ever
rewritten or deleted (deleting needs extra rights on the PC mount):
  claims/<n>/            created atomically with mkdir; the highest <n> is the current claim
  claims/<n>/owner.json  written once: session, branch, areas, started, heartbeat_unix
  claims/<n>/herzschlag  appended on every heartbeat/entry of the owner (its mtime = last sign of life)
  claims/<n>/freigegeben created on release
A claim is active until released or 6 h without heartbeat (locks: 30 min).
Issue ids are reserved atomically with mkdir <issues>/.ids/<n> (the game does the same).

Where are the issues?  --dir, else $TT_ISSUES, else the first data folder that exists of:
  $HOME/mnt/Tiefbau Tycoon/userdata      (device shell on Jonathan's PC)
  <folder above tools/ or .agent/>/userdata

Usage (examples, S = your session id):
  issues.py next                     what to work on next (priority, unclaimed) + busy areas
  issues.py list [--all]             issues, newest first, with claims
  issues.py show 12 [--json]         everything about #12 (text, context, files, thread)
  issues.py claim 12 --session S --branch issue/12-kipper --areas baustelle,fahrzeuge
  issues.py plan 12 --session S --text "Ursache …, Plan …"
  issues.py ask 12 --session S --text "Welcher Kipper?"            -> status rueckfrage
  issues.py fix 12 --session S --build build/main --commit abc --text "…"   -> status bitte_pruefen
  issues.py comment 12 --session S --text "…"                      (no claim needed)
  issues.py heartbeat 12 --session S
  issues.py release 12 --session S --note "abgegeben"
  issues.py claims                   all active claims and their areas
  issues.py create --session S --type aufgabe --area verkehr --title "…" --text "…"
  issues.py lock build-main --session S [--note …]  /  issues.py unlock build-main --session S
  issues.py --version
Exit codes: 0 ok, 2 claimed/locked by someone else or not your claim, 3 lost a race, 4 not found.
"""
import argparse, datetime, json, os, re, secrets, shutil, sys, time
from pathlib import Path

VERSION = 3          # bump on every change; sessions only replace an older agent copy on the PC
STALE_S = 6 * 3600
LOCK_STALE_S = 30 * 60
PENDING_S = 30 * 60  # claim folder without readable owner.json counts as taken this long
PRIO_ORDER = {"blockiert": 0, "hoch": 1, "normal": 2, "niedrig": 3}
AREAS = ["verkehr", "baustelle", "fahrzeuge", "karte", "oberflaeche", "grafik", "leistung", "wirtschaft", "sonstiges",
         "werkzeuge"]  # game/src/core/issue_store.gd AREAS (+ werkzeuge for repo/tooling work)
STATUS_TEXT = {"offen": "offen", "in_arbeit": "in Arbeit", "rueckfrage": "Rückfrage", "bitte_pruefen": "bitte prüfen",
               "erledigt": "erledigt", "abgelehnt": "abgelehnt"}
NEEDS_CLAIM = {"question", "plan", "fix", "status"}


def data_dir():
    here = Path(__file__).resolve().parent
    cands = [Path.home() / "mnt" / "Tiefbau Tycoon" / "userdata"]
    for up in [here.parent.parent, here.parent]:  # repo/tools/agent -> repo ; userdata/.agent -> userdata/..
        cands.append(up / "userdata")
    for c in cands:
        if c.is_dir():
            return c
    sys.exit("Kein Datenordner gefunden (userdata). --dir <issues-ordner> oder TT_ISSUES setzen.")


def find_dir(arg):
    if arg:
        return Path(arg)
    if os.environ.get("TT_ISSUES"):
        return Path(os.environ["TT_ISSUES"])
    return data_dir() / "issues"


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
        for line in p.read_text(encoding="utf-8", errors="replace").splitlines():
            line = line.strip()
            if line:
                try:
                    e = json.loads(line)
                    if isinstance(e, dict):
                        out.append(e)
                except Exception:
                    pass  # a line damaged by a concurrent writer; its author re-appends it
    return out


def status_of(th):
    st = "offen"
    for e in th:
        if "status" in e:
            st = e["status"]
    return st


def append(folder, entry):
    """Append one line (O_APPEND) and verify it landed: the game appends with seek+write, which can
    clobber a line written at the very same moment; then the entry is written again."""
    entry = {"t": now_iso(), "eid": secrets.token_hex(4), **entry}
    line = json.dumps(entry, ensure_ascii=False) + "\n"
    p = folder / "verlauf.jsonl"
    for attempt in range(4):
        with open(p, "a", encoding="utf-8") as f:
            f.write(line)
        time.sleep(0.05)
        if any(e.get("eid") == entry["eid"] for e in thread(folder)[-50:]):
            return
    print("WARNUNG: Eintrag im Verlauf nicht wiedergefunden: %s" % p, file=sys.stderr)


# --- claims and locks -------------------------------------------------------------------------

def gens(cdir):
    if not cdir.is_dir():
        return []
    return sorted(int(d.name) for d in cdir.iterdir() if d.is_dir() and d.name.isdigit())


def claim_state(cdir, g, stale):
    """(active, owner) for claim folder cdir/g."""
    d = cdir / str(g)
    owner = read_json(d / "owner.json")
    if (d / "freigegeben").exists():
        return False, owner
    try:
        hb = max(d.stat().st_mtime, (d / "herzschlag").stat().st_mtime if (d / "herzschlag").exists() else 0)
    except OSError:
        return False, owner
    if not owner:  # just created (owner.json not written yet) or broken: taken for a while
        return time.time() - hb < PENDING_S, {"session": "?", "branch": "?", "areas": [], "heartbeat_unix": hb}
    hb = max(hb, float(owner.get("heartbeat_unix", 0)))
    owner["heartbeat_unix"] = hb
    return (not owner.get("released")) and time.time() - hb < stale, owner


def current(cdir, stale):
    """(listed generations, active (g, owner) or None) from ONE directory listing."""
    gl = gens(cdir)
    if not gl:
        return gl, None
    act, owner = claim_state(cdir, gl[-1], stale)
    return gl, ((gl[-1], owner) if act else None)


def take(cdir, gl, session, info):
    """Create the next generation after the listed one. A concurrent taker gets FileExistsError."""
    nxt = (gl[-1] + 1) if gl else 1
    os.makedirs(cdir, exist_ok=True)
    try:
        os.mkdir(cdir / str(nxt))
    except FileExistsError:
        return None
    owner = {"session": session, "started": now_iso(), "heartbeat_unix": time.time(), **info}
    (cdir / str(nxt) / "owner.json").write_text(json.dumps(owner, ensure_ascii=False, indent=1), encoding="utf-8")
    return nxt


def beat(cdir, g):
    with open(cdir / str(g) / "herzschlag", "a", encoding="utf-8") as f:
        f.write("%.0f\n" % time.time())


def free(cdir, g, note):
    with open(cdir / str(g) / "freigegeben", "a", encoding="utf-8") as f:
        f.write(json.dumps({"t": now_iso(), "note": note or ""}, ensure_ascii=False) + "\n")


def active_claim(folder):
    return current(folder / "claims", STALE_S)[1]


def own_claim(folder, session):
    ac = active_claim(folder)
    return ac if ac and ac[1].get("session") == session else None


# --- issues -----------------------------------------------------------------------------------

def issues(root):
    out = []
    for d in sorted(root.iterdir()) if root.is_dir() else []:
        if not d.is_dir() or d.name.startswith("."):
            continue
        meta = read_json(d / "issue.json")
        if not meta:
            continue
        th = thread(d)
        ac = active_claim(d)
        out.append({"id": int(meta.get("id", 0) or 0), "folder": d, "meta": meta, "thread": th, "status": status_of(th),
                    "claim": ac[1] if ac else None})
    out.sort(key=lambda x: -x["id"])
    return out


def get(root, ident):
    ident = str(ident).lstrip("#")
    for it in issues(root):
        if str(it["id"]) == ident or it["folder"].name.startswith(ident):
            return it
    print("Meldung %s nicht gefunden in %s" % (ident, root), file=sys.stderr)
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
    all_ = issues(root)
    busy = [it for it in all_ if it["claim"]]
    if busy:
        print("Gerade in Arbeit (Bereiche meiden oder abstimmen):")
        for it in busy:
            print("  " + line(it))
    cand = [it for it in all_ if not it["claim"] and it["status"] == "offen"]
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
        print(json.dumps({**m, "status": it["status"], "claim": it["claim"], "thread": it["thread"], "folder": str(folder)},
                         ensure_ascii=False, indent=1))
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
    print("Dateien:", ", ".join(sorted(p.name for p in folder.iterdir() if p.is_file())))
    print("\nVerlauf:")
    for e in it["thread"]:
        st = (" -> " + e["status"]) if "status" in e else ""
        print("  %s %s %s%s: %s" % (str(e.get("t", ""))[:16], e.get("by", ""), e.get("kind", ""), st, e.get("text", "")))
        if e.get("files"):
            print("      Dateien:", ", ".join(e["files"]))


def cmd_claim(a, root):
    it = get(root, a.id)
    folder = it["folder"]
    cdir = folder / "claims"
    gl, ac = current(cdir, STALE_S)
    if ac and ac[1].get("session") != a.session:
        print("Schon in Arbeit bei %s (Branch %s, Herzschlag vor %d min)" % (
            ac[1].get("session"), ac[1].get("branch"), (time.time() - ac[1].get("heartbeat_unix", 0)) / 60))
        sys.exit(2)
    if ac:
        beat(cdir, ac[0])
        print("OK: #%d gehört schon %s" % (it["id"], a.session))
        return
    areas = [x for x in (a.areas or "").split(",") if x]
    g = take(cdir, gl, a.session, {"branch": a.branch or "", "areas": areas})
    if g is None:
        print("Jemand anderes war schneller.")
        sys.exit(3)
    for other in issues(root):
        c = other["claim"]
        if c and other["id"] != it["id"] and c.get("session") != a.session and set(areas) & set(c.get("areas", [])):
            print("WARNUNG: Bereich %s wird auch in #%d bearbeitet (%s, Branch %s) – klein committen, oft zusammenführen"
                  % (",".join(sorted(set(areas) & set(c.get("areas", [])))), other["id"], c.get("session"), c.get("branch")))
    append(folder, {"by": "agent:" + a.session, "kind": "status", "status": "in_arbeit",
                    "text": "Übernommen (Branch %s, Bereiche: %s)" % (a.branch or "-", a.areas or "-")})
    print("OK: #%d gehört jetzt %s" % (it["id"], a.session))


def _need_own(it, session):
    ac = own_claim(it["folder"], session)
    if not ac:
        print("#%d ist nicht von %s übernommen (erst: issues.py claim %d --session %s …)" % (it["id"], session, it["id"], session),
              file=sys.stderr)
        sys.exit(2)
    return ac


def cmd_heartbeat(a, root):
    it = get(root, a.id)
    g, _ = _need_own(it, a.session)
    beat(it["folder"] / "claims", g)
    print("OK")


def cmd_release(a, root):
    it = get(root, a.id)
    g, _ = _need_own(it, a.session)
    free(it["folder"] / "claims", g, a.note)
    entry = {"by": "agent:" + a.session, "kind": "comment", "text": a.note or "Arbeit abgegeben"}
    if it["status"] == "in_arbeit":
        entry["status"] = "offen"
    append(it["folder"], entry)
    print("OK")


def _entry(a, root, kind, status=None, extra=None):
    it = get(root, a.id)
    if kind in NEEDS_CLAIM:
        g, _ = _need_own(it, a.session)
        beat(it["folder"] / "claims", g)
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
                  ",".join(c.get("areas", [])), str(c.get("started", ""))[:16]))
    if not any_:
        print("Keine aktiven Übernahmen.")
    ldir = root.parent / "locks"
    for name in sorted(p.name for p in ldir.iterdir()) if ldir.is_dir() else []:
        _, ac = current(ldir / name, LOCK_STALE_S)
        if ac:
            print("Sperre %-12s %s seit %s %s" % (name, ac[1].get("session"), str(ac[1].get("started", ""))[:16], ac[1].get("note", "")))


def reserve_id(root):
    """Next free issue id, reserved with mkdir <root>/.ids/<n> (atomic; the game does the same)."""
    ids = root / ".ids"
    os.makedirs(ids, exist_ok=True)
    used = [int(d.name.split("-")[0]) for d in root.iterdir() if d.is_dir() and d.name.split("-")[0].isdigit()]
    used += [int(d.name) for d in ids.iterdir() if d.name.isdigit()]
    n = (max(used) + 1) if used else 1
    while True:
        try:
            os.mkdir(ids / str(n))
            return n
        except FileExistsError:
            n += 1


def cmd_create(a, root):
    root.mkdir(parents=True, exist_ok=True)
    slug = re.sub(r"[^a-z0-9]+", "-", a.title.lower().replace("ä", "ae").replace("ö", "oe").replace("ü", "ue").replace("ß", "ss")).strip("-")[:40]
    while True:
        nid = reserve_id(root)
        folder = root / ("%04d-%s" % (nid, slug or "meldung"))
        try:
            os.makedirs(folder)
            break
        except FileExistsError:
            continue
    append(folder, {"by": "agent:" + a.session, "kind": "status", "status": "offen", "text": "Von einem Agenten angelegt"})
    (folder / "beschreibung.md").write_text("# %s\n\n%s\n" % (a.title, a.text), encoding="utf-8")
    meta = {"id": nid, "title": a.title, "text": a.text, "type": a.type, "area": a.area, "priority": a.priority,
            "origin": "agent", "created": now_iso(), "files": [], "pins": [], "camera": {}, "build": {}, "map": {}}
    # issue.json last: folders without it are invisible (half-written)
    (folder / "issue.json").write_text(json.dumps(meta, ensure_ascii=False, indent=1), encoding="utf-8")
    print("OK: #%d %s" % (nid, folder))


def cmd_lock(a, root):
    cdir = root.parent / "locks" / a.name
    gl, ac = current(cdir, LOCK_STALE_S)
    if ac and ac[1].get("session") != a.session:
        print("Gesperrt von %s seit %s (%s) – später nochmal" % (ac[1].get("session"), str(ac[1].get("started", ""))[:16], ac[1].get("note", "")))
        sys.exit(2)
    if ac:
        beat(cdir, ac[0])
        print("OK: Sperre %s gehört schon %s" % (a.name, a.session))
        return
    if take(cdir, gl, a.session, {"note": a.note or ""}) is None:
        print("Jemand anderes war schneller.")
        sys.exit(3)
    print("OK: Sperre %s gehört %s (gilt 30 min ohne Lebenszeichen)" % (a.name, a.session))


def cmd_unlock(a, root):
    cdir = root.parent / "locks" / a.name
    _, ac = current(cdir, LOCK_STALE_S)
    if not ac or ac[1].get("session") != a.session:
        print("Sperre %s gehört nicht %s" % (a.name, a.session), file=sys.stderr)
        sys.exit(2)
    free(cdir, ac[0], "")
    print("OK")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--dir", help="Meldungsordner (Standard: <userdata>/issues)")
    p.add_argument("--version", action="version", version=str(VERSION))
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
    for name in ["lock", "unlock"]:
        s = sub.add_parser(name); s.add_argument("name"); s.add_argument("--session", required=True)
        if name == "lock":
            s.add_argument("--note")
    a = p.parse_args()
    root = find_dir(a.dir)
    print("Meldungen: %s" % root, file=sys.stderr)
    {"list": cmd_list, "next": cmd_next, "claims": cmd_claims, "show": cmd_show, "claim": cmd_claim,
     "heartbeat": cmd_heartbeat, "release": cmd_release, "create": cmd_create, "lock": cmd_lock, "unlock": cmd_unlock,
     "comment": lambda a, r: _entry(a, r, "comment"), "plan": lambda a, r: _entry(a, r, "plan"),
     "ask": lambda a, r: _entry(a, r, "question", "rueckfrage"),
     "status": lambda a, r: _entry(a, r, "status", a.status),
     "fix": lambda a, r: _entry(a, r, "fix", "bitte_pruefen", {"build": a.build, "commit": a.commit}),
     }[a.cmd](a, root)


if __name__ == "__main__":
    main()
