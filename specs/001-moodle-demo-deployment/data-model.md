# Data Model: Moodle Demo Site Deployment

**Feature**: `001-moodle-demo-deployment`  
**Phase**: 1 — Design  
**Date**: 2026-04-03

---

## 1. Service Architecture Overview

```
Internet
   │
   ▼ :80/:443
┌──────────────────────────────────────────────────────┐
│  traefik  (TLS termination, HTTP→HTTPS redirect,     │
│  per-client Host() routing, per-domain ACME TLS)     │
│  image: traefik:v3.1                                 │
└───────┬──────────────────┬───────────────────────────┘
        │ Host(clientA.com)│ Host(clientB.com)
        ▼                  ▼
┌───────────────┐  ┌───────────────┐  ┌─── ... ───┐
│ moodle-       │  │ moodle-       │  │ moodle-   │
│ {client-a}    │  │ {client-b}    │  │ {client-N}│
│ bitnami/      │  │ bitnami/      │  │ bitnami/  │
│ moodle:4.3    │  │ moodle:4.3    │  │ moodle:4.3│
│ own volumes   │  │ own volumes   │  │ own vols  │
└──────┬────────┘  └──────┬────────┘  └────┬──────┘
       │                  │                │
       ▼                  ▼                ▼
┌──────────────────────────────────────────────────────┐
│  mariadb  (shared container)                         │
│  image: bitnami/mariadb:10.11                        │
│  db_client_a | db_client_b | ... (per-client DBs)    │
└──────────────────────────────────────────────────────┘
       │                  │                │
       ▼                  ▼                ▼
┌──────────────────────────────────────────────────────┐
│  redis  (shared container)                           │
│  image: bitnami/redis:7.2                            │
│  key prefix: moodle_{client}_session_ per client     │
└──────────────────────────────────────────────────────┘
           ▲              ▲
┌──────────────┐  ┌──────────────┐
│ seed-{client-a} │  │ seed-{client-b} │
│ one-shot seed │  │ one-shot seed │
│ restart: no   │  │ restart: no   │
└───────────────┘  └───────────────┘
```

All services communicate on a single internal Docker bridge network (`moodle_network`). Only Traefik's ports 80/443 are published to the host. Each client has its own named service, named volumes, and MariaDB database. Redis and MariaDB are shared infrastructure containers.

---

## 2. Docker Services

### 2.1 traefik

| Attribute | Value |
|-----------|-------|
| Image | `traefik:v3.1` |
| Restart Policy | `unless-stopped` |
| Published Ports | `80:80`, `443:443` |
| Volumes | `/var/run/docker.sock:/var/run/docker.sock:ro`, `traefik_certs:/letsencrypt` |
| Config Mount | `./traefik/traefik.yml:/etc/traefik/traefik.yml:ro` |
| Networks | `moodle_network` |
| Labels | `traefik.enable=false` (dashboard disabled) |

**Key static config** (`traefik/traefik.yml`):
- `entryPoints.web` (port 80) → permanent HTTP→HTTPS redirect
- `entryPoints.websecure` (port 443) → TLS
- `certificatesResolvers.letsencrypt` → ACME HTTP-01 challenge
- `providers.docker.exposedByDefault: false`

### 2.2 mariadb

| Attribute | Value |
|-----------|-------|
| Image | `bitnami/mariadb:10.11` |
| Restart Policy | `unless-stopped` |
| Published Ports | None (internal only) |
| Volumes | `mariadb_data:/bitnami/mariadb` |
| Networks | `moodle_network` |
| Health Check | `mysqladmin ping -h localhost -u root -p${MARIADB_ROOT_PASSWORD}` |
| Health Check Timing | `interval: 10s`, `timeout: 5s`, `retries: 10`, `start_period: 30s` |

