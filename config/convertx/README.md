# ConvertX-Konfiguration

ConvertX speichert Daten persistent unter `data/convertx`, gemountet nach `/app/data`.

`CONVERTX_JWT_SECRET` muss stabil bleiben, damit Sessions nach Neustarts gültig bleiben. `ACCOUNT_REGISTRATION=false` verhindert offene Selbstregistrierung. `MAX_CONVERT_PROCESS=2` begrenzt parallele Konvertierungen für den aktuellen 4-vCPU-Server.
