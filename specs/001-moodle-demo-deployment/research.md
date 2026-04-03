# Research: Moodle Demo Site Deployment

**Feature**: `001-moodle-demo-deployment`  
**Phase**: 0 — Unknowns & Best Practices  
**Date**: 2026-04-03

---

## 1. Bitnami Moodle Image Version & Configuration

**Decision**: `bitnami/moodle:4.3` (Moodle 4.3 LTS, PHP 8.2)

**Rationale**:
- Moodle 4.3 is the current LTS-eligible stable release with the longest support window.
- Bitnami's image ships with PHP 8.2, opcache pre-configured, and environment variable bootstrapping for zero-touch first-run setup.
- The Bitnami image supports all required configuration via environment variables: database host/credentials, admin credentials, site name, SMTP, and Redis session/cache settings.

**Key environment variables** (full list in `contracts/environment-variables.md`):
- `MOODLE_DATABASE_HOST`, `MOODLE_DATABASE_USER`, `MOODLE_DATABASE_PASSWORD`, `MOODLE_DATABASE_NAME`
- `MOODLE_USERNAME`, `MOODLE_PASSWORD`, `MOODLE_EMAIL`, `MOODLE_SITE_NAME`
- `MOODLE_HOST` (public domain, used for `$CFG->wwwroot`)
- `MOODLE_SKIP_BOOTSTRAP` — set to `no` on first run to trigger installation

**Data directories inside the container**:
- `/bitnami/moodle` — Moodle application files (themes, plugins). Must be a named volume.
- `/bitnami/moodledata` — User-uploaded files, cache files. Must be a named volume.

**Alternatives considered**: Official Moodle Docker image (`moodle/moodle-php-apache`) — rejected because it requires manual PHP + web server config and does not support environment variable bootstrapping; significantly more operational overhead for a demo deployment.

---

## 2. Theme Selection

**Decision**: **Moove** theme v4.3 (maintained by Willian Mano, UFAM)

**Rationale**:
- Moove is one of the most popular third-party Moodle themes on moodle.org with 100,000+ installs.
- Built on Boost (Bootstrap 4/5 base), so it inherits responsive layouts and modern CSS.
- Ships with WCAG 2.1 AA compliance, satisfying Constitution Gate 3.
- Supports customisation via Moodle's built-in theme settings (logo, colours, typography, footer text) — no PHP code changes needed; admin UI configuration is sufficient.
- Compatible with Moodle 4.3 LTS.
- Free/open source (GPLv3).

**Installation approach**: Mount theme files into the Moodle container at `/bitnami/moodle/theme/moove/` via the `moodle_data` named volume. The seed script then activates it via Moodle CLI (`php admin/cli/cfg.php --name=theme --set=moove`).

**Alternatives considered**:
- **Adaptable** — feature-rich but complex configuration; higher risk of display inconsistencies for a demo.
- **Fordson** — visually strong but last updated for Moodle 3.x; compatibility risk with 4.3.
- **Classic** (built-in) — rejected; too plain for a showcase.
- **Boost** (built-in) — rejected; default look does not demonstrate visual quality.

---

## 3. Traefik Version & Docker Compose Integration

**Decision**: `traefik:v3.1`

**Rationale**:
- Traefik v3 is the current stable major; v3.1 adds improved Docker provider performance and dashboard usability.
- Native Docker Compose label-based routing: no separate config files needed for routing rules — labels on the Moodle service define the router, TLS, and middleware.
- Built-in ACME client issues and auto-renews Let's Encrypt certificates; zero manual cert management.
- HTTP→HTTPS redirect is a built-in middleware (`redirectscheme`).
- API dashboard disabled in production to minimise the attack surface (OWASP: security misconfiguration).

**Key static config** (`traefik/traefik.yml`):
```yaml
entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
  websecure:
    address: ":443"
certificatesResolvers:
  letsencrypt:
    acme:
      email: ${ACME_EMAIL}
      storage: /letsencrypt/acme.json
      httpChallenge:
        entryPoint: web
providers:
  docker:
    exposedByDefault: false
api:
  dashboard: false
```

**Alternatives considered**: Nginx Proxy Manager — GUI-based, but adds complexity and is harder to drive from CI. Caddy — simpler syntax, but Traefik has wider Docker ecosystem adoption and better label-based dynamic config.

---

## 4. Redis Session Cache Configuration for Moodle

**Decision**: Bitnami Redis 7.2 (`bitnami/redis:7.2`) with Moodle MUC (Moodle Universal Cache) configured for application cache + Redis session handler for PHP sessions.

