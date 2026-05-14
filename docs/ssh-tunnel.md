# SSH-Tunnel

Alle Filehub-Webdienste laufen nur auf `127.0.0.1` des Servers. Für Remote-Zugriff wird SSH-Portweiterleitung genutzt.

```bash
ssh -L 3000:127.0.0.1:3000 \
    -L 3001:127.0.0.1:3001 \
    -L 3002:127.0.0.1:3002 \
    -L 3003:127.0.0.1:3003 \
    -L 3004:127.0.0.1:3004 \
    -L 8000:127.0.0.1:8000 \
    -L 9999:127.0.0.1:9999 \
    sebastian@SERVER_IP
```

Danach lokal im Browser:

- Paperless: `http://127.0.0.1:8000`
- ConvertX: `http://127.0.0.1:3000`
- Homepage: `http://127.0.0.1:3001`
- Uptime Kuma: `http://127.0.0.1:3002`
- Filebrowser: `http://127.0.0.1:3003`
- Stirling PDF: `http://127.0.0.1:3004`
- Dozzle: `http://127.0.0.1:9999`

## Termix (iOS) Local Forwards

| Name | Remote Host | Remote Port | Local Port |
|---|---|---|---|
| filehub-paperless | 127.0.0.1 | 8000 | 8000 |
| filehub-convertx | 127.0.0.1 | 3000 | 3000 |
| filehub-homepage | 127.0.0.1 | 3001 | 3001 |
| filehub-uptime-kuma | 127.0.0.1 | 3002 | 3002 |
| filehub-filebrowser | 127.0.0.1 | 3003 | 3003 |
| filehub-stirling-pdf | 127.0.0.1 | 3004 | 3004 |
| filehub-dozzle | 127.0.0.1 | 9999 | 9999 |

Nur die Ports tunneln, die wirklich gebraucht werden. Der Tunnel ersetzt keine App-Logins.
