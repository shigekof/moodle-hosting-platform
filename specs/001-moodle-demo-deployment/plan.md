# Implementation Plan: Moodle Demo Site Deployment

**Branch**: `001-moodle-demo-deployment` | **Date**: 2026-04-03 | **Spec**: [spec.md](spec.md)  
**Input**: Feature specification from `/specs/001-moodle-demo-deployment/spec.md`

## Summary

Deploy a self-contained, automated Moodle LMS demo on a DigitalOcean Droplet using Docker Compose. A push to `main` triggers a GitHub Actions workflow that SSH-deploys Traefik (reverse proxy + TLS), Bitnami MariaDB 10.11, and Bitnami Redis 7.2 as shared infrastructure. Each client is provisioned as a separate named container using the same `bitnami/moodle:4.3` image but with a dedicated domain, dedicated MariaDB database, and dedicated named volumes — enabling full data isolation. New clients are added via a single `scripts/add-client.sh` command that creates the database, generates the Docker Compose service block from a template, starts the container, and runs the seed script to produce a showcase-ready learning platform accessible over HTTPS.

## Technical Context

**Language/Version**: YAML (Docker Compose v2, GitHub Actions), Bash (seed + deploy scripts)  
**Primary Dependencies**: Traefik v3.1, Bitnami Moodle 4.3 (PHP 8.2), Bitnami MariaDB 10.11, Bitnami Redis 7.2, Moove theme 4.3+, moosh CLI (Moodle Shell) for seeding, `envsubst` for client template expansion  
**Storage**: MariaDB 10.11 named volume (structured data — one database per client), Redis 7.2 named volume (sessions shared with per-client key prefixes), Docker named volumes for Moodle uploaded files and data (one pair per client)  
**Testing**: Docker Compose native `healthcheck` (service liveness), curl smoke test in GitHub Actions post-deploy job (integration), yamllint + shellcheck (static analysis), pa11y-ci (accessibility), Lighthouse CI (performance baseline)  
**Target Platform**: Ubuntu 22.04 LTS on DigitalOcean Droplet (minimum: s-2vcpu-4gb for 1–2 clients; recommended: s-4vcpu-8gb for 3–5 clients; ~1 GB RAM + 0.5 vCPU headroom per additional client)  
**Project Type**: Infrastructure-as-code deployment repository  
**Performance Goals**: TTI ≤ 3 s on broadband per client site (SC-002); Traefik routing p95 < 100 ms overhead; Moodle page cache hit rate > 80% via Redis MUC (per-client key prefix); no cross-client cache contamination  
**Constraints**: Single Droplet (no HA/cluster); per-client container isolation; ≤ 50 concurrent showcase visitors per client; no email delivery required for demo  
**Scale/Scope**: Demo/showcase sites; ~20–50 simultaneous visitors per client; 1–5 clients on a single Droplet; ~5–10 sample courses; ~10 demo user accounts per client

**Performance Baseline** (recorded for constitution Gate 4):
- Moodle homepage TTI target: ≤ 3 s (broadband, warm cache)
- Traefik HTTPS routing overhead: < 50 ms
- MariaDB query time for course list: < 100 ms
- Redis session read/write: < 5 ms

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design — see POST-DESIGN CHECK below.*

| Gate | Principle | Assessment | Status |
|------|-----------|------------|--------|
| Gate 1 | Code Quality — Static Analysis | yamllint on all YAML; shellcheck on all bash scripts; pinned image digests/tags in compose; no floating `latest` tags in production; CI lint job enforces this on every PR | ✅ PASS |
| Gate 2 | Testing Standards — Test Suite | Infrastructure TDD: smoke tests (curl) and health check assertions written in CI before infra code; P1 integration: post-deploy job asserts HTTPS 200 + valid TLS; service health checks in compose ensure dependency ordering; pa11y CI job covers accessibility regressions | ✅ PASS |
| Gate 3 | UX Consistency — Accessibility Audit | Moove theme v4.3 is WCAG 2.1 AA certified; pa11y-ci job runs axe-core rules against deployed URL after every deploy; zero critical/serious violations required to pass | ✅ PASS |
| Gate 4 | Performance Requirements — Performance Budget | Redis MUC cache configured for all Moodle stores; Lighthouse CI job captures baseline TTI after first deploy; performance targets recorded in Technical Context above | ✅ PASS |
| Gate 5 | UX Review — Design System Conformance | Moove theme colour palette and logo configured via environment variables at deploy time; all pages use Moove's design tokens; deviations require design approval | ✅ PASS |

