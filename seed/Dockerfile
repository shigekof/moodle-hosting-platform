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

# Install moosh (Moodle Shell) via Composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer \
    && composer global require moodlehq/moosh @dev \
    && ln -s /root/.composer/vendor/bin/moosh /usr/local/bin/moosh

COPY seed.sh /usr/local/bin/seed.sh
RUN chmod +x /usr/local/bin/seed.sh

CMD ["/usr/local/bin/seed.sh"]
