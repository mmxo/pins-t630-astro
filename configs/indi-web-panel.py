#!/usr/bin/env python3
import html, subprocess, urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingThreadingHTTPServer

def run(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=4).stdout
    except Exception:
        return ""

def get_devices():
    devs = {}
    for line in run(["indi_getprop", "-t", "2"]).splitlines():
        if "=" not in line or "." not in line:
            continue
        k, v = line.split("=", 1)
        d, prop = k.split(".", 1)
        if prop.startswith(("CONNECTION.", "DEVICE_PORT.", "DEVICE_BAUD_RATE.", "ABS_FOCUS_POSITION.")):
            devs.setdefault(d, {})[prop] = v
    return devs

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        act = next(iter(q.get("act", [])), "")
        dev = next(iter(q.get("dev", [])), "")
        if dev and act == "connect":
            if "OnStep" in dev:
                run(["indi_setprop", f"{dev}.DEVICE_PORT.PORT=/dev/mount"])
                run(["indi_setprop", f"{dev}.DEVICE_BAUD_RATE.9600=On"])
            elif "Focuser" in dev:
                run(["indi_setprop", f"{dev}.DEVICE_PORT.PORT=/dev/focusser"])
            run(["indi_setprop", f"{dev}.CONNECTION.CONNECT=On"])
        elif dev and act == "disconnect":
            run(["indi_setprop", f"{dev}.CONNECTION.DISCONNECT=On"])
        elif dev and act == "save":
            run(["indi_setprop", f"{dev}.CONFIG_PROCESS.CONFIG_SAVE=On"])

        devs = get_devices()
        cards = []
        for d, p in sorted(devs.items()):
            on = p.get("CONNECTION.CONNECT") == "On"
            port = p.get("DEVICE_PORT.PORT", "-")
            pos = p.get("ABS_FOCUS_POSITION.FOCUS_ABSOLUTE_POSITION", "") if "Focuser" in d else ""
            u = urllib.parse.quote(d)
            st = "<b style='color:#4ade80'>VERBUNDEN</b>" if on else "<b style='color:#f87171'>GETRENNT</b>"
            extra = f" | Pos: <b>{html.escape(pos)}</b>" if pos else ""
            cards.append(f"<div class='c'><h3>{html.escape(d)}</h3><p>{st} | Port: <code>{html.escape(port)}</code>{extra}</p>"
                         f"<a class='b g' href='/?act=connect&dev={u}'>Connect</a>"
                         f"<a class='b r' href='/?act=disconnect&dev={u}'>Disconnect</a>"
                         f"<a class='b' href='/?act=save&dev={u}'>Save</a></div>")
        body = "".join(cards) or "<p>Kein aktives INDI-Geraet gefunden.</p>"
        page = (f"<!doctype html><html><head><meta name='viewport' content='width=device-width,initial-scale=1'>"
                f"<title>INDI Control</title><style>body{{background:#111;color:#eee;font-family:sans-serif;padding:12px}}"
                f".c{{background:#1e1e1e;padding:12px;border-radius:10px;margin-bottom:12px}}h3{{margin:0 0 6px}}"
                f".b{{display:inline-block;padding:10px 14px;margin:4px 6px 0 0;background:#333;color:#fff;text-decoration:none;border-radius:8px;font-weight:bold}}"
                f".g{{background:#166534}}.r{{background:#991b1b}}</style></head>"
                f"<body><h2>INDI Live-Control <a class='b' href='/'>Refresh</a></h2>{body}</body></html>")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        self.wfile.write(page.encode())
    def log_message(self, *a): pass

ThreadingThreadingHTTPServer(("0.0.0.0", 8624), Handler).serve_forever()