**Environment variables** (from `.env` / GitHub secrets):
```
MARIADB_ROOT_PASSWORD
MARIADB_DATABASE=moodle
MARIADB_USER=moodle
MARIADB_PASSWORD
MARIADB_CHARACTER_SET=utf8mb4
MARIADB_COLLATE=utf8mb4_unicode_ci
```

### 2.3 redis

| Attribute | Value |
|-----------|-------|
| Image | `bitnami/redis:7.2` |
| Restart Policy | `unless-stopped` |
| Published Ports | None (internal only) |
| Volumes | `redis_data:/bitnami/redis/data` |
| Networks | `moodle_network` |
| Health Check | `redis-cli ping` |
| Health Check Timing | `interval: 10s`, `timeout: 5s`, `retries: 5`, `start_period: 10s` |

**Environment variables**:
```
ALLOW_EMPTY_PASSWORD=yes   # safe: port not published, isolated Docker network
```

### 2.4 moodle-{client-name} (per-client service)

Each client has a uniquely named service in `clients/{name}/docker-compose.yml`. All client services
use the same `bitnami/moodle:4.3` image but are fully isolated from one another.

| Attribute | Value |
|-----------|-------|
| Image | `bitnami/moodle:4.3` |
| Service Name | `moodle-{client-name}` (e.g., `moodle-acme-corp`) |
| Restart Policy | `unless-stopped` |
| Published Ports | None (Traefik routes via internal network) |
| Volumes | `moodle_{client}_data:/bitnami/moodle`, `moodledata_{client}_data:/bitnami/moodledata` |
| Networks | `moodle_network` |
| Depends On | `mariadb: service_healthy`, `redis: service_healthy` |
| Health Check | `curl -sf http://localhost:8080/login/index.php` |
| Health Check Timing | `interval: 30s`, `timeout: 10s`, `retries: 10`, `start_period: 5m` |
| Env File | `clients/{name}/.env` |

**Traefik labels** (unique per client):
```
traefik.enable=true
traefik.http.routers.moodle-{name}.rule=Host(`{CLIENT_DOMAIN}`)
traefik.http.routers.moodle-{name}.entrypoints=websecure
traefik.http.routers.moodle-{name}.tls.certresolver=letsencrypt
traefik.http.services.moodle-{name}.loadbalancer.server.port=8080
```

**Key environment variables** (per-client, from `clients/{name}/.env`):
```
CLIENT_NAME                # short slug, e.g. acme-corp
CLIENT_DOMAIN              # public domain, e.g. acme-corp.com
MOODLE_DATABASE_HOST=mariadb
MOODLE_DATABASE_PORT_NUMBER=3306
MOODLE_DATABASE_USER=moodle
MOODLE_DATABASE_PASSWORD   # shared DB user password
MOODLE_DATABASE_NAME=moodle_{client-name}  # per-client database
MOODLE_USERNAME            # site admin username
MOODLE_PASSWORD            # site admin password (auto-generated)
MOODLE_EMAIL               # site admin email
MOODLE_SITE_NAME           # site display name
MOODLE_HOST                # must match CLIENT_DOMAIN
MOODLE_EXTRA_CONFIGPHP     # injects Redis session prefix:
  $CFG->session_handler_class = '\core\session\redis';
  $CFG->session_redis_host = 'redis';
  $CFG->session_redis_port = 6379;
  $CFG->session_redis_prefix = 'moodle_{client-name}_session_';  # per-client prefix
  $CFG->session_redis_acquire_lock_timeout = 120;
  $CFG->session_redis_lock_expire = 7200;
```

### 2.5 seed-{client-name} (per-client, one-shot)

| Attribute | Value |
|-----------|-------|
| Image | `moodle-demo-seed` (built from `./seed/Dockerfile`) |
| Service Name | `seed-{client-name}` (e.g., `seed-acme-corp`) |
| Restart Policy | `no` |
| Volumes | `moodle_{client}_data:/bitnami/moodle`, `moodledata_{client}_data:/bitnami/moodledata` |
| Networks | `moodle_network` |
| Depends On | `moodle-{client-name}: service_healthy` |
| Env File | `clients/{name}/.env` |

