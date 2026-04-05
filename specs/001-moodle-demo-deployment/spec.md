# Feature Specification: Moodle Demo Site Deployment

**Feature Branch**: `001-moodle-demo-deployment`  
**Created**: 2026-04-03  
**Status**: Draft  
**Input**: User description: "Build a demo moodle site with basic features. I want to use Digital Ocean for the server, Docker Compose, Traefik, Bitnami Moodle, MariaDB, and Redis to deploy this demo moodle application. I want to add .github/workflow to automate the deployment as well. App needs to have nice theme for UI to make this as a good showcase."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - First-Time Deployment by Site Administrator (Priority: P1)

A site administrator clones this repository onto their local machine, configures environment variables (domain name, admin credentials, DigitalOcean API token), pushes to the main branch, and the GitHub Actions workflow automatically provisions the server, sets up TLS, and brings up a fully functional Moodle site accessible at the configured domain — all without manual server intervention.

**Why this priority**: This is the entire purpose of the repository. Without a working automated deployment, nothing else can be demonstrated or tested. It is the foundation all other stories depend on.

**Independent Test**: Run the GitHub Actions deployment workflow against a fresh DigitalOcean Droplet. Verify the Moodle login page is reachable over HTTPS at the configured domain within 10 minutes of triggering the workflow, with a valid TLS certificate.

**Acceptance Scenarios**:

1. **Given** a repository with all required secrets configured (DO_API_TOKEN, DOMAIN, ADMIN_PASSWORD, etc.), **When** a commit is pushed to the `main` branch, **Then** the GitHub Actions workflow succeeds and Moodle is accessible over HTTPS at the configured domain with no browser TLS warnings.
2. **Given** a running deployment, **When** the administrator visits the Moodle admin dashboard, **Then** they can log in with the credentials supplied during deployment and see a fully operational Moodle instance.
3. **Given** the deployment workflow completes, **When** checked from an external network, **Then** HTTP requests are automatically redirected to HTTPS.
4. **Given** a failed deployment run, **When** the administrator reviews the GitHub Actions log, **Then** the failure point is clearly identified with a descriptive error message.

---

### User Story 2 - Showcase Visitor Browses the Moodle Site (Priority: P2)

A visitor (potential client, stakeholder, or student) opens the Moodle site in a web browser and is greeted by a polished, professional-looking site with a custom theme, sample course content, and demo enrolment data — demonstrating Moodle's capabilities as a learning management platform.

**Why this priority**: The primary goal of the demo site is to showcase Moodle. Visual quality and pre-loaded demo content directly determine whether this goal is achieved. Without an attractive theme and sample data, it is just a blank LMS.

**Independent Test**: Deploy the site to a test environment and verify the homepage presents the custom theme, at least one sample course is visible and browsable, and the page renders correctly on both desktop and mobile viewports.

**Acceptance Scenarios**:

1. **Given** a first-time visitor lands on the Moodle homepage, **When** the page loads, **Then** they see a visually polished theme (consistent branding, custom colours/logo, non-default appearance) rather than the Moodle default theme.
2. **Given** a visitor browsing the site without logging in, **When** they view the course catalogue, **Then** at least 2 sample courses with descriptions and cover images are visible.
3. **Given** a logged-in demo learner account, **When** they navigate a sample course, **Then** they can view course sections, activities, and resources without errors.
4. **Given** the site on a mobile device (viewport width ≤ 768 px), **When** the homepage loads, **Then** all navigation and content are fully usable without horizontal scrolling.

---

### User Story 3 - Administrator Updates Deployment via CI/CD (Priority: P3)

An administrator pushes a change to the repository (e.g., updated theme configuration, new environment variable, Docker Compose version bump) and the GitHub Actions workflow re-deploys only the affected containers with zero downtime for end users — bringing the site to the new desired state without requiring a full teardown.

**Why this priority**: Ongoing maintainability and iterative improvement of the demo site are important but secondary to the initial deployment. This story adds significant durability to the project.

**Independent Test**: Push a non-breaking change to the compose configuration on a live deployment. Verify the workflow completes, the change is reflected, and the site remained reachable throughout the update (no 5xx errors during the re-deploy window).

**Acceptance Scenarios**:

