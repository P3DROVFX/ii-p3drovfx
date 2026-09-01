#!/usr/bin/env python3
"""Collect normalized plan-quota snapshots for AI tools installed locally.

The collector is deliberately one-shot. Quickshell owns the refresh cadence;
this helper only reduces the provider dialects into a small JSON frame:

* ChatGPT/Codex: newest ``rate_limits`` snapshot in Codex JSONL sessions.
* Claude: Claude Code's OAuth usage endpoint, guarded by a local cache and
  never refreshing or rewriting Claude's credentials.
* Antigravity: the localhost language-server API already used by ``agy`` and
  the Antigravity UI. No Antigravity process is started by this script.
* Z.AI GLM Coding Plan, Kimi Code, OpenCode Go and OpenRouter: documented
  read-only usage endpoints, reusing credentials from their installed clients.

No access or refresh token is ever included in stdout, stderr, or the cache.
"""

from __future__ import annotations

import argparse
import copy
import http.client
import json
import os
import re
import ssl
import subprocess
import sys
import time
import tomllib
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable, Iterable


PROVIDER_META = {
    "chatgpt": {"name": "ChatGPT", "icon": "openai-symbolic.svg"},
    "claude": {"name": "Claude", "icon": "bootstrap_claude.svg"},
    "antigravity": {"name": "Antigravity", "icon": "material-symbols_antigravity.svg"},
    "zai": {"name": "Z.AI GLM", "icon": "Zai.png"},
    "kimi": {"name": "Kimi Code", "icon": "MoonshotAI.png"},
    "opencode": {"name": "OpenCode Go", "icon": "opencode-logo-light.svg"},
    "openrouter": {"name": "OpenRouter", "icon": "openrouter-symbolic.svg"},
}

ANTIGRAVITY_SERVICE = "exa.language_server_pb.LanguageServerService"
ANTIGRAVITY_SUMMARY_PATH = f"/{ANTIGRAVITY_SERVICE}/RetrieveUserQuotaSummary"
ANTIGRAVITY_STATUS_PATH = f"/{ANTIGRAVITY_SERVICE}/GetUserStatus"
CLAUDE_USAGE_URL = "https://api.anthropic.com/api/oauth/usage"
ZAI_USAGE_URL = "https://api.z.ai/api/monitor/usage/quota/limit"
KIMI_USAGE_URL = "https://api.kimi.com/coding/v1/usages"
OPENCODE_USAGE_URL = "https://opencode.ai/zen/go/v1/usage"
OPENROUTER_CREDITS_URL = "https://openrouter.ai/api/v1/credits"
OPENROUTER_KEY_URL = "https://openrouter.ai/api/v1/key"
NETWORK_CACHE_TTL_MS = 4 * 60 * 1000


def clamp(value: Any, low: float = 0.0, high: float = 100.0) -> float:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return low
    return max(low, min(high, number))


def finite_number(value: Any) -> float | None:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    if number != number or number in (float("inf"), float("-inf")):
        return None
    return number


def parse_timestamp_ms(value: Any) -> int:
    if value is None or value == "":
        return 0
    if isinstance(value, (int, float)):
        number = float(value)
        return int(number if number > 10_000_000_000 else number * 1000)
    try:
        normalized = str(value).strip().replace("Z", "+00:00")
        parsed = datetime.fromisoformat(normalized)
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=timezone.utc)
        return int(parsed.timestamp() * 1000)
    except (TypeError, ValueError):
        return 0


def window_kind(window_minutes: int = 0, label: str = "") -> str:
    text = label.lower().replace("_", "-")
    if "month" in text or window_minutes >= 25 * 24 * 60:
        return "monthly"
    if "week" in text or "7d" in text or window_minutes >= 6 * 24 * 60:
        return "weekly"
    if "day" in text or "24h" in text or window_minutes >= 20 * 60:
        return "daily"
    return "short"


def duration_label(window_minutes: int, fallback: str = "") -> str:
    if fallback:
        lowered = fallback.lower()
        if lowered in {"5h", "five_hour", "five-hour"} or (
            ("five" in lowered or "5" in lowered) and "hour" in lowered
        ):
            return "5 hours"
        if lowered in {"7d", "seven_day", "seven-day", "weekly"} or "week" in lowered:
            return "Weekly"
        if lowered in {"24h", "daily"} or "daily" in lowered:
            return "Daily"
        if lowered in {"30d", "monthly"} or "month" in lowered:
            return "Monthly"
        if "limit" in lowered:
            return fallback
    if window_minutes >= 25 * 24 * 60:
        months = max(1, round(window_minutes / (30 * 24 * 60)))
        return "Monthly" if months == 1 else f"{months} months"
    if window_minutes >= 6 * 24 * 60:
        weeks = max(1, round(window_minutes / (7 * 24 * 60)))
        return "Weekly" if weeks == 1 else f"{weeks} weeks"
    if window_minutes >= 20 * 60:
        days = max(1, round(window_minutes / (24 * 60)))
        return "Daily" if days == 1 else f"{days} days"
    if window_minutes >= 60:
        hours = window_minutes / 60
        return f"{hours:g} hours"
    if window_minutes > 0:
        return f"{window_minutes} minutes"
    return fallback or "Current window"


def make_item(
    *,
    item_id: str,
    provider_id: str,
    used_percent: Any,
    window_label: str,
    window_kind_value: str,
    resets_at: Any = 0,
    window_minutes: int = 0,
    group_id: str = "",
    group_name: str = "",
    metric_kind: str = "quota",
    remaining_amount: Any = None,
    total_amount: Any = None,
    currency: str = "",
) -> dict[str, Any]:
    used = clamp(used_percent)
    item = {
        "id": item_id,
        "providerId": provider_id,
        "providerName": PROVIDER_META[provider_id]["name"],
        "providerIcon": PROVIDER_META[provider_id]["icon"],
        "groupId": group_id,
        "groupName": group_name,
        "windowKind": window_kind_value,
        "windowLabel": window_label,
        "windowMinutes": max(0, int(window_minutes or 0)),
        "usedPercent": round(used, 2),
        "remainingPercent": round(100.0 - used, 2),
        "resetsAt": parse_timestamp_ms(resets_at),
        "metricKind": str(metric_kind or "quota"),
    }
    if remaining_amount is not None:
        item["remainingAmount"] = round(max(0.0, float(remaining_amount)), 4)
    if total_amount is not None:
        item["totalAmount"] = round(max(0.0, float(total_amount)), 4)
    if currency:
        item["currency"] = str(currency)
    return item


