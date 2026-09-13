#!/usr/bin/env python3
"""Small synchronous client for the mpv JSON IPC protocol.

The production helper owns one instance of this class.  It never shells out to
`socat` and never uses a shared mpvpaper socket.
"""

from __future__ import annotations

import json
import os
import socket
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Sequence


class MpvIpcError(RuntimeError):
    pass


class MpvPropertyUnavailable(MpvIpcError):
    """mpv accepted a load request but has not exposed the property yet."""


class MpvIpcClient:
    def __init__(self, socket_path: str | Path) -> None:
        self.socket_path = Path(socket_path)
        self._socket: socket.socket | None = None
        self._buffer = b""
        self._request_id = 0
        self._events: list[dict[str, Any]] = []

    def connect(self, timeout: float = 2.0) -> None:
        deadline = time.monotonic() + timeout
        last_error: OSError | None = None
        while time.monotonic() < deadline:
            connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            try:
                connection.connect(os.fspath(self.socket_path))
                connection.settimeout(max(0.05, deadline - time.monotonic()))
                self._socket = connection
                return
            except OSError as error:
                connection.close()
                last_error = error
                time.sleep(0.02)
        raise MpvIpcError(f"could not connect to mpv IPC socket {self.socket_path}: {last_error}")

    def close(self) -> None:
        if self._socket is not None:
            self._socket.close()
            self._socket = None

    def _read_line(self, timeout: float) -> dict[str, Any]:
        if self._socket is None:
            raise MpvIpcError("mpv IPC client is not connected")
        deadline = time.monotonic() + timeout
        while b"\n" not in self._buffer:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise MpvIpcError("timed out waiting for mpv IPC response")
            self._socket.settimeout(remaining)
            try:
                chunk = self._socket.recv(65536)
            except OSError as error:
                raise MpvIpcError(f"failed reading mpv IPC response: {error}") from error
            if not chunk:
                raise MpvIpcError("mpv IPC socket closed")
            self._buffer += chunk
        raw_line, self._buffer = self._buffer.split(b"\n", 1)
        try:
            result = json.loads(raw_line.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise MpvIpcError("mpv IPC returned malformed JSON") from error
        if not isinstance(result, dict):
            raise MpvIpcError("mpv IPC returned a non-object response")
        return result

    def command(self, name: str, arguments: Sequence[Any] = (), timeout: float = 2.0) -> Any:
        if self._socket is None:
            raise MpvIpcError("mpv IPC client is not connected")
        self._request_id += 1
        request_id = self._request_id
        request = {"command": [name, *arguments], "request_id": request_id}
        try:
            self._socket.sendall(json.dumps(request, separators=(",", ":")).encode("utf-8") + b"\n")
        except OSError as error:
            raise MpvIpcError(f"failed writing mpv IPC request: {error}") from error

        deadline = time.monotonic() + timeout
        while True:
            response = self._read_line(max(0.01, deadline - time.monotonic()))
            if isinstance(response.get("event"), str):
                self._events.append(response)
                continue
            if response.get("request_id") != request_id:
                continue
            if response.get("error") != "success":
                error = str(response.get("error", "unknown mpv error"))
                if error == "property unavailable":
                    raise MpvPropertyUnavailable(error)
                raise MpvIpcError(error)
            return response.get("data")

    def wait_for_event(
        self,
        predicate: Callable[[dict[str, Any]], bool],
        timeout: float = 2.0,
    ) -> dict[str, Any]:
        """Wait for an mpv async event without confusing it with a reply."""

        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            for index, queued in enumerate(self._events):
                if predicate(queued):
                    return self._events.pop(index)
            message = self._read_line(max(0.01, deadline - time.monotonic()))
            if isinstance(message.get("event"), str):
                self._events.append(message)
        raise MpvIpcError("timed out waiting for mpv event")

    def get_property(self, name: str, timeout: float = 2.0) -> Any:
        return self.command("get_property", (name,), timeout)

    def set_property(self, name: str, value: Any, timeout: float = 2.0) -> Any:
        return self.command("set_property", (name, value), timeout)

    def wait_for_property(
        self,
        name: str,
        predicate: Callable[[Any], bool],
        timeout: float = 2.0,
    ) -> Any:
        deadline = time.monotonic() + timeout
        last_value: Any = None
        while time.monotonic() < deadline:
            try:
                last_value = self.get_property(name, timeout=min(0.5, deadline - time.monotonic()))
            except MpvPropertyUnavailable:
                time.sleep(0.02)
                continue
            if predicate(last_value):
                return last_value
            time.sleep(0.02)
        raise MpvIpcError(f"mpv property {name!r} did not reach the expected value: {last_value!r}")


@dataclass
class MpvProcess:
    socket_path: Path
    mpv_binary: str = "mpv"
    null_audio: bool = False
    start_paused: bool = False
    process: subprocess.Popen[bytes] | None = None
    client: MpvIpcClient | None = None

    def command_line(self) -> list[str]:
        command = [
            self.mpv_binary,
            "--no-config",
            "--no-video",
            "--force-window=no",
            "--idle=yes",
            "--keep-open=yes",
            "--terminal=no",
            "--gapless-audio=yes",
            f"--input-ipc-server={self.socket_path}",
        ]
        if self.null_audio:
            command.append("--ao=null")
        if self.start_paused:
            command.append("--pause=yes")
        return command

    def start(self, timeout: float = 3.0) -> MpvIpcClient:
        if self.process is not None:
            raise MpvIpcError("mpv process is already running")
        if self.socket_path.exists():
            try:
                test_sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                test_sock.settimeout(0.2)
                test_sock.connect(str(self.socket_path))
                test_sock.close()
                raise MpvIpcError(f"refusing to reuse an existing mpv IPC socket: {self.socket_path}")
            except (ConnectionRefusedError, OSError):
                try:
                    self.socket_path.unlink()
                except OSError:
                    pass
        self.socket_path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)

        def _preexec() -> None:
            try:
                import ctypes
                import signal
                libc = ctypes.CDLL(None)
                # PR_SET_PDEATHSIG = 1
                libc.prctl(1, signal.SIGTERM)
            except Exception:
                pass

        self.process = subprocess.Popen(
            self.command_line(),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            preexec_fn=_preexec,
        )
        client = MpvIpcClient(self.socket_path)
        try:
            client.connect(timeout)
            self.client = client
            return client
        except Exception:
            self.stop()
            raise

    def stop(self) -> None:
        client, self.client = self.client, None
        if client is not None:
            try:
                client.command("quit", timeout=0.5)
            except MpvIpcError:
                pass
            finally:
                client.close()

        process, self.process = self.process, None
        if process is not None:
            try:
                process.wait(timeout=1.5)
            except subprocess.TimeoutExpired:
                process.terminate()
                try:
                    process.wait(timeout=1.0)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=1.0)

        if self.socket_path.exists() and self.socket_path.is_socket():
            self.socket_path.unlink()
