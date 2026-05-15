# Caddy Snippet Validation - 2026-05-15

- Date: 2026-05-15
- Base commit: 014ee533b6e01a769575d4a6696f731286cb81b8
- Validator: caddy adapt + caddy validate --adapter caddyfile
- Runtime: existing filehub-gateway container (no reload, no restart)
- Scope: syntactic validation only. Snippets remain .disabled.

## Method

Each snippet was embedded into a wrapper Caddyfile with the standard
global header (admin off, auto_https off, h1+h2c) and a `:8080 { ... }`
site block, then copied into the running gateway container under
`/tmp/cv/` and validated via:

```
caddy adapt    --config /tmp/cv/<file>
caddy validate --adapter caddyfile --config /tmp/cv/<file>
```

A Caddyfile fmt warning on the wrapper line 9 is expected (caused by the
extra indentation level introduced when embedding the handle block) and
is unrelated to the snippet itself. The forward_auth blocks reference
`filehub-authentik-server:9000`, which is only resolved at runtime; this
does not affect syntactic validation.

## Per-snippet results

### apps/grafana/caddy.disabled

Snippet (excerpt):

```
handle /grafana/* {
    uri strip_prefix /grafana
    reverse_proxy filehub-grafana:3000
}
```

Result: OK. `caddy adapt` succeeded, `caddy validate` reported
"Valid configuration".

### apps/grafana/caddy.authentik.disabled

Snippet (excerpt):

```
handle /grafana/* {
    uri strip_prefix /grafana
    forward_auth filehub-authentik-server:9000 {
        uri /outpost.goauthentik.io/auth/caddy
        copy_headers X-Authentik-Username ...
        trusted_proxies private_ranges
    }
    reverse_proxy filehub-grafana:3000
}
```

Result: OK. Valid configuration. forward_auth directive parses cleanly.

### apps/whisper-asr/caddy.disabled

Snippet (excerpt):

```
handle /whisper/* {
    uri strip_prefix /whisper
    reverse_proxy filehub-whisper-asr:9000
}
```

Result: OK. Valid configuration.

### apps/whisper-asr/caddy.authentik.disabled

Snippet (excerpt):

```
handle /whisper/* {
    uri strip_prefix /whisper
    forward_auth filehub-authentik-server:9000 {
        uri /outpost.goauthentik.io/auth/caddy
        copy_headers X-Authentik-Username ...
        trusted_proxies private_ranges
    }
    reverse_proxy filehub-whisper-asr:9000
}
```

Result: OK. Valid configuration.

## Summary table

| Snippet                                       | Result |
|-----------------------------------------------|--------|
| apps/grafana/caddy.disabled                   | OK     |
| apps/grafana/caddy.authentik.disabled         | OK     |
| apps/whisper-asr/caddy.disabled               | OK     |
| apps/whisper-asr/caddy.authentik.disabled     | OK     |

No syntax errors were found. The only non-error output was the generic
"Caddyfile input is not formatted" warning produced by the test wrapper
indentation, which does not apply to the snippet files in their
on-disk form.

## Aktivierungspfad

This is a documentation reference; it is NOT executed by this report.

1. Rename the chosen snippet from `.disabled` to `.caddy`, e.g.:
   - `apps/grafana/caddy.disabled` -> `apps/grafana/caddy`
   - or with auth: `apps/grafana/caddy.authentik.disabled`
     -> `apps/grafana/caddy.authentik`
   Only ONE variant (plain or authentik) should be active per app.
2. Inside the `:8080 { ... }` site block of
   `config/caddy/filehub-gateway.Caddyfile`, add an `import` line that
   points to the renamed file relative to the gateway container's
   working directory, for example:
   ```
   import /etc/caddy/apps/grafana/caddy
   import /etc/caddy/apps/whisper-asr/caddy
   ```
   (Adjust the path prefix to whatever the gateway compose file mounts;
   the `apps/` tree must be available inside the container.)
3. Reload the gateway only via the project's standard procedure
   (compose up / reload script). Do not edit live state.
4. Verify with `caddy validate` inside the container before reload.

End of report.
