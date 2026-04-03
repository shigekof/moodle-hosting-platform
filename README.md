# Moodle Demo Site

Multi-client Moodle demo deployment using Docker Compose, Traefik, Bitnami Moodle 4.3, MariaDB, and Redis on a DigitalOcean Droplet. Each client gets an isolated Moodle container, database, and HTTPS domain — all provisioned with one command.

## Quickstart

See [specs/001-moodle-demo-deployment/quickstart.md](specs/001-moodle-demo-deployment/quickstart.md) for the full step-by-step guide.

## Add a new client

```bash
# On the Droplet, from /opt/moodle-demo:
./scripts/add-client.sh acme-corp acme-corp.com
```

## Project structure

```
docker-compose.yml          # Shared infra: Traefik, MariaDB, Redis
.env.example                # Shared infra env template
traefik/traefik.yml         # Traefik v3 static config
seed/
  Dockerfile                # One-shot moosh seed container
  seed.sh                   # Seeds theme, courses, users per client
clients/
  _template/                # Compose + env templates for new clients
  {client-name}/            # Generated per-client compose + env
scripts/
  add-client.sh             # Provision a new client
.github/workflows/
  deploy.yml                # Deploy shared infra on push to main
  lint.yml                  # yamllint + shellcheck on PRs
```

## Requirements

- Docker Engine 24+ and Docker Compose v2.20+
- Registered domain(s) with DNS A records pointing to the Droplet IP
- GitHub repository secrets configured (see quickstart)