def provider_result(
    provider_id: str,
    *,
    items: Iterable[dict[str, Any]] = (),
    plan: str = "",
    source: str = "",
    error: str = "",
    stale: bool = False,
    updated_at: int = 0,
) -> dict[str, Any]:
    normalized_items = list(items)
    meta = PROVIDER_META[provider_id]
    return {
        "id": provider_id,
        "name": meta["name"],
        "icon": meta["icon"],
        "plan": str(plan or ""),
        "source": str(source or ""),
        "available": bool(normalized_items),
        "stale": bool(stale),
        "error": str(error or ""),
        "updatedAt": int(updated_at or int(time.time() * 1000)),
        "items": normalized_items,
    }


def read_json_tail(path: Path, max_bytes: int = 2 * 1024 * 1024) -> list[dict[str, Any]]:
    """Return JSONL objects newest-first without reading unbounded transcripts."""
    try:
        with path.open("rb") as handle:
            handle.seek(0, os.SEEK_END)
            size = handle.tell()
            start = max(0, size - max_bytes)
            handle.seek(start)
            payload = handle.read().decode("utf-8", "replace")
    except OSError:
        return []
    lines = payload.splitlines()
    if start > 0 and lines:
        lines = lines[1:]
    objects: list[dict[str, Any]] = []
    for line in reversed(lines):
        try:
            value = json.loads(line)
        except (TypeError, json.JSONDecodeError):
            continue
        if isinstance(value, dict):
            objects.append(value)
    return objects


def newest_files(roots: Iterable[Path], limit: int = 80) -> list[Path]:
    candidates: list[tuple[float, Path]] = []
    for root in roots:
        if not root.exists():
            continue
        try:
            iterator = root.rglob("*.jsonl") if root.is_dir() else [root]
            for path in iterator:
                try:
                    candidates.append((path.stat().st_mtime, path))
                except OSError:
                    continue
        except OSError:
            continue
    candidates.sort(key=lambda pair: pair[0], reverse=True)
    return [path for _, path in candidates[:limit]]


def parse_codex_rate_limits(rate_limits: dict[str, Any], updated_at: Any = 0) -> dict[str, Any]:
    items: list[dict[str, Any]] = []
    # Default window sizes used when a lane is null (fully exhausted).
    _default_minutes = {"primary": 300, "secondary": 10080}
    for lane_name in ("primary", "secondary"):
        lane = rate_limits.get(lane_name)
        if lane is None:
            # When Codex fully exhausts a quota window, the API returns the
            # lane as null instead of an object with used_percent.  Treat this
            # as 100 % used so the widget shows "0 % remaining" rather than
            # "Unavailable".
            minutes = _default_minutes.get(lane_name, 300)
            kind = window_kind(minutes, lane_name)
            items.append(
                make_item(
                    item_id=f"chatgpt:{kind}",
                    provider_id="chatgpt",
                    used_percent=100,
                    window_label=duration_label(minutes, lane_name),
                    window_kind_value=kind,
                    resets_at=0,
                    window_minutes=minutes,
                )
            )
            continue
        if not isinstance(lane, dict) or lane.get("used_percent") is None:
            continue
        minutes = int(lane.get("window_minutes") or 0)
        kind = window_kind(minutes, lane_name)
        resets_at: Any = lane.get("resets_at")
        if not resets_at and lane.get("resets_in_seconds") is not None:
            try:
                resets_at = int(
                    time.time() * 1000
                    + max(0.0, float(lane.get("resets_in_seconds") or 0)) * 1000
                )
            except (TypeError, ValueError):
                resets_at = 0
        items.append(
            make_item(
                item_id=f"chatgpt:{kind}",
                provider_id="chatgpt",
                used_percent=lane.get("used_percent"),
                window_label=duration_label(minutes, lane_name),
                window_kind_value=kind,
                resets_at=resets_at,
                window_minutes=minutes,
            )
        )
    return provider_result(
        "chatgpt",
        items=items,
        plan=str(rate_limits.get("plan_type") or ""),
        source="Codex session",
        error="" if items else "No Codex quota snapshot found",
        updated_at=parse_timestamp_ms(updated_at),
    )


def collect_chatgpt(home: Path | None = None) -> dict[str, Any]:
    codex_home = home or Path(os.environ.get("CODEX_HOME") or Path.home() / ".codex")
    files = newest_files(
        [codex_home / "sessions", codex_home / "archived_sessions"], limit=100
    )
    for path in files:
        for entry in read_json_tail(path):
            payload = entry.get("payload")
            if (
                entry.get("type") != "event_msg"
                or not isinstance(payload, dict)
                or payload.get("type") != "token_count"
                or not isinstance(payload.get("rate_limits"), dict)
            ):
                continue
            return parse_codex_rate_limits(payload["rate_limits"], entry.get("timestamp"))
    return provider_result(
        "chatgpt",
        source="Codex session",
        error="Use Codex once so it can publish a quota snapshot",
    )


def cache_path(cache_dir: Path, provider_id: str) -> Path:
    return cache_dir / f"{provider_id}.json"


def load_provider_cache(cache_dir: Path, provider_id: str) -> dict[str, Any] | None:
    path = cache_path(cache_dir, provider_id)
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    if not isinstance(payload, dict) or payload.get("id") != provider_id:
        return None
    try:
        updated_at = int(payload.get("updatedAt") or 0)
    except (TypeError, ValueError):
        return None
    if updated_at < 0 or not isinstance(payload.get("items", []), list):
        return None
    payload["updatedAt"] = updated_at
    return payload