**Rationale**:
- Redis 7.2 is the latest stable LTS-compatible release as of 2026.
- Moodle supports two Redis integration points:
  1. **PHP session storage** — configured in `config.php` via `$CFG->session_handler_class = '\core\session\redis'` and `$CFG->session_redis_host`.
  2. **MUC (application cache)** — configured via Moodle admin UI or CLI to use a Redis cache store for all application-level caches (user data, course structures, etc.).
- The Bitnami Moodle image exposes `MOODLE_EXTRA_CONFIGPHP` which allows injecting raw `config.php` lines — used to set Redis session handler.
- MUC configuration is applied by the seed script after first-run via `moosh cache-add-redis-store` and `moosh cache-map-mode`.

**Redis data persistence**: Named volume mounted at `/bitnami/redis/data` ensures session data survives container restarts (important for active demo sessions). No additional Redis configuration (AOF/RDB) needed for demo scale.

**Security**: Redis configured without password for internal Docker network use only. Port 6379 NOT exposed to the host. Internal Docker network provides isolation (OWASP: security misconfiguration prevention).

**Alternatives considered**: Memcached — native Moodle support but no session handler; would still need a separate session mechanism. PostgreSQL session table — heavier than Redis for high-frequency session operations.

---

## 5. GitHub Actions Deployment to DigitalOcean

**Decision**: SSH-based deployment via `appleboy/ssh-action@v1` from GitHub Marketplace.

**Rationale**:
- Simple, battle-tested action that connects to the Droplet over SSH and executes remote commands.
- Does not require the DigitalOcean API at deploy time (API token only needed for optional provisioning step or Droplet health checks).
- Workflow steps:
  1. **Lint** (PR gate): yamllint + shellcheck
  2. **Deploy** (on push to `main`): ssh into Droplet → `git pull` + `docker compose pull` + `docker compose up -d --remove-orphans`
  3. **Smoke test**: curl HTTPS endpoint, assert HTTP 200; curl admin login, assert auth page loads
  4. **Accessibility**: pa11y-ci against HTTPS URL (optional, on schedule or manual trigger)
  5. **Concurrency control**: `concurrency: group: deploy / cancel-in-progress: true` prevents overlapping deploys (edge case from spec).

**SSH key management**: ED25519 key pair. Private key stored as `SSH_PRIVATE_KEY` GitHub secret. Public key added to `~/.ssh/authorized_keys` on the Droplet. Separate deploy key avoids using root SSH credentials.

**Alternatives considered**:
- DigitalOcean App Platform — rejected; contradicts the Docker Compose + own-server requirement.
- Ansible — more powerful but significantly more configuration for a single-Droplet deploy.
- Docker Machine / Docker Context — deprecated in Docker 24+.
- Webhook receiver on Droplet — requires running a persistent service; more attack surface.

---

## 6. Demo Content Seeding with moosh

**Decision**: One-shot `seed` service in Docker Compose using a custom image built from `php:8.2-cli` with `moosh` installed, running after Moodle is healthy.

**Rationale**:
- `moosh` (Moodle Shell) is the standard Moodle CLI administration tool with 200+ commands for managing courses, users, categories, and configuration.
- Key commands used:
  - `moosh course-create --fullname="..." --shortname=... --category=...`
  - `moosh user-create --email=... --password=... username`
  - `moosh course-enrol -e manual username shortname`
  - `moosh config-set theme moove`
  - `moosh cache-add-redis-store --host=redis --port=6379 redis_store`
  - `moosh cache-map-mode --store=redis_store --mode=application`
- The seed container runs with `restart: no` and `depends_on: moodle: condition: service_healthy`, ensuring it only runs after Moodle's installation wizard has completed.
- Idempotent: the seed script checks whether courses already exist before creating them (avoids duplicate data on redeploy).

**Sample content decision**:
- **Course 1**: "Introduction to Online Learning" — Category: General; 3 sections; activities: Forum, Quiz, Page resource
- **Course 2**: "Digital Collaboration Tools" — Category: General; 2 sections; activities: Assignment, SCORM package (stub), Resource

**Alternatives considered**: Moodle backup/restore of a pre-built `.mbz` file — simpler but requires committing a binary backup archive; tricky to version-control and update. Direct SQL inserts — fragile across Moodle version upgrades.

---

## 7. DigitalOcean Droplet Provisioning

**Decision**: Manual one-time Droplet setup documented in `quickstart.md`; no automated Droplet provisioning in CI (Terraform/Doctl out of scope for MVP demo).

