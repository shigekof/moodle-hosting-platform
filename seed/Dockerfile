FROM php:8.2-cli

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    unzip \
    libzip-dev \
    libonig-dev \
    && docker-php-ext-install zip mbstring \
    && rm -rf /var/lib/apt/lists/*

# Install moosh (Moodle Shell) directly from GitHub source
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer \
    && git clone --depth 1 https://github.com/tmuras/moosh.git /opt/moosh \
    && cd /opt/moosh && composer install --no-dev --no-interaction \
    && ln -s /opt/moosh/moosh.php /usr/local/bin/moosh

COPY seed.sh /usr/local/bin/seed.sh
RUN chmod +x /usr/local/bin/seed.sh

CMD ["/usr/local/bin/seed.sh"]
