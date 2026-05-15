#!/usr/bin/env python3
"""Idempotente Anlage/Aktualisierung der ntfy-Notification in Uptime Kuma.

Erwartete Env-Variablen:
  UPTIME_KUMA_URL       z. B. http://127.0.0.1:3002
  UPTIME_KUMA_USER
  UPTIME_KUMA_PASSWORD
  NTFY_SERVER_URL       z. B. https://ntfy.sh
  NTFY_TOPIC            z. B. filehub-<random>

Optional:
  NTFY_PRIORITY         integer 1..5 (Default: 3 = "default")
  RUN_TEST              "1" -> ruft testNotification auf (Default: 0)

Sicherheit:
- Es werden keine Secrets, Tokens oder Passwoerter geloggt.
- Bricht sicher ab, wenn Pflichtvariablen fehlen oder die API einen Fehler liefert.
"""

from __future__ import annotations

import os
import sys

from uptime_kuma_api import UptimeKumaApi, NotificationType
from uptime_kuma_api.exceptions import UptimeKumaException


NOTIFICATION_NAME = "Filehub ntfy"
MONITOR_PREFIX = "Filehub "


def _require(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        print(f"ERROR: Pflicht-Variable {name} fehlt.", file=sys.stderr)
        sys.exit(2)
    return value


def main() -> int:
    url = _require("UPTIME_KUMA_URL")
    user = _require("UPTIME_KUMA_USER")
    password = _require("UPTIME_KUMA_PASSWORD")
    ntfy_server = _require("NTFY_SERVER_URL")
    ntfy_topic = _require("NTFY_TOPIC")
    try:
        ntfy_priority = int(os.environ.get("NTFY_PRIORITY", "3"))
    except ValueError:
        ntfy_priority = 3
    ntfy_priority = max(1, min(5, ntfy_priority))

    run_test = os.environ.get("RUN_TEST", "0") == "1"

    print(f"Verbinde mit Uptime Kuma unter {url} ...")
    with UptimeKumaApi(url) as api:
        api.login(user, password)
        print("Login OK.")

        # ntfy-Notification finden oder neu anlegen / aktualisieren.
        existing = None
        for n in api.get_notifications():
            if n.get("name") == NOTIFICATION_NAME:
                existing = n
                break

        common_fields = dict(
            name=NOTIFICATION_NAME,
            type=NotificationType.NTFY,
            isDefault=True,
            applyExisting=True,
            ntfyserverurl=ntfy_server,
            ntfytopic=ntfy_topic,
            ntfyPriority=ntfy_priority,
        )

        if existing is None:
            print(f"Lege Notification '{NOTIFICATION_NAME}' an ...")
            try:
                result = api.add_notification(**common_fields)
            except UptimeKumaException as exc:
                print(f"ERROR: add_notification fehlgeschlagen: {exc}", file=sys.stderr)
                return 3
            notification_id = result["id"]
            print(f"  created  id={notification_id}")
        else:
            notification_id = existing["id"]
            print(f"Aktualisiere Notification '{NOTIFICATION_NAME}' (id={notification_id}) ...")
            try:
                api.edit_notification(notification_id, **common_fields)
            except UptimeKumaException as exc:
                print(f"ERROR: edit_notification fehlgeschlagen: {exc}", file=sys.stderr)
                return 3
            print("  updated")

        # Notification-ID an allen Filehub-Monitoren idempotent anhaengen.
        attached = 0
        already = 0
        for m in api.get_monitors():
            name = m.get("name", "")
            if not name.startswith(MONITOR_PREFIX):
                continue
            ids = m.get("notificationIDList") or []
            # Normalisieren: Library liefert i.d.R. dict {"<id>": True} oder list.
            if isinstance(ids, dict):
                ids = [int(k) for k, v in ids.items() if v]
            ids = list({int(x) for x in ids})

            if notification_id in ids:
                already += 1
                continue

            new_ids = sorted(ids + [notification_id])
            try:
                api.edit_monitor(id_=m["id"], notificationIDList=new_ids)
            except UptimeKumaException as exc:
                print(f"  WARN: edit_monitor {name} (id={m['id']}) fehlgeschlagen: {exc}",
                      file=sys.stderr)
                continue
            attached += 1
            print(f"  attach  {name}  (monitor_id={m['id']})")

        print(f"\nNotification '{NOTIFICATION_NAME}' id={notification_id}")
        print(f"Monitore: attached={attached} already={already}")

        if run_test:
            print("Sende Test-Notification ...")
            try:
                resp = api.test_notification(**common_fields)
                ok = resp.get("ok", False)
                msg = resp.get("msg", "")
                # msg darf keinen Secret enthalten - Server-Antwort ist generisch.
                print(f"  test  ok={ok}  msg={msg}")
            except UptimeKumaException as exc:
                print(f"  WARN: test_notification fehlgeschlagen: {exc}", file=sys.stderr)

    return 0


if __name__ == "__main__":
    sys.exit(main())
