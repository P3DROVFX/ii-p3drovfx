#!/usr/bin/env python3
"""Universal Notes Export Engine.

Exports notes into various open formats:
- Markdown (.md) with external asset directory and frontmatter
- Self-contained HTML (.html) with Base64 embedded images and modern CSS styling
- ZIP backup (.zip) containing the entire notes store structure
- PDF document (.pdf) via weasyprint or wkhtmltopdf with clear installation diagnostics

Usage:
  python3 notes_export.py --format markdown --output /path/to/dest [--all | --note-id <id>]
  python3 notes_export.py --format html --output /path/to/dest.html [--note-id <id>]
  python3 notes_export.py --format zip --output /path/to/backup.zip
  python3 notes_export.py --format pdf --output /path/to/dest.pdf [--note-id <id>]
"""

import argparse
import base64
import datetime
import html
import json
import mimetypes
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path


def emit(payload: dict) -> int:
    sys.stdout.write(json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n")
    return 0 if payload.get("ok", True) else 1


def load_store(store_dir: Path) -> dict:
    index_file = store_dir / "index.json"
    if not index_file.exists():
        return {"schema": 1, "notes": [], "notebooks": []}
    try:
        return json.loads(index_file.read_text(encoding="utf-8"))
    except Exception:
        return {"schema": 1, "notes": [], "notebooks": []}


def get_document(store_dir: Path, note_id: str) -> dict:
    doc_path = store_dir / "docs" / f"{note_id}.json"
    if not doc_path.exists():
        return {}
    try:
        return json.loads(doc_path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def sanitize_filename(name: str) -> str:
    clean = re.sub(r'[\\/*?:"<>|]', "_", name or "Untitled").strip()
    return clean[:80] or "note"


def document_to_markdown(doc: dict, note_meta: dict, asset_prefix: str = "assets/") -> str:
    """Convert a NotesDocument into standard CommonMark Markdown with YAML frontmatter."""
    lines = []
    
    # Frontmatter
    lines.append("---")
    lines.append(f'title: "{note_meta.get("title", "")}"')
    if note_meta.get("tags"):
        lines.append(f'tags: [{", ".join(note_meta.get("tags", []))}]')
    created_ts = note_meta.get("created")
    if created_ts:
        dt = datetime.datetime.fromtimestamp(created_ts / 1000.0, tz=datetime.timezone.utc)
        lines.append(f'created: "{dt.isoformat()}"')
    lines.append("---")
    lines.append("")

    blocks = doc.get("blocks", [])
    for b in blocks:
        b_type = b.get("type", "text")
        text = b.get("text", "")
        indent = b.get("indent", 0)
        indent_pad = "  " * indent

        if b_type == "heading":
            level = max(1, min(6, int(b.get("level", 1))))
            lines.append(f"{'#' * level} {text}")
            lines.append("")
        elif b_type == "list":
            style = b.get("style", "bullet")
            if style == "checkbox":
                check = "x" if b.get("checked") else " "
                lines.append(f"{indent_pad}- [{check}] {text}")
            elif style == "number":
                lines.append(f"{indent_pad}1. {text}")
            else:
                lines.append(f"{indent_pad}- {text}")
        elif b_type == "code":
            lang = b.get("language", "")
            lines.append(f"```{lang}")
            lines.append(text)
            lines.append("```")
            lines.append("")
        elif b_type == "quote":
            for q_line in text.split("\n"):
                lines.append(f"{indent_pad}> {q_line}")
            lines.append("")
        elif b_type == "callout":
            tone = b.get("tone", "info").upper()
            tone_map = {"INFO": "NOTE", "SUCCESS": "TIP", "WARNING": "WARNING", "ERROR": "CAUTION"}
            alert_name = tone_map.get(tone, "NOTE")
            lines.append(f"> [!{alert_name}]")
            for c_line in text.split("\n"):
                lines.append(f"> {c_line}")
            lines.append("")
        elif b_type == "divider":
            lines.append("---")
            lines.append("")
        elif b_type == "image":
            asset_name = b.get("asset", "")
            lines.append(f"![{asset_name}]({asset_prefix}{asset_name})")
            lines.append("")
        elif b_type == "ink":
            asset_name = b.get("asset", "")
            if asset_name:
                lines.append(f"![Drawing]({asset_prefix}{asset_name})")
                lines.append("")
        elif b_type == "table":
            cols = b.get("columns", 3)
            rows = b.get("rows", [])
            has_hdr = b.get("header", True)
            if rows:
                hdr_row = rows[0] if has_hdr else [f"Col {i+1}" for i in range(cols)]
                lines.append("| " + " | ".join(hdr_row) + " |")
                lines.append("| " + " | ".join(["---"] * len(hdr_row)) + " |")
                data_rows = rows[1:] if has_hdr else rows
                for r in data_rows:
                    lines.append("| " + " | ".join(r) + " |")
                lines.append("")
        elif b_type == "linkPreview":
            url = b.get("url", "")
            title = b.get("title") or url
            lines.append(f"[{title}]({url})")
            lines.append("")
        elif b_type == "fileLink":
            path = b.get("path", "")
            fname = Path(path).name
            lines.append(f"[{fname}]({path})")
            lines.append("")
        else:
            # Default text
            lines.append(f"{indent_pad}{text}")
            lines.append("")

    return "\n".join(lines).strip() + "\n"


def document_to_html(doc: dict, note_meta: dict, store_dir: Path, embed_base64: bool = True) -> str:
    """Render a standalone, beautifully styled HTML document for reading or PDF conversion."""
    title = html.escape(note_meta.get("title") or "Untitled Note")
    tags = note_meta.get("tags") or []
    created_ts = note_meta.get("created")
    date_str = ""
    if created_ts:
        dt = datetime.datetime.fromtimestamp(created_ts / 1000.0)
        date_str = dt.strftime("%d de %B de %Y, %H:%M")

    note_id = note_meta.get("id", "")
    blocks = doc.get("blocks", [])

    body_elements = []

    for b in blocks:
        b_type = b.get("type", "text")
        raw_text = b.get("text", "")
        escaped_text = html.escape(raw_text).replace("\n", "<br>")

        if b_type == "heading":
            level = max(1, min(6, int(b.get("level", 1))))
            body_elements.append(f"<h{level}>{escaped_text}</h{level}>")
        elif b_type == "list":
            style = b.get("style", "bullet")
            if style == "checkbox":
                checked = "checked" if b.get("checked") else ""
                body_elements.append(
                    f'<div class="task-item"><input type="checkbox" {checked} disabled> <span>{escaped_text}</span></div>'
                )
            elif style == "number":
                body_elements.append(f'<div class="list-item num"><span>{escaped_text}</span></div>')
            else:
                body_elements.append(f'<div class="list-item bullet"><span>{escaped_text}</span></div>')
        elif b_type == "code":
            lang = html.escape(b.get("language", ""))
            body_elements.append(f'<pre><code class="lang-{lang}">{html.escape(raw_text)}</code></pre>')
        elif b_type == "quote":
            body_elements.append(f'<blockquote>{escaped_text}</blockquote>')
        elif b_type == "callout":
            tone = b.get("tone", "info").lower()
            body_elements.append(f'<div class="callout callout-{tone}">{escaped_text}</div>')
        elif b_type == "divider":
            body_elements.append('<hr>')
        elif b_type in ("image", "ink"):
            asset_name = b.get("asset", "")
            img_src = ""
            if asset_name:
                asset_file = store_dir / "assets" / note_id / asset_name
                if asset_file.exists():
                    if embed_base64:
                        mime = mimetypes.guess_type(str(asset_file))[0] or "image/png"
                        b64 = base64.b64encode(asset_file.read_bytes()).decode("utf-8")
                        img_src = f"data:{mime};base64,{b64}"
                    else:
                        img_src = f"assets/{asset_name}"
            if img_src:
                body_elements.append(f'<div class="image-wrapper"><img src="{img_src}" alt="{html.escape(asset_name)}"></div>')
        elif b_type == "table":
            rows = b.get("rows", [])
            has_hdr = b.get("header", True)
            if rows:
                t_html = ['<table>']
                if has_hdr and len(rows) > 0:
                    t_html.append('<thead><tr>')
                    for cell in rows[0]:
                        t_html.append(f'<th>{html.escape(cell)}</th>')
                    t_html.append('</tr></thead>')
                    rows = rows[1:]
                t_html.append('<tbody>')
                for r in rows:
                    t_html.append('<tr>')
                    for cell in r:
                        t_html.append(f'<td>{html.escape(cell)}</td>')
                    t_html.append('</tr>')
                t_html.append('</tbody></table>')
                body_elements.append("".join(t_html))
        elif b_type == "linkPreview":
            url = html.escape(b.get("url", ""))
            l_title = html.escape(b.get("title") or url)
            body_elements.append(f'<p><a href="{url}" target="_blank" class="link-card">🔗 {l_title}</a></p>')
        elif b_type == "fileLink":
            path = html.escape(b.get("path", ""))
            fname = html.escape(Path(path).name)
            body_elements.append(f'<p class="file-card">📎 <strong>{fname}</strong> <small>({path})</small></p>')
        else:
            if escaped_text:
                body_elements.append(f'<p>{escaped_text}</p>')

    tags_html = "".join(f'<span class="tag">{html.escape(t)}</span>' for t in tags)

    return f"""<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8">
  <title>{title}</title>
  <style>
    :root {{
      --bg: #141318;
      --surface: #1e1c24;
      --surface-high: #292831;
      --text: #e6e1e9;
      --subtext: #948f99;
      --primary: #d0bcff;
      --border: #49454f;
      --accent: #381e72;
    }}
    @media (prefers-color-scheme: light) {{
      :root {{
        --bg: #fdf8fd;
        --surface: #f4eefa;
        --surface-high: #eae3f1;
        --text: #1d1b20;
        --subtext: #49454f;
        --primary: #6750a4;
        --border: #cac4d0;
        --accent: #eaddff;
      }}
    }}
    body {{
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Liberation Sans", sans-serif;
      background-color: var(--bg);
      color: var(--text);
      line-height: 1.6;
      margin: 0;
      padding: 40px 20px;
    }}
    .container {{
      max-width: 780px;
      margin: 0 auto;
      background: var(--surface);
      padding: 40px 48px;
      border-radius: 16px;
      border: 1px solid var(--border);
    }}
    h1 {{ font-size: 2.2rem; margin-top: 0; color: var(--primary); }}
    h2 {{ font-size: 1.5rem; border-bottom: 1px solid var(--border); padding-bottom: 6px; margin-top: 28px; }}
    h3 {{ font-size: 1.2rem; margin-top: 20px; }}
    .meta {{ font-size: 0.85rem; color: var(--subtext); margin-bottom: 24px; display: flex; gap: 12px; align-items: center; flex-wrap: wrap; }}
    .tag {{ background: var(--surface-high); border: 1px solid var(--border); padding: 2px 8px; border-radius: 12px; font-size: 0.75rem; }}
    p {{ margin: 0.8em 0; }}
    blockquote {{ border-left: 4px solid var(--primary); margin: 1em 0; padding-left: 16px; color: var(--subtext); font-style: italic; }}
    pre {{ background: var(--surface-high); padding: 16px; border-radius: 8px; overflow-x: auto; font-family: "JetBrains Mono", Consolas, monospace; font-size: 0.9rem; border: 1px solid var(--border); }}
    code {{ font-family: "JetBrains Mono", Consolas, monospace; }}
    .callout {{ padding: 14px 18px; border-radius: 8px; margin: 16px 0; background: var(--surface-high); border-left: 4px solid var(--primary); }}
    .callout-warning {{ border-color: #f59e0b; background: rgba(245, 158, 11, 0.1); }}
    .callout-error {{ border-color: #ef4444; background: rgba(239, 68, 68, 0.1); }}
    .callout-success {{ border-color: #10b981; background: rgba(16, 185, 129, 0.1); }}
    .task-item {{ display: flex; align-items: center; gap: 10px; margin: 6px 0; }}
    .list-item {{ margin: 6px 0; }}
    .list-item.bullet::before {{ content: "• "; color: var(--primary); font-weight: bold; margin-right: 6px; }}
    .image-wrapper {{ text-align: center; margin: 20px 0; }}
    .image-wrapper img {{ max-width: 100%; border-radius: 8px; border: 1px solid var(--border); }}
    table {{ width: 100%; border-collapse: collapse; margin: 20px 0; }}
    th, td {{ border: 1px solid var(--border); padding: 8px 12px; text-align: left; }}
    th {{ background: var(--surface-high); }}
    hr {{ border: none; border-top: 1px solid var(--border); margin: 24px 0; }}
    a {{ color: var(--primary); text-decoration: none; }}
    a:hover {{ text-decoration: underline; }}
  </style>
</head>
<body>
  <div class="container">
    <h1>{title}</h1>
    <div class="meta">
      {f'<span>{date_str}</span>' if date_str else ''}
      {tags_html}
    </div>
    <div class="content">
      {''.join(body_elements)}
    </div>
  </div>
</body>
</html>"""


def export_notes(store_dir: Path, export_format: str, output_path: Path, note_id: str = "", export_all: bool = False) -> dict:
    """Main export dispatcher."""
    store_data = load_store(store_dir)
    notes = store_data.get("notes", [])

    if note_id:
        target_notes = [n for n in notes if n.get("id") == note_id]
        if not target_notes:
            return {"ok": False, "error": "note_not_found", "message": f"No note with the id '{note_id}'."}
    elif export_all:
        target_notes = notes
    else:
        target_notes = notes[:1] if notes else []

    if not target_notes:
        return {"ok": False, "error": "empty_store", "message": "There is nothing to export."}

    # ── 1. Markdown Export ────────────────────────────────────────────────
    if export_format == "markdown":
        output_dir = output_path if output_path.suffix == "" else output_path.parent / output_path.stem
        output_dir.mkdir(parents=True, exist_ok=True)
        assets_dir = output_dir / "assets"
        assets_dir.mkdir(parents=True, exist_ok=True)

        count = 0
        for n in target_notes:
            nid = n.get("id", "")
            doc = get_document(store_dir, nid)
            if not doc:
                continue
            md_text = document_to_markdown(doc, n, asset_prefix="assets/")
            fname = sanitize_filename(n.get("title") or "note") + f"_{nid[-6:]}.md"
            (output_dir / fname).write_text(md_text, encoding="utf-8")

            # Copy note assets
            note_assets = store_dir / "assets" / nid
            if note_assets.exists():
                for f in note_assets.iterdir():
                    if f.is_file():
                        shutil.copy2(str(f), str(assets_dir / f.name))
            count += 1

        return {
            "ok": True,
            "format": "markdown",
            "count": count,
            "output": str(output_dir),
            "message": f"{count} notes written as Markdown to '{output_dir}'."
        }

    # ── 2. HTML Export ────────────────────────────────────────────────────
    elif export_format == "html":
        if len(target_notes) == 1 and output_path.suffix.lower() == ".html":
            n = target_notes[0]
            doc = get_document(store_dir, n.get("id", ""))
            html_content = document_to_html(doc, n, store_dir, embed_base64=True)
            output_path.parent.mkdir(parents=True, exist_ok=True)
            output_path.write_text(html_content, encoding="utf-8")
            return {
                "ok": True,
                "format": "html",
                "count": 1,
                "output": str(output_path),
                "message": f"Note written as a web page to '{output_path}'."
            }
        else:
            output_dir = output_path if output_path.suffix == "" else output_path.parent / output_path.stem
            output_dir.mkdir(parents=True, exist_ok=True)
            count = 0
            for n in target_notes:
                nid = n.get("id", "")
                doc = get_document(store_dir, nid)
                if not doc:
                    continue
                html_content = document_to_html(doc, n, store_dir, embed_base64=True)
                fname = sanitize_filename(n.get("title") or "note") + f"_{nid[-6:]}.html"
                (output_dir / fname).write_text(html_content, encoding="utf-8")
                count += 1
            return {
                "ok": True,
                "format": "html",
                "count": count,
                "output": str(output_dir),
                "message": f"{count} notes written as web pages to '{output_dir}'."
            }

    # ── 3. ZIP Archive Export ─────────────────────────────────────────────
    elif export_format == "zip":
        zip_path = output_path if output_path.suffix.lower() == ".zip" else output_path.with_suffix(".zip")
        zip_path.parent.mkdir(parents=True, exist_ok=True)

        with zipfile.ZipFile(str(zip_path), "w", zipfile.ZIP_DEFLATED) as zf:
            index_path = store_dir / "index.json"
            if index_path.exists():
                zf.write(str(index_path), "index.json")

            for n in target_notes:
                nid = n.get("id", "")
                doc_file = store_dir / "docs" / f"{nid}.json"
                if doc_file.exists():
                    zf.write(str(doc_file), f"docs/{nid}.json")
                note_assets = store_dir / "assets" / nid
                if note_assets.exists():
                    for f in note_assets.iterdir():
                        if f.is_file():
                            zf.write(str(f), f"assets/{nid}/{f.name}")

        return {
            "ok": True,
            "format": "zip",
            "count": len(target_notes),
            "output": str(zip_path),
            "message": f"Everything archived to '{zip_path}'."
        }

    # ── 4. PDF Export ─────────────────────────────────────────────────────
    elif export_format == "pdf":
        pdf_path = output_path if output_path.suffix.lower() == ".pdf" else output_path.with_suffix(".pdf")
        pdf_path.parent.mkdir(parents=True, exist_ok=True)

        # Check compiler availability
        has_weasyprint = shutil.which("weasyprint") is not None
        has_wkhtmltopdf = shutil.which("wkhtmltopdf") is not None
        has_chromium = shutil.which("chromium") is not None or shutil.which("google-chrome") is not None

        if not (has_weasyprint or has_wkhtmltopdf or has_chromium):
            return {
                "ok": False,
                "error": "pdf_compiler_missing",
                "message": (
                    "Nothing on this machine can make a PDF.\n"
                    "Install one of these first:\n"
                    "  - Arch Linux: sudo pacman -S weasyprint\n"
                    "  - Ubuntu/Debian: sudo apt install weasyprint (or wkhtmltopdf)\n"
                    "  - pip: pip install weasyprint"
                )
            }

        # Build intermediate HTML
        n = target_notes[0]
        doc = get_document(store_dir, n.get("id", ""))
        html_text = document_to_html(doc, n, store_dir, embed_base64=True)

        temp_html = tempfile.NamedTemporaryFile("w", suffix=".html", delete=False, encoding="utf-8")
        try:
            temp_html.write(html_text)
            temp_html.flush()
            temp_html.close()

            if has_weasyprint:
                cmd = ["weasyprint", temp_html.name, str(pdf_path)]
            elif has_wkhtmltopdf:
                cmd = ["wkhtmltopdf", "--quiet", temp_html.name, str(pdf_path)]
            else:
                browser = shutil.which("chromium") or shutil.which("google-chrome")
                cmd = [browser, "--headless", "--disable-gpu", f"--print-to-pdf={str(pdf_path)}", temp_html.name]

            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
            if proc.returncode != 0 or not pdf_path.exists():
                return {
                    "ok": False,
                    "error": "pdf_compilation_failed",
                    "message": f"The PDF could not be made: {proc.stderr.strip()}"
                }

            return {
                "ok": True,
                "format": "pdf",
                "count": 1,
                "output": str(pdf_path),
                "message": f"PDF written to '{pdf_path}'."
            }

        finally:
            if os.path.exists(temp_html.name):
                os.unlink(temp_html.name)

    return {"ok": False, "error": "unsupported_format", "message": f"'{export_format}' is not a format this can write."}


def main() -> int:
    parser = argparse.ArgumentParser(description="Universal Notes Export Engine")
    parser.add_argument("--format", choices=["markdown", "html", "zip", "pdf"], default="markdown",
                        help="Export format")
    parser.add_argument("--output", type=str, required=True, help="Destination file or directory path")
    parser.add_argument("--store", type=str, default=os.path.expanduser("~/.local/state/quickshell/user/notes"),
                        help="Path to notes store directory")
    parser.add_argument("--note-id", type=str, default="", help="Export a specific note ID")
    parser.add_argument("--all", action="store_true", help="Export all notes")

    args = parser.parse_args()

    store_path = Path(args.store).resolve()
    output_path = Path(args.output).resolve()

    res = export_notes(store_path, args.format, output_path, note_id=args.note_id, export_all=args.all)
    return emit(res)


if __name__ == "__main__":
    sys.exit(main())
