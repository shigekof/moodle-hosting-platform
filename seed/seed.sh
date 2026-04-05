#!/usr/bin/env bash
# seed.sh — Demo content and configuration seeding for one Moodle client.
# Runs as a one-shot container after the Moodle service is healthy.
# Reads CLIENT_NAME and CLIENT_DOMAIN from environment.
set -euo pipefail

: "${CLIENT_NAME:?CLIENT_NAME is required}"
: "${CLIENT_DOMAIN:?CLIENT_DOMAIN is required}"

MOODLE_DIR="/var/www/html"
MOOSH="moosh -n -p ${MOODLE_DIR}"

log() { echo "[seed] $*"; }

log "Starting seed for client: ${CLIENT_NAME} (${CLIENT_DOMAIN})"

# ---------------------------------------------------------------------------
# 1. Verify moosh can connect to Moodle
# ---------------------------------------------------------------------------
log "Verifying moosh connection..."
$MOOSH info >/dev/null

# ---------------------------------------------------------------------------
# 2. Activate Moove theme
# ---------------------------------------------------------------------------
log "Activating Moove theme..."
if $MOOSH config-get theme 2>/dev/null | grep -q "moove"; then
    log "Moove theme already active — skipping."
else
    $MOOSH config-set theme moove
    log "Moove theme activated."
fi

# ---------------------------------------------------------------------------
# 3. Configure Redis MUC application cache store
# ---------------------------------------------------------------------------
log "Configuring Redis MUC cache store..."
STORE_NAME="redis_${CLIENT_NAME//-/_}"
if ! $MOOSH cache-list-stores 2>/dev/null | grep -q "${STORE_NAME}"; then
    $MOOSH cache-add-redis-store --host=redis --port=6379 "${STORE_NAME}"
    $MOOSH cache-map-mode --store="${STORE_NAME}" --mode=application
    log "Redis MUC store '${STORE_NAME}' configured."
else
    log "Redis MUC store already configured — skipping."
fi

# ---------------------------------------------------------------------------
# 4. Self-registration: enable for showcase visitors
# ---------------------------------------------------------------------------
log "Enabling self-registration..."
$MOOSH config-set registerauth email

# ---------------------------------------------------------------------------
# 5. Set front page to show course list
# ---------------------------------------------------------------------------
log "Configuring front page..."
$MOOSH config-set frontpageloggedin courselist
$MOOSH config-set frontpage courselist

# ---------------------------------------------------------------------------
# 6. Create demo user accounts
# ---------------------------------------------------------------------------
log "Creating demo user accounts..."

create_user_if_missing() {
    local username="$1" password="$2" email="$3" firstname="$4" lastname="$5"
    if $MOOSH user-list --pattern="${username}" 2>/dev/null | grep -q "${username}"; then
        log "User '${username}' already exists — skipping."
    else
        $MOOSH user-create \
            --password="${password}" \
            --email="${email}" \
            --firstname="${firstname}" \
            --lastname="${lastname}" \
            "${username}"
        log "User '${username}' created."
    fi
}

create_user_if_missing "learner1" "Demo@Learner1!" \
    "learner1@${CLIENT_DOMAIN}" "Alex" "Demo"
create_user_if_missing "learner2" "Demo@Learner2!" \
    "learner2@${CLIENT_DOMAIN}" "Jordan" "Demo"

# ---------------------------------------------------------------------------
# 7. Create course category
# ---------------------------------------------------------------------------
log "Creating 'Demo Courses' category..."
CATEGORY_ID=""
if $MOOSH category-list 2>/dev/null | grep -q "Demo Courses"; then
    log "Category 'Demo Courses' already exists — skipping."
    CATEGORY_ID=$($MOOSH category-list 2>/dev/null | grep "Demo Courses" | awk '{print $1}')
else
    CATEGORY_ID=$($MOOSH course-create-categories --json \
        '[{"name":"Demo Courses","parent":0}]' 2>/dev/null \
        | grep -oP '"id":\K[0-9]+' | head -1 || true)
    # Fallback: use category id 1 (Miscellaneous) if creation fails
    CATEGORY_ID="${CATEGORY_ID:-1}"
    log "Category created (id: ${CATEGORY_ID})."
fi
CATEGORY_ID="${CATEGORY_ID:-1}"

# ---------------------------------------------------------------------------
# 8. Create demo courses
# ---------------------------------------------------------------------------
log "Creating demo courses..."

create_course_if_missing() {
    local shortname="$1" fullname="$2"
    if $MOOSH course-list 2>/dev/null | grep -q "${shortname}"; then
        log "Course '${shortname}' already exists — skipping."
        $MOOSH course-list 2>/dev/null | grep "${shortname}" | awk '{print $1}'
    else
        local id
        id=$($MOOSH course-create \
            --fullname="${fullname}" \
            --shortname="${shortname}" \
            --category="${CATEGORY_ID}" \
            --format=topics \
            2>/dev/null | grep -oP 'id=\K[0-9]+' | head -1 || echo "")
        log "Course '${shortname}' created (id: ${id})."
        echo "${id}"
    fi
}

COURSE1_ID=$(create_course_if_missing \
    "INTRO-ONLINE-${CLIENT_NAME}" \
    "Introduction to Online Learning")

COURSE2_ID=$(create_course_if_missing \
    "DIGITAL-COLLAB-${CLIENT_NAME}" \
    "Digital Collaboration Tools")

# ---------------------------------------------------------------------------
# 9. Enrol demo users in both courses
# ---------------------------------------------------------------------------
log "Enrolling demo users in courses..."

enrol_if_needed() {
    local username="$1" shortname="$2"
    $MOOSH course-enrol -e manual "${username}" "${shortname}" 2>/dev/null || true
    log "Enrolled '${username}' in '${shortname}'."
}

COURSE1_SHORT="INTRO-ONLINE-${CLIENT_NAME}"
COURSE2_SHORT="DIGITAL-COLLAB-${CLIENT_NAME}"

enrol_if_needed "learner1" "${COURSE1_SHORT}"
enrol_if_needed "learner1" "${COURSE2_SHORT}"
enrol_if_needed "learner2" "${COURSE1_SHORT}"
enrol_if_needed "learner2" "${COURSE2_SHORT}"

# ---------------------------------------------------------------------------
# 10. Purge caches to ensure everything loads fresh
# ---------------------------------------------------------------------------
log "Purging Moodle caches..."
php "${MOODLE_DIR}/admin/cli/purge_caches.php"

log "Seed complete for client: ${CLIENT_NAME}"
