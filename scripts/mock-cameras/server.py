"""Mock Olympus (OI.Share), Ricoh GR and DLNA (Sony/Panasonic) camera APIs serving a folder as the camera's card.

usage: python3 server.py olympus|ricoh|dlna PORT CARD_DIR
CARD_DIR contains DCIM/<folder>/<files>, like a real card.
"""
import html, json, os, re, sys, urllib.parse
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

kind, port, card = sys.argv[1], int(sys.argv[2]), sys.argv[3]
dcim = os.path.join(card, "DCIM")

def fat(ts):
    t = datetime.fromtimestamp(ts)
    return ((t.year - 1980) << 9) | (t.month << 5) | t.day, (t.hour << 11) | (t.minute << 5) | (t.second // 2)

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args): pass

    def send(self, code, body, content_type="text/plain"):
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_file(self, path):
        if not os.path.isfile(path): return self.send(404, b"not found")
        with open(path, "rb") as f: self.send(200, f.read(), "image/jpeg")

    def do_GET(self):
        url = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(url.query)
        if kind == "olympus":
            if self.headers.get("User-Agent") != "OlympusCameraKit": return self.send(403, b"")
            if url.path == "/get_caminfo.cgi":
                return self.send(200, b'<?xml version="1.0"?><caminfo><model>E-M10MarkII</model></caminfo>', "text/xml")
            if url.path == "/switch_cammode.cgi": return self.send(200, b"")
            if url.path == "/get_imglist.cgi":
                d = q["DIR"][0]
                lines = ["VER_100"]
                for name in sorted(os.listdir(os.path.join(card, d.lstrip("/")))):
                    p = os.path.join(card, d.lstrip("/"), name)
                    st = os.stat(p)
                    date, time = fat(st.st_mtime)
                    lines.append(f"{d},{name},{0 if os.path.isdir(p) else st.st_size},{16 if os.path.isdir(p) else 0},{date},{time}")
                return self.send(200, "\r\n".join(lines).encode() + b"\r\n")
            if url.path == "/get_thumbnail.cgi": return self.send(404, b"")
            return self.send_file(os.path.join(card, url.path.lstrip("/")))
        if kind == "ricoh":
            if url.path == "/v1/props":
                return self.send(200, json.dumps({"errCode": 200, "model": "RICOH GR III"}).encode(), "application/json")
            if url.path == "/v1/photos":
                dirs = [{"name": d, "files": sorted(os.listdir(os.path.join(dcim, d)))} for d in sorted(os.listdir(dcim))]
                return self.send(200, json.dumps({"errCode": 200, "dirs": dirs}).encode(), "application/json")
            parts = url.path.split("/")  # ['', 'v1', 'photos', dir, file, ('info')]
            if len(parts) >= 5 and parts[2] == "photos":
                path = os.path.join(dcim, parts[3], parts[4])
                if len(parts) == 6 and parts[5] == "info":
                    st = os.stat(path)
                    when = datetime.fromtimestamp(st.st_mtime, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
                    return self.send(200, json.dumps({"errCode": 200, "size": st.st_size, "datetime": when}).encode(), "application/json")
                if q.get("size") == ["thumb"]: return self.send(404, b"")
                return self.send_file(path)
        if kind == "dlna":
            if url.path == "/DmsDesc.xml":
                return self.send(200, f"""<?xml version="1.0"?><root xmlns="urn:schemas-upnp-org:device-1-0"><device>
<friendlyName>DSC-RX100M3</friendlyName><manufacturer>Sony Corporation</manufacturer><modelName>SonyImagingDevice</modelName>
<serviceList><service><serviceType>urn:schemas-upnp-org:service:ContentDirectory:1</serviceType>
<controlURL>/upnp/control/ContentDirectory</controlURL></service></serviceList></device></root>""".encode(), "text/xml")
            if url.path.startswith("/files/"):
                name = url.path.split("/")[-1]
                if q.get("size") == ["thumb"]: return self.send(200, b"T" * 200, "image/jpeg")
                return self.send_file(os.path.join(dcim, url.path[len("/files/"):]))
        self.send(404, b"")

    def do_POST(self):
        if kind != "dlna" or self.path != "/upnp/control/ContentDirectory": return self.send(404, b"")
        body = self.rfile.read(int(self.headers["Content-Length"])).decode()
        object_id = re.search(r"<ObjectID>(.*?)</ObjectID>", body).group(1)
        host = f"http://127.0.0.1:{port}"
        if object_id == "0":
            entries = [f'<container id="{d}" parentID="0"><dc:title>{d}</dc:title></container>' for d in sorted(os.listdir(dcim))]
        else:
            entries = []
            for name in sorted(os.listdir(os.path.join(dcim, object_id))):
                size = os.path.getsize(os.path.join(dcim, object_id, name))
                entries.append(f'<item id="{object_id}/{name}" parentID="{object_id}"><dc:title>{name}</dc:title><dc:date>2026-10-30T09:34:12</dc:date>'
                               f'<res protocolInfo="http-get:*:image/jpeg:DLNA.ORG_PN=JPEG_TN" size="200">{host}/files/{object_id}/{name}?size=thumb</res>'
                               f'<res protocolInfo="http-get:*:image/jpeg:*" size="{size}">{host}/files/{object_id}/{name}</res></item>')
        didl = ('<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/" '
                'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">' + "".join(entries) + "</DIDL-Lite>")
        envelope = ('<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>'
                    '<u:BrowseResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">'
                    f"<Result>{html.escape(didl)}</Result><NumberReturned>{len(entries)}</NumberReturned>"
                    f"<TotalMatches>{len(entries)}</TotalMatches><UpdateID>1</UpdateID></u:BrowseResponse></s:Body></s:Envelope>")
        self.send(200, envelope.encode(), "text/xml")

ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
