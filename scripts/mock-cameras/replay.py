"""A mock camera that replays a Ferry diagnostics file (ferryctl --trace, or "Save Diagnostics" in the apps).

usage: python3 replay.py DIAGNOSTICS.json [--session N] [--port PORT]

It answers each request with what the real camera answered in the recorded session, in the same order when the same
request was made more than once (the last answer repeats after that). Photo data was never recorded: downloads and
thumbnails get a small grey JPEG padded to the recorded size. Where the camera failed, it fails the same way: it hangs
up, or stops answering when the camera timed out.

Fujifilm cameras are served on ports 55740-55742 and PTP/IP cameras on 15740 (fixed by the protocols), so stop vcam
first. HTTP cameras (Olympus, Ricoh, GoPro, Sony/Panasonic DLNA) are served on --port (default 8080). The command
to point ferryctl at it is printed on start.
"""
import base64, json, socket, struct, sys, threading, time, urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

GREY_JPEG = base64.b64decode("""
/9j/4AAQSkZJRgABAQAASABIAAD/4QBMRXhpZgAATU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEAAKACAAQA
AAABAAAAEKADAAQAAAABAAAAEAAAAAD/7QA4UGhvdG9zaG9wIDMuMAA4QklNBAQAAAAAAAA4QklNBCUAAAAAABDUHYzZjwCyBOmA
CZjs+EJ+/8AAEQgAEAAQAwEiAAIRAQMRAf/EAB8AAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkKC//EALUQAAIBAwMCBAMFBQQE
AAABfQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYnKCkqNDU2Nzg5OkNERUZHSElKU1RVVldY
WVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk
5ebn6Onq8fLz9PX29/j5+v/EAB8BAAMBAQEBAQEBAQEAAAAAAAABAgMEBQYHCAkKC//EALURAAIBAgQEAwQHBQQEAAECdwABAgMR
BAUhMQYSQVEHYXETIjKBCBRCkaGxwQkjM1LwFWJy0QoWJDThJfEXGBkaJicoKSo1Njc4OTpDREVGR0hJSlNUVVZXWFlaY2RlZmdo
aWpzdHV2d3h5eoKDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uLj5OXm5+jp6vLz
9PX29/j5+v/bAEMACQkJCQkJEAkJEBYQEBAWHhYWFhYeJh4eHh4eJi4mJiYmJiYuLi4uLi4uLjc3Nzc3N0BAQEBASEhISEhISEhI
SP/bAEMBCwwMEhESHxERH0szKjNLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS//dAAQA
Af/aAAwDAQACEQMRAD8AKKKKAP/Z
""".replace("\n", ""))


def placeholder(size):
    """A valid JPEG of exactly `size` bytes (padded after the end marker), or as much of it as fits."""
    return GREY_JPEG[:size] if size <= len(GREY_JPEG) else GREY_JPEG + bytes(size - len(GREY_JPEG))


class Answers:
    """Recorded answers per request, served in order; the last one repeats."""

    def __init__(self):
        self.queues, self.used = {}, {}

    def add(self, key, answer):
        self.queues.setdefault(key, []).append(answer)

    def next(self, *keys):
        for key in keys:
            queue = self.queues.get(key)
            if queue:
                i = self.used.get(key, 0)
                self.used[key] = i + 1
                return queue[min(i, len(queue) - 1)]
        return None


def fails_by_hanging(event):
    return "stopped responding" in event.get("error", "") or "timed out" in event.get("error", "")


# MARK: - PTP (Fujifilm and PTP/IP)