**Operations performed by `seed/seed.sh`** (reads `CLIENT_NAME` and `CLIENT_DOMAIN` from env):
1. Verify moosh can connect (`moosh info`)
2. Configure Moove theme active (`moosh config-set theme moove`)
3. Configure Redis MUC cache store
4. Create demo user accounts (learner1, learner2)
5. Create Category: "Demo Courses"
6. Create Course 1: "Introduction to Online Learning" with Forum + Quiz + Page
7. Create Course 2: "Digital Collaboration Tools" with Assignment + Resource
8. Enrol demo users in both courses
9. Set site front page to display course list

---

## 3. Named Volumes

| Volume | Service | Path in Container | Purpose | Persistence |
|--------|---------|------------------|---------|-------------|
| `mariadb_data` | mariadb | `/bitnami/mariadb` | All client databases | Must survive restart |
| `moodle_{client}_data` | moodle-{client}, seed-{client} | `/bitnami/moodle` | Per-client Moodle app files | Must survive restart; isolated per client |
| `moodledata_{client}_data` | moodle-{client}, seed-{client} | `/bitnami/moodledata` | Per-client user uploads, temp files | Must survive restart; isolated per client |
| `redis_data` | redis | `/bitnami/redis/data` | All client sessions + cache (key-prefixed) | Should survive restart (active sessions) |
| `traefik_certs` | traefik | `/letsencrypt` | ACME certificate store (all client domains) | Must survive restart (avoid cert re-issuance rate limits) |

Volume naming convention: `moodle_{client-slug}_data`, `moodledata_{client-slug}_data` where `{client-slug}` is the client name with hyphens replaced by underscores (e.g., `acme-corp` → `moodle_acme_corp_data`).

---

## 4. Network Topology

| Network | Type | Services | External |
|---------|------|----------|----------|
| `moodle_network` | bridge | traefik, moodle-{all clients}, mariadb, redis, seed-{all clients} | No — internal only |

Published ports on host:
- `0.0.0.0:80` → traefik web entrypoint (redirects to HTTPS)
- `0.0.0.0:443` → traefik websecure entrypoint

All other service ports (3306, 6379, 8080) are internal to `moodle_network` only — never published to the host. Security requirement: FR-014.

---

## 5. Data State Transitions

### First Deployment (fresh Droplet — shared infrastructure only)

```
Start compose (shared infra only, no clients yet)
  └─▶ traefik starts → exposes :80 and :443
  └─▶ mariadb starts → health check passes (30s)
  └─▶ redis starts → health check passes (10s)
  └─▶ Shared infra ready. No client containers yet.
```

### Provisioning a New Client (`scripts/add-client.sh <name> <domain>`)

```
scripts/add-client.sh acme-corp acme-corp.com
  └─▶ Validate: name is alphanumeric-hyphen; domain resolves to Droplet IP
  └─▶ Create clients/acme-corp/.env with generated credentials
  └─▶ envsubst on template → clients/acme-corp/docker-compose.yml
  └─▶ MariaDB: CREATE DATABASE moodle_acme_corp;
               GRANT ALL ON moodle_acme_corp.* TO 'moodle'@'%';
  └─▶ Append include: entry to docker-compose.yml (idempotent)
  └─▶ docker compose up -d moodle-acme-corp
        ├─ Bitnami init: creates schema in moodle_acme_corp
        ├─ Creates admin account from CLIENT_ADMIN_USERNAME/PASSWORD
        ├─ Configures wwwroot = acme-corp.com
        └─ Injects Redis session prefix: moodle_acme_corp_session_
  └─▶ moodle-acme-corp health check passes (~3–8 min)
  └─▶ Traefik: discovers container, issues Let's Encrypt cert for acme-corp.com
  └─▶ docker compose run --rm seed-acme-corp
        ├─ Sets theme to moove
        ├─ Configures Redis MUC
        ├─ Creates demo users + courses
        └─ Exits (restart: no)
  └─▶ https://acme-corp.com is live
```

