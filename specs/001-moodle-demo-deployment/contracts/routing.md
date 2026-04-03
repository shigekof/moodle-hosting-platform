# Contract: HTTP Routing (Traefik)

**Feature**: `001-moodle-demo-deployment`  
**Interface**: Public HTTP/HTTPS endpoints at the configured domain  
**Managed by**: Traefik v3.1 via Docker Compose labels and static config

---

## Public Endpoints

Each provisioned client has its own public endpoint. All clients are served from the same Droplet IP address; Traefik routes based on the `Host` header.

| Endpoint | Protocol | Behaviour |
|----------|----------|-----------|
| `http://{CLIENT_DOMAIN}:80/*` | HTTP | Permanent 301 redirect → `https://{CLIENT_DOMAIN}/*` |
| `https://{CLIENT_DOMAIN}:443/*` | HTTPS | Proxied to the client’s `moodle-{name}` container on port 8080 |

One row exists per provisioned client. No other ports are exposed to the public internet. Ports 3306, 6379, and internal service ports are bound only to the internal Docker network.

---

## TLS Configuration

| Attribute | Value |
|-----------|-------|
| Certificate Authority | Let's Encrypt (production) |
| Challenge Type | HTTP-01 (via Traefik ACME client) |
| Certificate Resolver | `letsencrypt` |
| Certificate Storage | `/letsencrypt/acme.json` (named volume `traefik_certs`) |
| Auto-Renewal | Traefik renews automatically ≥ 30 days before expiry |
| TLS Versions | TLS 1.2 minimum (Traefik v3 default profile) |

**Pre-condition for TLS issuance (per client)**: DNS A record for each `CLIENT_DOMAIN` MUST point to the Droplet’s public IP *before* running `scripts/add-client.sh`. Let’s Encrypt’s HTTP-01 challenge requires port 80 to be reachable from the internet. Each client domain gets its own independently managed TLS certificate stored in `traefik_certs`.

---

## HTTP→HTTPS Redirect

Configured as a Traefik entrypoint-level redirect (not a router-level middleware), ensuring ALL paths under port 80 redirect permanently to HTTPS. This is the most robust placement because it applies before any router matching.

```yaml
# traefik/traefik.yml (static config)
entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
          permanent: true
```

---

## Per-Client Traefik Router Labels

Each client container (`moodle-{name}`) in `clients/{name}/docker-compose.yml` carries its own unique Traefik labels. The router name, service name, and `Host()` rule are all unique per client.

```yaml
# clients/acme-corp/docker-compose.yml
services:
  moodle-acme-corp:
    labels:
      traefik.enable: "true"
      traefik.http.routers.moodle-acme-corp.rule: "Host(`acme-corp.com`)"
      traefik.http.routers.moodle-acme-corp.entrypoints: "websecure"
      traefik.http.routers.moodle-acme-corp.tls: "true"
      traefik.http.routers.moodle-acme-corp.tls.certresolver: "letsencrypt"
      traefik.http.services.moodle-acme-corp.loadbalancer.server.port: "8080"
```

The label naming convention is: `moodle-{CLIENT_NAME}` for both the router and service names. Router names MUST be globally unique across all client containers; using the client slug ensures this.

---

## Per-Client Domain Routing

Traefik routes each incoming HTTPS request to the correct client container based on the `Host` header matching the client’s registered domain. Each client is an independent routing target — there is no shared load balancer pool between clients.

| Behaviour | Detail |
|-----------|--------|
| Routing key | `Host()` header matcher per client domain |
| Isolation | Each client’s traffic is routed exclusively to its own `moodle-{name}` container |
| TLS | Each client domain has its own Let’s Encrypt certificate |
| Health checks | Traefik removes a client’s container from routing if the Docker health check fails; other clients are unaffected |
| New client activation | Traefik discovers the new container automatically via the Docker socket when `docker compose up -d moodle-{name}` is run |
| Client removal | Remove the `include:` entry and stop the container; Traefik removes it from routing immediately |

Traefik’s API dashboard is **disabled** in production (`api.dashboard: false` in `traefik.yml`). This prevents information disclosure about the routing configuration (OWASP A05: Security Misconfiguration).

---

## Security Headers

Traefik applies the following security response headers to all HTTPS responses via a shared middleware:

| Header | Value |
|--------|-------|
| `X-Frame-Options` | `SAMEORIGIN` |
| `X-Content-Type-Options` | `nosniff` |
| `Referrer-Policy` | `strict-origin-when-cross-origin` |
| `Permissions-Policy` | `camera=(), microphone=(), geolocation=()` |
| `Strict-Transport-Security` | `max-age=31536000; includeSubDomains` |

These are applied via a Traefik middleware defined in `traefik/traefik.yml` and attached to the Moodle router.

---

## Firewall Requirements (DigitalOcean Cloud Firewall)

The DigitalOcean Droplet firewall MUST allow:

| Direction | Port | Protocol | Source |
|-----------|------|----------|--------|
| Inbound | 80 | TCP | `0.0.0.0/0` (all IPv4), `::/0` (all IPv6) |
| Inbound | 443 | TCP | `0.0.0.0/0` (all IPv4), `::/0` (all IPv6) |
| Inbound | 22 | TCP | Administrator IP(s) only |
| Outbound | All | All | `0.0.0.0/0` |

All other inbound ports MUST be blocked at the cloud firewall level. This is a defense-in-depth measure in addition to Docker not publishing internal service ports.
