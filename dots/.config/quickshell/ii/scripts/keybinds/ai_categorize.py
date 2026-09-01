#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
AI Keybinding Categorizer for Quickshell Cheatsheet.

Classifies keyboard shortcuts into intelligent semantic categories using
the user's configured AI model and active system language.
Supports OpenRouter, Google Gemini, and OpenAI-compatible providers.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path
from typing import Any


DEFAULT_STATE_FILE = Path.home() / ".local/state/quickshell/user/keybinds.json"
GEMINI_BASE_URL = "https://generativelanguage.googleapis.com/v1beta/models"
OPENROUTER_API_URL = "https://openrouter.ai/api/v1/chat/completions"
OPENAI_API_URL = "https://api.openai.com/v1/chat/completions"


def detect_system_language(cli_lang: str = "") -> str:
    """Determine the active UI language code (e.g., 'en_US', 'pt_BR')."""
    if cli_lang and cli_lang.strip() and cli_lang != "auto":
        return cli_lang.strip()
    for var in ("LC_ALL", "LC_MESSAGES", "LANG"):
        val = os.environ.get(var, "").strip()
        if val:
            return val.split(".")[0]
    return "en_US"


def get_language_meta(lang_code: str) -> dict[str, Any]:
    """Get metadata and standard category suggestions for the active language."""
    prefix = lang_code.lower()[:2]
    if prefix == "pt":
        return {
            "name": "Portuguese (Português)",
            "code": lang_code,
            "categories": [
                "Navegação & Movimentação",
                "Edição de Texto",
                "Janelas & Abas",
                "Busca & Substituição",
                "IA & Autocompletar",
                "Arquivos & Projeto",
                "Código & Refatoração",
                "Git & Controle de Versão",
                "Terminal & Execução",
                "Geral",
            ],
            "user_prompt": (
                "Por favor, analise e organize semanticamente os {count} atalhos de teclado do **{page_name}** "
                "({program_name}). Distribua atalhos genéricos em categorias intuitivas e claras."
            ),
            "assistant_summary": (
                "Organizei com sucesso os **{count} atalhos** de **{page_name}** em **{cat_count} categorias semânticas**:\n\n"
                "{cat_list}\n\nAs alterações foram aplicadas diretamente à sua coleção de atalhos."
            ),
            "cat_item": "- **{cat}**: {count} atalhos",
        }
    elif prefix == "es":
        return {
            "name": "Spanish (Español)",
            "code": lang_code,
            "categories": [
                "Navegación & Movimiento",
                "Edición de Texto",
                "Ventanas & Pestañas",
                "Búsqueda & Reemplazo",
                "IA & Autocompletado",
                "Archivos & Proyecto",
                "Código & Refactorización",
                "Git & Control de Versiones",
                "Terminal & Ejecución",
                "General",
            ],
            "user_prompt": (
                "Por favor, analiza y organiza semánticamente los {count} atajos de teclado de **{page_name}** "
                "({program_name}). Distribuye los atajos en categorías intuitivas."
            ),
            "assistant_summary": (
                "Se organizaron con éxito los **{count} atajos** de **{page_name}** en **{cat_count} categorías semánticas**:\n\n"
                "{cat_list}\n\nLos cambios se han aplicado directamente a su colección de atajos."
            ),
            "cat_item": "- **{cat}**: {count} atajos",
        }
    elif prefix == "de":
        return {
            "name": "German (Deutsch)",
            "code": lang_code,
            "categories": [
                "Navigation & Bewegung",
                "Textbearbeitung",
                "Fenster & Tabs",
                "Suchen & Ersetzen",
                "KI & Vervollständigung",
                "Dateien & Projekt",
                "Code & Refaktorisierung",
                "Git & Versionskontrolle",
                "Terminal & Ausführung",
                "Allgemein",
            ],
            "user_prompt": (
                "Bitte analysiere und organisiere die {count} Tastaturkürzel für **{page_name}** "
                "({program_name}) in semantische Kategorien."
            ),
            "assistant_summary": (
                "Die **{count} Tastaturkürzel** für **{page_name}** wurden erfolgreich in **{cat_count} semantische Kategorien** eingeteilt:\n\n"
                "{cat_list}\n\nDie Änderungen wurden direkt übernommen."
            ),
            "cat_item": "- **{cat}**: {count} Kürzel",
        }
    elif prefix == "fr":
        return {
            "name": "French (Français)",
            "code": lang_code,
            "categories": [
                "Navigation & Déplacement",
                "Édition de texte",
                "Fenêtres & Onglets",
                "Recherche & Remplacement",
                "IA & Complétion",
                "Fichiers & Projet",
                "Code & Refactorisation",
                "Git & Contrôle de version",
                "Terminal & Exécution",
                "Général",
            ],
            "user_prompt": (
                "Veuillez analyser et classer sémantiquement les {count} raccourcis clavier pour **{page_name}** "
                "({program_name})."
            ),
            "assistant_summary": (
                "Les **{count} raccourcis** pour **{page_name}** ont été organisés avec succès en **{cat_count} catégories sémantiques**:\n\n"
                "{cat_list}\n\nLes modifications ont été appliquées."
            ),
            "cat_item": "- **{cat}**: {count} raccourcis",
        }
    else:
        return {
            "name": "English",
            "code": lang_code,
            "categories": [
                "Navigation & Motion",
                "Editing & Text Manipulation",
                "Window & Buffer Management",
                "Search & Replace",
                "AI & Completion",
                "File & Project Operations",
                "Code & Refactoring",
                "Git & Version Control",
                "Terminal & Execution",
                "General",
            ],
            "user_prompt": (
                "Please analyze and semantically categorize the {count} keyboard shortcuts for **{page_name}** "
                "({program_name}). Group generic shortcuts into intuitive semantic categories."
            ),
            "assistant_summary": (
                "Successfully organized **{count} shortcuts** for **{page_name}** into **{cat_count} semantic categories**:\n\n"
                "{cat_list}\n\nThe changes have been applied directly to your shortcut collection."
            ),
            "cat_item": "- **{cat}**: {count} shortcuts",
        }


