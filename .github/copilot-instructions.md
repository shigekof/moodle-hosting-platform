# moodle-demo Development Guidelines

Auto-generated from all feature plans. Last updated: 2026-04-03

## Active Technologies

- YAML (Docker Compose v2, GitHub Actions), Bash (seed + deploy scripts) + Traefik v3.1, Bitnamilegacy Moodle 5.0.2 (PHP 8.2), Bitnamilegacy MariaDB 11.8.3, Bitnamilegacy Redis 7.2, Moove theme 4.3+, moosh CLI (Moodle Shell) for seeding (001-moodle-demo-deployment)
- Multi-client Moodle: one container per client (`moodle-{name}`) all from `bitnami/moodle:4.3`; each client has a dedicated MariaDB database and named volumes; Redis is shared with per-client session key prefixes; Traefik routes by `Host()` per client domain; new clients provisioned via `scripts/add-client.sh`

## Project Structure

```text
docker-compose.yml      # Shared infra: Traefik, MariaDB, Redis + include: entries for clients
.env.example            # Shared infra environment variables template
traefik/
  traefik.yml           # Traefik v3 static configuration
seed/
  Dockerfile            # One-shot moosh seed container
  seed.sh               # Demo course, user, theme seeding (reads CLIENT_NAME/DOMAIN)
clients/
  _template/
    docker-compose.yml.tpl  # Per-client compose service template (envsubst)
    .env.example            # Per-client env template
  {client-name}/
    docker-compose.yml  # Generated from template by add-client.sh
    .env                # Per-client credentials (gitignored)
scripts/
  add-client.sh         # Provision new client: creates DB, generates compose, starts+seeds
.github/
  workflows/
    deploy.yml          # Deploy on push to main (SSH → docker compose up)
    lint.yml            # yamllint + shellcheck on PR
specs/
  001-moodle-demo-deployment/
    plan.md / spec.md / research.md / data-model.md / quickstart.md / contracts/
```

## Commands

```bash
# Local compose (requires .env file — shared infra only)
docker compose up -d

# Provision a new client (on the Droplet):
./scripts/add-client.sh acme-corp acme-corp.com

# Check all client container status
docker compose ps

# View logs for a specific client
docker compose logs -f moodle-acme-corp

# Lint YAML files
yamllint docker-compose.yml traefik/traefik.yml .github/workflows/*.yml

# Lint shell scripts
shellcheck seed/seed.sh scripts/add-client.sh

# View live logs
docker compose logs -f traefik

# Manual seed run for a client (after its Moodle is healthy)
docker compose run --rm seed-acme-corp

# Purge Moodle caches for a client
docker compose exec moodle-acme-corp php /opt/bitnami/moodle/admin/cli/purge_caches.php
```

## Code Style

- **YAML**: 2-space indent; all image tags pinned to explicit versions (no `latest`); yamllint enforced in CI
- **Bash**: shellcheck enforced; `set -euo pipefail` at top of every script; no hard-coded secrets

## Recent Changes

- 001-moodle-demo-deployment: Added multi-client per-container architecture — one `moodle-{name}` container per client from shared `bitnami/moodle:4.3` image; per-client MariaDB databases; shared Redis with per-client session key prefixes; Traefik `Host()` routing per domain; `scripts/add-client.sh` for dynamic provisioning; `clients/_template/` and `clients/{name}/` directory structure; Docker Compose `include:` modular assembly

<!-- MANUAL ADDITIONS START -->
<!-- MANUAL ADDITIONS END -->
