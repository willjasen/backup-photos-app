#!/usr/bin/env python3
"""Local web interface for the macOS Photos export script."""

from __future__ import annotations

import argparse
import json
import os
import re
import signal
import subprocess
import threading
import webbrowser
from collections import deque
from datetime import datetime
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from tempfile import NamedTemporaryFile
from urllib.parse import parse_qs, urlparse


ROOT = Path(__file__).resolve().parent
ANSI_ESCAPE = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
EXPORT_FLAGS = {
    "albums": "--albums",
    "people": "--people",
    "date": "--date",
    "all": "--all",
}
LIST_FILES = {
    "albums": "albums.txt",
    "people": "people.txt",
}


class AppError(Exception):
    def __init__(self, message: str, status: int = HTTPStatus.BAD_REQUEST):
        super().__init__(message)
        self.status = status


def active_entries(text: str) -> list[str]:
    return [
        line.strip()
        for line in text.splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]


def validate_lists(contents: dict[str, str]) -> None:
    for name in LIST_FILES:
        if name not in contents or not isinstance(contents[name], str):
            raise AppError(f"Missing text for {name}.")

    invalid_albums = [
        number
        for number, line in enumerate(contents["albums"].splitlines(), start=1)
        if line.strip() and not line.lstrip().startswith("#") and "," in line
    ]
    if invalid_albums:
        numbers = ", ".join(str(number) for number in invalid_albums)
        raise AppError(
            f"Album names cannot contain commas. Check line(s): {numbers}."
        )