def get_api_credentials() -> dict[str, str]:
    """Retrieve available API keys from environment or secret-tool."""
    credentials: dict[str, str] = {}
    
    # Check environment variables
    if os.environ.get("OPENROUTER_API_KEY"):
        credentials["openrouter"] = os.environ["OPENROUTER_API_KEY"].strip()
    if os.environ.get("GEMINI_API_KEY"):
        credentials["gemini"] = os.environ["GEMINI_API_KEY"].strip()
    if os.environ.get("OPENAI_API_KEY"):
        credentials["openai"] = os.environ["OPENAI_API_KEY"].strip()

    # If missing, query secret-tool
    if not credentials.get("openrouter") or not credentials.get("gemini") or not credentials.get("openai"):
        try:
            result = subprocess.run(
                ["secret-tool", "lookup", "application", "illogical-impulse"],
                capture_output=True,
                text=True,
                check=False,
                timeout=4,
            )
            if result.returncode == 0 and result.stdout.strip():
                data = json.loads(result.stdout.strip())
                api_keys = data.get("apiKeys", {})
                if not credentials.get("openrouter") and api_keys.get("openrouter"):
                    credentials["openrouter"] = str(api_keys["openrouter"]).strip()
                if not credentials.get("gemini") and api_keys.get("gemini"):
                    credentials["gemini"] = str(api_keys["gemini"]).strip()
                if not credentials.get("openai") and api_keys.get("openai"):
                    credentials["openai"] = str(api_keys["openai"]).strip()
        except Exception as exc:
            print(f"[ai_categorize] Keyring lookup note: {exc}", file=sys.stderr)

    return credentials