**Rationale**:
- Automated Droplet provisioning (Terraform + DigitalOcean provider) adds significant scope and requires Terraform state management.
- For a demo deployment, provisioning is a one-time operation; the CI/CD pipeline manages the application lifecycle, not the server lifecycle.
- `quickstart.md` documents the manual steps: create Ubuntu 22.04 Droplet, configure firewall (ports 80/443 open), install Docker via `apt`, copy SSH public key, configure DNS A record.
- The DigitalOcean API token is only needed for optional use cases (e.g., configuring Droplet monitoring); it is included as an optional secret.

**Droplet sizing**:
| Droplet | vCPU | RAM | Monthly | Use |
|---------|------|-----|---------|-----|
| s-2vcpu-4gb | 2 | 4 GB | ~$24 | Minimum — 1 Moodle replica only |
| s-4vcpu-8gb | 4 | 8 GB | ~$48 | **Recommended for 1–2 replicas** |
| s-8vcpu-16gb | 8 | 16 GB | ~$96 | Comfortable for 3–4 replicas |

**Alternatives considered**: Using the DigitalOcean API to provision a fresh Droplet on each deployment — rejected; wasteful for a demo, and provisioning time would exceed SC-001's 15-minute target.

---

## 8. Docker Compose Health Checks and Dependency Ordering

**Decision**: Native `healthcheck` directives on MariaDB, Redis, and Moodle services; `depends_on` with `condition: service_healthy` for correct startup ordering.

**Startup order and health check configuration**:
```
Redis (healthy) ──┐
                  ├──▶ Moodle (healthy) ──▶ Seed (runs once)
MariaDB (healthy) ┘
```

