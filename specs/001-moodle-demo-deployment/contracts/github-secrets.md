# Contract: GitHub Actions Secrets

**Feature**: `001-moodle-demo-deployment`  
**Interface**: GitHub repository secrets (Settings → Secrets and variables → Actions)

---

## Required Secrets

These secrets MUST be configured in the GitHub repository before the deployment workflow can run. The workflow validates for their presence at the start of each run.

### Server Access

| Secret Name | Description | How to Obtain |
|-------------|-------------|---------------|
| `SSH_HOST` | Public IP address of the DigitalOcean Droplet | DigitalOcean console → Droplet → IP address |
| `SSH_USERNAME` | SSH user on the Droplet | Typically `root` for a new Ubuntu Droplet, or a dedicated deploy user |
| `SSH_PRIVATE_KEY` | ED25519 private key for SSH access | Generated locally: `ssh-keygen -t ed25519 -C "deploy@moodle-demo"` → paste private key |

### Application Configuration

| Secret Name | Corresponds To | Description |
|-------------|----------------|-------------|
| `MOODLE_DOMAIN` | `.env / MOODLE_DOMAIN` | Public domain name (e.g., `moodle.example.com`) |
| `ACME_EMAIL` | `.env / ACME_EMAIL` | Email for Let's Encrypt registration |
| `MOODLE_USERNAME` | `.env / MOODLE_USERNAME` | Admin username |
| `MOODLE_PASSWORD` | `.env / MOODLE_PASSWORD` | Admin password (≥ 16 chars, mixed) |
| `MOODLE_EMAIL` | `.env / MOODLE_EMAIL` | Admin email |
| `MOODLE_SITE_NAME` | `.env / MOODLE_SITE_NAME` | Site display name |
| `MARIADB_ROOT_PASSWORD` | `.env / MARIADB_ROOT_PASSWORD` | MariaDB root password |
| `MARIADB_PASSWORD` | `.env / MARIADB_PASSWORD` | Moodle DB user password |

---

## How the Workflow Uses Secrets

The deploy workflow (`deploy.yml`) uses secrets in two ways:

**1. SSH connection** — `appleboy/ssh-action` uses `SSH_HOST`, `SSH_USERNAME`, `SSH_PRIVATE_KEY` to open an authenticated connection to the Droplet.

**2. `.env` file generation** — The workflow writes a `.env` file on the Droplet from secrets, then runs `docker compose up`. The generated file is stored at `/opt/moodle-demo/.env` with permissions `600` (owner-readable only):

```bash
cat > /opt/moodle-demo/.env <<EOF
MOODLE_DOMAIN=${{ secrets.MOODLE_DOMAIN }}
ACME_EMAIL=${{ secrets.ACME_EMAIL }}
MOODLE_USERNAME=${{ secrets.MOODLE_USERNAME }}
MOODLE_PASSWORD=${{ secrets.MOODLE_PASSWORD }}
MOODLE_EMAIL=${{ secrets.MOODLE_EMAIL }}
MOODLE_SITE_NAME=${{ secrets.MOODLE_SITE_NAME }}
MARIADB_ROOT_PASSWORD=${{ secrets.MARIADB_ROOT_PASSWORD }}
MARIADB_PASSWORD=${{ secrets.MARIADB_PASSWORD }}
EOF
chmod 600 /opt/moodle-demo/.env
```

---

## Security Requirements

- Secrets are never echoed to workflow logs (GitHub redacts known secret values, but avoid `echo "${{ secrets.X }}"` patterns).
- The SSH private key must correspond to a public key in `~/.ssh/authorized_keys` on the Droplet.
- The deploy user should have access only to `/opt/moodle-demo/` and Docker commands — principle of least privilege.
- Rotate secrets by updating GitHub secret values and re-running the workflow; no code changes required.
- The `.env` file written on the Droplet MUST NOT be readable by other users (`chmod 600`).

---

## Concurrency Behavior

The workflow uses `concurrency` groups to prevent overlapping deployments:

```yaml
concurrency:
  group: deploy-production
  cancel-in-progress: true
```

If two pushes are made in quick succession, the first workflow run is cancelled and only the latest runs to completion. This satisfies the concurrent-deploy edge case in the spec.