**POST-DESIGN CHECK** (after Phase 1): All gates remain green. No constitution violations detected.

## Project Structure

### Documentation (this feature)

```text
specs/001-moodle-demo-deployment/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   ├── environment-variables.md
│   ├── github-secrets.md
│   └── routing.md
└── tasks.md             # Phase 2 output (/speckit.tasks — NOT created here)
```

### Source Code (repository root)

```text
moodle-demo/
├── docker-compose.yml          # Shared infra services: Traefik, MariaDB, Redis
│                               # Also includes Docker Compose `include:` entries for each client
├── .env.example                # Shared infra variable template (committed, no secrets)
├── traefik/
│   └── traefik.yml             # Traefik v3 static configuration (entrypoints, ACME, providers)
├── seed/
│   ├── Dockerfile              # One-shot moosh/PHP seed container
│   └── seed.sh                 # Seeds demo courses, users, Redis cache config + theme
│                               # Reads CLIENT_NAME and CLIENT_DOMAIN env vars per client
├── clients/
│   ├── _template/
│   │   ├── docker-compose.yml.tpl  # Compose service template (envsubst variables)
│   │   └── .env.example            # Per-client env template (CLIENT_NAME, CLIENT_DOMAIN, etc.)
│   └── {client-name}/          # One directory per provisioned client
│       ├── docker-compose.yml  # Generated from template by add-client.sh
│       └── .env                # Per-client credentials (gitignored, never committed)
├── scripts/
│   └── add-client.sh           # Provisions new client: creates DB, generates compose,
│                               # starts container, runs seed
├── .github/
│   └── workflows/
│       ├── deploy.yml          # Deploy shared infra + all clients on push to main
│       └── lint.yml            # yamllint + shellcheck on PR
└── README.md                   # Project overview and quick-start link
```

**Structure Decision**: Multi-client infrastructure-as-code repository. Shared infrastructure (Traefik, MariaDB, Redis) lives in the root `docker-compose.yml`. Each client is isolated in its own `clients/{name}/` directory with a generated Compose service block. The root `docker-compose.yml` uses Docker Compose v2.20+ `include:` directives to assemble all client service files at deploy time. Dynamic client provisioning is handled by `scripts/add-client.sh`, which creates the database, generates `clients/{name}/docker-compose.yml` via `envsubst`, and starts the client's Moodle container and seed.

# Phase 0 Update: Custom Moodle Image Strategy (2026-04-04)

## Image Build Approach
- Build a custom Moodle image based on official Debian and PHP images (e.g. `debian:12-slim` + `php:8.2-apache`).
- Use Apache with mod_php for initial deployment (simpler, easier to maintain for MVP).
- Install only required PHP extensions per Moodle requirements.
- Pin Moodle version and pre-install required plugins/themes at build time.
- Use Docker build args for reproducibility (Moodle version, plugin versions).
- Use environment variables for DB, Redis, SMTP, and site config (never hard-code secrets).
- Mount `moodledata` as a Docker volume (never in the image).
- Document all build args, env vars, and volumes in the Dockerfile and README.

## Rationale
- Apache/mod_php is simpler for small/medium deployments and MVPs.
- Official Debian/PHP images are well-maintained and secure.
- This approach allows easy migration to Nginx/PHP-FPM in the future if needed.
- Avoids Bitnami/legacy images for long-term maintainability.

## Next Steps
- Write a Dockerfile using `php:8.2-apache` as the base, installing Moodle and required extensions.
- Update documentation and quickstart to reflect the new image build process.
- Test the image locally and in CI before production deployment.
