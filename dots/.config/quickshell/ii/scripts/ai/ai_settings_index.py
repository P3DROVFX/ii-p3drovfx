#!/usr/bin/env python3
"""Generate the Settings search index outside the Quickshell process.

The Settings pages are QML and their controls already carry the useful facts:
their Config binding, label, range, choices, section, and sometimes an enabled
dependency.  Reading those files from the shell every time the Settings window
opens is both costly and insufficient for tools, because the old registry does
not preserve the Config key.  This module deliberately keeps the parser small
and deterministic instead of trying to evaluate QML.

It is an infrastructure command, not an AI tool.  The shell can call ``check``
once per session and rebuild in the background when the source fingerprint is
out of date.  ``search`` and ``get`` are also useful for testing and for the
future Settings/overview consumers.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import time
import unicodedata
from collections.abc import Iterable
from pathlib import Path
from typing import Any


SCHEMA_VERSION = 6
# How far below the best match a result may score and still be worth showing.
RELEVANCE_FLOOR = 0.5
# A hard ceiling on results, whatever the caller asks for. A question has a
# handful of answers; a list of twenty is a search page, not an answer.
MAX_RESULTS = 6
SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_ROOT = SCRIPT_DIR.parents[1]
DEFAULT_CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "illogical-impulse/config.json"
DEFAULT_OUTPUT = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "quickshell/user/ai/settings_index.json"

WIDGETS: dict[str, tuple[str, str]] = {
    "ConfigSwitch": ("bool", "checked"),
    "ConfigSpinBox": ("int", "value"),
    "ConfigSlider": ("real", "value"),
    "ConfigSelectionArray": ("enum", "currentValue"),
    "ConfigComboBox": ("enum", "currentValue"),
    "DynamicConfigSelectionArray": ("enum", "currentValue"),
    "ConfigTextField": ("string", "inputText"),
    "ConfigLightDarkToggle": ("enum", "currentValue"),
    # Multi-line string editors bound straight to a config key (the AI system
    # prompt, for one) are settings like any other and take text writes.
    "MaterialTextArea": ("string", "text"),
}


def normalize(value: object) -> str:
    """Lowercase a human-searchable value while keeping accent-free matches."""
    text = unicodedata.normalize("NFKD", str(value or ""))
    text = "".join(char for char in text if not unicodedata.combining(char))
    return text.lower()


def tokenize(value: object) -> list[str]:
    return [token for token in re.split(r"[^\w]+", normalize(value)) if len(token) > 1]


# Words that carry no signal about which setting is meant. A question asked in
# full sentences — "where can I enable automatic suspend?" — otherwise scores
# every option containing "enable", and coverage rewards the ones that happen
# to contain the most filler.
STOPWORDS = frozenset("""
about and are can change configure disable do does enable find for from get
have how i in is it its me my of on onde option options or set setting settings
show that the their there this to turn use want was what when where which who
why with you your
como configurar de do dos das em como habilitar ligar desligar meu minha na no
onde opcao opcoes para por qual que quero seu sua tem ter um uma
""".split())


# The shortest prefix worth treating as the same word. "suspension" and
# "suspend" are the same question asked twice; "sus" is not a question. Six
# rather than five because five made "suspend" match "suspect", and one page's
# aliases mention hiding suspect wallpapers.
STEM_LENGTH = 6


def stem_of(token: str) -> str:
    return token[:STEM_LENGTH] if len(token) > STEM_LENGTH else ""


def stem_hit(stem: str, text: str) -> bool:
    """Whether any word in `text` starts with `stem`."""
    if not stem:
        return False
    for word in re.split(r"[^\w]+", text):
        if len(word) > STEM_LENGTH and word.startswith(stem):
            return True
    return False


def query_tokens_of(value: object) -> list[str]:
    """The words of a question that actually name something."""
    tokens = tokenize(value)
    meaningful = [token for token in tokens if token not in STOPWORDS]
    # Everything was filler: fall back rather than answer nothing at all.
    return meaningful or tokens


def _matching_end(text: str, start: int, opening: str = "{", closing: str = "}") -> int | None:
    """Return the matching delimiter while ignoring quoted strings/comments."""
    depth = 0
    quote = ""
    escaped = False
    line_comment = False
    block_comment = False
    index = start
    while index < len(text):
        char = text[index]
        next_char = text[index + 1] if index + 1 < len(text) else ""
        if line_comment:
            if char == "\n":
                line_comment = False
            index += 1
            continue
        if block_comment:
            if char == "*" and next_char == "/":
                block_comment = False
                index += 2
                continue
            index += 1
            continue
        if quote:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = ""
            index += 1
            continue
        if char in ("'", '"', "`"):
            quote = char
            index += 1
            continue
        if char == "/" and next_char == "/":
            line_comment = True
            index += 2
            continue
        if char == "/" and next_char == "*":
            block_comment = True
            index += 2
            continue
        if char == opening:
            depth += 1
        elif char == closing:
            depth -= 1
            if depth == 0:
                return index
        index += 1
    return None


def extract_blocks(text: str, component: str) -> list[dict[str, Any]]:
    """Port of SearchRegistry.extractBlocks, with comment-aware balancing."""
    results: list[dict[str, Any]] = []
    pattern = re.compile(rf"(?<![A-Za-z0-9_]){re.escape(component)}\s*{{")
    for match in pattern.finditer(text):
        brace = text.find("{", match.start(), match.end())
        end = _matching_end(text, brace)
        if end is None:
            continue
        results.append({
            "start": match.start(),
            "end": end + 1,
            "innerStart": brace + 1,
            "inner": text[brace + 1:end],
        })
    return results


def property_expression(block: str, name: str) -> str:
    """Read a simple QML property expression without evaluating it."""
    # Option objects inside `options: [...]` are written JSON-style with the
    # key quoted ("displayName": ...), which the plain-identifier pattern
    # never matched — every selection array came back with zero options.
    # Compact QML also places several properties on one line separated by
    # semicolons. Capturing to the newline made `buttonIcon: "bluetooth";
    # text: "Bluetooth"` one expression, and the later translated label won
    # when it was interpreted as text. Recognize semicolons as property
    # boundaries and stop only at a top-level separator, preserving nested JS
    # expressions and quoted punctuation.
    pattern = re.compile(rf"(?:^|[\n;])\s*\"?{re.escape(name)}\"?\s*:\s*")
    match = pattern.search(block)
    if not match:
        return ""

    start = match.end()
    depth = 0
    quote = ""
    escaped = False
    index = start
    while index < len(block):
        char = block[index]
        if quote:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = ""
            index += 1
            continue
        if char in ("'", '"', "`"):
            quote = char
        elif char in "([{":
            depth += 1
        elif char in ")]}" and depth > 0:
            depth -= 1
        elif depth == 0 and char in (";", "\n"):
            break
        index += 1

    return block[start:index].strip().rstrip(",").strip()


def text_from_expression(expression: str) -> str:
    """Extract static text from Translation.tr() or a quoted QML expression."""
    if not expression:
        return ""
    translated = re.search(r"Translation\.tr\(\s*(['\"])(.*?)\1", expression)
    if translated:
        return translated.group(2)
    literal = re.match(r"\s*(['\"])(.*?)\1", expression)
    return literal.group(2) if literal else ""


def config_key(expression: str) -> str:
    match = re.search(r"\bConfig\.options\.([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)", expression)
    return match.group(1) if match else ""



CONFIG_ASSIGNMENT = re.compile(
    r"\bConfig\.options\.([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)"
    r"\s*(?<![+\-*/%&|^=!<>])=(?![=>])"
)


def assigned_keys(block: str) -> set[str]:
    """Every config path the block's handlers write to.

    Only real assignments count: comparisons (`==`, `!=`, `>=`) and arrow
    functions (`=>`) are not writes, and compound assignments would bypass a
    control that claims to own the key alone.
    """
    return set(CONFIG_ASSIGNMENT.findall(block))


def direct_binding(expression: str) -> str:
    """The config path when a binding reads exactly one, bare."""
    expression = expression.strip()
    match = re.fullmatch(
        r"Config\.options\.([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)",
        expression,
    )
    # A computed value (`Config.options.x * 100`, a ternary, a helper) cannot
    # be written back safely by anything that only knows the stored key.
    return match.group(1) if match else ""


def qml_value(expression: str) -> Any:
    expression = expression.strip().rstrip(",")
    quoted = re.fullmatch(r"(['\"])(.*?)\1", expression)
    if quoted:
        return quoted.group(2)
    if expression == "true":
        return True
    if expression == "false":
        return False
    try:
        return float(expression) if "." in expression else int(expression)
    except ValueError:
        return None


def _object_property(block: str, name: str) -> str:
    """Read one key from an option object, however the lines are packed.

    Real pages spread `{ displayName, value }` over several lines, but packed
    single-line options exist too, and the line-anchored property reader only
    ever saw the first key of such an object.
    """
    match = re.search(rf"[\"']?{re.escape(name)}[\"']?\s*:", block)
    if not match:
        return ""
    rest = block[match.end():].lstrip()
    depth = 0
    end = len(rest)
    for index, char in enumerate(rest):
        if char in "([{":
            depth += 1
        elif char in ")]}":
            end = index
            break
        elif char == "," and depth == 0:
            end = index
            break
    return rest[:end].strip().rstrip(";").strip()


def option_values(block: str) -> list[dict[str, Any]]:
    """Extract stable display/value pairs from a ConfigSelectionArray.

    Pages use both a literal ``options: [...]`` and a computed binding such as
    ``options: { ...; return [...]; }``.  The latter is especially common for
    composite controls (bar position, sidebar position), which must remain
    searchable even though the launcher deliberately refuses to write them
    inline.
    """
    match = re.search(r"(?:^|\n)\s*options\s*:", block)
    if not match:
        return []
    expression = block[match.end():]
    direct_array = re.match(r"\s*\[", expression)
    returned_array = None if direct_array else re.search(r"\breturn\s*\[", expression)
    if direct_array:
        opening = match.end() + direct_array.end() - 1
    elif returned_array:
        opening = match.end() + returned_array.end() - 1
    else:
        return []
    end = _matching_end(block, opening, "[", "]")
    if end is None:
        return []
    values: list[dict[str, Any]] = []
    array = block[opening + 1:end]
    index = 0
    while index < len(array):
        start = array.find("{", index)
        if start < 0:
            break
        finish = _matching_end(array, start)
        if finish is None:
            break
        entry = array[start + 1:finish]
        value = qml_value(_object_property(entry, "value"))
        if value is not None:
            values.append({
                "label": text_from_expression(_object_property(entry, "displayName")),
                "value": value,
            })
        index = finish + 1
    return values


def options_are_dynamic(block: str) -> bool:
    """Whether option availability is decided by executable QML/JS.

    The generated index intentionally stores only stable labels and values.
    It cannot reproduce an option's live ``enabled`` binding, so a computed
    option array is searchable but must be opened in its real Settings page.
    """
    match = re.search(r"(?:^|\n)\s*options\s*:", block)
    if not match:
        return False
    expression = block[match.end():]
    direct_array = re.match(r"\s*\[", expression)
    returned_array = None if direct_array else re.search(r"\breturn\s*\[", expression)
    if direct_array:
        opening = match.end() + direct_array.end() - 1
    elif returned_array:
        opening = match.end() + returned_array.end() - 1
    else:
        # An external/helper-provided option model is executable state too.
        return True
    end = _matching_end(block, opening, "[", "]")
    if end is None:
        return True
    array = block[opening + 1:end]
    has_live_availability = re.search(r"(?:^|[,{])\s*[\"']?enabled[\"']?\s*:", array) is not None
    return direct_array is None or has_live_availability


def parse_pages(registry_path: Path) -> list[dict[str, Any]]:
    text = registry_path.read_text(encoding="utf-8")
    pages_marker = text.find("readonly property var pages")
    if pages_marker < 0:
        raise ValueError(f"could not find pages in {registry_path}")
    opening = text.find("[", pages_marker)
    closing = _matching_end(text, opening, "[", "]")
    if closing is None:
        raise ValueError(f"could not parse pages in {registry_path}")
    pages_text = text[opening + 1:closing]
    pages: list[dict[str, Any]] = []
    index = 0
    while index < len(pages_text):
        start = pages_text.find("{", index)
        if start < 0:
            break
        end = _matching_end(pages_text, start)
        if end is None:
            break
        entry = pages_text[start + 1:end]
        field = lambda name: re.search(rf'"{re.escape(name)}"\s*:\s*"([^"]*)"', entry)
        identifier = field("id")
        component = field("component")
        if identifier and component:
            def strings(name: str) -> list[str]:
                array = re.search(rf'"{re.escape(name)}"\s*:\s*\[([^\]]*)\]', entry, re.S)
                return re.findall(r'"([^"]+)"', array.group(1)) if array else []

            pages.append({
                "id": identifier.group(1),
                "name": field("name").group(1) if field("name") else identifier.group(1),
                "component": component.group(1),
                "subPages": strings("subPages"),
                "searchSources": strings("searchSources"),
                "aliases": strings("aliases"),
                "searchable": not bool(re.search(r'"searchable"\s*:\s*false', entry)),
            })
        index = end + 1
    return pages


def source_records(root: Path) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    config_root = root / "modules/settings/configs"
    for page in parse_pages(root / "modules/common/SettingsPageRegistry.qml"):
        if not page["searchable"]:
            continue
        records.append({**page, "path": root / page["component"], "subPage": ""})
        for subpage in page["subPages"]:
            records.append({**page, "path": config_root / subpage, "subPage": subpage})
        for source in page["searchSources"]:
            records.append({**page, "path": config_root / source, "subPage": ""})
    return records


def localized(value: str, translations: dict[str, Any]) -> str:
    translated = translations.get(value)
    return translated if isinstance(translated, str) and translated else value


def flat_config(value: Any, prefix: str = "") -> Iterable[tuple[str, Any]]:
    if isinstance(value, dict):
        for key, nested in value.items():
            yield from flat_config(nested, f"{prefix}.{key}" if prefix else key)
    elif prefix:
        yield prefix, value


def value_type(value: Any) -> str:
    if isinstance(value, bool):
        return "bool"
    if isinstance(value, int):
        return "int"
    if isinstance(value, float):
        return "real"
    if isinstance(value, str):
        return "string"
    if isinstance(value, list):
        return "list"
    return "unknown"


def source_fingerprint(root: Path, language: str) -> str:
    records = source_records(root)
    paths = [root / "modules/common/SettingsPageRegistry.qml", root / "scripts/ai/settings_synonyms.json"]
    if language:
        paths.append(root / "translations" / f"{language}.json")
    paths.extend(record["path"] for record in records)
    digest = hashlib.sha256()
    for path in sorted({path.resolve() for path in paths if path.exists()}):
        stat = path.stat()
        try:
            relative = path.relative_to(root)
        except ValueError:
            relative = path
        digest.update(f"{relative}\0{stat.st_mtime_ns}\0{stat.st_size}\n".encode("utf-8"))
    return digest.hexdigest()


def _section_for(offset: int, sections: list[dict[str, Any]], translations: dict[str, Any]) -> tuple[str, str, str]:
    containing = [section for section in sections if section["start"] <= offset < section["end"]]
    if not containing:
        return "", "", ""
    section = min(containing, key=lambda item: item["end"] - item["start"])
    title = text_from_expression(property_expression(section["inner"], "title"))
    return title, localized(title, translations), text_from_expression(property_expression(section["inner"], "icon"))


def extract_entries(record: dict[str, Any], root: Path, translations: dict[str, Any]) -> list[dict[str, Any]]:
    path: Path = record["path"]
    if not path.exists():
        return []
    text = path.read_text(encoding="utf-8")
    sections = extract_blocks(text, "ContentSection") + extract_blocks(text, "ContentSubsection")
    entries: list[dict[str, Any]] = []
    for widget, (widget_type, binding) in WIDGETS.items():
        for block in extract_blocks(text, widget):
            binding_expression = property_expression(block["inner"], binding)
            binding_key = direct_binding(binding_expression)
            referenced_binding_key = config_key(binding_expression)
            writes = assigned_keys(block["inner"])
            key = binding_key
            if binding_key:
                has_ui = len(writes) == 0 or writes == {binding_key}
            elif referenced_binding_key:
                # The display value mentions this key but transforms or
                # combines it. Keep the result discoverable without exposing
                # a control that writes display units into stored units.
                key = referenced_binding_key
                has_ui = False
            elif len(writes) == 1:
                # Controls that keep the current value on a helper object and
                # write the choice to config from the handler
                # (`currentValue: page.opts.x` + `onSelected: … appStats.x = v`).
                key = next(iter(writes))
                has_ui = True
            # A control driving several settings at once (the bar-position
            # selector packs bottom+vertical into one bitmask) must stay
            # findable and openable, but nothing may claim to write it
            # directly: writing one of its keys alone would corrupt the pair.
            else:
                # Last resort for identity only — the first config path the
                # block happens to mention. Never writable, still searchable
                # and deep-linkable like any other entry.
                key = config_key(block["inner"])
                has_ui = False
            if not key:
                continue
            label = ""
            for property_name in ("text", "title", "label", "placeholderText"):
                label = text_from_expression(property_expression(block["inner"], property_name))
                if label:
                    break
            description = text_from_expression(property_expression(block["inner"], "description"))
            if not description:
                for tooltip in extract_blocks(block["inner"], "StyledToolTip"):
                    description = text_from_expression(property_expression(tooltip["inner"], "text"))
                    if description:
                        break
            section, section_localized, section_icon = _section_for(block["start"], sections, translations)
            icon = text_from_expression(property_expression(block["inner"], "icon"))
            if not icon:
                icon = text_from_expression(property_expression(block["inner"], "buttonIcon")) or section_icon
            options = option_values(block["inner"])
            if options_are_dynamic(block["inner"]):
                has_ui = False
            option_labels = [str(option.get("label", "")) for option in options]
            if label:
                source_label = label
            elif section:
                # Arrays and text areas often carry no title of their own;
                # the subsection heading is what the interface shows right
                # above them, so it is the name a person would search.
                source_label = section
            else:
                source_label = key.rsplit(".", 1)[-1]
            entry: dict[str, Any] = {
                "key": key,
                "type": widget_type,
                "widget": widget,
                "hasUi": has_ui,
                # One label, in the language the interface is showing. The
                # index used to carry both and hand both to the model, which
                # is how an English interface got Portuguese toggles back.
                "label": localized(source_label, translations),
                "description": localized(description, translations),
                "icon": icon,
                "pageId": record["id"],
                "pageName": localized(record["name"], translations),
                "sectionTitle": section_localized or section,
                "subPage": record["subPage"],
                "aliases": list(record["aliases"]),
                "source": str(path.relative_to(root)),
                "blockStart": block["start"],
                "blockEnd": block["end"],
                # Only for matching: the untranslated strings stay searchable
                # so a key someone knows in English is still findable in a
                # translated interface. Never shown, never sent to a model.
                # Option names belong here too — "Week" is what someone sees
                # on the control, not just `defaultGranularity`.
                "match": " ".join(filter(None, [source_label, description, *option_labels, section, record["name"]])),
            }
            if widget in ("ConfigSpinBox", "ConfigSlider"):
                lower = qml_value(property_expression(block["inner"], "from"))
                upper = qml_value(property_expression(block["inner"], "to"))
                step = qml_value(property_expression(block["inner"], "stepSize"))
                if lower is not None or upper is not None or step is not None:
                    entry["range"] = {"from": lower, "to": upper, "step": step}
            if options:
                entry["options"] = options
            enabled_key = config_key(property_expression(block["inner"], "enabled"))
            if enabled_key:
                entry["dependsOn"] = enabled_key
            entries.append(entry)
    return entries


def load_json(path: Path, default: Any) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return default


def build_index(*, root: Path = DEFAULT_ROOT, config_path: Path = DEFAULT_CONFIG, language: str = "", output_path: Path = DEFAULT_OUTPUT) -> dict[str, Any]:
    root = Path(root).resolve()
    config_path = Path(config_path)
    # An empty locale, or one with no catalogue, means the source strings —
    # which are already English. Defaulting to any particular language here is
    # what made an English interface answer in Portuguese.
    translations = load_json(root / "translations" / f"{language}.json", {}) if language else {}
    synonyms = load_json(root / "scripts/ai/settings_synonyms.json", {})
    config = load_json(config_path, {})
    leaves = dict(flat_config(config))
    merged: dict[str, dict[str, Any]] = {}

    for record in source_records(root):
        for entry in extract_entries(record, root, translations):
            entry["currentValue"] = leaves.get(entry["key"])
            if entry["key"] in leaves:
                # The persisted type is authoritative.  Widgets provide the
                # useful UI shape, but QML may expose an int as a real alias.
                value_kind = value_type(leaves[entry["key"]])
                if entry["type"] != "enum":
                    entry["type"] = value_kind
            existing = merged.get(entry["key"])
            if existing is None:
                merged[entry["key"]] = entry
            else:
                location = {"pageId": entry["pageId"], "subPage": entry["subPage"]}
                if location != {"pageId": existing["pageId"], "subPage": existing["subPage"]}:
                    existing.setdefault("alsoIn", []).append(location)

    for key, value in leaves.items():
        if key in merged:
            continue
        merged[key] = {
            "key": key,
            "type": value_type(value),
            "widget": "",
            "hasUi": False,
            # No control anywhere, so there is no label to show. The last
            # segment of the key is a stand-in, and `label` stays empty so
            # ranking can tell "named by a person" from "named by the path".
            "label": "",
            "description": "",
            "icon": "settings",
            "pageId": "",
            "pageName": "",
            "sectionTitle": "",
            "subPage": "",
            "aliases": [],
            "source": "config.json",
            "blockStart": -1,
            "blockEnd": -1,
            "currentValue": value,
            "match": "",
        }

    for entry in merged.values():
        # Only what the entry says about itself. Including the page name, its
        # section and its aliases gave every option on the Power page the
        # synonyms for "suspend", so a search for "automatic suspend" answered
        # with the low-battery warning threshold.
        haystack = " ".join([entry["key"], entry["label"], entry["description"], entry["match"]])
        domains = [domain for domain in synonyms if domain in normalize(haystack)]
        keywords = sorted({word for domain in domains for word in [domain, *synonyms.get(domain, [])]})
        entry["keywords"] = keywords

    index = {
        "schema": SCHEMA_VERSION,
        "generatedAt": int(time.time()),
        "sourceHash": source_fingerprint(root, language),
        "language": language,
        "entries": sorted(merged.values(), key=lambda entry: entry["key"]),
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(index, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return index


def index_is_current(index: dict[str, Any], root: Path = DEFAULT_ROOT, language: str = "") -> bool:
    return index.get("schema") == SCHEMA_VERSION and index.get("language") == language and index.get("sourceHash") == source_fingerprint(Path(root).resolve(), language)


def load_index(path: Path) -> dict[str, Any]:
    index = load_json(path, {})
    if not isinstance(index, dict) or not isinstance(index.get("entries"), list):
        raise ValueError(f"invalid settings index: {path}")
    return index


def score_entry(original: dict[str, Any], query_tokens: list[str], query_normalized: str) -> dict[str, int]:
    """How well one entry answers a query.

    Three numbers come back, because ranking needs to tell apart three things
    that a single score blurs together:

    `covered`  — how much of the question this entry speaks to. A setting that
                 answers the whole question beats one that answers half of it,
                 whatever either scores. Without this, an entry whose label is
                 the single word "mode" beat the actual dark-mode switch for
                 the query "dark mode".

    `identity` — how much of that came from the entry *itself* rather than from
                 the page it happens to sit on. Sharing a page with something
                 called "Automatic suspend" is not the same as being it.

    `score`    — the ordering, phrase bonus included.
    """
    label = normalize(original.get("label"))
    key = normalize(original.get("key"))
    last_key = key.rsplit(".", 1)[-1]
    key_words = tokenize(key)
    description = normalize(original.get("description"))
    navigation = normalize(" ".join([
        *original.get("aliases", []),
        original.get("pageName", ""),
        original.get("sectionTitle", ""),
    ]))
    # The untranslated strings, so a key someone knows in English stays
    # findable in a translated interface.
    fallback = normalize(original.get("match", ""))
    option_labels = normalize(" ".join(
        str(option.get("label", "")) for option in original.get("options", [])
    ))
    keywords = [normalize(keyword) for keyword in original.get("keywords", [])]
    has_ui = bool(original.get("hasUi"))

    score = 40 if has_ui else 0
    covered = 0
    identity = 0
    for token in query_tokens:
        stem = stem_of(token)
        own = 0
        if token == label:
            own = max(own, 500)
        elif label.startswith(token):
            own = max(own, 220)
        elif token in label:
            own = max(own, 150)
        elif stem_hit(stem, label):
            own = max(own, 110)
        if token == last_key or token in tokenize(last_key):
            own = max(own, 180)
        elif token in key_words or any(word.startswith(token) for word in key_words):
            own = max(own, 120)
        elif stem_hit(stem, key):
            own = max(own, 90)
        if token in description:
            own = max(own, 120)
        elif stem_hit(stem, description):
            own = max(own, 80)
        if token in fallback:
            own = max(own, 90)
        elif stem_hit(stem, fallback):
            own = max(own, 70)

        # A domain synonym is curated for this entry — "dormir" really is what
        # this switch does — so it counts as the entry's own evidence. It is
        # the bridge that lets someone search in one language an interface
        # that is showing another.
        if token in keywords:
            own = max(own, 90)

        # The visible option names are the control's own words — someone
        # searching "week" means the Day/Week/Month selector, not whatever
        # else on the page contains the letters. Stronger than page-sharing,
        # weaker than the label itself.
        if token in tokenize(option_labels):
            own = max(own, 130)
        elif stem_hit(stem, option_labels):
            own = max(own, 100)

        # Borrowed evidence is not stemmed, and never stands alone. Sharing a
        # page with a word is weak enough already; matching it approximately
        # turns every option on that page into an answer.
        borrowed = 0
        if token in navigation:
            borrowed = max(borrowed, 100)

        best = max(own, borrowed)
        if best:
            covered += 1
            score += best
            identity += own

    base = score
    if query_normalized and query_normalized == label:
        score += 500
    # A key with no control anywhere has no label of its own; it should turn up
    # when someone names it, not when they describe something else.
    if not has_ui:
        score = int(score * 0.6)
        base = int(base * 0.6)
    return {"score": score, "base": base, "covered": covered, "identity": identity}


def search_entries(index: dict[str, Any], query: str, limit: int = 5) -> list[dict[str, Any]]:
    """The settings that answer a query, best first and few.

    Three rules keep the list short enough to read:

      * an entry has to speak to the whole question, when anything does;
      * it has to do so on its own account, not only because of the page it
        lives on — otherwise every option on the Power page answers "automatic
        suspend";
      * and it has to score within reach of the best match.

    Eight results for "automatic suspend" was not eight answers. It was two
    answers and six things that contain the word "suspend".
    """
    query_normalized = normalize(query).strip()
    query_tokens = query_tokens_of(query_normalized)
    if not query_tokens:
        return []

    scored: list[tuple[dict[str, int], dict[str, Any]]] = []
    for original in index.get("entries", []):
        verdict = score_entry(original, query_tokens, query_normalized)
        if verdict["covered"] == 0 or verdict["identity"] == 0:
            continue
        scored.append((verdict, original))

    if not scored:
        return []

    best_coverage = max(verdict["covered"] for verdict, _ in scored)
    scored = [item for item in scored if item[0]["covered"] == best_coverage]

    # The floor is measured against the best match *without* its exact-phrase
    # bonus. Measuring against the bonus lets one perfect hit push out every
    # other reasonable answer — which is how "Suspend at (%)" disappeared from
    # a search for "automatic suspend".
    top_base = max(verdict["base"] for verdict, _ in scored)
    floor = top_base * RELEVANCE_FLOOR
    scored = [item for item in scored if item[0]["base"] >= floor]

    scored.sort(key=lambda item: (-item[0]["score"], not item[1].get("hasUi"), item[1]["key"]))
    results = []
    for verdict, original in scored[:max(1, min(int(limit), MAX_RESULTS))]:
        entry = dict(original)
        entry["score"] = verdict["score"]
        results.append(entry)
    return results


def _arguments() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=DEFAULT_ROOT, help="II repository root")
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG, help="config.json to introspect")
    parser.add_argument("--lang", default="", help="interface locale; empty means the untranslated source strings")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUTPUT, help="index JSON path")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("build")
    commands.add_parser("check")
    search = commands.add_parser("search")
    search.add_argument("query")
    search.add_argument("--limit", type=int, default=5)
    get = commands.add_parser("get")
    get.add_argument("key")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _arguments().parse_args(argv)
    if args.command == "build":
        index = build_index(root=args.root, config_path=args.config, language=args.lang, output_path=args.out)
        print(json.dumps({"entries": len(index["entries"]), "sourceHash": index["sourceHash"], "out": str(args.out)}, ensure_ascii=False))
        return 0
    try:
        index = load_index(args.out)
    except ValueError as error:
        print(error, file=sys.stderr)
        return 1
    if args.command == "check":
        current = index_is_current(index, args.root, args.lang)
        print(index.get("sourceHash", ""))
        return 0 if current else 1
    if args.command == "search":
        print(json.dumps(search_entries(index, args.query, args.limit), ensure_ascii=False, indent=2))
        return 0
    for entry in index["entries"]:
        if entry.get("key") == args.key:
            print(json.dumps(entry, ensure_ascii=False, indent=2))
            return 0
    print(f"unknown setting key: {args.key}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
