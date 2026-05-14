#!/usr/bin/env python3
"""Idempotente Baseline fuer Paperless-ngx.

Erstellt Dokumenttypen, Tags und Korrespondenten ueber die Paperless REST-API.
Bestehende Eintraege werden nicht veraendert.
Es werden keine Secrets geloggt.
"""
import os
import sys
import requests

URL = os.environ["PAPERLESS_URL"].rstrip("/")
TOKEN = os.environ.get("PAPERLESS_TOKEN", "").strip()
USER = os.environ.get("PAPERLESS_USERNAME", "").strip()
PW = os.environ.get("PAPERLESS_PASSWORD", "").strip()

DOC_TYPES = [
    "Rechnung", "Vertrag", "Brief", "Steuerunterlage", "Versicherung",
    "Garantie", "Lohnabrechnung", "Kontoauszug", "Sonstiges",
]
TAGS = [
    "Privat", "Wichtig", "Steuer", "Rechnung", "Vertrag", "Versicherung",
    "Garantie", "Gesundheit", "Arbeit", "Auto", "Wohnung",
    "To-Review", "Archiviert",
]
CORRESPONDENTS = [
    "Finanzamt", "Krankenkasse", "Bank", "Versicherung", "Arbeitgeber",
    "Vodafone", "Telekom", "Amazon", "Sonstiges",
]


def get_token() -> str:
    global TOKEN
    if TOKEN:
        return TOKEN
    if not (USER and PW):
        print("ERROR: weder Token noch User/Passwort gesetzt", file=sys.stderr)
        sys.exit(1)
    r = requests.post(f"{URL}/api/token/",
                      json={"username": USER, "password": PW}, timeout=15)
    r.raise_for_status()
    TOKEN = r.json()["token"]
    print("API-Token via Login bezogen.")
    return TOKEN


def list_all(session: requests.Session, endpoint: str) -> list:
    items = []
    url = f"{URL}/api/{endpoint}/?page_size=100"
    while url:
        r = session.get(url, timeout=15)
        r.raise_for_status()
        data = r.json()
        items.extend(data.get("results", []))
        url = data.get("next")
    return items


def ensure(session: requests.Session, endpoint: str, names: list[str]) -> tuple[int, int]:
    existing = {x["name"]: x["id"] for x in list_all(session, endpoint)}
    created = 0
    skipped = 0
    for name in names:
        if name in existing:
            skipped += 1
            continue
        r = session.post(f"{URL}/api/{endpoint}/",
                         json={"name": name}, timeout=15)
        if r.status_code in (200, 201):
            created += 1
            print(f"  + {endpoint}: {name}")
        else:
            print(f"  ! {endpoint}: {name} -> {r.status_code} {r.text[:80]}")
    return created, skipped


def main() -> int:
    token = get_token()
    s = requests.Session()
    s.headers["Authorization"] = f"Token {token}"
    s.headers["Accept"] = "application/json"

    print(f"Paperless: {URL}")
    for endpoint, items in [
        ("document_types", DOC_TYPES),
        ("tags", TAGS),
        ("correspondents", CORRESPONDENTS),
    ]:
        c, s2 = ensure(s, endpoint, items)
        print(f"{endpoint}: created={c} skipped={s2}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