class PTPReplay:
    def __init__(self, events):
        self.answers = Answers()
        self.sizes = {}
        for e in events:
            if e["kind"] == "ptp":
                op, params = int(e["op"], 16), tuple(e["params"])
                self.answers.add((op, params), e)
                self.answers.add((op,), e)

    def answer(self, op, params):
        """(code, data) for a request, or "hang"/"close" to fail like the camera did."""
        e = self.answers.next((op, tuple(params)), (op,))
        if op in (0x101B, 0x1009):  # GetPartialObject, GetObject: placeholder bytes of the right size
            handle = params[0]
            size = self.sizes.get(handle, 0)
            if e is not None and "code" not in e:
                return "hang" if fails_by_hanging(e) else "close"
            if e is not None and e["code"] != "0x2001":
                return int(e["code"], 16), b""
            whole = placeholder(size)
            if op == 0x1009:
                return 0x2001, whole
            offset, count = params[1], params[2]
            return 0x2001, whole[offset:offset + count]
        if e is None:
            return (0x2009 if op == 0x1008 else 0x2005), b""
        if "code" not in e:
            return "hang" if fails_by_hanging(e) else "close"
        code = int(e["code"], 16)
        if "in" in e:
            data = bytes.fromhex(e["in"])
        elif "inSize" in e:
            data = placeholder(e["inSize"])
        else:
            data = b""
        if op == 0x1008 and code == 0x2001 and len(data) >= 12:  # remember sizes for downloads
            self.sizes[params[0]] = struct.unpack_from("<I", data, 8)[0]
        return code, data


def read_exactly(conn, n):
    data = b""
    while len(data) < n:
        chunk = conn.recv(n - len(data))
        if not chunk:
            raise ConnectionError("client closed")
        data += chunk
    return data


def serve(port, handler):
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", port))
    server.listen(5)

    def loop():
        while True:
            conn, _ = server.accept()
            threading.Thread(target=run, args=(conn,), daemon=True).start()

    def run(conn):
        try:
            handler(conn)
        except (ConnectionError, OSError):
            pass
        finally:
            conn.close()

    threading.Thread(target=loop, daemon=True).start()