def save_provider_cache(cache_dir: Path, payload: dict[str, Any]) -> None:
    try:
        cache_dir.mkdir(parents=True, exist_ok=True)
        target = cache_path(cache_dir, str(payload.get("id") or "unknown"))
        temporary = target.with_suffix(".json.tmp")
        temporary.write_text(
            json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n",
            encoding="utf-8",
        )
        os.chmod(temporary, 0o600)
        temporary.replace(target)
    except OSError:
        pass


def stale_cache(
    cached: dict[str, Any] | None, error: str, source_suffix: str = "cache"
) -> dict[str, Any] | None:
    if not cached:
        return None
    result = copy.deepcopy(cached)
    result["stale"] = True
    result["error"] = error
    original_source = str(result.get("source") or "")
    result["source"] = f"{original_source} ({source_suffix})".strip()
    return result


def read_json_object(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return value if isinstance(value, dict) else {}


def read_opencode_api_key(
    provider_ids: Iterable[str], auth_path: Path | None = None
) -> str:
    """Read one named OpenCode credential without exposing unrelated keys."""
    target = auth_path or Path.home() / ".local" / "share" / "opencode" / "auth.json"
    credentials = read_json_object(target)
    for provider_id in provider_ids:
        entry = credentials.get(provider_id)
        if not isinstance(entry, dict):
            continue
        key = str(entry.get("key") or "").strip()
        if key:
            return key
    return ""


def read_illogical_keyring_api_key(key_id: str) -> str:
    """Read one shell keyring field in memory; never write it to cache or stdout."""
    try:
        raw = subprocess.check_output(
            ["secret-tool", "lookup", "application", "illogical-impulse"],
            text=True,
            timeout=2,
            stderr=subprocess.DEVNULL,
        )
        payload = json.loads(raw)
    except (OSError, subprocess.SubprocessError, json.JSONDecodeError):
        return ""
    api_keys = payload.get("apiKeys") if isinstance(payload, dict) else None
    if not isinstance(api_keys, dict):
        return ""
    return str(api_keys.get(key_id) or "").strip()


def zai_api_key(
    *,
    claude_settings_path: Path | None = None,
    opencode_auth_path: Path | None = None,
) -> str:
    for name in ("ZAI_API_KEY", "Z_AI_API_KEY", "ZHIPUAI_API_KEY"):
        key = str(os.environ.get(name) or "").strip()
        if key:
            return key

    settings_path = claude_settings_path or Path.home() / ".claude" / "settings.json"
    settings = read_json_object(settings_path)
    environment = settings.get("env") if isinstance(settings.get("env"), dict) else {}
    base_url = str(environment.get("ANTHROPIC_BASE_URL") or "").lower()
    key = str(environment.get("ANTHROPIC_AUTH_TOKEN") or "").strip()
    if "api.z.ai" in base_url and key:
        return key

    return read_opencode_api_key(
        ("zai-coding-plan", "zai", "zhipuai", "zhipu"), opencode_auth_path
    )


def _kimi_config_api_key(target: Path) -> str:
    try:
        with target.open("rb") as handle:
            payload = tomllib.load(handle)
    except (OSError, tomllib.TOMLDecodeError):
        return ""
    providers = payload.get("providers") if isinstance(payload, dict) else None
    if not isinstance(providers, dict):
        return ""
    for provider in providers.values():
        if not isinstance(provider, dict):
            continue
        base_url = str(provider.get("base_url") or "").lower()
        key = str(provider.get("api_key") or "").strip()
        if "api.kimi.com/coding" in base_url and key:
            return key
    return ""


def kimi_api_key(
    *,
    kimi_roots: Iterable[Path] | None = None,
    opencode_auth_path: Path | None = None,
) -> str:
    key = str(os.environ.get("KIMI_API_KEY") or "").strip()
    if key:
        return key

    configured_share = str(os.environ.get("KIMI_SHARE_DIR") or "").strip()
    roots = list(kimi_roots) if kimi_roots is not None else [
        Path(configured_share) if configured_share else Path.home() / ".kimi",
        Path.home() / ".kimi-code",
    ]
    for root in roots:
        for relative in (
            Path("credentials") / "kimi-code.json",
            Path("credentials.json"),
        ):
            credential = read_json_object(root / relative)
            access_token = str(
                credential.get("access_token") or credential.get("accessToken") or ""
            ).strip()
            expires_at = finite_number(
                credential.get("expires_at") or credential.get("expiresAt")
            )
            if expires_at and expires_at > 10_000_000_000:
                expires_at /= 1000
            if access_token and (not expires_at or expires_at > time.time()):
                return access_token
        config_key = _kimi_config_api_key(root / "config.toml")
        if config_key:
            return config_key

    return read_opencode_api_key(("kimi-code", "kimi"), opencode_auth_path)


def opencode_api_key(auth_path: Path | None = None) -> str:
    key = str(os.environ.get("OPENCODE_GO_API_KEY") or "").strip()
    return key or read_opencode_api_key(("opencode-go",), auth_path)


def openrouter_api_key(auth_path: Path | None = None) -> str:
    for name in ("OPENROUTER_MANAGEMENT_KEY", "OPENROUTER_API_KEY"):
        key = str(os.environ.get(name) or "").strip()
        if key:
            return key
    key = read_illogical_keyring_api_key("openrouter")
    return key or read_opencode_api_key(("openrouter",), auth_path)


def request_json(
    url: str,
    api_key: str,
    *,
    opener: Callable[..., Any] = urllib.request.urlopen,
) -> dict[str, Any]:
    request = urllib.request.Request(
        url,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Accept": "application/json",
            "User-Agent": "ii-ai-plan-usage/1.0",
        },
        method="GET",
    )
    with opener(request, timeout=5) as response:
        payload = json.loads(response.read().decode("utf-8", "replace"))
    if not isinstance(payload, dict):
        raise ValueError("response is not an object")
    return payload


def usage_percent(values: dict[str, Any]) -> float | None:
    used = finite_number(values.get("used"))
    limit = finite_number(values.get("limit"))
    remaining = finite_number(values.get("remaining"))
    if used is None and limit is not None and remaining is not None:
        used = limit - remaining
    if limit is not None and limit > 0 and used is not None:
        return clamp(used / limit * 100)
    if used is not None and remaining is not None and used + remaining > 0:
        return clamp(used / (used + remaining) * 100)
    return None


