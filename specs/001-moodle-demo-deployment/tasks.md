---
description: "Task list for Moodle Demo Site Deployment (multi-client, per-container)"
---

# Tasks: Moodle Demo Site Deployment (Multi-Client, Per-Container)

**Input**: Design documents from `/specs/001-moodle-demo-deployment/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

## Phase 1: Setup (Shared Infrastructure)

- [x] T001 Create repository structure as per plan.md (docker-compose.yml, clients/, seed/, scripts/, traefik/, .github/)
- [x] T002 Initialize shared Docker Compose file for infra (traefik, mariadb, redis) in docker-compose.yml
- [x] T003 [P] Create .env.example for shared infra variables at root
- [x] T004 [P] Create traefik/traefik.yml with static config (entrypoints, ACME, providers)
- [x] T005 [P] Create clients/_template/docker-compose.yml.tpl and .env.example for per-client services
- [x] T006 [P] Create seed/Dockerfile and seed/seed.sh for demo content seeding
- [x] T007 [P] Create scripts/add-client.sh for dynamic client provisioning
- [x] T008 [P] Create .github/workflows/deploy.yml and lint.yml for CI/CD

---

## Phase 2: Foundational (Blocking Prerequisites)

- [x] T009 Implement Docker Compose healthchecks for mariadb, redis, and moodle containers
- [x] T010 [P] Implement .gitignore to exclude .env and client secrets
- [x] T011 [P] Configure DigitalOcean Droplet firewall (allow 80/443/22, block all others)
- [x] T012 [P] Document DNS and firewall setup in quickstart.md
- [x] T013 [P] Implement environment variable validation in deploy.yml and add-client.sh
- [x] T014 [P] Create README.md with project overview and quickstart link

---

## Phase 3: User Story 1 - First-Time Deployment by Site Administrator (Priority: P1) 🎯 MVP

**Goal**: Enable a site administrator to deploy the full stack and access Moodle at a configured domain via automated CI/CD.

**Independent Test**: Run GitHub Actions workflow, verify Moodle login page is reachable over HTTPS at the configured domain within 10 minutes, with valid TLS.

- [x] T015 [US1] Implement GitHub Actions workflow to SSH into Droplet, pull repo, and run docker compose up
- [x] T016 [P] [US1] Implement deploy.yml step to generate .env from GitHub secrets
- [x] T017 [P] [US1] Implement deploy.yml step to run docker compose pull and up for shared infra
- [x] T018 [P] [US1] Implement deploy.yml step to run smoke test (curl HTTPS endpoint, assert 200)
- [x] T019 [US1] Document admin credential setup and workflow usage in quickstart.md
- [x] T020 [US1] Document troubleshooting for failed deployments in quickstart.md

---

## Phase 4: User Story 2 - Showcase Visitor Browses the Moodle Site (Priority: P2)

**Goal**: Visitors see a polished, themed Moodle site with demo content and can browse courses on desktop and mobile.

**Independent Test**: Deploy site, verify homepage shows custom theme, at least one sample course is visible, and site is responsive.

- [x] T021 [US2] Implement seed/seed.sh to create demo courses, users, and enrolments
- [x] T022 [P] [US2] Implement Moove theme activation in seed/seed.sh
- [x] T023 [P] [US2] Implement mobile responsiveness check in pa11y-ci or Lighthouse CI job
- [x] T024 [US2] Document demo user accounts and sample content in quickstart.md
- [x] T025 [US2] Document theme customization options in quickstart.md

---

## Phase 5: Custom Moodle Image (Official Debian/PHP, Apache/mod_php)

**Goal**: Build and deploy a custom Moodle Docker image based on official Debian and PHP images, using Apache/mod_php for initial deployment.

- [x] T026 Research and document best practices for custom Moodle image (see research.md)
- [x] T027 Write Dockerfile using `php:8.2-apache` as base, install required PHP extensions, Moodle, and plugins/themes
- [x] T027a Ensure all required and recommended PHP extensions for Moodle are installed (intl, soap, gd, zip, curl, mbstring, opcache, xsl, exif, sodium, ldap)
- [x] T027b Install and enable the Redis PHP extension via pecl; configure Moodle for Redis sessions and MUC cache
- [x] T027c Add and document a cron container/service to run Moodle's admin/cli/cron.php every minute
- [x] T027d Set PHP and Apache config for large file uploads (upload_max_filesize=512M, post_max_size=512M, memory_limit=512M) in moodle/php.ini
- [x] T027e Validate multi-client hosting: one container per client, per-client config, DB, moodledata, and Redis key prefix (MOODLE_SESSION_REDIS_PREFIX per client)
- [x] T028 Pin Moodle and plugin/theme versions using build args (MOODLE_VERSION, MOOVE_BRANCH) in moodle/Dockerfile
- [x] T029 Update docker-compose files to use the custom image instead of Bitnami
- [ ] T030 Update quickstart.md and spec.md to document the new image build and deployment process
- [ ] T031 Test the custom image locally (docker compose build && up, verify Moodle install and theme)
- [ ] T032 Update GitHub Actions workflow to build/push the custom image and deploy it
- [ ] T033 Document upgrade and maintenance process for the custom image

---

## Phase 5: Administrator Updates Deployment via CI/CD (Priority: P3)

**Goal**: Admin can push changes to the repo and trigger zero-downtime rolling updates for affected containers only.

**Independent Test**: Push a config change, verify workflow completes, site remains available, and only changed containers restart.

- [x] T026 [US3] Implement deploy.yml logic to restart only changed containers (docker compose up -d --remove-orphans)
- [x] T027 [P] [US3] Implement concurrency control in deploy.yml to prevent overlapping deploys
- [x] T028 [US3] Document update and rollback process in quickstart.md

---

## Phase 6: Polish & Cross-Cutting Concerns

- [x] T029 [P] Implement pa11y-ci accessibility test job in .github/workflows/lint.yml
- [x] T030 [P] Implement Lighthouse CI performance baseline in .github/workflows/lint.yml
- [x] T031 [P] Document backup/restore and data persistence strategy in quickstart.md
- [x] T032 [P] Review and update all documentation for accuracy and completeness

---

## Dependencies

- Phase 1 (Setup) → Phase 2 (Foundational) → User Stories (Phases 3–5, in priority order)
- Each user story phase is independently testable after foundational tasks are complete
- Polish phase can proceed in parallel with user story phases after foundational tasks

## Parallel Execution Examples

- T003, T004, T005, T006, T007, T008 can be done in parallel (different files)
- T010, T011, T012, T013, T014 can be done in parallel
- T016, T017, T018 can be done in parallel after T015
- T022, T023 can be done in parallel after T021
- T027, T030, T031, T032 can be done in parallel after user stories

## Implementation Strategy

- Deliver MVP by completing all Phase 1, Phase 2, and Phase 3 (User Story 1) tasks
- Incrementally deliver User Story 2 and 3 phases
- Polish and cross-cutting tasks run in parallel after core functionality is live
