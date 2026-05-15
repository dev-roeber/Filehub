# Verschluesseltes Secrets-Backup

Stand: 2026-05-15.

## Strategie

Der **Passwortmanager ist die primaere Quelle** fuer Secrets. Alle
relevanten Logins, API-Keys und Restic-/rclone-Konfigurationen gehoeren
dort hinein. Das verschluesselte Secrets-Backup ist nur eine zweite,
unabhaengige Kopie.

## Skript

`scripts/export-secrets-encrypted.sh` erzeugt ein verschluesseltes Tar
ueber `.secrets/` (und optional weitere kritische Pfade). Das Skript
**verweigert die Ausfuehrung**, wenn weder `AGE_RECIPIENT` noch
`GPG_RECIPIENT` gesetzt ist. Es gibt keinen Klartext-Fallback.

### Output

```text
backups/secrets/filehub-secrets-YYYYMMDD-HHMMSS.tar.age
backups/secrets/filehub-secrets-YYYYMMDD-HHMMSS.tar.gpg
```

Dateimodus `600`. Verzeichnis `backups/secrets/` ebenfalls `700`.

## Verschluesselung

Zwei Varianten:

### age

```bash
export AGE_RECIPIENT="age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
scripts/export-secrets-encrypted.sh
```

### GPG

```bash
export GPG_RECIPIENT="0xDEADBEEFCAFEBABE"
scripts/export-secrets-encrypted.sh
```

## Was darf in Git, was nicht

- **In Git zulaessig:** age-Public-Key (Recipient), GPG-Fingerprint des
  Recipients.
- **Niemals in Git:** privater age-Key, privater GPG-Key, entschluesselte
  Archive, `.secrets/`-Inhalte.
- Niemals unverschluesselt in `restic`/`rclone` ablegen. Restic-Backups
  sind zwar verschluesselt, aber das Secrets-Archiv soll auch unabhaengig
  vom Restic-Passwort entschluesselbar sein.

## Wiederherstellung

In einem leeren Repo:

```bash
# age
age -d -i ~/.age/filehub.key \
  -o filehub-secrets.tar \
  backups/secrets/filehub-secrets-YYYYMMDD-HHMMSS.tar.age

# oder GPG
gpg --decrypt \
  -o filehub-secrets.tar \
  backups/secrets/filehub-secrets-YYYYMMDD-HHMMSS.tar.gpg

# Tar entpacken
tar -xf filehub-secrets.tar
chmod 700 .secrets
chmod 600 .secrets/*
```

Danach `.env`-Datei pruefen, Bind-Adressen und Mode-Bits verifizieren.

## Aufbewahrung

- Mehrere unabhaengige Speicherorte (lokal verschluesselt, Cloud
  verschluesselt, Offline-Medium).
- Recipient-Key rotieren, wenn ein Geraet verloren geht.
- Alte verschluesselte Archive nicht ewig aufheben, wenn die Recipients
  rotiert wurden.
