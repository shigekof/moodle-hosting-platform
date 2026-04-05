---
# Per-client Moodle service template
# Generated from this template by scripts/add-client.sh using envsubst.
# Variables replaced: CLIENT_NAME, CLIENT_DOMAIN

name: moodle-demo

services:
  moodle-${CLIENT_NAME}:
    image: moodle-custom:latest
    restart: unless-stopped
    env_file:
      - clients/${CLIENT_NAME}/.env
    volumes:
      - moodledata_${CLIENT_NAME_UNDER}_data:/var/moodledata
    networks:
      - moodle_network
    depends_on:
      mariadb:
        condition: service_healthy
      redis:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-sf", "http://localhost/login/index.php"]
      interval: 30s
      timeout: 10s
      retries: 10
      start_period: 300s
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.moodle-${CLIENT_NAME}.rule=Host(`${CLIENT_DOMAIN}`)"
      - "traefik.http.routers.moodle-${CLIENT_NAME}.entrypoints=websecure"
      - "traefik.http.routers.moodle-${CLIENT_NAME}.tls=true"
      - "traefik.http.routers.moodle-${CLIENT_NAME}.tls.certresolver=letsencrypt"
      - "traefik.http.routers.moodle-${CLIENT_NAME}.middlewares=secure-headers@file"
      - "traefik.http.services.moodle-${CLIENT_NAME}.loadbalancer.server.port=80"

  # Moodle cron — runs Moodle background tasks every minute (T027c)
  moodle-cron-${CLIENT_NAME}:
    image: moodle-custom:latest
    restart: unless-stopped
    env_file:
      - clients/${CLIENT_NAME}/.env
    volumes:
      - moodledata_${CLIENT_NAME_UNDER}_data:/var/moodledata
    networks:
      - moodle_network
    depends_on:
      moodle-${CLIENT_NAME}:
        condition: service_healthy
    entrypoint: ["/bin/bash", "-c"]
    command:
      - |
        set -euo pipefail
        /usr/local/bin/docker-entrypoint.sh true
        echo "[cron] Starting Moodle cron loop for ${CLIENT_NAME}..."
        while true; do
          php /var/www/html/admin/cli/cron.php
          sleep 60
        done

  seed-${CLIENT_NAME}:
    build:
      context: ./seed
      dockerfile: Dockerfile
    restart: "no"
    env_file:
      - clients/${CLIENT_NAME}/.env
    volumes:
      - moodledata_${CLIENT_NAME_UNDER}_data:/var/moodledata
    networks:
      - moodle_network
    depends_on:
      moodle-${CLIENT_NAME}:
        condition: service_healthy

volumes:
  moodledata_${CLIENT_NAME_UNDER}_data:

networks:
  moodle_network:
    external: true