1. **Given** a live Moodle deployment, **When** a change to the `main` branch is pushed, **Then** the workflow re-deploys the updated service(s) without restarting unaffected containers.
2. **Given** a re-deploy in progress, **When** an external client requests the Moodle site, **Then** requests are served without a 502/503 error (Traefik continues routing to the healthy container).
3. **Given** a deployment workflow that fails mid-run due to a configuration error, **When** the administrator corrects the error and re-runs the workflow, **Then** the site returns to a fully operational state.

---

### Edge Cases

- What happens when the DigitalOcean API token is missing or invalid — workflow must fail fast with a clear error before any resources are provisioned.
- What happens when the configured domain has no DNS record pointing to the server — TLS certificate issuance fails; the system must surface this as an actionable error rather than a silent hang.
- What happens if MariaDB or Redis fails to start during deployment — Moodle container must not silently start in a degraded state; the health-check must fail and the workflow must report the error.
- What happens when disk space on the Droplet is exhausted — data persistence must not corrupt existing course data; the site should degrade gracefully and log a clear capacity warning.
- What happens when deployment is triggered concurrently (two pushes in quick succession) — only the latest run should apply; the earlier run must not leave the environment in a partial state.

## Requirements *(mandatory)*

### Functional Requirements

**Deployment & Infrastructure**

- **FR-001**: The system MUST deploy all services (Moodle application, database, cache, and reverse proxy) using a single automated pipeline triggered by a push to the `main` branch.
- **FR-002**: The system MUST provision TLS certificates automatically for the configured domain and serve the application exclusively over HTTPS; HTTP MUST redirect to HTTPS.
- **FR-003**: The system MUST source all sensitive configuration (admin credentials, API tokens, database passwords, domain name) from repository secrets and environment variables — no secrets MUST be hard-coded in any committed file.
- **FR-004**: The deployment pipeline MUST perform a health check after deploying and report success only when the Moodle application is responding to HTTP requests.
- **FR-005**: The infrastructure MUST support multiple isolated Moodle client instances, each running as a separate named container from the same `bitnami/moodle:4.3` image; each client instance MUST be fully independent (separate database, separate volumes, separate admin credentials, separate public domain).
- **FR-006**: The system MUST persist course data, user data, and uploaded files for every client across container restarts and redeployments — data MUST NOT be lost on a normal redeploy for any client.
- **FR-007**: Re-deployment MUST update only services whose configuration has changed, preserving uptime for all running client containers that are unaffected by the change.
- **FR-015**: The system MUST provide a client provisioning script (`scripts/add-client.sh`) that provisions a new client instance (creates database, generates Compose service configuration from template, starts the container, runs the seed) via a single command with the client name and domain as inputs.
- **FR-016**: Each client MUST be routed via its own registered domain, with Traefik issuing and managing a separate Let’s Encrypt TLS certificate per client domain automatically.

**Moodle Application**

- **FR-008**: The Moodle instance MUST be pre-configured with an administrator account whose credentials are supplied via secrets at deployment time.
- **FR-009**: The Moodle site MUST have a custom theme applied that replaces the default appearance with a polished, professional look.
- **FR-010**: The deployment MUST seed the site with at least 2 sample courses, each containing at least one section and one activity, to enable immediate showcase capability.
- **FR-011**: User self-registration MUST be enabled so showcase visitors can create accounts and enrol in demo courses without administrator intervention.
- **FR-012**: The system MUST use the session/cache store to accelerate page loads and reduce database load; Moodle caching MUST be configured to use the dedicated cache service.

**Operations & Observability**

- **FR-013**: All services MUST write structured logs accessible via standard container log commands, enabling the administrator to diagnose issues without SSH-ing into individual processes.
- **FR-014**: The reverse proxy MUST expose an HTTPS endpoint only; no application ports MUST be publicly accessible directly on the host.

### Key Entities