def parse_zai_usage(payload: dict[str, Any], updated_at: Any = 0) -> dict[str, Any]:
    data = payload.get("data") if isinstance(payload.get("data"), dict) else {}
    items: list[dict[str, Any]] = []
    for limit in data.get("limits", []) or []:
        if not isinstance(limit, dict) or limit.get("percentage") is None:
            continue
        unit = int(finite_number(limit.get("unit")) or 0)
        number = int(finite_number(limit.get("number")) or 0)
        if unit == 3 and number == 5:
            kind, minutes, label = "short", 300, "5 hours"
        elif unit == 6 and number == 1:
            kind, minutes, label = "weekly", 10080, "Weekly"
        else:
            continue
        items.append(
            make_item(
                item_id=f"zai:{kind}",
                provider_id="zai",
                used_percent=limit.get("percentage"),
                window_label=label,
                window_kind_value=kind,
                resets_at=limit.get("nextResetTime"),
                window_minutes=minutes,
            )
        )
    return provider_result(
        "zai",
        items=items,
        plan=str(data.get("level") or ""),
        source="Z.AI quota API",
        error="" if items else "Z.AI did not return coding-plan quota windows",
        updated_at=parse_timestamp_ms(updated_at),
    )


def parse_kimi_usage(payload: dict[str, Any], updated_at: Any = 0) -> dict[str, Any]:
    items: list[dict[str, Any]] = []
    for row in payload.get("limits", []) or []:
        if not isinstance(row, dict):
            continue
        window = row.get("window") if isinstance(row.get("window"), dict) else {}
        detail = row.get("detail") if isinstance(row.get("detail"), dict) else {}
        duration = int(finite_number(window.get("duration")) or 0)
        time_unit = str(window.get("timeUnit") or "").upper()
        if "HOUR" in time_unit:
            minutes = duration * 60
        elif "DAY" in time_unit:
            minutes = duration * 24 * 60
        else:
            minutes = duration
        kind = window_kind(minutes)
        used = usage_percent(detail)
        if used is None and minutes > 0:
            # Kimi omits detail for a completely fresh rolling window.
            used = 0
        if used is None:
            continue
        items.append(
            make_item(
                item_id=f"kimi:{kind}",
                provider_id="kimi",
                used_percent=used,
                window_label=duration_label(minutes),
                window_kind_value=kind,
                resets_at=detail.get("resetTime") or row.get("resetTime"),
                window_minutes=minutes,
            )
        )

    weekly = payload.get("usage") if isinstance(payload.get("usage"), dict) else {}
    weekly_used = usage_percent(weekly)
    if weekly_used is not None:
        items.append(
            make_item(
                item_id="kimi:weekly",
                provider_id="kimi",
                used_percent=weekly_used,
                window_label="Weekly",
                window_kind_value="weekly",
                resets_at=weekly.get("resetTime"),
                window_minutes=10080,
            )
        )

    membership = payload.get("user") if isinstance(payload.get("user"), dict) else {}
    membership = (
        membership.get("membership")
        if isinstance(membership.get("membership"), dict)
        else {}
    )
    raw_level = str(membership.get("level") or "")
    plan = raw_level.removeprefix("LEVEL_").replace("_", " ").title()
    return provider_result(
        "kimi",
        items=items,
        plan=plan,
        source="Kimi Code usage API",
        error="" if items else "Kimi Code did not return quota windows",
        updated_at=parse_timestamp_ms(updated_at),
    )


def parse_opencode_usage(payload: dict[str, Any], updated_at: Any = 0) -> dict[str, Any]:
    usage = payload.get("usage") if isinstance(payload.get("usage"), dict) else {}
    items: list[dict[str, Any]] = []
    known = (
        ("rolling", "short", "5 hours", 300),
        ("weekly", "weekly", "Weekly", 10080),
        ("monthly", "monthly", "Monthly", 43200),
    )
    for key, kind, label, minutes in known:
        lane = usage.get(key)
        if not isinstance(lane, dict) or lane.get("percent") is None:
            continue
        items.append(
            make_item(
                item_id=f"opencode:{kind}",
                provider_id="opencode",
                used_percent=lane.get("percent"),
                window_label=label,
                window_kind_value=kind,
                resets_at=lane.get("resetsAt"),
                window_minutes=minutes,
            )
        )
    return provider_result(
        "opencode",
        items=items,
        plan="Go",
        source="OpenCode Go usage API",
        error="" if items else "OpenCode Go did not return quota windows",
        updated_at=parse_timestamp_ms(updated_at),
    )


def parse_openrouter_credits(
    payload: dict[str, Any], updated_at: Any = 0
) -> dict[str, Any]:
    data = payload.get("data") if isinstance(payload.get("data"), dict) else {}
    total = finite_number(data.get("total_credits"))
    used = finite_number(data.get("total_usage"))
    if total is None or used is None:
        return provider_result(
            "openrouter",
            source="OpenRouter credits API",
            error="OpenRouter did not return a credit balance",
            updated_at=parse_timestamp_ms(updated_at),
        )
    remaining = max(0.0, total - used)
    used_percent = clamp(used / total * 100) if total > 0 else 0
    item = make_item(
        item_id="openrouter:balance",
        provider_id="openrouter",
        used_percent=used_percent,
        window_label="Available balance",
        window_kind_value="balance",
        metric_kind="credits",
        remaining_amount=remaining,
        total_amount=max(0.0, total),
        currency="USD",
    )
    return provider_result(
        "openrouter",
        items=[item],
        plan="Credits",
        source="OpenRouter credits API",
        updated_at=parse_timestamp_ms(updated_at),
    )


