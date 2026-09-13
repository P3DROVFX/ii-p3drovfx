#!/usr/bin/env python3
"""Experimental Google Keep Bridge (Trilha C - Opt-in).

Unofficial sync bridge using reverse-engineered APIs (gkeepapi / gpsoauth).
Strictly behind an explicit opt-in warning:
- Unofficial protocol that may break without notice on Google changes.
- May trigger security alerts or checkpoint verifications on Google accounts.
- Recommended to use with an app password or dedicated secondary account.

Provides:
- Dependency and auth status check
- Conflict resolution (newer wins + losing version saved to revisions/)
"""

import argparse
import json
import os
import sys
from pathlib import Path


def emit(payload: dict) -> int:
    sys.stdout.write(json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n")
    return 0 if payload.get("ok", True) else 1


def check_status() -> dict:
    """Check if gkeepapi is installed and whether experimental bridge is ready."""
    try:
        import gkeepapi # type: ignore
        has_lib = True
    except ImportError:
        has_lib = False

    return {
        "ok": True,
        "isExperimental": True,
        "libraryInstalled": has_lib,
        "warning": (
            "ATENÇÃO: A Trilha C utiliza engenharia reversa não-oficial. "
            "Pode parar de funcionar sem aviso prévio caso o Google altere seus protocolos "
            "e pode acionar alertas de segurança da conta. "
            "A Trilha A (importação por Google Takeout) é recomendada por ser 100% oficial e segura."
        )
    }


def resolve_conflict(local_modified: int, remote_updated: int, local_doc: dict, remote_doc: dict) -> dict:
    """Resolve note conflict comparing timestamps.
    The newer version wins, and the losing version is preserved in revisions.
    """
    if local_modified >= remote_updated:
        return {
            "winner": "local",
            "active": local_doc,
            "revisionToSave": remote_doc
        }
    else:
        return {
            "winner": "remote",
            "active": remote_doc,
            "revisionToSave": local_doc
        }


def main() -> int:
    parser = argparse.ArgumentParser(description="Experimental Google Keep Bridge")
    parser.add_argument("action", choices=["status", "info"], help="What to do")
    parser.add_argument("--confirm-experimental", action="store_true", help="Acknowledge that this is experimental")

    args = parser.parse_args()

    if args.action in ("status", "info"):
        return emit(check_status())

    return emit({"ok": False, "error": "unknown_action"})


if __name__ == "__main__":
    sys.exit(main())