- **Moodle Application (per client)**: One container running the `bitnami/moodle:4.3` image for a specific client. Each client container is fully isolated: separate database, separate named volumes, separate domain, and separate admin credentials. All client containers are provisioned from the same image.
- **Client**: A named tenant of the deployment. Identified by a short slug (e.g., `acme-corp`) and a registered domain (e.g., `acme-corp.com`). Each client has exactly one Moodle container, one database, and two private named volumes.
- **Relational Database (MariaDB)**: Stores all structured Moodle data — users, courses, enrolments, activity completions, settings. Must persist across restarts.
- **Session & Cache Store (Redis)**: Stores Moodle session data and application-level caches. Improves response times and reduces database load. Data loss on restart is acceptable (cache is warm/cold, not authoritative).
- **Reverse Proxy (Traefik)**: Routes all inbound HTTPS traffic, handles TLS termination and certificate issuance, enforces HTTP→HTTPS redirect. Acts as the single public ingress point.
- **Deployment Pipeline (GitHub Actions Workflow)**: Orchestrates the full lifecycle — configures secrets as environment variables, connects to the server, pulls latest images, and applies the compose configuration.
- **Demo Course**: Pre-loaded course content used to showcase Moodle features. Includes metadata (title, description, cover image), at least one section, and at least one activity type (e.g., quiz or resource).
- **Demo User Account**: Pre-created learner account used to demonstrate the student view during showcase walkthroughs.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A site administrator can go from a fresh repository with secrets configured to a publicly accessible, HTTPS-secured Moodle site in under 15 minutes, using only the automated workflow — no manual server commands required.
- **SC-002**: The Moodle homepage loads within 3 seconds (Time to Interactive) on a standard broadband connection for a returning visitor.
- **SC-003**: All running client sites remain available (no 5xx errors) during a re-deployment triggered by a push to `main`. Provisioning or removing one client MUST NOT cause downtime for other clients.
- **SC-004**: All pre-loaded demo course content and user accounts survive a full container restart cycle with zero data loss.
- **SC-005**: A first-time visitor with no Moodle experience can self-register, find a sample course, and complete a course activity within 5 minutes without requiring instructions.
- **SC-006**: The site's visual appearance is consistently themed across all pages — homepage, course catalogue, course view, and user profile — with no pages falling back to default Moodle styling.
- **SC-007**: The deployment workflow produces a clear pass/fail result visible in the GitHub Actions UI; a failed deployment always surfaces an actionable error message in the workflow log.

## Assumptions

- The target audience for the showcase is non-technical stakeholders and potential clients; the site must look polished "out of the box" with no manual theming steps after deployment.
- A single DigitalOcean Droplet is the intended hosting environment; multi-node clustering is out of scope. Multi-client capacity is achieved by running one container per client on the same Droplet. Each additional client requires approximately 1 GB RAM and 0.5 vCPU headroom on the Droplet.
- A domain name is available and DNS can be pointed to the Droplet's IP address by the administrator before triggering the first deployment.
- The repository is hosted on GitHub; the CI/CD pipeline uses GitHub Actions.
- The deployment target is a clean Ubuntu-based Droplet; Docker and Docker Compose will be installed by the pipeline if not already present.
- Demo content (sample courses, activities, user accounts) will be seeded during the deployment process; manual content creation after deployment is not required for the showcase.
- Email delivery (e.g., password reset, enrolment notifications) is a nice-to-have and will be disabled or configured with a placeholder SMTP service; it is not a blocking requirement for the showcase.
- The Bitnami Moodle image is used as the application container for all clients; all containers are provisioned from the same `bitnami/moodle:4.3` image. Each client’s container is isolated via separate named volumes and a separate MariaDB database.
- Mobile responsiveness is required for the showcase (visitors may use tablets/phones) but a native mobile app is out of scope.
- A compatible open-source Moodle theme (e.g., Boost-based or a well-maintained community theme) will be selected to satisfy the visual quality requirement; custom theme development from scratch is out of scope.
- Each client’s domain must have a DNS A record pointing to the Droplet’s IP before the client container is started; Traefik requires port 80 reachability for Let’s Encrypt HTTP-01 certificate issuance per domain.
- Client provisioning is a sequential operation — each new client’s Bitnami first-run initialisation must complete before the next client is provisioned; concurrent new-client provisioning is not supported.

# Phase 0 Update: Custom Image Specification (2026-04-04)

- The deployment will use a custom-built Moodle image based on official Debian and PHP images (php:8.2-apache), not Bitnami or legacy images.
- Apache/mod_php will be used for initial deployment for simplicity and maintainability.
- All required PHP extensions, Moodle version, and plugins/themes will be installed at build time.
- Environment variables will be used for configuration (DB, Redis, SMTP, etc.).
- This approach allows for future migration to Nginx/PHP-FPM if needed.
