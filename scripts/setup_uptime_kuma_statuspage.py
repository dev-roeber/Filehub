#!/usr/bin/env python3
"""Idempotente Anlage einer lokalen Filehub-Statuspage in Uptime Kuma.

Erwartete Env-Variablen:
  UPTIME_KUMA_URL       z. B. http://127.0.0.1:3002
  UPTIME_KUMA_USER
  UPTIME_KUMA_PASSWORD

Eigenschaften:
- Slug:  "filehub-local"
- Titel: "Filehub Local Status"
- Bindet alle existierenden Monitore mit Praefix "Filehub " als Gruppe "Filehub".
- Wird NICHT publiziert (published=False).
- Idempotent: existiert die Statuspage bereits, wird sie aktualisiert, nicht doppelt angelegt.

Es werden keine Secrets, Tokens oder Passwoerter geloggt.
"""

import os
import sys

from uptime_kuma_api import UptimeKumaApi, UptimeKumaException


SLUG = "filehub-local"
TITLE = "Filehub Local Status"
GROUP_NAME = "Filehub"
MONITOR_NAME_PREFIX = "Filehub "


def main() -> int:
    url = os.environ["UPTIME_KUMA_URL"]
    user = os.environ["UPTIME_KUMA_USER"]
    password = os.environ["UPTIME_KUMA_PASSWORD"]

    print(f"Verbinde mit Uptime Kuma unter {url} ...")
    with UptimeKumaApi(url) as api:
        api.login(user, password)
        print("Login OK.")

        filehub_monitors = [
            m for m in api.get_monitors()
            if m.get("name", "").startswith(MONITOR_NAME_PREFIX)
        ]
        filehub_monitors.sort(key=lambda m: m["name"])
        print(f"Gefundene Filehub-Monitore: {len(filehub_monitors)}")
        for m in filehub_monitors:
            print(f"  - {m['name']} (id={m['id']})")

        if not filehub_monitors:
            print("Keine Filehub-Monitore vorhanden. Erst Monitore anlegen.")
            return 2

        public_group_list = [{
            "name": GROUP_NAME,
            "weight": 1,
            "monitorList": [{"id": m["id"]} for m in filehub_monitors],
        }]

        existing_pages = api.get_status_pages()
        existing = None
        for p in existing_pages:
            if p.get("slug") == SLUG:
                existing = p
                break

        if existing is None:
            print(f"Lege Statuspage '{SLUG}' an ...")
            try:
                api.add_status_page(slug=SLUG, title=TITLE)
            except UptimeKumaException as e:
                print(f"add_status_page Fehler: {e}")
                return 3

        print(f"Speichere Statuspage '{SLUG}' (published=False) ...")
        api.save_status_page(
            slug=SLUG,
            title=TITLE,
            description="Lokale Statuspage des Filehub-Stacks. Nicht publiziert.",
            theme="auto",
            published=False,
            showTags=False,
            showPoweredBy=True,
            publicGroupList=public_group_list,
        )

        print("Aktuelle Statuspages:")
        for p in api.get_status_pages():
            print(f"  slug={p.get('slug')}  title={p.get('title')}  published={p.get('published')}")

        print()
        print(f"Aufrufbar lokal unter: {url}/status/{SLUG}")
        print("Hinweis: 'published=False' verbirgt die Page in der Uebersicht;")
        print("der direkte Slug-Link bleibt fuer lokale Aufrufe verwendbar.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
