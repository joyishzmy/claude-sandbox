# Troubleshooting

## Docker is not ready

Start Docker Desktop first. On Windows also enable WSL integration for your distro
(Settings → Resources → WSL Integration). On macOS wait for the engine to finish
starting. Then rerun `./sandbox up`.

If `docker` works in PowerShell but not in WSL, integration is the missing piece;
this package intentionally uses the native WSL Docker CLI rather than translating
paths through `docker.exe`.

## Docker Hub pull fails

In mainland China or another restricted network, configure a Docker Hub registry
mirror in Docker Desktop's daemon settings. Apply changes while Docker Desktop is
stopped, then start it again: Docker Desktop can rewrite settings files on exit.
`APT_MIRROR` only changes Ubuntu package downloads during the image build; it does
not configure Docker Hub.

## No proxy nodes found

Select the intended subscription in Clash Verge Rev first, then `./sandbox nodes`.
The current profile must contain US nodes whose names match `美国`, `西美`, `US`, or
`United States`. For other naming schemes, use a YAML file with a `proxies:` list and
`./sandbox import`, or adjust the filter in `gateway/config.yaml` and
`scripts/nodes.py` consistently.

## Pinned node disappeared

A subscription update can remove or rename a node. `./sandbox refresh` then refuses
to guess a replacement and prints the available US node names. Run `./sandbox pin
"NEW NAME"` or `./sandbox pin --auto` to recover.

## Tunnel is down

Read `./sandbox logs` first. Common causes:

- the selected node is dead or its credentials expired;
- a CDN-fronted VLESS/WS node fails at the protocol layer even though TCP/TLS connects;
- the proxy subscription is exhausted;
- the gateway restarted without restarting the workspace.

Try another node, refresh the subscription, then `./sandbox refresh`. To rebuild the
namespace relationship cleanly: `./sandbox down && ./sandbox up`.

If you see `activate health check` repeatedly, do not switch the health endpoint to
`www.gstatic.com`: in some networks it resolves to a domestic IP and falsely marks
all overseas nodes dead. The supplied Cloudflare endpoint avoids that failure.

## DNS or locale looks wrong

`./sandbox verify` prints the timezone files, locale, DNS result, and egress JSON.
Both `/etc/localtime` and `/etc/timezone` must say `America/Los_Angeles`. If you
change the timezone in `.env`, also change the image's zoneinfo entries in
`image/Dockerfile` and rebuild; the two text/binary timezone files must agree.

## Files created in the workspace cannot be edited on the host

Check `.env`: `SANDBOX_UID` and `SANDBOX_GID` should match `id -u` and `id -g` on the
host. The entrypoint drops to that user after startup. Older root-created files may
need a one-time ownership repair by an administrator on the host.

## GUI applications do not open a window

This package targets CLI work and does not provide an X11/Wayland bridge. Run the
GUI on the host against the same project directory. Do not infer a sandbox network
failure from a GUI display failure.

## macOS-specific checks

On a Mac, run in order:

```bash
./sandbox doctor
./sandbox verify --kill-switch
docker exec sandbox-workspace date
```

If TUN creation fails, inspect `./sandbox logs` for `/dev/net/tun` or permission
errors and verify that Docker Desktop (not an untested alternative runtime) is in
use. On Apple Silicon also check `docker image inspect metacubex/mihomo:v1.19.32`
to confirm that an arm64 variant was pulled.
