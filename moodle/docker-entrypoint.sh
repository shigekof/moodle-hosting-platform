#!/bin/bash
# docker-entrypoint.sh — Generates config.php, waits for DB, installs Moodle
# if not already installed, then starts Apache.
set -euo pipefail

# ── Environment variables with defaults ──────────────────────────────────────
DB_HOST="${MOODLE_DATABASE_HOST:-mariadb}"
DB_PORT="${MOODLE_DATABASE_PORT_NUMBER:-3306}"
DB_USER="${MOODLE_DATABASE_USER:-moodle}"
DB_PASS="${MOODLE_DATABASE_PASSWORD}"
DB_NAME="${MOODLE_DATABASE_NAME:-moodle}"

MOODLE_HOST="${MOODLE_HOST:-localhost}"
MOODLE_DATA_DIR="${MOODLE_DATA_DIR:-/var/moodledata}"

REDIS_HOST="${MOODLE_REDIS_HOST:-redis}"
REDIS_PORT="${MOODLE_REDIS_PORT:-6379}"
SESSION_PREFIX="${MOODLE_SESSION_REDIS_PREFIX:-moodle_session_}"

ADMIN_USER="${MOODLE_USERNAME:-admin}"
ADMIN_PASS="${MOODLE_PASSWORD}"
ADMIN_EMAIL="${MOODLE_EMAIL:-admin@example.com}"
SITE_NAME="${MOODLE_SITE_NAME:-Moodle}"

# Derive wwwroot: if MOODLE_WWWROOT is not set, default to http://$MOODLE_HOST
if [ -n "${MOODLE_WWWROOT:-}" ]; then
    WWWROOT="${MOODLE_WWWROOT}"
elif [[ "${MOODLE_HOST}" == http* ]]; then
    WWWROOT="${MOODLE_HOST}"
else
    WWWROOT="http://${MOODLE_HOST}"
fi

echo "[entrypoint] wwwroot: ${WWWROOT}"
echo "[entrypoint] moodledata: ${MOODLE_DATA_DIR}"

# ── Create moodledata directory ───────────────────────────────────────────────
mkdir -p "${MOODLE_DATA_DIR}"
chown -R www-data:www-data "${MOODLE_DATA_DIR}"
chmod 770 "${MOODLE_DATA_DIR}"

# ── Wait for MariaDB ──────────────────────────────────────────────────────────
echo "[entrypoint] Waiting for MariaDB at ${DB_HOST}:${DB_PORT}..."
until php -r "
    try {
        new PDO(
            'mysql:host=${DB_HOST};port=${DB_PORT};dbname=${DB_NAME}',
            '${DB_USER}',
            '${DB_PASS}'
        );
        exit(0);
    } catch (Exception \$e) {
        exit(1);
    }
" 2>/dev/null; do
    echo "[entrypoint]   ... not ready, retrying in 3s"
    sleep 3
done
echo "[entrypoint] MariaDB is ready."

# ── Generate config.php ───────────────────────────────────────────────────────
echo "[entrypoint] Generating config.php..."
cat > /var/www/html/config.php <<PHP
<?php
unset(\$CFG);
global \$CFG;
\$CFG = new stdClass();

\$CFG->dbtype    = 'mariadb';
\$CFG->dblibrary = 'native';
\$CFG->dbhost    = '${DB_HOST}';
\$CFG->dbname    = '${DB_NAME}';
\$CFG->dbuser    = '${DB_USER}';
\$CFG->dbpass    = '${DB_PASS}';
\$CFG->prefix    = 'mdl_';
\$CFG->dboptions = ['dbport' => ${DB_PORT}];

\$CFG->wwwroot  = '${WWWROOT}';
\$CFG->dataroot = '${MOODLE_DATA_DIR}';
\$CFG->admin    = 'admin';

\$CFG->directorypermissions = 02777;

// Redis session handler (T027b)
\$CFG->session_handler_class          = '\core\session\redis';
\$CFG->session_redis_host             = '${REDIS_HOST}';
\$CFG->session_redis_port             = ${REDIS_PORT};
\$CFG->session_redis_prefix           = '${SESSION_PREFIX}';
\$CFG->session_redis_acquire_lock_timeout = 120;
\$CFG->session_redis_lock_expire      = 7200;

require_once(__DIR__ . '/lib/setup.php');
PHP
chown www-data:www-data /var/www/html/config.php
chmod 640 /var/www/html/config.php

# ── Install Moodle DB if not already installed ────────────────────────────────
INSTALLED=$(php -r "
    try {
        \$pdo = new PDO(
            'mysql:host=${DB_HOST};port=${DB_PORT};dbname=${DB_NAME}',
            '${DB_USER}',
            '${DB_PASS}'
        );
        \$r = \$pdo->query(
            \"SELECT value FROM mdl_config WHERE name = 'siteidentifier'\"
        );
        echo (\$r && \$r->fetch()) ? 'yes' : 'no';
    } catch (Exception \$e) {
        echo 'no';
    }
" 2>/dev/null)

if [ "${INSTALLED}" = "yes" ]; then
    echo "[entrypoint] Moodle already installed — skipping installation."
else
    echo "[entrypoint] Running Moodle database installation..."
    su -s /bin/bash www-data -c "php /var/www/html/admin/cli/install_database.php \
        --agree-license \
        --fullname='${SITE_NAME}' \
        --shortname='moodle' \
        --summary='' \
        --adminuser='${ADMIN_USER}' \
        --adminpass='${ADMIN_PASS}' \
        --adminemail='${ADMIN_EMAIL}'"
    echo "[entrypoint] Moodle installation complete."
fi

# ── Hand off to Apache ────────────────────────────────────────────────────────
echo "[entrypoint] Starting Apache..."
exec "$@"
