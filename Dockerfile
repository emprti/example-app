FROM php:apache

# Install system dependencies
RUN apt-get update -y && apt-get install -y openssl zip unzip git libpng-dev libonig-dev libxml2-dev

# Clear cache
RUN apt-get clean && rm -rf /var/lib/apt/lists/*

# Install PHP extensions
RUN docker-php-ext-install pdo mbstring exif pcntl bcmath gd opcache

# Get latest Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html

COPY . /var/www/html

# RUN cp .env.example .env && php artisan key:generate

COPY vhost.conf /etc/apache2/sites-available/000-default.conf

RUN composer install --no-scripts --no-interaction

RUN chown -R www-data:www-data /var/www/html

RUN a2enmod rewrite