def fuji_handler(replay, init):
    def handle(conn):
        length = struct.unpack("<I", read_exactly(conn, 4))[0]
        read_exactly(conn, length - 4)
        conn.sendall(init)
        while True:
            length = struct.unpack("<I", read_exactly(conn, 4))[0]
            rest = read_exactly(conn, length - 4)
            if length == 8:  # Fuji's goodbye
                return
            _, op, tid = struct.unpack_from("<HHI", rest)
            params = list(struct.unpack_from("<%dI" % ((length - 12) // 4), rest, 8))
            if op == 0x1016:  # SetDevicePropValue: the value follows in a data container
                n = struct.unpack("<I", read_exactly(conn, 4))[0]
                read_exactly(conn, n - 4)
            answer = replay.answer(op, params)
            if answer == "hang":
                time.sleep(3600)
            if answer == "close":
                return
            code, data = answer
            if data:
                conn.sendall(struct.pack("<IHHI", 12 + len(data), 2, op, tid) + data)
            conn.sendall(struct.pack("<IHHI", 12, 3, code, tid))
    return handle


def ptpip_handler(replay, ack, refused):
    def packet(kind, payload=b""):
        return struct.pack("<II", 8 + len(payload), kind) + payload

    def handle(conn):
        while True:
            length, kind = struct.unpack("<II", read_exactly(conn, 8))
            payload = read_exactly(conn, length - 8) if length > 8 else b""
            if kind == 1:  # InitCommandRequest
                conn.sendall(packet(5 if refused else 2, ack))
                if refused:
                    return
            elif kind == 3:  # InitEventRequest: the event channel just stays open
                conn.sendall(packet(4))
                while conn.recv(4096):
                    pass
                return
            elif kind == 6:  # OperationRequest
                op, tid = struct.unpack_from("<HI", payload, 4)
                params = list(struct.unpack_from("<%dI" % ((len(payload) - 10) // 4), payload, 10))
                answer = replay.answer(op, params)
                if answer == "hang":
                    time.sleep(3600)
                if answer == "close":
                    return
                code, data = answer
                if data:
                    conn.sendall(packet(9, struct.pack("<IQ", tid, len(data))) + packet(12, struct.pack("<I", tid) + data))
                conn.sendall(packet(7, struct.pack("<HI", code, tid)))
    return handle


# MARK: - HTTP cameras

def http_replay(events, port):
    answers = Answers()
    origins = set()
    for e in events:
        if e["kind"] != "http":
            continue
        url = urllib.parse.urlsplit(e["url"])
        origins.add(f"{url.scheme}://{url.netloc}")
        path = url.path + (f"?{url.query}" if url.query else "")
        answers.add((e["method"], path, e.get("requestBody", "")), e)
        answers.add((e["method"], path), e)
    here = f"http://127.0.0.1:{port}"

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def answer(self, body=""):
            e = answers.next((self.command, self.path, body), (self.command, self.path))
            if e is None:
                return self.reply(404, b"", "text/plain")
            if "status" not in e:
                if fails_by_hanging(e):
                    time.sleep(3600)
                self.close_connection = True
                return
            if "body" in e:
                text = e["body"]
                for origin in origins:
                    text = text.replace(origin, here)
                data = text.encode()
            elif "bodyBase64" in e:
                data = base64.b64decode(e["bodyBase64"])
            else:
                data = placeholder(e.get("bodySize", 0))
            self.reply(e["status"], data, e.get("contentType") or ("image/jpeg" if "bodyOmitted" in e else "text/plain"))

        def reply(self, status, data, content_type):
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            self.answer()

        def do_POST(self):
            self.answer(self.rfile.read(int(self.headers.get("Content-Length", 0))).decode())

    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return origins


def main():
    args = sys.argv[1:]
    if not args or args[0] in ("-h", "--help"):
        sys.exit(__doc__)
    trace = json.load(open(args[0]))
    session_index = int(args[args.index("--session") + 1]) if "--session" in args else trace.get("mainSession", len(trace["sessions"]) - 1)
    port = int(args[args.index("--port") + 1]) if "--port" in args else 8080
    session = trace["sessions"][session_index]
    events = session["events"]
    protocol = session.get("protocol")
    print("\n".join(trace.get("summary", [])))
    print(f"\nReplaying session {session_index} ({session.get('camera', 'unknown camera')}, {protocol}, reached {session['reached']})")

    if protocol == "fuji":
        init = next((bytes.fromhex(e["received"]) for e in events if e["kind"] == "raw" and e["channel"] == "init"), None)
        if init is None:
            sys.exit("The trace has no answer to the connection request, so there's nothing to replay.")
        serve(55740, fuji_handler(PTPReplay(events), init))
        for extra in (55741, 55742):
            serve(extra, lambda conn: [None for _ in iter(lambda: conn.recv(4096), b"")])
        print("Fujifilm camera on 127.0.0.1:55740-55742. Try: ferryctl --host 127.0.0.1 --protocol fuji list")
    elif protocol == "ptpip":
        raw = next((e for e in events if e["kind"] == "raw" and e["channel"] in ("initCommandAck", "initFail")), None)
        if raw is None:
            sys.exit("The trace has no answer to the connection request, so there's nothing to replay.")
        serve(15740, ptpip_handler(PTPReplay(events), bytes.fromhex(raw["received"]), raw["channel"] == "initFail"))
        print("PTP/IP camera on 127.0.0.1:15740. Try: ferryctl --host 127.0.0.1 --protocol ptpip list")
    elif protocol in ("olympus", "ricoh", "gopro", "dlna"):
        origins = http_replay(events, port)
        host = f"127.0.0.1:{port}"
        if protocol == "dlna":
            first = next((e["url"] for e in events if e["kind"] == "http"), "")
            url = urllib.parse.urlsplit(first)
            host = f"http://127.0.0.1:{port}{url.path}"
        print(f"{protocol} camera on http://127.0.0.1:{port} (recorded at {', '.join(sorted(origins))}).")
        print(f"Try: ferryctl --host {host} --protocol {protocol} list")
    else:
        sys.exit(f"Nothing to replay: no camera protocol answered in session {session_index}.")
    try:
        while True:
            time.sleep(3600)
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
