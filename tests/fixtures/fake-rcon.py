"""A stand-in that speaks the Source rcon protocol on TCP 27015, for tests/rcon.sh.

FAKE_PW is the password it accepts. With FAKE_MARKER=1 it answers the empty
packet a client sends after a command, the way srcds does, so the client sees
the end of the reply; with 0 it never does. status comes back in two packets.
"""
import os, socket, struct, threading

PW = os.environ.get("FAKE_PW", "")
MARKER = os.environ.get("FAKE_MARKER", "1") == "1"


def packet(i, kind, body):
    b = struct.pack("<ii", i, kind) + body.encode() + b"\x00\x00"
    return struct.pack("<i", len(b)) + b


def serve(c):
    buf = b""
    try:
        while True:
            d = c.recv(4096)
            if not d:
                return
            buf += d
            while len(buf) >= 4 and len(buf) >= 4 + struct.unpack("<i", buf[:4])[0]:
                n = struct.unpack("<i", buf[:4])[0]
                i, kind = struct.unpack("<ii", buf[4:12])
                body = buf[12:4 + n - 2].decode()
                buf = buf[4 + n:]
                if kind == 3:                                   # auth
                    c.sendall(packet(i, 0, ""))
                    c.sendall(packet(i if body == PW else -1, 2, ""))
                elif kind == 2 and body == "status":
                    c.sendall(packet(i, 0, "hostname: stand-in\n"))
                    c.sendall(packet(i, 0, "version : 1.41.9.4\n"))
                elif kind == 2:
                    c.sendall(packet(i, 0, "ran: %s\n" % body))
                elif kind == 0 and MARKER:                      # the end marker
                    c.sendall(packet(i, 0, ""))
    finally:
        c.close()


s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("0.0.0.0", 27015))
s.listen(8)
print("fake rcon listening", flush=True)
while True:
    conn, _ = s.accept()
    threading.Thread(target=serve, args=(conn,), daemon=True).start()