def build_categorization_prompt(
    page_name: str,
    program_name: str,
    keybinds: list[dict[str, Any]],
    lang_meta: dict[str, Any],
) -> str:
    """Build a system prompt enforcing the target language and JSON schema."""
    context_info = f"Application: {program_name or page_name} (Page: {page_name})"
    target_lang = lang_meta["name"]
    category_examples = "\n".join(f"   - \"{c}\"" for c in lang_meta["categories"])

    items_to_process = []
    for idx, kb in enumerate(keybinds):
        items_to_process.append({
            "index": idx,
            "keys": kb.get("keys", ""),
            "description": kb.get("description", ""),
            "category": kb.get("category", "General"),
            "context": kb.get("context", ""),
            "command": kb.get("command", ""),
        })

    prompt = f"""You are an expert software developer and keyboard shortcut organizer.

Context: {context_info}
Target Language: {target_lang} ({lang_meta["code"]})

Task:
You are provided with {len(keybinds)} keyboard shortcuts.
Many shortcuts are currently grouped into a single generic category (such as "Custom mappings" or "General") or have vague placeholder descriptions (such as "Custom mapping").

Instructions:
1. Classify every shortcut into a cohesive, professional semantic category.
   All category names MUST be in {target_lang}.
   Examples of standard categories in {target_lang}:
{category_examples}

2. If a shortcut description is vague (e.g., "Custom mapping", empty, or generic placeholder), deduce and provide a clear, concise description in {target_lang} based on the shortcut key combination, context, and command.

3. PRESERVE EVERY SINGLE SHORTCUT. Do NOT add, remove, or modify shortcut keys. Return exactly {len(keybinds)} items matching their original "index".

Input Shortcuts:
{json.dumps(items_to_process, ensure_ascii=False, indent=2)}

Output Format:
You MUST return ONLY a JSON object matching this schema:
{{
  "keybinds": [
    {{
      "index": 0,
      "category": "Category in {target_lang}",
      "description": "Concise description in {target_lang}"
    }}
  ]
}}
"""
    return prompt