def parse_openrouter_key(payload: dict[str, Any], updated_at: Any = 0) -> dict[str, Any]:
    data = payload.get("data") if isinstance(payload.get("data"), dict) else {}
    total = finite_number(data.get("limit"))
    remaining = finite_number(data.get("limit_remaining"))
    if total is None or remaining is None:
        return provider_result(
            "openrouter",
            source="OpenRouter current key",
            error="A management key or a capped OpenRouter key is required",
            updated_at=parse_timestamp_ms(updated_at),
        )
    remaining = max(0.0, remaining)
    used_percent = clamp((total - remaining) / total * 100) if total > 0 else 0
    item = make_item(
        item_id="openrouter:balance",
        provider_id="openrouter",
        used_percent=used_percent,
        window_label="Key balance",
        window_kind_value="balance",
        metric_kind="credits",
        remaining_amount=remaining,
        total_amount=max(0.0, total),
        currency="USD",
    )
    return provider_result(
        "openrouter",
        items=[item],
        plan="Key credits",
        source="OpenRouter current key",
        updated_at=parse_timestamp_ms(updated_at),
    )


def _cached_network_result(
    cache_dir: Path, provider_id: str, force: bool
) -> dict[str, Any] | None:
    cached = load_provider_cache(cache_dir, provider_id)
    if (
        cached
        and not force
        and int(time.time() * 1000) - int(cached.get("updatedAt") or 0)
        < NETWORK_CACHE_TTL_MS
    ):
        return cached
    return None


def collect_zai(
    cache_dir: Path,
    *,
    force: bool = False,
    api_key: str = "",
    opener: Callable[..., Any] = urllib.request.urlopen,
) -> dict[str, Any]:
    cached = _cached_network_result(cache_dir, "zai", force)
    if cached:
        return cached
    key = api_key or zai_api_key()
    if not key:
        return stale_cache(
            load_provider_cache(cache_dir, "zai"), "Z.AI coding-plan credentials are unavailable"
        ) or provider_result(
            "zai", source="Z.AI quota API", error="Sign in to Z.AI in a supported coding client first"
        )
    now_ms = int(time.time() * 1000)
    try:
        result = parse_zai_usage(request_json(ZAI_USAGE_URL, key, opener=opener), now_ms)
    except urllib.error.HTTPError as error:
        reason = f"Z.AI usage returned HTTP {error.code}"
        result = None
    except (urllib.error.URLError, TimeoutError, OSError):
        reason, result = "Z.AI usage is unreachable", None
    except (TypeError, ValueError, json.JSONDecodeError):
        reason, result = "Z.AI usage returned invalid data", None
    if result is not None:
        if result["available"]:
            save_provider_cache(cache_dir, result)
        return result
    return stale_cache(load_provider_cache(cache_dir, "zai"), reason) or provider_result(
        "zai", source="Z.AI quota API", error=reason
    )


def collect_kimi(
    cache_dir: Path,
    *,
    force: bool = False,
    api_key: str = "",
    opener: Callable[..., Any] = urllib.request.urlopen,
) -> dict[str, Any]:
    cached = _cached_network_result(cache_dir, "kimi", force)
    if cached:
        return cached
    key = api_key or kimi_api_key()
    if not key:
        return stale_cache(
            load_provider_cache(cache_dir, "kimi"), "Kimi Code credentials are unavailable"
        ) or provider_result(
            "kimi", source="Kimi Code usage API", error="Sign in with Kimi Code first"
        )
    now_ms = int(time.time() * 1000)
    try:
        result = parse_kimi_usage(request_json(KIMI_USAGE_URL, key, opener=opener), now_ms)
    except urllib.error.HTTPError as error:
        reason = f"Kimi Code usage returned HTTP {error.code}"
        result = None
    except (urllib.error.URLError, TimeoutError, OSError):
        reason, result = "Kimi Code usage is unreachable", None
    except (TypeError, ValueError, json.JSONDecodeError):
        reason, result = "Kimi Code usage returned invalid data", None
    if result is not None:
        if result["available"]:
            save_provider_cache(cache_dir, result)
        return result
    return stale_cache(load_provider_cache(cache_dir, "kimi"), reason) or provider_result(
        "kimi", source="Kimi Code usage API", error=reason
    )


def collect_opencode(
    cache_dir: Path,
    *,
    force: bool = False,
    api_key: str = "",
    opener: Callable[..., Any] = urllib.request.urlopen,
) -> dict[str, Any]:
    cached = _cached_network_result(cache_dir, "opencode", force)
    if cached:
        return cached
    key = api_key or opencode_api_key()
    if not key:
        return stale_cache(
            load_provider_cache(cache_dir, "opencode"), "OpenCode Go credentials are unavailable"
        ) or provider_result(
            "opencode", source="OpenCode Go usage API", error="Connect an OpenCode Go account first"
        )
    now_ms = int(time.time() * 1000)
    try:
        result = parse_opencode_usage(
            request_json(OPENCODE_USAGE_URL, key, opener=opener), now_ms
        )
    except urllib.error.HTTPError as error:
        reason = f"OpenCode Go usage returned HTTP {error.code}"
        result = None
    except (urllib.error.URLError, TimeoutError, OSError):
        reason, result = "OpenCode Go usage is unreachable", None
    except (TypeError, ValueError, json.JSONDecodeError):
        reason, result = "OpenCode Go usage returned invalid data", None
    if result is not None:
        if result["available"]:
            save_provider_cache(cache_dir, result)
        return result
    return stale_cache(load_provider_cache(cache_dir, "opencode"), reason) or provider_result(
        "opencode", source="OpenCode Go usage API", error=reason
    )


