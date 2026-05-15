#!/usr/bin/env python3
"""Idempotente Anlage der Filehub-Monitore in Uptime Kuma.

Erwartete Env-Variablen:
  UPTIME_KUMA_URL       z. B. http://127.0.0.1:3002
  UPTIME_KUMA_USER
  UPTIME_KUMA_PASSWORD

Vorhandene Monitore mit gleichem Namen werden aktualisiert, nicht dupliziert.
Es werden keine Secrets, Tokens oder Passwoerter geloggt.
"""

import os
import sys

from uptime_kuma_api import UptimeKumaApi, MonitorType


HTTP_MONITORS = [
    ("Filehub Paperless",     "http://paperless-webserver:8000"),
    ("Filehub ConvertX",      "http://convertx:3000"),
    ("Filehub Homepage",      "http://homepage:3000"),
    ("Filehub Dozzle",        "http://dozzle:8080"),
    ("Filehub Uptime Kuma",   "http://uptime-kuma:3001"),
    ("Filehub Gotenberg",     "http://paperless-gotenberg:3000/health"),
    ("Filehub Tika",          "http://paperless-tika:9998/"),
    ("Filehub Filebrowser",   "http://filebrowser:80/"),
    ("Filehub Stirling PDF",  "http://stirling-pdf:8080/"),
    ("Filehub Authentik",     "http://filehub-authentik-server:9000/-/health/live/"),
    ("Filehub Gateway",       "http://filehub-gateway:8080/_health"),
]

TCP_MONITORS = [
    ("Filehub PostgreSQL", "paperless-db",    5432),
    ("Filehub Redis",      "paperless-redis", 6379),
]

DEFAULTS = dict(
    interval=60,
    maxretries=2,
    retryInterval=60,
    timeout=20,
)

TAG_NAME = "filehub"


def main() -> int:
    url = os.environ["UPTIME_KUMA_URL"]
    user = os.environ["UPTIME_KUMA_USER"]
    password = os.environ["UPTIME_KUMA_PASSWORD"]

    print(f"Verbinde mit Uptime Kuma unter {url} ...")
    with UptimeKumaApi(url) as api:
        api.login(user, password)
        print("Login OK.")

        # Tag fuer Gruppierung anlegen, falls noch nicht vorhanden.
        tag_id = None
        for tag in api.get_tags():
            if tag.get("name") == TAG_NAME:
                tag_id = tag["id"]
                break
        if tag_id is None:
            tag_id = api.add_tag(name=TAG_NAME, color="#3b82f6")["id"]
            print(f"Tag '{TAG_NAME}' angelegt (id={tag_id}).")
        else:
            print(f"Tag '{TAG_NAME}' bereits vorhanden (id={tag_id}).")

        existing = {m["name"]: m for m in api.get_monitors()}

        created = 0
        updated = 0
        skipped = 0

        def ensure(name: str, mtype: MonitorType, **fields):
            nonlocal created, updated, skipped
            if name in existing:
                mid = existing[name]["id"]
                api.edit_monitor(id_=mid, name=name, type=mtype,
                                 accepted_statuscodes=fields.pop("accepted_statuscodes", ["200-299"]),
                                 **DEFAULTS, **fields)
                print(f"  update  {name}  (id={mid})")
                updated += 1
                return mid
            result = api.add_monitor(
                type=mtype, name=name,
                accepted_statuscodes=fields.pop("accepted_statuscodes", ["200-299"]),
                **DEFAULTS, **fields,
            )
            mid = result["monitorID"]
            print(f"  create  {name}  (id={mid})")
            created += 1
            return mid

        all_ids = []
        # Stirling und Filebrowser geben 200-499 (Login-Redirect/401/404 sind UP).
        broad_codes = ["200-299", "300-399", "401", "403", "404"]
        for name, url_ in HTTP_MONITORS:
            codes = broad_codes if name in ("Filehub Stirling PDF", "Filehub Filebrowser") else ["200-299"]
            mid = ensure(name, MonitorType.HTTP, url=url_, method="GET",
                         accepted_statuscodes=codes)
            all_ids.append(mid)

        for name, host, port in TCP_MONITORS:
            mid = ensure(name, MonitorType.PORT, hostname=host, port=port)
            all_ids.append(mid)

        # Tag jedem Monitor zuweisen, falls noch nicht vorhanden.
        for mid in all_ids:
            existing_tags = {t["tag_id"] for t in api.get_monitor(mid).get("tags", [])}
            if tag_id not in existing_tags:
                api.add_monitor_tag(tag_id=tag_id, monitor_id=mid, value="")

        print(f"\nMonitore: created={created} updated={updated} skipped={skipped}")
        print("Status-Snapshot:")
        for m in api.get_monitors():
            if m["name"].startswith("Filehub "):
                print(f"  {m['id']:>4}  active={m.get('active')}  {m['name']}  type={m['type']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
