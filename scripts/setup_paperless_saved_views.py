#!/usr/bin/env python3
"""Idempotente Anlage von Saved Views in Paperless-ngx.

Erstellt definierte Saved Views ueber die REST-API. Bestehende Views mit
gleichem Namen werden per PATCH auf den Soll-Zustand gebracht. Es wird
nichts geloescht. Tags werden bei Bedarf nachgelegt.

Auth analog zu setup_paperless_baseline.py (Token oder User/Passwort via
/api/token/). Es werden keine Secrets geloggt.

Paperless filter_rules rule_type Referenz (stabile API-Werte):
  3 = correspondent
  6 = has tags (any)
  7 = document_type
  9 = title contains
"""
import os
import sys
import json
import requests

URL = os.environ["PAPERLESS_URL"].rstrip("/")
TOKEN = os.environ.get("PAPERLESS_TOKEN", "").strip()
USER = os.environ.get("PAPERLESS_USERNAME", "").strip()
PW = os.environ.get("PAPERLESS_PASSWORD", "").strip()

# Tags die fuer die Views noetig sind. Werden nachgelegt falls fehlen.
REQUIRED_TAGS = ["Rechnung", "Vertrag", "Steuer", "Wichtig", "To-Review"]

RULE_HAS_TAGS = 6
RULE_DOC_TYPE = 7


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


def ensure_tag(session: requests.Session, name: str, existing: dict) -> int:
    if name in existing:
        return existing[name]
    r = session.post(f"{URL}/api/tags/", json={"name": name}, timeout=15)
    if r.status_code not in (200, 201):
        print(f"ERROR: Tag '{name}' konnte nicht angelegt werden: "
              f"{r.status_code} {r.text[:120]}", file=sys.stderr)
        sys.exit(2)
    tid = r.json()["id"]
    existing[name] = tid
    print(f"  + tag: {name}")
    return tid


def build_views(tag_id: dict, doc_type_id: dict) -> list[dict]:
    """Baut die Soll-Definition aller Saved Views.

    sort_field=added, sort_reverse=True => neueste zuerst (added desc).
    """
    def has_tag(tid: int) -> dict:
        return {"rule_type": RULE_HAS_TAGS, "value": str(tid)}

    rechnungen_rules = [has_tag(tag_id["Rechnung"])]
    if "Rechnung" in doc_type_id:
        rechnungen_rules.append(
            {"rule_type": RULE_DOC_TYPE, "value": str(doc_type_id["Rechnung"])}
        )

    common = {
        "show_on_dashboard": True,
        "show_in_sidebar": True,
        "sort_field": "added",
        "sort_reverse": True,
    }
    return [
        {**common, "name": "Rechnungen", "filter_rules": rechnungen_rules},
        {**common, "name": "Vertraege",
         "filter_rules": [has_tag(tag_id["Vertrag"])]},
        {**common, "name": "Steuer",
         "filter_rules": [has_tag(tag_id["Steuer"])]},
        {**common, "name": "Wichtig",
         "filter_rules": [has_tag(tag_id["Wichtig"])]},
        {**common, "name": "To-Review",
         "filter_rules": [has_tag(tag_id["To-Review"])]},
    ]


def rules_equal(a: list, b: list) -> bool:
    def norm(rs):
        return sorted(
            (int(r["rule_type"]), str(r.get("value", ""))) for r in rs
        )
    return norm(a) == norm(b)


def upsert_view(session: requests.Session, view: dict, existing: dict) -> str:
    """Returns 'created' | 'updated' | 'unchanged'."""
    name = view["name"]
    if name not in existing:
        r = session.post(f"{URL}/api/saved_views/", json=view, timeout=15)
        if r.status_code not in (200, 201):
            print(f"ERROR: View '{name}' konnte nicht angelegt werden: "
                  f"{r.status_code} {r.text[:200]}", file=sys.stderr)
            sys.exit(3)
        print(f"  + view: {name}")
        return "created"

    cur = existing[name]
    needs_update = (
        cur.get("show_on_dashboard") != view["show_on_dashboard"]
        or cur.get("show_in_sidebar") != view["show_in_sidebar"]
        or cur.get("sort_field") != view["sort_field"]
        or cur.get("sort_reverse") != view["sort_reverse"]
        or not rules_equal(cur.get("filter_rules", []), view["filter_rules"])
    )
    if not needs_update:
        return "unchanged"
    r = session.patch(f"{URL}/api/saved_views/{cur['id']}/",
                      json=view, timeout=15)
    if r.status_code not in (200, 201):
        print(f"ERROR: View '{name}' konnte nicht aktualisiert werden: "
              f"{r.status_code} {r.text[:200]}", file=sys.stderr)
        sys.exit(4)
    print(f"  ~ view: {name}")
    return "updated"


def main() -> int:
    token = get_token()
    s = requests.Session()
    s.headers["Authorization"] = f"Token {token}"
    s.headers["Accept"] = "application/json"
    s.headers["Content-Type"] = "application/json"

    print(f"Paperless: {URL}")

    # Schemacheck: saved_views Endpoint erreichbar?
    probe = s.get(f"{URL}/api/saved_views/?page_size=1", timeout=15)
    if probe.status_code != 200:
        print(f"ERROR: /api/saved_views/ nicht erreichbar: "
              f"{probe.status_code} {probe.text[:120]}", file=sys.stderr)
        return 5

    tags = {x["name"]: x["id"] for x in list_all(s, "tags")}
    tags_created = 0
    for name in REQUIRED_TAGS:
        if name not in tags:
            ensure_tag(s, name, tags)
            tags_created += 1

    doc_types = {x["name"]: x["id"] for x in list_all(s, "document_types")}

    existing_views = {x["name"]: x for x in list_all(s, "saved_views")}
    desired = build_views(tags, doc_types)

    counts = {"created": 0, "updated": 0, "unchanged": 0}
    for v in desired:
        counts[upsert_view(s, v, existing_views)] += 1

    print(f"tags_created={tags_created}")
    print(f"views: created={counts['created']} updated={counts['updated']} "
          f"unchanged={counts['unchanged']}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except requests.HTTPError as e:
        print(f"ERROR: HTTP {e.response.status_code} {e.response.text[:200]}",
              file=sys.stderr)
        sys.exit(10)
