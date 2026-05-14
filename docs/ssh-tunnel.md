# SSH-Tunnel

Alle Filehub-Webdienste laufen nur auf `127.0.0.1` des Servers. Für Remote-Zugriff wird SSH-Portweiterleitung genutzt.

```bash
ssh -L 3000:127.0.0.1:3000 -L 8000:127.0.0.1:8000 -L 9999:127.0.0.1:9999 -L 3001:127.0.0.1:3001 -L 3002:127.0.0.1:3002 sebastian@SERVER_IP
```

Danach lokal im Browser:

- Paperless: `http://127.0.0.1:8000`
- ConvertX: `http://127.0.0.1:3000`
- Homepage: `http://127.0.0.1:3001`
- Dozzle: `http://127.0.0.1:9999`
- Uptime Kuma: `http://127.0.0.1:3002`

Nur die Ports tunneln, die wirklich gebraucht werden. Der Tunnel ersetzt keine App-Logins.