### Subsequent Deployments (rolling update)

```
push to main → GitHub Actions:
  ├─ docker compose pull (new image versions if any)
  ├─ docker compose up -d --remove-orphans
  │   └─ Only changed services restart (Compose reconciles state)
  │   └─ Traefik continues routing to all other healthy client containers
  ├─ smoke test: curl each client HTTPS endpoint → assert 200
  └─ workflow passes
```

### Data Preservation Guarantee

Named volumes are NOT removed by `docker compose up -d`. A redeploy that changes only the `moodle` service version will:
- Restart only the moodle container
- Keep MariaDB and Redis running (no data loss)
- Re-mount existing `moodle_data` and `moodledata_data` volumes into the new container

---

## 6. Configuration Entity: Environment File

All runtime configuration is supplied via a `.env` file on the Droplet (never committed). The `.env.example` file documents every required variable. See `contracts/environment-variables.md` for the full specification.

### Key entity relationships (env → service)

```
.env  (shared infra)
  ├── MARIADB_ROOT_PASSWORD  → mariadb, add-client.sh (DB provisioning)
  ├── MARIADB_PASSWORD       → mariadb + all client moodle containers
  └── ACME_EMAIL             → traefik ACME cert registration email

clients/{name}/.env  (per-client)
  ├── CLIENT_NAME            → service naming + Redis prefix
  ├── CLIENT_DOMAIN          → MOODLE_HOST + Traefik Host() rule
  ├── MOODLE_DATABASE_NAME   → per-client MariaDB database (moodle_{name})
  ├── MOODLE_USERNAME        → first-run admin username
  ├── MOODLE_PASSWORD        → first-run admin password (auto-generated)
  ├── MOODLE_EMAIL           → admin email
  ├── MOODLE_SITE_NAME       → site display name
  └── MOODLE_EXTRA_CONFIGPHP → Redis session handler + per-client prefix
```

---

## 7. Seed Content Entities

### Demo Course 1 — Introduction to Online Learning

| Attribute | Value |
|-----------|-------|
| Short Name | `INTRO001` |
| Category | Demo Courses |
| Sections | 3 |
| Activities | Forum (Welcome discussion), Quiz (LMS Basics, 5 questions), Page (Course Guide) |
| Enrolment | Manual — learner1, learner2 enrolled |
| Visible | Yes |

### Demo Course 2 — Digital Collaboration Tools

| Attribute | Value |
|-----------|-------|
| Short Name | `COLLAB001` |
| Category | Demo Courses |
| Sections | 2 |
| Activities | Assignment (Group Project Brief), Resource (PDF — Collaboration Guide) |
| Enrolment | Manual — learner1, learner2 enrolled |
| Visible | Yes |

### Demo User Accounts

| Username | Role | Enrolled In | Purpose |
|----------|------|-------------|---------|
| `admin` | Site Administrator | N/A | Supplied via MOODLE_USERNAME secret. Admin dashboard walkthroughs |
| `learner1` | Student | INTRO001, COLLAB001 | Demonstrate student view / course navigation |
| `learner2` | Student | INTRO001, COLLAB001 | Demonstrate peer interactions (forums, assignments) |

Passwords for `learner1` and `learner2` are set in `seed.sh` and documented in `quickstart.md` (default showcase passwords, reset before any public use).

# Phase 0 Update: Data Model Impact of Custom Image (2026-04-04)

- Moodle service will use a custom image built from official Debian/PHP with Apache/mod_php.
- No change to MariaDB or Redis data model; volumes and per-client DBs remain as before.
- moodledata remains a named Docker volume, not part of the image.
- All configuration and secrets are injected via environment variables, not baked into the image.