def collect_openrouter(
    cache_dir: Path,
    *,
    force: bool = False,
    api_key: str = "",
    opener: Callable[..., Any] = urllib.request.urlopen,
) -> dict[str, Any]:
    cached = _cached_network_result(cache_dir, "openrouter", force)
    if cached:
        return cached
    key = api_key or openrouter_api_key()
    if not key:
        return stale_cache(
            load_provider_cache(cache_dir, "openrouter"), "OpenRouter credentials are unavailable"
        ) or provider_result(
            "openrouter", source="OpenRouter credits API", error="Add an OpenRouter key in AI settings first"
        )
    now_ms = int(time.time() * 1000)
    try:
        result = parse_openrouter_credits(
            request_json(OPENROUTER_CREDITS_URL, key, opener=opener), now_ms
        )
    except urllib.error.HTTPError as error:
        if error.code not in (401, 403):
            reason = f"OpenRouter credits returned HTTP {error.code}"
            result = None
        else:
            try:
                result = parse_openrouter_key(
                    request_json(OPENROUTER_KEY_URL, key, opener=opener), now_ms
                )
            except urllib.error.HTTPError as key_error:
                reason = f"OpenRouter credits returned HTTP {key_error.code}"
                result = None
            except (urllib.error.URLError, TimeoutError, OSError):
                reason, result = "OpenRouter credits are unreachable", None
            except (TypeError, ValueError, json.JSONDecodeError):
                reason, result = "OpenRouter credits returned invalid data", None
    except (urllib.error.URLError, TimeoutError, OSError):
        reason, result = "OpenRouter credits are unreachable", None
    except (TypeError, ValueError, json.JSONDecodeError):
        reason, result = "OpenRouter credits returned invalid data", None
    if result is not None:
        if result["available"]:
            save_provider_cache(cache_dir, result)
        return result
    return stale_cache(
        load_provider_cache(cache_dir, "openrouter"), reason
    ) or provider_result("openrouter", source="OpenRouter credits API", error=reason)


def parse_claude_usage(
    payload: dict[str, Any], plan: str = "", updated_at: Any = 0
) -> dict[str, Any]:
    items: list[dict[str, Any]] = []
    known = (
        ("five_hour", "short", "5 hours", "", ""),
        ("seven_day", "weekly", "Weekly", "", ""),
        ("seven_day_opus", "weekly", "Weekly · Opus", "opus", "Opus"),
        ("seven_day_sonnet", "weekly", "Weekly · Sonnet", "sonnet", "Sonnet"),
    )
    for key, kind, label, group_id, group_name in known:
        lane = payload.get(key)
        if not isinstance(lane, dict) or lane.get("utilization") is None:
            continue
        item_id = f"claude:{group_id}:{kind}" if group_id else f"claude:{kind}"
        items.append(
            make_item(
                item_id=item_id,
                provider_id="claude",
                used_percent=lane.get("utilization"),
                window_label=label,
                window_kind_value=kind,
                resets_at=lane.get("resets_at"),
                group_id=group_id,
                group_name=group_name,
            )
        )
    return provider_result(
        "claude",
        items=items,
        plan=plan,
        source="Claude plan usage",
        error="" if items else "Claude did not return quota windows",
        updated_at=parse_timestamp_ms(updated_at),
    )


def find_nested(value: Any, key: str) -> Iterable[Any]:
    if isinstance(value, dict):
        if key in value:
            yield value[key]
        for child in value.values():
            yield from find_nested(child, key)
    elif isinstance(value, list):
        for child in value:
            yield from find_nested(child, key)


def local_claude_exhaustion(claude_home: Path | None = None) -> dict[str, Any] | None:
    home = claude_home or Path.home() / ".claude"
    for path in newest_files([home / "projects"], limit=40):
        for entry in read_json_tail(path, max_bytes=512 * 1024):
            for quota in find_nested(entry, "quotaLimits"):
                if not isinstance(quota, dict) or quota.get("status") != "rejected":
                    continue
                resets_at = parse_timestamp_ms(quota.get("resetsAt"))
                if resets_at and resets_at < int(time.time() * 1000) - 60_000:
                    continue
                raw_kind = str(quota.get("rateLimitType") or "five_hour")
                kind = window_kind(0, raw_kind)
                item = make_item(
                    item_id=f"claude:{kind}",
                    provider_id="claude",
                    used_percent=100,
                    window_label=duration_label(0, raw_kind),
                    window_kind_value=kind,
                    resets_at=resets_at,
                )
                return provider_result(
                    "claude",
                    items=[item],
                    source="Claude session limit event",
                    error="Only an exhausted local window is available",
                    stale=False,
                    updated_at=parse_timestamp_ms(entry.get("timestamp")),
                )
    return None


def collect_claude(
    cache_dir: Path,
    *,
    network_enabled: bool = True,
    force: bool = False,
    credentials_path: Path | None = None,
    opener: Callable[..., Any] = urllib.request.urlopen,
) -> dict[str, Any]:
    cached = load_provider_cache(cache_dir, "claude")
    now_ms = int(time.time() * 1000)
    if cached and not force and now_ms - int(cached.get("updatedAt") or 0) < 4 * 60 * 1000:
        return cached
    if not network_enabled:
        fallback = stale_cache(cached, "Network refresh is disabled in Settings")
        return fallback or local_claude_exhaustion() or provider_result(
            "claude",
            source="Claude local state",
            error="Enable Claude network refresh or open a Claude Code session",
        )

    path = credentials_path or Path.home() / ".claude" / ".credentials.json"
    try:
        credentials = json.loads(path.read_text(encoding="utf-8"))
        oauth = credentials.get("claudeAiOauth") or {}
        token = str(oauth.get("accessToken") or "")
        plan = str(oauth.get("subscriptionType") or "")
        expires_at = int(oauth.get("expiresAt") or 0)
    except (OSError, json.JSONDecodeError, TypeError, ValueError):
        token, plan, expires_at = "", "", 0

    if not token:
        fallback = stale_cache(cached, "Claude Code credentials are unavailable")
        return fallback or local_claude_exhaustion() or provider_result(
            "claude", source="Claude local state", error="Sign in with Claude Code first"
        )
    if expires_at and expires_at <= now_ms:
        fallback = stale_cache(cached, "Claude access token expired; open Claude Code to refresh it")
        return fallback or local_claude_exhaustion() or provider_result(
            "claude",
            plan=plan,
            source="Claude plan usage",
            error="Open Claude Code once to refresh its sign-in",
        )

    request = urllib.request.Request(
        CLAUDE_USAGE_URL,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/json",
            "User-Agent": "claude-cli/2.1 (AI Plan Usage; Quickshell)",
            "anthropic-beta": "oauth-2025-04-20",
        },
    )
    try:
        with opener(request, timeout=5) as response:
            raw = response.read().decode("utf-8", "replace")
            payload = json.loads(raw)
        result = parse_claude_usage(payload, plan=plan, updated_at=now_ms)
        if result["available"]:
            save_provider_cache(cache_dir, result)
        return result
    except urllib.error.HTTPError as error:
        reason = f"Claude usage returned HTTP {error.code}"
    except (urllib.error.URLError, TimeoutError, OSError) as error:
        reason = f"Claude usage is unreachable: {error.reason if hasattr(error, 'reason') else error}"
    except (TypeError, ValueError, json.JSONDecodeError):
        reason = "Claude usage returned invalid data"
    fallback = stale_cache(cached, reason)
    return fallback or local_claude_exhaustion() or provider_result(
        "claude", plan=plan, source="Claude plan usage", error=reason
    )


