---
# Per-client Moodle service template
# Generated from this template by scripts/add-client.sh using envsubst.
# Variables replaced: CLIENT_NAME, CLIENT_DOMAIN

name: moodle-demo

services:
  moodle-${CLIENT_NAME}:
    image: bitnami/moodle:4.3
    restart: unless-stopped
    env_file:
      - clients/${CLIENT_NAME}/.env
    volumes:
      - moodle_${CLIENT_NAME_UNDER}_data:/bitnami/moodle
      - moodledata_${CLIENT_NAME_UNDER}_data:/bitnami/moodledata
    networks:
      - moodle_network
    depends_on:
      mariadb:
        condition: service_healthy
      redis:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-sf", "http://localhost:8080/login/index.php"]
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
      - "traefik.http.services.moodle-${CLIENT_NAME}.loadbalancer.server.port=8080"

  seed-${CLIENT_NAME}:
    build:
      context: ./seed
      dockerfile: Dockerfile
    restart: "no"
    env_file:
      - clients/${CLIENT_NAME}/.env
    volumes:
      - moodle_${CLIENT_NAME_UNDER}_data:/bitnami/moodle
      - moodledata_${CLIENT_NAME_UNDER}_data:/bitnami/moodledata
    networks:
      - moodle_network
    depends_on:
      moodle-${CLIENT_NAME}:
        condition: service_healthy

volumes:
  moodle_${CLIENT_NAME_UNDER}_data:
  moodledata_${CLIENT_NAME_UNDER}_data:

networks:
  moodle_network:
    external: true
