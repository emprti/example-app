FROM node:17-alpine3.15 AS nodejs

FROM php:8.1.3-fpm-alpine3.15

USER root

WORKDIR /var/www/html

COPY conf/supervisord.conf /etc/supervisord.conf
COPY conf/nginx.conf /etc/nginx/nginx.conf
COPY conf/default.conf /etc/nginx/conf.d/default.conf
COPY start.sh /start.sh

ENV PHP_MODULE_DEPS zlib-dev libpng-dev libxml2-dev libzip-dev postgresql-dev

RUN set -xe \
    && apk update \
    && apk add --no-cache nginx nodejs npm php8-cli php8-dev libstdc++ bash \
        supervisor zip unzip coreutils libpng  \
        libzip postgresql-client postgresql-libs libcap tzdata \
    && apk add --no-cache --update --virtual .phpize-deps $PHPIZE_DEPS \
    && apk add --no-cache --update --virtual .all-deps $PHP_MODULE_DEPS \
    # needed? intl soap mysqli pdo(included) pdo_mysql ldap imap iconv dom(included)
    && docker-php-ext-install sockets gd bcmath pgsql pdo_pgsql zip opcache \
    && pecl install -o -f redis \
    && rm -rf /tmp/pear \
    && docker-php-ext-enable redis \
    && docker-php-ext-enable sockets \
    # needed?
    && pecl install msgpack && docker-php-ext-enable msgpack \
    # needed?
    && pecl install igbinary && docker-php-ext-enable igbinary \
    && apk del .all-deps .phpize-deps \
    && rm -rf /var/cache/apk/* /tmp/* /var/tmp/* \
    && rm -f /etc/nginx/conf.d/default.conf.apk-new && rm -f /etc/nginx/nginx.conf.apk-new \
    && setcap 'cap_net_bind_service=+ep' /usr/local/bin/php \
    && mkdir -p /var/log/supervisor \
    && chmod +x /start.sh \
    #&& addgroup -g 101 -S nginx \
    #&& adduser -S -D -H -u 101 -h /var/cache/nginx -s /sbin/nologin -G nginx -g nginx nginx \
    # forward request and error logs to docker log collector
    && ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log

ENV fpm_conf /usr/local/etc/php-fpm.d/www.conf
ENV php_vars /usr/local/etc/php/conf.d/docker-vars.ini

RUN echo "cgi.fix_pathinfo=0" > ${php_vars} &&\
    echo "upload_max_filesize = 100M"  >> ${php_vars} &&\
    echo "post_max_size = 100M"  >> ${php_vars} &&\
    echo "variables_order = \"EGPCS\""  >> ${php_vars} && \
    echo "memory_limit = 128M"  >> ${php_vars} && \
    sed -i \
        -e "s/;catch_workers_output\s*=\s*yes/catch_workers_output = yes/g" \
        -e "s/pm.max_children = 5/pm.max_children = 64/g" \
        -e "s/pm.start_servers = 2/pm.start_servers = 8/g" \
        -e "s/pm.min_spare_servers = 1/pm.min_spare_servers = 8/g" \
        -e "s/pm.max_spare_servers = 3/pm.max_spare_servers = 32/g" \
        -e "s/;pm.max_requests = 500/pm.max_requests = 800/g" \
        -e "s/user = www-data/user = nginx/g" \
        -e "s/group = www-data/group = nginx/g" \
        -e "s/;listen.mode = 0660/listen.mode = 0666/g" \
        -e "s/;listen.owner = www-data/listen.owner = nginx/g" \
        -e "s/;listen.group = www-data/listen.group = nginx/g" \
        -e "s/listen = 127.0.0.1:9000/listen = \/var\/run\/php-fpm.sock/g" \
        -e "s/^;clear_env = no$/clear_env = no/" \
        ${fpm_conf} \
    && cp /usr/local/etc/php/php.ini-production /usr/local/etc/php/php.ini \
    && sed -i 's/session.save_handler = files/session.save_handler = redis\nsession.save_path = "tcp:\/\/redis:6379"/g' /usr/local/etc/php/php.ini

COPY . /var/www/html

COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

RUN composer install --no-ansi --no-interaction --no-progress --no-scripts --optimize-autoloader \
    && npm install \
    && chown -Rf nginx:nginx /var/www/html

USER nginx

RUN npm run prod \
    && cp .env.example .env \
    && php artisan key:generate \
    && php artisan config:cache \
    && php artisan route:cache \
    && php artisan view:cache \
    && chown -Rf nginx:nginx /var/www/html

EXPOSE 443 80

USER root

CMD ["/start.sh"]