def extract_arg(command_line: str, name: str) -> str:
    match = re.search(
        rf"{re.escape(name)}(?:=|\s+)([^\s\"']+|\"[^\"]+\"|'[^']+')", command_line
    )
    return match.group(1).strip("\"'") if match else ""


def antigravity_candidates() -> list[dict[str, Any]]:
    try:
        output = subprocess.check_output(
            ["ps", "-eo", "pid=,args="], text=True, timeout=2, stderr=subprocess.DEVNULL
        )
    except (OSError, subprocess.SubprocessError):
        return []
    candidates: list[dict[str, Any]] = []
    for line in output.splitlines():
        stripped = line.strip()
        parts = stripped.split(None, 1)
        if len(parts) != 2 or not parts[0].isdigit():
            continue
        pid, command = int(parts[0]), parts[1]
        lowered = command.lower()
        is_language_server = "language_server" in lowered
        is_agy = re.search(r"(?:^|[\s/])agy(?:\s|$)", command) is not None
        if not is_language_server and not is_agy:
            continue
        if "antigravity" not in lowered and not is_agy:
            continue
        token = extract_arg(command, "--csrf_token")
        if not token:
            continue
        is_cli = "antigravity-cli" in lowered or is_agy
        is_app = "/opt/antigravity/" in lowered and "antigravity-ide" not in lowered
        score = 100 if is_cli else (90 if is_app else 50)
        candidates.append(
            {
                "pid": pid,
                "token": token,
                "command": command,
                "kind": "agy" if is_cli else ("app" if is_app else "ide"),
                "score": score,
            }
        )
    candidates.sort(key=lambda item: int(item["score"]), reverse=True)
    return candidates


def listening_ports(pid: int, command_line: str = "") -> list[int]:
    ports: list[int] = []
    for argument in ("--https_server_port", "--extension_server_port"):
        raw = extract_arg(command_line, argument)
        if raw.isdigit() and int(raw) > 0:
            ports.append(int(raw))
    try:
        output = subprocess.check_output(
            ["ss", "-ltnpH"], text=True, timeout=2, stderr=subprocess.DEVNULL
        )
    except (OSError, subprocess.SubprocessError):
        output = ""
    pid_marker = f"pid={pid},"
    for line in output.splitlines():
        if pid_marker not in line:
            continue
        columns = line.split()
        if len(columns) < 4:
            continue
        local_address = columns[3]
        match = re.search(r":(\d+)$", local_address)
        if match:
            ports.append(int(match.group(1)))
    return list(dict.fromkeys(port for port in ports if 0 < port < 65536))


def antigravity_request(
    port: int, csrf_token: str, path: str, use_https: bool
) -> dict[str, Any]:
    body = json.dumps(
        {
            "metadata": {
                "ideName": "antigravity",
                "extensionName": "antigravity",
                "ideVersion": "unknown",
                "locale": "en",
            }
        }
    )
    headers = {
        "Accept": "application/json",
        "Content-Type": "application/json",
        "Connect-Protocol-Version": "1",
        "X-Codeium-Csrf-Token": csrf_token,
    }
    if use_https:
        connection: Any = http.client.HTTPSConnection(
            "127.0.0.1", port, timeout=2, context=ssl._create_unverified_context()
        )
    else:
        connection = http.client.HTTPConnection("127.0.0.1", port, timeout=2)
    try:
        connection.request("POST", path, body, headers)
        response = connection.getresponse()
        raw = response.read().decode("utf-8", "replace")
        if response.status < 200 or response.status >= 300:
            raise RuntimeError(f"HTTP {response.status}")
        value = json.loads(raw)
        if not isinstance(value, dict):
            raise ValueError("response is not an object")
        return value
    finally:
        connection.close()


def antigravity_group_id(label: str) -> tuple[str, str]:
    lowered = label.lower()
    if "gemini" in lowered or "google" in lowered:
        return "gemini", "Gemini models"
    if "claude" in lowered or "gpt" in lowered or "openai" in lowered:
        return "other", "Claude & GPT models"
    normalized = re.sub(r"[^a-z0-9]+", "-", lowered).strip("-") or "models"
    return normalized, label or "Models"


def parse_antigravity_summary(
    payload: dict[str, Any], source: str = "agy local server"
) -> dict[str, Any]:
    root: Any = payload.get("response", payload)
    if isinstance(root, dict) and isinstance(root.get("quotaSummary"), dict):
        root = root["quotaSummary"]
    groups = root.get("groups", []) if isinstance(root, dict) else []
    items: list[dict[str, Any]] = []
    for group in groups or []:
        if not isinstance(group, dict):
            continue
        group_label = str(group.get("displayName") or group.get("name") or "Models")
        group_id, group_name = antigravity_group_id(group_label)
        for bucket in group.get("buckets", []) or []:
            if not isinstance(bucket, dict) or bucket.get("remainingFraction") is None:
                continue
            raw_window = str(
                bucket.get("window")
                or bucket.get("displayName")
                or bucket.get("bucketId")
                or ""
            )
            kind = window_kind(0, raw_window)
            remaining = clamp(float(bucket.get("remainingFraction")) * 100)
            label = duration_label(0, str(bucket.get("displayName") or raw_window))
            items.append(
                make_item(
                    item_id=f"antigravity:{group_id}:{kind}",
                    provider_id="antigravity",
                    used_percent=100 - remaining,
                    window_label=label,
                    window_kind_value=kind,
                    resets_at=bucket.get("resetTime"),
                    group_id=group_id,
                    group_name=group_name,
                )
            )
    plan = ""
    if isinstance(root, dict):
        plan = str(root.get("userTier") or root.get("planName") or "")
    return provider_result(
        "antigravity",
        items=items,
        plan=plan,
        source=source,
        error="" if items else "Antigravity quota summary is empty",
    )


