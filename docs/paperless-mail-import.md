# Paperless Mail-Import

Stand: 2026-05-15. Dieses Dokument bereitet den Mail-Import vor, **ohne**
echte Credentials zu erzeugen oder zu hinterlegen.

## Empfehlung Postfach

- **Dediziertes Postfach**, z.B. `paperless@your-domain`.
- Kein Posteingang mit normalem Mailverkehr — das Postfach existiert
  ausschliesslich fuer Paperless.
- **App-Passwort** statt Hauptpasswort. Falls der Provider keine App-
  Passwoerter unterstuetzt: separates Mailkonto anlegen.
- **OAuth bevorzugen**, wenn der Provider es unterstuetzt (Gmail,
  Microsoft 365). Spart Passwort-Rotation und ist widerruflich.
- Verbindung **IMAP + TLS** (Port 993). Kein STARTTLS-Fallback auf
  unverschluesselt.

## Variablen

Nur Variablennamen, keine Werte:

```text
PAPERLESS_MAIL_FROM
PAPERLESS_MAIL_HOST
PAPERLESS_MAIL_USER
PAPERLESS_MAIL_PASSWORD
```

Ablageoptionen:

- `.secrets/paperless-mail.env`, Mode `600`, gitignored. Wird per
  `env_file` in den Paperless-Container reingereicht.
- Oder direkt im **Paperless-UI** als Mail-Account konfigurieren. Dann
  liegen die Credentials in der Paperless-Datenbank. Beide Wege sind
  zulaessig, nicht beide gleichzeitig.

## Konfiguration in der Paperless-UI

1. Anmelden, `Einstellungen` -> `Mail`.
2. **Mail-Account** anlegen:
   - Host, Port 993, IMAP, TLS.
   - Benutzer, Passwort (oder OAuth-Token).
3. **Mail-Regel** anlegen:
   - Quell-Ordner: `INBOX`.
   - Aktion: **Anhang verarbeiten** (PDF, JPG, PNG).
   - Filter optional: Betreff, Absender.
   - **Tag setzen** (z.B. `mail-import`).
   - **Korrespondent** automatisch aus Absender setzen.
   - Nach Verarbeitung in `verarbeitet`-Ordner verschieben oder als
     gelesen markieren.

## Sicherheit

- Postfach nicht fuer normalen Mailverkehr nutzen.
- OAuth statt Passwort, wenn Provider unterstuetzt.
- Keine Klartext-Speicherung in committed Files. `.secrets/`-Dateien
  sind `Mode 600`, gitignored.
- Bei Kompromittierungsverdacht: App-Passwort widerrufen, neues
  vergeben.

## Testablauf

1. Test-PDF an `PAPERLESS_MAIL_FROM` senden.
2. 5 Minuten warten (Polling-Intervall Standard).
3. In Paperless pruefen, ob Dokument im Eingang ist und das Tag gesetzt
   wurde.
4. Im Postfach pruefen, ob die Mail in den `verarbeitet`-Ordner
   verschoben wurde.

## Was dieses Dokument **nicht** tut

- Keine echten Mail-Credentials erzeugen.
- Kein Schreiben in `.secrets/`.
- Keine Aenderung an `compose.paperless.yml`.