class ExportManager:
    def __init__(self, script: Path, working_directory: Path):
        self.script = script
        self.working_directory = working_directory
        self._lock = threading.Lock()
        self._process: subprocess.Popen[str] | None = None
        self._lines: deque[tuple[int, str]] = deque(maxlen=2500)
        self._next_line = 0
        self._modes: list[str] = []
        self._started_at: str | None = None
        self._finished_at: str | None = None
        self._exit_code: int | None = None

    def _append(self, line: str) -> None:
        clean = ANSI_ESCAPE.sub("", line.rstrip("\r\n"))
        with self._lock:
            self._lines.append((self._next_line, clean))
            self._next_line += 1

    def start(self, modes: list[str]) -> None:
        unique_modes = list(dict.fromkeys(modes))
        if not unique_modes or any(mode not in EXPORT_FLAGS for mode in unique_modes):
            raise AppError("Choose at least one valid export type.")
        if not self.script.is_file():
            raise AppError(f"Export script not found: {self.script}", HTTPStatus.NOT_FOUND)

        with self._lock:
            if self._process is not None and self._process.poll() is None:
                raise AppError("An export is already running.", HTTPStatus.CONFLICT)

            command = ["/bin/zsh", str(self.script)]
            command.extend(EXPORT_FLAGS[mode] for mode in unique_modes)
            self._lines.clear()
            self._next_line = 0
            self._modes = unique_modes
            self._started_at = datetime.now().astimezone().isoformat(timespec="seconds")
            self._finished_at = None
            self._exit_code = None
            try:
                self._process = subprocess.Popen(
                    command,
                    cwd=self.working_directory,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    errors="replace",
                    bufsize=1,
                    start_new_session=True,
                )
            except OSError as exc:
                self._process = None
                raise AppError(f"Could not start the export: {exc}") from exc

            process = self._process

        self._append(f"Starting export: {', '.join(unique_modes)}")
        threading.Thread(
            target=self._collect_output,
            args=(process,),
            daemon=True,
            name="photo-export-output",
        ).start()

    def _collect_output(self, process: subprocess.Popen[str]) -> None:
        if process.stdout is not None:
            for line in process.stdout:
                self._append(line)
            process.stdout.close()

        exit_code = process.wait()
        self._append(
            "Export finished successfully."
            if exit_code == 0
            else f"Export stopped with exit code {exit_code}."
        )
        with self._lock:
            self._exit_code = exit_code
            self._finished_at = datetime.now().astimezone().isoformat(timespec="seconds")

    def stop(self) -> None:
        with self._lock:
            process = self._process
            if process is None or process.poll() is not None:
                raise AppError("There is no running export.", HTTPStatus.CONFLICT)
            pid = process.pid

        self._append("Stopping export…")
        try:
            os.killpg(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass

    def status(self, after: int = -1) -> dict[str, object]:
        with self._lock:
            process = self._process
            running = process is not None and process.poll() is None
            lines = [
                {"number": number, "text": text}
                for number, text in self._lines
                if number > after
            ]
            return {
                "running": running,
                "modes": self._modes,
                "started_at": self._started_at,
                "finished_at": self._finished_at,
                "exit_code": self._exit_code,
                "lines": lines,
                "next_after": self._next_line - 1,
            }


class PhotoExportApp:
    def __init__(self, root: Path = ROOT, script: Path | None = None):
        self.root = root.resolve()
        self.config_file = self.root / "config.json"
        self.static_directory = self.root / "static"
        self.manager = ExportManager(
            (script or self.root / "export-photos.zsh").resolve(),
            self.root,
        )

    def config(self) -> dict[str, object]:
        if not self.config_file.is_file():
            raise AppError(
                "config.json is missing. Copy config.example.json to config.json first.",
                HTTPStatus.NOT_FOUND,
            )
        try:
            config = json.loads(self.config_file.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            raise AppError(f"Could not read config.json: {exc}") from exc
        if not isinstance(config, dict):
            raise AppError("config.json must contain a JSON object.")
        return config

    def backup_directory(self) -> Path:
        value = self.config().get("photo_backup_dir")
        if not isinstance(value, str) or not value.strip():
            raise AppError("Set photo_backup_dir in config.json.")
        return Path(value).expanduser()

    def read_lists(self) -> dict[str, object]:
        backup_directory = self.backup_directory()
        contents: dict[str, str] = {}
        for name, filename in LIST_FILES.items():
            path = backup_directory / filename
            try:
                contents[name] = path.read_text(encoding="utf-8") if path.exists() else ""
            except OSError as exc:
                raise AppError(f"Could not read {path}: {exc}") from exc
        return {
            "contents": contents,
            "counts": {
                name: len(active_entries(text)) for name, text in contents.items()
            },
            "directory": str(backup_directory),
        }

    def save_lists(self, contents: dict[str, str]) -> dict[str, object]:
        validate_lists(contents)
        backup_directory = self.backup_directory()
        try:
            backup_directory.mkdir(parents=True, exist_ok=True)
            for name, filename in LIST_FILES.items():
                destination = backup_directory / filename
                text = contents[name]
                if text and not text.endswith("\n"):
                    text += "\n"
                with NamedTemporaryFile(
                    "w",
                    encoding="utf-8",
                    dir=backup_directory,
                    prefix=f".{filename}.",
                    delete=False,
                ) as temporary:
                    temporary.write(text)
                    temporary_path = Path(temporary.name)
                os.replace(temporary_path, destination)
        except OSError as exc:
            raise AppError(f"Could not save the list files: {exc}") from exc
        return self.read_lists()

    def overview(self) -> dict[str, object]:
        config = self.config()
        return {
            "backup_directory": config.get("photo_backup_dir"),
            "photos_library": config.get("photos_library_dir"),
            "date_range": {
                "from": config.get("from_date"),
                "to": config.get("to_date"),
                "available": bool(config.get("from_date") and config.get("to_date")),
            },
        }

    def validate_export(self, modes: list[str]) -> None:
        config = self.config()
        required = ("photo_backup_dir", "photos_library_dir", "reports_dir_name", "checkpoints")
        missing = [name for name in required if config.get(name) in (None, "")]
        if missing:
            raise AppError(f"config.json is missing: {', '.join(missing)}.")
        if "date" in modes and not (config.get("from_date") and config.get("to_date")):
            raise AppError("Add from_date and to_date to config.json before a date export.")


class RequestHandler(BaseHTTPRequestHandler):
    server_version = "PhotoExportWeb/1.0"

    @property
    def app(self) -> PhotoExportApp:
        return self.server.app  # type: ignore[attr-defined]

    def log_message(self, format: str, *args: object) -> None:
        return

    def _json_body(self) -> dict[str, object]:
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError as exc:
            raise AppError("Invalid request length.") from exc
        if length > 1_000_000:
            raise AppError("Request is too large.", HTTPStatus.REQUEST_ENTITY_TOO_LARGE)
        try:
            value = json.loads(self.rfile.read(length) or b"{}")
        except json.JSONDecodeError as exc:
            raise AppError("Request body must be valid JSON.") from exc
        if not isinstance(value, dict):
            raise AppError("Request body must be a JSON object.")
        return value

    def _send_json(self, value: object, status: int = HTTPStatus.OK) -> None:
        body = json.dumps(value).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(body)

    def _send_file(self, path: Path, content_type: str) -> None:
        if not path.is_file():
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        body = path.read_bytes()
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-cache")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header(
            "Content-Security-Policy",
            "default-src 'self'; style-src 'self'; script-src 'self'; "
            "img-src 'self' data:; connect-src 'self'",
        )
        self.end_headers()
        self.wfile.write(body)

    def _handle_error(self, exc: Exception) -> None:
        if isinstance(exc, AppError):
            self._send_json({"error": str(exc)}, exc.status)
        else:
            self._send_json(
                {"error": f"Unexpected server error: {exc}"},
                HTTPStatus.INTERNAL_SERVER_ERROR,
            )

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        try:
            if parsed.path == "/":
                self._send_file(self.app.static_directory / "index.html", "text/html; charset=utf-8")
            elif parsed.path == "/styles.css":
                self._send_file(self.app.static_directory / "styles.css", "text/css; charset=utf-8")
            elif parsed.path == "/app.js":
                self._send_file(
                    self.app.static_directory / "app.js",
                    "text/javascript; charset=utf-8",
                )
            elif parsed.path == "/api/overview":
                self._send_json(self.app.overview())
            elif parsed.path == "/api/lists":
                self._send_json(self.app.read_lists())
            elif parsed.path == "/api/export/status":
                query = parse_qs(parsed.query)
                try:
                    after = int(query.get("after", ["-1"])[0])
                except ValueError:
                    after = -1
                self._send_json(self.app.manager.status(after))
            else:
                self._send_json({"error": "Not found."}, HTTPStatus.NOT_FOUND)
        except Exception as exc:
            self._handle_error(exc)

    def do_PUT(self) -> None:
        try:
            if self.path != "/api/lists":
                self._send_json({"error": "Not found."}, HTTPStatus.NOT_FOUND)
                return
            body = self._json_body()
            contents = body.get("contents")
            if not isinstance(contents, dict):
                raise AppError("Missing list contents.")
            result = self.app.save_lists(contents)  # type: ignore[arg-type]
            self._send_json(result)
        except Exception as exc:
            self._handle_error(exc)

    def do_POST(self) -> None:
        try:
            if self.path == "/api/export/start":
                body = self._json_body()
                modes = body.get("modes")
                if not isinstance(modes, list) or not all(
                    isinstance(mode, str) for mode in modes
                ):
                    raise AppError("modes must be a list.")
                self.app.validate_export(modes)
                self.app.manager.start(modes)
                self._send_json(self.app.manager.status(), HTTPStatus.ACCEPTED)
            elif self.path == "/api/export/stop":
                self.app.manager.stop()
                self._send_json({"stopping": True}, HTTPStatus.ACCEPTED)
            else:
                self._send_json({"error": "Not found."}, HTTPStatus.NOT_FOUND)
        except Exception as exc:
            self._handle_error(exc)


class PhotoExportServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address: tuple[str, int], app: PhotoExportApp):
        self.app = app
        super().__init__(address, RequestHandler)


def main() -> None:
    parser = argparse.ArgumentParser(description="Run the local Photos export website.")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--open", action="store_true", help="Open the site in a browser.")
    args = parser.parse_args()

    server = PhotoExportServer((args.host, args.port), PhotoExportApp())
    url = f"http://{args.host}:{server.server_port}"
    print(f"Photos Export is available at {url}")
    print("Press Control-C to stop the website.")
    if args.open:
        threading.Timer(0.5, webbrowser.open, args=(url,)).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping website.")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