def parse_antigravity_status(
    payload: dict[str, Any], source: str = "Antigravity local server"
) -> dict[str, Any]:
    response = payload.get("response")
    response = response if isinstance(response, dict) else {}
    user_status = payload.get("userStatus") or response.get("userStatus") or {}
    user_status = user_status if isinstance(user_status, dict) else {}
    plan_status = user_status.get("planStatus") or {}
    plan_status = plan_status if isinstance(plan_status, dict) else {}
    plan_info = plan_status.get("planInfo") or {}
    plan_info = plan_info if isinstance(plan_info, dict) else {}
    cascade = user_status.get("cascadeModelConfigData") or {}
    cascade = cascade if isinstance(cascade, dict) else {}
    aggregated: dict[str, dict[str, Any]] = {}
    for model in cascade.get("clientModelConfigs", []) or []:
        if not isinstance(model, dict):
            continue
        quota = model.get("quotaInfo") or {}
        quota = quota if isinstance(quota, dict) else {}
        if quota.get("remainingFraction") is None:
            continue
        model_alias = model.get("modelOrAlias") or {}
        model_alias = model_alias if isinstance(model_alias, dict) else {}
        model_label = str(model.get("label") or model_alias.get("model") or "Models")
        group_id, group_name = antigravity_group_id(model_label)
        used = 100 - clamp(float(quota.get("remainingFraction")) * 100)
        existing = aggregated.get(group_id)
        if existing is None or used > float(existing["used"]):
            aggregated[group_id] = {
                "used": used,
                "reset": quota.get("resetTime"),
                "name": group_name,
            }
    items = [
        make_item(
            item_id=f"antigravity:{group_id}:short",
            provider_id="antigravity",
            used_percent=value["used"],
            window_label="Current session",
            window_kind_value="short",
            resets_at=value["reset"],
            group_id=group_id,
            group_name=value["name"],
        )
        for group_id, value in aggregated.items()
    ]
    return provider_result(
        "antigravity",
        items=items,
        plan=str(plan_info.get("planName") or ""),
        source=source,
        error="" if items else "Antigravity did not expose model quotas",
    )


def collect_antigravity(cache_dir: Path) -> dict[str, Any]:
    cached = load_provider_cache(cache_dir, "antigravity")
    last_error = "Start agy or Antigravity to read its local quota service"
    for candidate in antigravity_candidates():
        ports = listening_ports(int(candidate["pid"]), str(candidate.get("command") or ""))
        for port in ports:
            for use_https in (True, False):
                source = "agy local server" if candidate["kind"] == "agy" else "Antigravity local server"
                try:
                    summary = antigravity_request(
                        port, str(candidate["token"]), ANTIGRAVITY_SUMMARY_PATH, use_https
                    )
                    result = parse_antigravity_summary(summary, source=source)
                    if result["available"]:
                        save_provider_cache(cache_dir, result)
                        return result
                except (OSError, RuntimeError, ValueError, json.JSONDecodeError) as error:
                    last_error = f"Antigravity quota summary unavailable: {error}"
                try:
                    status = antigravity_request(
                        port, str(candidate["token"]), ANTIGRAVITY_STATUS_PATH, use_https
                    )
                    result = parse_antigravity_status(status, source=source)
                    if result["available"]:
                        save_provider_cache(cache_dir, result)
                        return result
                except (OSError, RuntimeError, ValueError, json.JSONDecodeError) as error:
                    last_error = f"Antigravity local quota unavailable: {error}"
    fallback = stale_cache(cached, last_error)
    return fallback or provider_result(
        "antigravity", source="Antigravity local server", error=last_error
    )


def collect(
    providers: Iterable[str],
    *,
    cache_dir: Path,
    claude_network: bool,
    force: bool,
) -> dict[str, Any]:
    requested = [provider for provider in providers if provider in PROVIDER_META]
    results: list[dict[str, Any]] = []
    for provider_id in requested:
        try:
            if provider_id == "chatgpt":
                result = collect_chatgpt()
            elif provider_id == "claude":
                result = collect_claude(
                        cache_dir,
                        network_enabled=claude_network,
                        force=force,
                    )
            elif provider_id == "antigravity":
                result = collect_antigravity(cache_dir)
            elif provider_id == "zai":
                result = collect_zai(cache_dir, force=force)
            elif provider_id == "kimi":
                result = collect_kimi(cache_dir, force=force)
            elif provider_id == "opencode":
                result = collect_opencode(cache_dir, force=force)
            else:
                result = collect_openrouter(cache_dir, force=force)
        except Exception:
            # Provider payloads and local client state are independent. One
            # malformed adapter response must not erase healthy snapshots from
            # the other services, and exception text is intentionally omitted
            # because it could contain command-line credentials.
            result = provider_result(
                provider_id,
                source="AI plan collector",
                error=f"{PROVIDER_META[provider_id]['name']} quota data is invalid",
            )
        results.append(result)
    items = [item for provider in results for item in provider.get("items", [])]
    return {
        "ok": any(provider.get("available") for provider in results),
        "generatedAt": int(time.time() * 1000),
        "providers": results,
        "items": items,
    }


def parse_bool(value: str) -> bool:
    return str(value).strip().lower() not in {"0", "false", "no", "off"}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--providers",
        default="chatgpt,claude,antigravity",
        help="comma-separated provider ids",
    )
    parser.add_argument(
        "--cache-dir",
        default=os.path.join(
            os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache")),
            "ii",
            "ai-plan-usage",
        ),
    )
    parser.add_argument("--claude-network", default="true")
    parser.add_argument("--force", action="store_true")
    arguments = parser.parse_args()
    payload = collect(
        [item.strip() for item in arguments.providers.split(",") if item.strip()],
        cache_dir=Path(arguments.cache_dir).expanduser(),
        claude_network=parse_bool(arguments.claude_network),
        force=arguments.force,
    )
    json.dump(payload, sys.stdout, ensure_ascii=False, separators=(",", ":"))
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