def call_openrouter(api_key: str, model_name: str, prompt: str) -> list[dict[str, Any]]:
    """Call OpenRouter API with JSON format."""
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "HTTP-Referer": "https://github.com/pedro-lucas-mp/quickshell-ii",
        "X-Title": "Quickshell Cheatsheet",
    }
    payload = {
        "model": model_name or "nvidia/nemotron-3-ultra-550b-a55b:free",
        "messages": [{"role": "user", "content": prompt}],
        "response_format": {"type": "json_object"},
        "temperature": 0.1,
    }
    req = urllib.request.Request(
        OPENROUTER_API_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers=headers,
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        body = json.loads(resp.read().decode("utf-8"))
        choices = body.get("choices", [])
        if not choices:
            raise ValueError("OpenRouter returned no choices.")
        text = choices[0]["message"]["content"]
        # Handle markdown code fences if model returned ```json ... ```
        clean_text = text.strip()
        if clean_text.startswith("```"):
            clean_text = clean_text.split("\n", 1)[-1].rsplit("```", 1)[0].strip()
        result = json.loads(clean_text)
        if isinstance(result, dict) and "keybinds" in result:
            return result["keybinds"]
        if isinstance(result, list):
            return result
        raise ValueError(f"Unexpected JSON structure: {text[:200]}")


def call_gemini(api_key: str, model_name: str, prompt: str) -> list[dict[str, Any]]:
    """Call Google Gemini API with JSON mode."""
    target_model = model_name or "gemini-2.5-flash"
    url = f"{GEMINI_BASE_URL}/{target_model}:generateContent"
    headers = {
        "x-goog-api-key": api_key,
        "Content-Type": "application/json",
    }
    payload = {
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {
            "temperature": 0.1,
            "responseMimeType": "application/json",
        },
    }
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers=headers,
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        body = json.loads(resp.read().decode("utf-8"))
        candidates = body.get("candidates", [])
        if not candidates:
            raise ValueError("Gemini returned no candidates.")
        text = candidates[0]["content"]["parts"][0]["text"]
        clean_text = text.strip()
        if clean_text.startswith("```"):
            clean_text = clean_text.split("\n", 1)[-1].rsplit("```", 1)[0].strip()
        result = json.loads(clean_text)
        if isinstance(result, dict) and "keybinds" in result:
            return result["keybinds"]
        if isinstance(result, list):
            return result
        raise ValueError(f"Unexpected response structure: {text[:200]}")


def call_openai(api_key: str, model_name: str, prompt: str) -> list[dict[str, Any]]:
    """Call OpenAI or OpenAI-compatible endpoint."""
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }
    payload = {
        "model": model_name or "gpt-4o",
        "messages": [{"role": "user", "content": prompt}],
        "response_format": {"type": "json_object"},
        "temperature": 0.1,
    }
    req = urllib.request.Request(
        OPENAI_API_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers=headers,
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        body = json.loads(resp.read().decode("utf-8"))
        choices = body.get("choices", [])
        if not choices:
            raise ValueError("OpenAI returned no choices.")
        text = choices[0]["message"]["content"]
        clean_text = text.strip()
        if clean_text.startswith("```"):
            clean_text = clean_text.split("\n", 1)[-1].rsplit("```", 1)[0].strip()
        result = json.loads(clean_text)
        if isinstance(result, dict) and "keybinds" in result:
            return result["keybinds"]
        if isinstance(result, list):
            return result
        raise ValueError(f"Unexpected response structure: {text[:200]}")


def record_ai_session(
    page_name: str,
    program_name: str,
    keybinds: list[dict[str, Any]],
    updated_keybinds: list[dict[str, Any]],
    unique_categories: list[str],
    model_used: str,
    lang_meta: dict[str, Any],
) -> None:
    """Record this categorization interaction into the AiChat / AiSessions history."""
    sessions_dir = Path.home() / ".local/state/quickshell/user/ai/sessions"
    try:
        sessions_dir.mkdir(parents=True, exist_ok=True)
        session_id = str(uuid.uuid4())
        now = int(time.time() * 1000)

        user_prompt_summary = lang_meta["user_prompt"].format(
            count=len(keybinds),
            page_name=page_name,
            program_name=program_name or "custom app",
        )

        counts_by_cat: dict[str, int] = {}
        for kb in updated_keybinds:
            cat = kb.get("category", "General")
            counts_by_cat[cat] = counts_by_cat.get(cat, 0) + 1

        cat_lines = "\n".join(
            lang_meta["cat_item"].format(cat=cat, count=cnt)
            for cat, cnt in sorted(counts_by_cat.items())
        )
        assistant_response = lang_meta["assistant_summary"].format(
            count=len(keybinds),
            page_name=page_name,
            cat_count=len(unique_categories),
            cat_list=cat_lines,
        )

        session_payload = {
            "schema": 1,
            "id": session_id,
            "title": f"Keybinds: {page_name}",
            "createdAt": now,
            "updatedAt": now,
            "pinned": False,
            "modelId": model_used or "gemini-2.5-flash",
            "messages": [
                {
                    "id": str(uuid.uuid4()),
                    "role": "user",
                    "content": user_prompt_summary,
                    "rawContent": user_prompt_summary,
                    "createdAt": now,
                },
                {
                    "id": str(uuid.uuid4()),
                    "role": "assistant",
                    "content": assistant_response,
                    "rawContent": assistant_response,
                    "createdAt": now + 10,
                },
            ],
            "tags": ["keybinds", "cheatsheet", program_name.lower() if program_name else "custom"],
        }

        # Write the session file
        session_file = sessions_dir / f"{session_id}.json"
        with open(session_file, "w", encoding="utf-8") as f:
            json.dump(session_payload, f, ensure_ascii=False, indent=2)

        # Update index.json
        index_file = sessions_dir / "index.json"
        index_data: list[dict[str, Any]] = []
        if index_file.exists():
            try:
                with open(index_file, "r", encoding="utf-8") as f:
                    raw_idx = json.load(f)
                if isinstance(raw_idx, dict) and isinstance(raw_idx.get("sessions"), list):
                    index_data = raw_idx["sessions"]
                elif isinstance(raw_idx, list):
                    index_data = raw_idx
            except Exception:
                index_data = []

        new_entry = {
            "id": session_id,
            "title": f"Keybinds: {page_name}",
            "createdAt": now,
            "updatedAt": now,
            "pinned": False,
            "modelId": model_used or "gemini-2.5-flash",
            "messageCount": 2,
            "preview": user_prompt_summary[:120],
            "tags": ["keybinds", "cheatsheet"],
        }
        index_data = [new_entry] + [e for e in index_data if isinstance(e, dict) and e.get("id") != session_id]
        with open(index_file, "w", encoding="utf-8") as f:
            json.dump({"schema": 3, "sessions": index_data}, f, ensure_ascii=False, indent=2)
    except Exception as exc:
        print(f"[ai_categorize] Warning saving AI chat session: {exc}", file=sys.stderr)


def categorize_page_keybinds(
    page_data: dict[str, Any],
    requested_model: str = "",
    lang_code: str = "en_US",
) -> tuple[bool, list[dict[str, Any]], str, str]:
    """Categorize keybinds using the requested AI model and target language."""
    keybinds = page_data.get("keybinds", [])
    if not keybinds:
        return True, [], "", "No keybinds to categorize."

    creds = get_api_credentials()
    lang_meta = get_language_meta(lang_code)

    page_name = str(page_data.get("name", "Shortcuts"))
    program_name = str(page_data.get("program", ""))
    prompt = build_categorization_prompt(page_name, program_name, keybinds, lang_meta)

    categorized_updates: list[dict[str, Any]] = []
    error_msg = ""
    model_used = ""

    # Parse requested model provider & identifier
    req_model = requested_model.strip()
    provider = ""
    model_name = ""

    if ":" in req_model:
        provider, model_name = req_model.split(":", 1)
    elif "/" in req_model and not req_model.startswith("gemini-"):
        provider = "openrouter"
        model_name = req_model
    elif req_model.startswith("gemini-"):
        provider = "gemini"
        model_name = req_model
    elif req_model.startswith("gpt-"):
        provider = "openai"
        model_name = req_model
    else:
        provider = req_model
        model_name = ""

    # 1. Execute requested provider first
    if provider == "openrouter" and creds.get("openrouter"):
        try:
            categorized_updates = call_openrouter(creds["openrouter"], model_name, prompt)
            model_used = req_model or f"openrouter:{model_name}"
        except Exception as e:
            error_msg = f"OpenRouter ({model_name}) failed: {e}"
            print(f"[ai_categorize] {error_msg}", file=sys.stderr)

    elif provider == "gemini" and creds.get("gemini"):
        try:
            categorized_updates = call_gemini(creds["gemini"], model_name, prompt)
            model_used = req_model or f"gemini:{model_name}"
        except Exception as e:
            error_msg = f"Gemini ({model_name}) failed: {e}"
            print(f"[ai_categorize] {error_msg}", file=sys.stderr)

    elif provider == "openai" and creds.get("openai"):
        try:
            categorized_updates = call_openai(creds["openai"], model_name, prompt)
            model_used = req_model or f"openai:{model_name}"
        except Exception as e:
            error_msg = f"OpenAI ({model_name}) failed: {e}"
            print(f"[ai_categorize] {error_msg}", file=sys.stderr)

    # 2. Fallbacks if primary attempt did not succeed
    if not categorized_updates and creds.get("openrouter") and provider != "openrouter":
        try:
            fallback_model = "nvidia/nemotron-3-ultra-550b-a55b:free"
            categorized_updates = call_openrouter(creds["openrouter"], fallback_model, prompt)
            model_used = f"openrouter:{fallback_model}"
        except Exception as e:
            error_msg = f"OpenRouter fallback failed: {e}"
            print(f"[ai_categorize] {error_msg}", file=sys.stderr)

    if not categorized_updates and creds.get("gemini") and provider != "gemini":
        try:
            fallback_model = "gemini-2.5-flash"
            categorized_updates = call_gemini(creds["gemini"], fallback_model, prompt)
            model_used = f"gemini:{fallback_model}"
        except Exception as e:
            error_msg = f"Gemini fallback failed: {e}"
            print(f"[ai_categorize] {error_msg}", file=sys.stderr)

    if not categorized_updates:
        if not creds:
            return False, keybinds, "", "No AI API keys configured (OpenRouter/Gemini/OpenAI)."
        return False, keybinds, "", error_msg or "Failed to categorize keybinds with AI."

    # Map updates back to original keybind array
    updated_keybinds = [dict(kb) for kb in keybinds]
    update_map = {}
    for item in categorized_updates:
        if isinstance(item, dict) and "index" in item:
            update_map[int(item["index"])] = item

    for idx, kb in enumerate(updated_keybinds):
        if idx in update_map:
            u = update_map[idx]
            new_cat = str(u.get("category", "")).strip()
            new_desc = str(u.get("description", "")).strip()
            if new_cat:
                kb["category"] = new_cat
            # If current description is generic, update with AI description
            current_desc = str(kb.get("description", "")).strip()
            if new_desc and (current_desc in ("Custom mapping", "Mapeamento personalizado", "") or not current_desc):
                kb["description"] = new_desc

    return True, updated_keybinds, model_used, ""


def main() -> None:
    parser = argparse.ArgumentParser(description="AI Keybinding Categorizer")
    parser.add_argument("page_id", nargs="?", default="", help="Page ID in keybinds storage")
    parser.add_argument("--file", default=str(DEFAULT_STATE_FILE), help="Path to keybinds.json")
    parser.add_argument("--json", dest="json_payload", default="", help="Inline JSON page payload")
    parser.add_argument("--model", default="", help="AI Model ID (e.g., 'openrouter:nvidia/nemotron-3-ultra-550b-a55b:free')")
    parser.add_argument("--lang", default="", help="Target language code (e.g., 'en_US', 'pt_BR')")

    args = parser.parse_args()
    lang_code = detect_system_language(args.lang)

    page_data: dict[str, Any] = {}
    storage_file = Path(args.file)

    if args.json_payload:
        try:
            page_data = json.loads(args.json_payload)
        except Exception as e:
            print(json.dumps({"ok": False, "error": f"Invalid JSON payload: {e}"}))
            sys.exit(1)
    elif args.page_id:
        if not storage_file.exists():
            print(json.dumps({"ok": False, "error": f"Keybinds file not found at {storage_file}"}))
            sys.exit(1)
        try:
            with open(storage_file, "r", encoding="utf-8") as f:
                storage_data = json.load(f)
            pages = storage_data.get("pages", [])
            for p in pages:
                if str(p.get("id")) == args.page_id:
                    page_data = p
                    break
            if not page_data:
                print(json.dumps({"ok": False, "error": f"Page with ID '{args.page_id}' not found."}))
                sys.exit(1)
        except Exception as e:
            print(json.dumps({"ok": False, "error": f"Error reading storage file: {e}"}))
            sys.exit(1)
    else:
        if not sys.stdin.isatty():
            try:
                page_data = json.loads(sys.stdin.read())
            except Exception as e:
                print(json.dumps({"ok": False, "error": f"Invalid stdin JSON: {e}"}))
                sys.exit(1)
        else:
            print(json.dumps({"ok": False, "error": "No page_id or JSON payload provided."}))
            sys.exit(1)

    ok, updated_keybinds, model_used, err = categorize_page_keybinds(
        page_data,
        requested_model=args.model,
        lang_code=lang_code,
    )
    if not ok:
        print(json.dumps({"ok": False, "error": err, "keybinds": updated_keybinds}, ensure_ascii=False))
        sys.exit(1)

    unique_categories = list(dict.fromkeys(
        str(kb.get("category", "")).strip() for kb in updated_keybinds if str(kb.get("category", "")).strip()
    ))

    page_name = str(page_data.get("name", "Shortcuts"))
    program_name = str(page_data.get("program", ""))
    lang_meta = get_language_meta(lang_code)

    record_ai_session(
        page_name,
        program_name,
        page_data.get("keybinds", []),
        updated_keybinds,
        unique_categories,
        model_used,
        lang_meta,
    )

    print(json.dumps({
        "ok": True,
        "pageId": args.page_id or page_data.get("id", ""),
        "modelUsed": model_used,
        "language": lang_code,
        "categoryCount": len(unique_categories),
        "categories": unique_categories,
        "keybinds": updated_keybinds,
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
