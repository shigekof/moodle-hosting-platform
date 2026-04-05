FROM php:8.2-apache

# ── Build-time version pins ─────────────────────────────────────────────────
# Override via --build-arg at build time to pin to a specific release.
ARG MOODLE_VERSION=MOODLE_500_STABLE
ARG MOOVE_BRANCH=MOODLE_500_STABLE

# ── System dependencies for PHP extensions ──────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    unzip \
    libpng-dev \
    libjpeg-dev \
    libfreetype6-dev \
    libzip-dev \
    libicu-dev \
    libxml2-dev \
    libxslt1-dev \
    libldap2-dev \
    libonig-dev \
    libsodium-dev \
    default-mysql-client \
    && rm -rf /var/lib/apt/lists/*

# ── PHP extensions (all required + recommended for Moodle) ──────────────────
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j"$(nproc)" \
        gd \
        intl \
        mysqli \
        pdo_mysql \
        zip \
        mbstring \
        opcache \
        soap \
        xsl \
        exif \
        sodium \
        ldap \
    && pecl install redis \
    && docker-php-ext-enable redis \
    && rm -rf /tmp/pear

# ── Apache modules required by Moodle ───────────────────────────────────────
RUN a2enmod rewrite headers expires deflate

# ── PHP config: large uploads, opcache, memory limit ────────────────────────
COPY php.ini /usr/local/etc/php/conf.d/99-moodle.ini

# ── Apache virtual host config ───────────────────────────────────────────────
COPY apache-moodle.conf /etc/apache2/sites-available/000-default.conf

# ── Clone Moodle source into web root ────────────────────────────────────────
RUN git clone --depth 1 --branch "${MOODLE_VERSION}" \
        https://github.com/moodle/moodle.git /var/www/html \
    && rm -rf /var/www/html/.git

# ── Install Moove theme ───────────────────────────────────────────────────────
RUN git clone --depth 1 --branch "${MOOVE_BRANCH}" \
        https://github.com/willianmano/moodle-theme_moove.git \
        /var/www/html/theme/moove \
    && rm -rf /var/www/html/theme/moove/.git

# ── Set file ownership ────────────────────────────────────────────────────────
RUN chown -R www-data:www-data /var/www/html

# ── Entrypoint: generates config.php, waits for DB, installs if needed ───────
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=10s --start-period=5m --retries=5 \
    CMD curl -sf http://localhost/login/index.php || exit 1

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["apache2-foreground"]
