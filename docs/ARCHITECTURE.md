# Architecture

## Process model

`claude-sandbox` is not a directory-level setting. Timezone, locale, and network
identity belong to processes, so the implementation binds them to a container pair:

```
your project (host)                    state/home (gitignored)
       | bind mount                           | bind mount
       v                                      v
+----------------------------------------------------------------+
| sandbox-workspace                                              |
|  ubuntu:24.04 + en_US.UTF-8 + America/Los_Angeles              |
|  no independent NIC, reduced capabilities, no new privileges   |
|  entrypoint drops from root to your host UID/GID               |
+----------------------------+-----------------------------------+
                             |
                    shared network namespace
                             |
+----------------------------+-----------------------------------+
| sandbox-gateway (mihomo)                                       |
|  NET_ADMIN + /dev/net/tun only                                 |
|  TUN auto-route + strict-route + DNS hijack                    |
|  proxy-providers: state/gateway/proxies.yaml                   |
|  one rule: MATCH -> US                                         |
+----------------------------+-----------------------------------+
                             |
                     selected US proxy node
```

The workspace cannot accidentally bypass the gateway: it has no independent network
interface or routing table. It also cannot alter that namespace because `NET_ADMIN`,
`NET_RAW`, `SYS_ADMIN`, `SYS_MODULE`, and `BPF` are dropped. The Docker socket is not
mounted, so the workspace cannot create sibling containers or inspect the host daemon.

## Kill switch

If mihomo or the gateway stops, the TUN device and its routes disappear. Workspace
connections fail; they do not fall back to the host's direct internet route.
`./sandbox verify --kill-switch` stops the gateway, asserts that an external request
fails, then restarts both containers in the required order.

Because the workspace shares the gateway's network namespace, a gateway restart makes
the old namespace stale. Always restart the workspace after restarting the gateway;
`./sandbox refresh` does this automatically.

## DNS

The gateway hijacks TCP and UDP port 53 inside the shared namespace. `fake-ip` mode
returns a synthetic address to the application and keeps the domain attached to the
connection for proxy-side resolution. Runtime DNS uses DoH through the tunnel. The
`proxy-server-nameserver` entries only resolve proxy hostnames and bootstrap DNS;
they are not a workspace bypass.

## Region consistency

The image sets `TZ`, `LANG`, `LC_ALL`, and `LANGUAGE`, generates `en_US.UTF-8`, and
sets both `/etc/localtime` and `/etc/timezone`. Their timestamps are backdated so a
fresh build does not look like a timezone changed minutes ago. Locale files and the
shell profile use ASCII paths. The default region is US/Pacific because that is the
intended deployment, not because other regions are technically impossible.

## Persistence and file ownership

`state/home/` becomes `/home/sandbox`; Claude Code and its login state live there.
`state/gateway/proxies.yaml` contains node credentials. `state/pinned-node` selects
a stable node. The entire `state/` tree is gitignored.

The entrypoint needs root only to create the UID/GID, seed shell files, and wait for
the tunnel. It then uses `runuser` to execute the shell as the host UID/GID. New
workspace files therefore belong to the normal host user, unlike a root-only dev
container. Use `./sandbox` or `docker exec -u UID:GID ...` for subsequent commands.

## Health checks and failover

The gateway uses a Cloudflare `generate_204` endpoint for provider and group health
checks. This avoids a subtle failure where a domain resolves to a domestic IP and
every healthy overseas node is incorrectly marked dead. With no pin, `url-test`
selects the fastest healthy US node. With a pin, the provider contains only that
node; health-check failure results in an offline workspace rather than silent
failover.

## English-only monitoring

The watcher runs on the host, not in a container. Docker Desktop bind mounts do not
reliably deliver host-side inotify events to containers, so the implementation uses a
small dependency-free polling loop. It skips VCS metadata, dependencies, and build
outputs, ignores binary files, and caps text reads at 5 MB.
