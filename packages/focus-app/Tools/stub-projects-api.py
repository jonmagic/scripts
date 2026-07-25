#!/usr/bin/env python3
"""A tiny stand-in for the GitHub Projects V2 API.

The Weekly Focus app reads and writes its task board over the network, so the
end-to-end test needs a board to talk to. Pointing it at the real board would be
slow, would need a token, and would mutate @jonmagic's actual tasks. This serves
just enough of the API for the app to boot, refresh, complete an item, and
create one.

Implemented:
  GET    /users/{owner}/projectsV2/{n}/items   list items (ETag + If-None-Match)
  PATCH  /users/{owner}/projectsV2/{n}/items/{id}   set field values
  POST   /graphql                             addProjectV2DraftIssue only

Plus a control surface the test harness drives directly, standing in for "someone
edited the board in a browser":
  GET    /__control/items                     dump raw state
  POST   /__control/items                     add an item
  DELETE /__control/items/{id}                remove an item

Usage:
    stub-projects-api.py [--port 0] [--owner jonmagic] [--project 6]

Prints "listening <port>" on the first line of stdout once it is ready.
"""

import argparse
import hashlib
import json
import re
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# These mirror BrainBoard.Field in FocusTask.swift. Field ids are stable board
# metadata, not secrets, and they already live in this repository.
FIELDS = {
    372_695_107: ("Title", "title"),
    372_695_109: ("Status", "single_select"),
    372_695_315: ("Week", "iteration"),
    372_695_329: ("Focus", "number"),
    372_695_330: ("Source", "text"),
    372_695_331: ("Target", "text"),
    372_695_332: ("Reviewed", "date"),
    372_695_333: ("Area", "single_select"),
}

TITLE, STATUS, WEEK, FOCUS, SOURCE, TARGET, REVIEWED, AREA = sorted(FIELDS)

STATUS_OPTIONS = {
    "bb8e27d2": "Inbox",
    "1c1703bf": "Todo",
    "7e587173": "Doing",
    "fc315b12": "Waiting",
    "d976124a": "Done",
}
STATUS_IDS = {name: option for option, name in STATUS_OPTIONS.items()}

CURRENT_ITERATION = {"id": "it-current", "start_date": "2026-07-19", "title": "Week of Jul 19"}


class Board:
    """Item state, keyed by REST id. Values are stored raw and rendered on read."""

    def __init__(self):
        self.lock = threading.Lock()
        self.items = {}
        self.next_id = 1001

    def add(self, title, status="Todo", focus=None, target=None, week=True):
        with self.lock:
            item_id = self.next_id
            self.next_id += 1
            fields = {TITLE: title}
            if status:
                fields[STATUS] = STATUS_IDS.get(status, STATUS_IDS["Todo"])
            if focus is not None:
                fields[FOCUS] = focus
            if target:
                fields[TARGET] = target
            if week:
                fields[WEEK] = CURRENT_ITERATION["id"]
            self.items[item_id] = {"node_id": "PVTI_stub_%d" % item_id, "fields": fields}
            return item_id

    def patch(self, item_id, updates):
        with self.lock:
            item = self.items.get(item_id)
            if item is None:
                return False
            for update in updates:
                field_id = int(update["id"])
                value = update.get("value")
                if value is None:
                    item["fields"].pop(field_id, None)
                else:
                    item["fields"][field_id] = value
            return True

    def delete(self, item_id):
        with self.lock:
            return self.items.pop(item_id, None) is not None

    def render(self):
        with self.lock:
            return [self._render_item(i, item) for i, item in sorted(self.items.items())]

    def _render_item(self, item_id, item):
        fields = []
        for field_id, raw in sorted(item["fields"].items()):
            name, data_type = FIELDS[field_id]
            fields.append(
                {"id": field_id, "name": name, "data_type": data_type, "value": _render_value(data_type, raw)}
            )
        return {"id": item_id, "node_id": item["node_id"], "fields": fields}


def _render_value(data_type, raw):
    if data_type in ("title", "text"):
        return {"raw": raw, "html": raw}
    if data_type == "single_select":
        name = STATUS_OPTIONS.get(raw, raw)
        return {"id": raw, "name": {"raw": name, "html": name}, "color": "BLUE"}
    if data_type == "iteration":
        title = CURRENT_ITERATION["title"]
        return {
            "id": raw,
            "start_date": CURRENT_ITERATION["start_date"],
            "duration": 7,
            "title": {"raw": title, "html": title},
            "completed": False,
        }
    return raw


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    board = None
    items_path = ""

    def log_message(self, *_args):
        pass

    def _send(self, status, payload=None, headers=None):
        body = b"" if payload is None else json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        self.end_headers()
        if body:
            self.wfile.write(body)

    def _read_json(self):
        length = int(self.headers.get("Content-Length") or 0)
        if not length:
            return {}
        return json.loads(self.rfile.read(length))

    def _path(self):
        return self.path.split("?", 1)[0]

    def do_GET(self):
        path = self._path()
        if path == "/__control/items":
            self._send(200, self.board.render())
            return
        if path == self.items_path:
            items = self.board.render()
            etag = '"%s"' % hashlib.sha256(json.dumps(items, sort_keys=True).encode()).hexdigest()[:16]
            if self.headers.get("If-None-Match") == etag:
                self.send_response(304)
                self.send_header("Content-Length", "0")
                self.send_header("ETag", etag)
                self.end_headers()
                return
            self._send(200, items, {"ETag": etag})
            return
        self._send(404, {"message": "Not Found"})

    def do_POST(self):
        path = self._path()
        if path == "/__control/items":
            body = self._read_json()
            item_id = self.board.add(
                body.get("title", "Untitled"),
                status=body.get("status", "Todo"),
                focus=body.get("focus"),
                target=body.get("target"),
            )
            self._send(201, {"id": item_id})
            return
        if path == "/graphql":
            self._handle_graphql(self._read_json())
            return
        self._send(404, {"message": "Not Found"})

    def _handle_graphql(self, body):
        query = body.get("query", "")
        if "addProjectV2DraftIssue" not in query:
            self._send(200, {"errors": [{"message": "stub supports addProjectV2DraftIssue only"}]})
            return
        title = (body.get("variables") or {}).get("title", "")
        # Drafts arrive with no status; the client PATCHes fields immediately after.
        item_id = self.board.add(title, status=None, week=False)
        self._send(200, {"data": {"addProjectV2DraftIssue": {"projectItem": {"databaseId": item_id}}}})

    def do_PATCH(self):
        match = re.fullmatch(re.escape(self.items_path) + r"/(\d+)", self._path())
        if not match:
            self._send(404, {"message": "Not Found"})
            return
        body = self._read_json()
        if self.board.patch(int(match.group(1)), body.get("fields", [])):
            self._send(200, {"id": int(match.group(1))})
        else:
            self._send(404, {"message": "Not Found"})

    def do_DELETE(self):
        match = re.fullmatch(r"/__control/items/(\d+)", self._path())
        if match and self.board.delete(int(match.group(1))):
            self._send(204)
        else:
            self._send(404, {"message": "Not Found"})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=0)
    parser.add_argument("--owner", default="jonmagic")
    parser.add_argument("--project", type=int, default=6)
    parser.add_argument("--seed", action="append", default=[], metavar="TITLE")
    args = parser.parse_args()

    board = Board()
    for index, title in enumerate(args.seed, start=1):
        board.add(title, focus=index)

    Handler.board = board
    Handler.items_path = "/users/%s/projectsV2/%d/items" % (args.owner, args.project)

    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print("listening %d" % server.server_address[1], flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    sys.exit(main())