**Health check commands**:
- **MariaDB**: `mysqladmin ping -h localhost -u root -p$MARIADB_ROOT_PASSWORD`
- **Redis**: `redis-cli ping`
- **Moodle**: `curl -sf http://localhost/login/index.php` (returns 200 when Moodle is alive; Moodle's first-run installation can take 3–8 minutes)

**Timing parameters** (Moodle first-run):
- Moodle `start_period: 5m` — allows installation wizard to complete before health check starts failing
- Moodle `interval: 30s`, `timeout: 10s`, `retries: 10`
- This ensures the seed container does not run before Moodle is fully installed.

---

## 9. Multi-Client Per-Container Architecture

**Decision**: Each client runs as a separately named Docker service (`moodle-{client-name}`) using the shared `bitnami/moodle:4.3` image, with a dedicated MariaDB database, dedicated Docker named volumes, a dedicated public domain, and its own Traefik router. New clients are provisioned via `scripts/add-client.sh`. Redis is shared across all clients with per-client session key prefixes for logical isolation.

---

### 9.1 Docker Compose Modular Composition

**Decision**: Use Docker Compose v2.20+ `include:` directive in the root `docker-compose.yml` to assemble per-client service files at deploy time.

**Rationale**: Each client has `clients/{name}/docker-compose.yml` containing its `moodle-{name}` and `seed-{name}` services. The root compose includes all client files. This keeps the shared infra file clean and makes adding/removing a client a file operation (add/remove an `include:` entry + client directory).

**Client Compose pattern** (`clients/acme-corp/docker-compose.yml`):
```yaml
services:
  moodle-acme-corp:
    image: bitnami/moodle:4.3
    env_file: clients/acme-corp/.env
    networks: [moodle_network]
    volumes:
      - moodle_acme_corp_data:/bitnami/moodle
      - moodledata_acme_corp_data:/bitnami/moodledata
    labels:
      - traefik.enable=true
      - traefik.http.routers.moodle-acme-corp.rule=Host(`acme-corp.com`)
      - traefik.http.routers.moodle-acme-corp.tls.certresolver=letsencrypt
      - traefik.http.services.moodle-acme-corp.loadbalancer.server.port=8080
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/login/index.php"]
      start_period: 300s
      interval: 30s

  seed-acme-corp:
    image: moodle-demo-seed
    restart: "no"
    depends_on:
      moodle-acme-corp:
        condition: service_healthy
    env_file: clients/acme-corp/.env

volumes:
  moodle_acme_corp_data:
  moodledata_acme_corp_data:
```

**Root `docker-compose.yml`** includes client files:
```yaml
include:
  - clients/acme-corp/docker-compose.yml
  - clients/globex/docker-compose.yml

services:
  traefik: ...
  mariadb: ...
  redis: ...
```

**Alternatives considered**:
- `docker compose -f docker-compose.yml -f clients/clientA/docker-compose.yml ...` \u2014 valid but requires enumerating all files in every command; fragile in CI/CD.
- Single monolithic `docker-compose.yml` with all clients inlined \u2014 works but file grows unboundedly with each new client.
- Docker Swarm services \u2014 adds complexity (overlay networking, swarm init); excessive for a single-host demo.

---

### 9.2 Client Template Generation (`scripts/add-client.sh`)

**Decision**: New clients are provisioned by a Bash script using `envsubst` to expand `clients/_template/docker-compose.yml.tpl` into a ready-to-use Compose file.

**Script workflow** (`scripts/add-client.sh <name> <domain>`):
1. Validate inputs (name: lowercase alphanumeric + hyphens; domain: valid hostname).
2. Create `clients/{name}/` directory.
3. Create `clients/{name}/.env` from `clients/_template/.env.example` with generated credentials.
4. Run `envsubst` to render `clients/_template/docker-compose.yml.tpl` \u2192 `clients/{name}/docker-compose.yml`.
5. Execute MariaDB SQL: `CREATE DATABASE moodle_{name}; GRANT ALL ON moodle_{name}.* TO 'moodle'@'%';`.
6. Add `include:` entry for the new client file to `docker-compose.yml` (append only, idempotent check).
7. Run `docker compose up -d moodle-{name}` to start the new container.
8. Wait for the container to be healthy, then `docker compose run --rm seed-{name}` to seed the client.

**Rationale**: `envsubst` is a POSIX utility available on all Linux targets with no extra dependencies. Script follows `set -euo pipefail` convention. All credentials are auto-generated (random passwords via `openssl rand -hex 24`); no hardcoded secrets.

---

### 9.3 Database Isolation (Shared MariaDB, Per-Client Database)

**Decision**: Single `bitnami/mariadb:10.11` container; each client gets a dedicated database (`moodle_{name}`) and `GRANT ALL` privileges for the shared `moodle` user on that database.

**Rationale**:
- One MariaDB container is resource-efficient (single buffer pool, single process) vs. N containers.
- Dedicated database per client provides complete data isolation \u2014 no cross-client SQL queries are possible.
- A single `moodle` user with grants on each database simplifies credential management; per-client DB users can be added if stricter isolation is needed.
- MariaDB supports up to thousands of databases on a single instance.

**Alternatives considered**:
- One MariaDB container per client \u2014 stronger isolation but 5\u00d7 the memory overhead; unnecessary for a demo scenario.
- Multi-tenancy via a single shared database with a `client_id` column \u2014 requires forking Moodle\u2019s database schema; completely out of scope.

---

### 9.4 Redis Sharing with Per-Client Key Prefixes

**Decision**: Share the single `bitnami/redis:7.2` container across all clients. Each client\u2019s Moodle instance is configured with a unique session key prefix (`moodle_{name}_session_`) set via `MOODLE_EXTRA_CONFIGPHP` environment variable.

**Rationale**:
- Redis memory overhead at idle is ~2\u20134 MB. Running N Redis containers multiplies this for no benefit in a single-host demo.
- Key prefixes are a standard Redis multi-tenancy pattern sufficient for logically isolating sessions between clients.
- Cross-client session collision is impossible when prefixes are unique.
- Shared Redis preserves the ability to inspect all client sessions via one `redis-cli` connection (useful for demo operations).

**Config pattern** (in `clients/{name}/.env`):
```
MOODLE_EXTRA_CONFIGPHP=$CFG->session_redis_prefix='moodle_{name}_session_';
```

**Alternatives considered**:
- One Redis container per client \u2014 full isolation but wastes ~4 MB RAM x N clients; not needed for a demo.
- Redis ACLs/namespaces \u2014 more complex to configure; key prefixes are sufficient and simpler.

---

### 9.5 Traefik Per-Client Domain Routing

**Decision**: Each client container has unique Traefik router labels using `Host()` matching its domain. Traefik\u2019s Docker provider discovers the container automatically when started. Let\u2019s Encrypt issues a separate TLS certificate per domain via HTTP-01 challenge.

**Rationale**:
- Traefik Docker provider labels are per-service \u2014 each new client service gets its own router name, Host() rule, and TLS cert resolver reference.
- HTTP-01 ACME requires port 80 reachability for the client domain before `add-client.sh` is run (DNS must point to Droplet IP).
- Router name must be unique per client (e.g., `moodle-acme-corp`) to prevent Traefik config conflicts.

**Pre-provisioning DNS requirement**:
- DNS A record for client domain \u2192 Droplet IP must exist before provisioning.
- `add-client.sh` validates DNS resolution before starting the container.
- Traefik issues cert automatically on first HTTPS request after container start.

**Alternatives considered**:
- Wildcard certificate (e.g., `*.demo.example.com`, clients on subdomains) \u2014 eliminates per-domain DNS setup but requires DNS-01 ACME challenge (needs DNS provider API key); adds complexity and constrains client domain choice.
- Per-client subpaths (e.g., `demo.example.com/clientA`) \u2014 Moodle does not support path-prefix installation without code changes; separate domains is the correct approach.