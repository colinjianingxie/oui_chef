"""Check deployed authentication; --live opts into one bounded, paid xAI turn."""
import argparse
import base64
import json
import os
import plistlib
import re
import select
import socket
import ssl
import struct
import subprocess
import time
import urllib.error
import urllib.request

PROJECT = "oui-chef-dev-20260914"
HOST = "oui-chef-voice-172500657212.us-east1.run.app"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--live", action="store_true", help="Spend a small amount of xAI credit on one spoken recipe answer")
live = parser.parse_args().live
service = json.loads(subprocess.check_output([
    "gcloud", "run", "services", "describe", "oui-chef-voice", "--project", PROJECT,
    "--region", "us-east1", "--format=json"]))
configured = any(env["name"] == "XAI_API_KEY" for container in service["spec"]["template"]["spec"]["containers"]
                 for env in container.get("env", []))
assert not live or configured, "--live requires a configured voice provider."

def request(url, body=None, token=None, method=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    req = urllib.request.Request(url, data=json.dumps(body).encode() if body is not None else None,
                                 headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=25) as response:
        raw = response.read()
        return json.loads(raw) if raw else {}

def connect(token=None):
    sock = ssl.create_default_context().wrap_socket(socket.create_connection((HOST, 443), timeout=25), server_hostname=HOST)
    auth = f"Authorization: Bearer {token}\r\n" if token else ""
    handshake = (f"GET /voice HTTP/1.1\r\nHost: {HOST}\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n"
                 f"Sec-WebSocket-Version: 13\r\nSec-WebSocket-Key: {base64.b64encode(os.urandom(16)).decode()}\r\n{auth}\r\n")
    sock.sendall(handshake.encode())
    header = b""
    while not header.endswith(b"\r\n\r\n"):
        chunk = sock.recv(1)
        if not chunk:
            raise RuntimeError("Handshake ended early")
        header += chunk
        assert len(header) < 16384
    return sock, int(header.split(b" ")[1])

def receive(sock, count, deadline=None):
    data = b""
    while len(data) < count:
        if deadline is not None:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("Live voice test reached its 30-second limit")
            sock.settimeout(remaining)
        chunk = sock.recv(count - len(data))
        if not chunk:
            raise RuntimeError("Voice socket closed early")
        data += chunk
    return data

def send_event(sock, event):
    payload = json.dumps(event).encode()
    mask = os.urandom(4)
    if len(payload) < 126:
        header = bytes([0x81, 0x80 | len(payload)])
    else:
        assert len(payload) < 65536
        header = bytes([0x81, 0x80 | 126]) + struct.pack("!H", len(payload))
    sock.sendall(header + mask + bytes(value ^ mask[i % 4] for i, value in enumerate(payload)))

def read_event(sock, deadline=None):
    first, length = receive(sock, 2, deadline)
    assert not length & 0x80, "Server frames must not be masked"
    length &= 0x7F
    if length == 126:
        length = struct.unpack("!H", receive(sock, 2, deadline))[0]
    elif length == 127:
        length = struct.unpack("!Q", receive(sock, 8, deadline))[0]
    assert first & 0xF == 1 and length < 1000000, "Expected a bounded JSON event"
    return json.loads(receive(sock, length, deadline))

assert request(f"https://{HOST}/health")["service"] == "oui-chef-voice"
sock, status = connect()
sock.close()
assert status == 403, status
with open("Configuration/GoogleService-Info.plist", "rb") as config:
    key = plistlib.load(config)["API_KEY"]
identity = request(f"https://identitytoolkit.googleapis.com/v1/accounts:signUp?key={key}", {"returnSecureToken": True})
admin = subprocess.check_output(["gcloud", "auth", "print-access-token"], text=True).strip()
identities = [identity]
sockets = []
voice_id = None
try:
    sock, status = connect(identity["idToken"])
    sockets.append(sock)
    assert status == 101, status
    event = read_event(sock)
    assert event["type"] == "ended" and event.get("code") == "sign_in_required"
    assert "Profile" in event["message"]
    sock.close()
    identity = request(f"https://identitytoolkit.googleapis.com/v1/accounts:signUp?key={key}", {
        "email": f"oui-chef-smoke-{os.urandom(12).hex()}@example.invalid",
        "password": os.urandom(24).hex(), "returnSecureToken": True})
    identities.append(identity)
    sock, status = connect(identity["idToken"])
    sockets.append(sock)
    assert status == 101, status
    if live:
        with open("OuiChef/Core/Resources/recipes.json") as recipe_file:
            catalog = json.load(recipe_file)
        recipe = next(recipe for recipe in catalog["recipes"] if recipe["style"] == "tequila")
        context = {"catalog": catalog["recipes"], "sessionID": "smoke-session", "revision": 0,
                   "session": {"id": "smoke-session", "recipe": recipe, "servings": recipe["baseServings"],
                               "revision": 0, "started": [], "completed": [], "timers": [], "guidancePaused": False}}
        send_event(sock, {"type": "start", "context": context})
        deadline = time.monotonic() + 30
        sent = False
        tools = 0
        audio_bytes = 0
        transcript = ""
        current_response = None
        tool_responses = set()
        while True:
            event = read_event(sock, deadline)
            kind = event["type"]
            if kind == "ready" and not sent:
                voice_id = event["sessionID"]
                send_event(sock, {"type": "text", "text": "Check the current recipe with your cooking tool, then tell me how many milliliters of lime juice it uses. Answer in one short sentence."})
                sent = True
            elif kind == "tool":
                tools += 1
                assert tools <= 2 and event["name"] == "cooking", "Unexpected tool loop"
                args = json.loads(event["arguments"])
                assert args["operation"] == "state", "Smoke test allows read-only state requests"
                tool_responses.add(current_response)
                send_event(sock, {"type": "tool_result", "callID": event["callID"], "context": context,
                                  "output": json.dumps({"ok": True, "state": context})})
            elif kind == "responding":
                current_response = event["responseID"]
            elif kind == "audio":
                audio_bytes += len(base64.b64decode(event["audio"], validate=True))
                assert audio_bytes <= 48000 * 10, "Spoken answer exceeded the 10-second test allowance"
            elif kind == "transcript" and event.get("role") == "assistant":
                transcript = event["text"]
            elif kind == "response_done" and audio_bytes and tools and event.get("responseID") not in tool_responses:
                break
            elif kind in ["error", "ended"]:
                raise RuntimeError(event.get("message", "Voice ended unexpectedly"))
        assert tools > 0 and audio_bytes > 0 and transcript, "Missing tool call, audio, or transcript"
        assert re.search(r"\b(15|fifteen)\b", transcript, re.IGNORECASE), "Spoken answer did not give the recipe's 15 mL lime quantity"
        print(f"PASS: live cooking tool and spoken answer ({audio_bytes / 48000:.2f}s output audio)")
        print("Assistant:", transcript)
    else:
        second = request(f"https://identitytoolkit.googleapis.com/v1/accounts:signUp?key={key}", {
            "email": f"oui-chef-smoke-{os.urandom(12).hex()}@example.invalid",
            "password": os.urandom(24).hex(), "returnSecureToken": True})
        identities.append(second)
        active = [sock]
        for token in [identity["idToken"], second["idToken"]]:
            connection, status = connect(token)
            sockets.append(connection)
            assert status == 101, status
            active.append(connection)
        # No start events: no budget reservations or paid provider connections.
        assert not select.select(active, [], [], 1)[0], "Signed-in connection was unexpectedly rejected"
        print("PASS: health, missing-auth rejection, guest sign-in prompt, three signed-in connections across two accounts; no xAI calls")
finally:
    for connection in sockets:
        connection.close()
    cleanup_errors = []
    for account in identities:
        try:
            request(f"https://identitytoolkit.googleapis.com/v1/accounts:delete?key={key}", {"idToken": account["idToken"]})
        except Exception:
            cleanup_errors.append(account["localId"])
    assert not cleanup_errors, f"Remove temporary smoke-test identities: {cleanup_errors}"
    print("Temporary test accounts removed; no enrollment records created")
    if voice_id:
        for attempt in range(5):
            record = request(f"https://firestore.googleapis.com/v1/projects/{PROJECT}/databases/(default)/documents/voiceSessions/{voice_id}", token=admin)["fields"]
            if record["status"]["stringValue"] == "finished":
                print("Server usage estimate (cents):", record["estimatedCents"]["integerValue"])
                break
            time.sleep(1)
        else:
            raise RuntimeError("Voice usage reservation did not finalize; inspect the server ledger")
