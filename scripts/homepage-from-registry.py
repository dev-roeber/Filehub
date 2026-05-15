#!/usr/bin/env python3
"""Generate gethomepage services.generated.yaml from config/apps.yml.

Reads the Filehub app registry (config/apps.yml) and writes a
gethomepage-kompatible services file. Schreibt NICHT direkt
services.yaml, sondern services.generated.yaml. Aktivierung
manuell via diff/rename.
"""
from __future__ import annotations

import sys
from pathlib import Path
from urllib.parse import urlparse

REPO_ROOT = Path(__file__).resolve().parent.parent
REGISTRY = REPO_ROOT / "config" / "apps.yml"
OUTPUT = REPO_ROOT / "config" / "homepage" / "services.generated.yaml"
PROTECTED = REPO_ROOT / "config" / "homepage" / "services.yaml"

CATEGORY_ORDER = ["productivity", "utility", "observability", "media"]
CATEGORY_TITLES = {
    "productivity": "Productivity",
    "utility": "Utility",
    "observability": "Observability",
    "media": "Media",
}


def parse_apps(text: str) -> list[dict]:
    """Sehr einfacher YAML-Parser fuer das apps.yml-Format.

    Erwartete Struktur:
        apps:
          - id: foo
            key: value
            ...
          - id: bar
            ...
        infra:
          ...
    """
    apps: list[dict] = []
    in_apps = False
    current: dict | None = None
    for raw in text.splitlines():
        line = raw.rstrip()
        stripped = line.lstrip()
        if not stripped or stripped.startswith("#"):
            continue
        if not line.startswith(" "):
            # Top-level key
            if stripped.startswith("apps:"):
                in_apps = True
                continue
            # Anderer Top-Level-Block beendet apps:
            if in_apps:
                if current is not None:
                    apps.append(current)
                    current = None
                in_apps = False
            continue
        if not in_apps:
            continue
        # Innerhalb von apps:
        indent = len(line) - len(stripped)
        if indent == 2 and stripped.startswith("- "):
            # Neuer Eintrag
            if current is not None:
                apps.append(current)
            current = {}
            kv = stripped[2:].strip()
            if ":" in kv:
                k, _, v = kv.partition(":")
                current[k.strip()] = _coerce(v.strip())
        elif indent >= 4 and current is not None and ":" in stripped:
            k, _, v = stripped.partition(":")
            current[k.strip()] = _coerce(v.strip())
    if in_apps and current is not None:
        apps.append(current)
    return apps


def _coerce(value: str):
    if value == "true":
        return True
    if value == "false":
        return False
    if value.isdigit():
        return int(value)
    # Quoted string entfernen
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ('"', "'"):
        return value[1:-1]
    return value


def container_from_internal_url(url: str) -> str | None:
    if not url:
        return None
    try:
        parsed = urlparse(url)
        return parsed.hostname
    except Exception:
        return None


def render(groups: dict[str, list[dict]]) -> str:
    lines: list[str] = []
    lines.append(
        "# AUTO-GENERATED aus config/apps.yml by scripts/homepage-from-registry.py."
    )
    lines.append("# NICHT manuell editieren - aenderbar ist die Registry oder das Generator-Script.")
    lines.append("# Aktivierung: services.generated.yaml mit services.yaml vergleichen, dann")
    lines.append("# bewusst zu services.yaml umbenennen oder Homepage neu starten.")
    lines.append("")

    first_group = True
    for cat in CATEGORY_ORDER:
        apps = groups.get(cat)
        if not apps:
            continue
        if not first_group:
            lines.append("")
        first_group = False
        title = CATEGORY_TITLES.get(cat, cat.title())
        lines.append(f"- {title}:")
        for app in apps:
            name = app.get("name") or app.get("id")
            lines.append(f"    - {name}:")
            port = app.get("port")
            if port:
                lines.append(f"        href: http://127.0.0.1:{port}")
            desc = app.get("description")
            if desc:
                lines.append(f"        description: {desc}")
            container = container_from_internal_url(app.get("internal_url", ""))
            if container:
                lines.append(f"        container: {container}")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    if not REGISTRY.exists():
        print(f"ERROR: Registry nicht gefunden: {REGISTRY}", file=sys.stderr)
        return 1
    text = REGISTRY.read_text(encoding="utf-8")
    apps = parse_apps(text)
    if not apps:
        print("ERROR: keine Apps in Registry geparst", file=sys.stderr)
        return 1

    groups: dict[str, list[dict]] = {}
    for app in apps:
        if not app.get("default_enabled"):
            continue
        missing = [f for f in ("id", "name", "category", "port") if not app.get(f)]
        if missing:
            print(
                f"WARN: app {app.get('id', '<unknown>')} ohne Pflichtfeld(er): {missing}",
                file=sys.stderr,
            )
            if "category" in missing or "name" in missing:
                continue
        cat = app.get("category", "utility")
        groups.setdefault(cat, []).append(app)

    output = render(groups)

    # Niemals services.yaml ueberschreiben
    if OUTPUT.resolve() == PROTECTED.resolve():
        print("ERROR: Output zielt auf services.yaml - abgebrochen", file=sys.stderr)
        return 1

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(output, encoding="utf-8")
    print(f"OK: {OUTPUT.relative_to(REPO_ROOT)} ({sum(len(v) for v in groups.values())} Services)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
