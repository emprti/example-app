FROM node:17-alpine3.15 AS nodejs

FROM php:8.1.3-fpm-alpine3.15

USER root

ENV WEBROOT /var/www/html/public

WORKDIR /var/www/html

COPY --from=nodejs /opt /opt
COPY --from=nodejs /usr/local /usr/local

COPY conf/supervisord.conf /etc/supervisord.conf
COPY conf/nginx.conf /etc/nginx/nginx.conf
COPY conf/default.conf /etc/nginx/conf.d/default.conf
COPY start.sh /start.sh

ENV PHP_MODULE_DEPS zlib-dev libmemcached-dev cyrus-sasl-dev libpng-dev libxml2-dev krb5-dev curl-dev icu-dev libzip-dev openldap-dev imap-dev postgresql-dev

ENV NGINX_VERSION 1.21.6
ENV NJS_VERSION   0.7.2
ENV PKG_RELEASE   1

RUN set -x \
    && apk update \
    && addgroup -g 101 -S nginx \
    && adduser -S -D -H -u 101 -h /var/cache/nginx -s /sbin/nologin -G nginx -g nginx nginx \
    && nginxPackages=" \
        nginx=${NGINX_VERSION}-r${PKG_RELEASE} \
        nginx-module-xslt=${NGINX_VERSION}-r${PKG_RELEASE} \
        nginx-module-geoip=${NGINX_VERSION}-r${PKG_RELEASE} \
        nginx-module-image-filter=${NGINX_VERSION}-r${PKG_RELEASE} \
        nginx-module-njs=${NGINX_VERSION}.${NJS_VERSION}-r${PKG_RELEASE} \
    " \
    && set -x \
    # && apk add -X "https://nginx.org/packages/mainline/alpine/v$(egrep -o '^[0-9]+\.[0-9]+' /etc/alpine-release)/main" --no-cache $nginxPackages \
    && apk add --no-cache nginx nginx-mod-http-xslt-filter nginx-mod-http-geoip nginx-mod-http-image-filter nginx-mod-http-js \
    # Bring in curl and ca-certificates to make registering on DNS SD easier
    && apk add --no-cache curl ca-certificates \
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

COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

RUN apk add --no-cache php8-cli php8-dev libstdc++ mysql-client bash bash-completion shadow \
        supervisor git zip unzip python2 coreutils libpng libmemcached-libs krb5-libs icu-libs \
        icu c-client libzip openldap-clients imap postgresql-client postgresql-libs libcap tzdata sqlite \
        lua-resty-core nginx-mod-http-lua \
    && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone \
    && set -xe \
    && apk add --no-cache --update --virtual .phpize-deps $PHPIZE_DEPS \
    && apk add --no-cache --update --virtual .all-deps $PHP_MODULE_DEPS \
    && docker-php-ext-install sockets gd bcmath intl soap mysqli pdo pdo_mysql pgsql pdo_pgsql zip ldap imap iconv dom opcache \
    && printf "\n\n\n\n" | pecl install -o -f redis \
    && rm -rf /tmp/pear \
    && docker-php-ext-enable redis \
    && docker-php-ext-enable sockets \
    && pecl install msgpack && docker-php-ext-enable msgpack \
    && pecl install igbinary && docker-php-ext-enable igbinary \
    && printf "\n\n\n\n\n\n\n\n\n\n" | pecl install memcached \
    && docker-php-ext-enable memcached \
    && apk del .all-deps .phpize-deps \
    && node --version \
    && npm --version \
    && yarn --version \
    # && cd /usr/local \
    # && npm config set registry https://registry.npm.taobao.org \
    # && if [ "$NPMMIRROR" != "" ]; then npm config set registry ${NPMMIRROR}; fi \
    && rm -rf /var/cache/apk/* /tmp/* /var/tmp/* \
    && rm -f /etc/nginx/conf.d/default.conf.apk-new && rm -f /etc/nginx/nginx.conf.apk-new \
    && set -ex \
    && setcap 'cap_net_bind_service=+ep' /usr/local/bin/php \
    && mkdir -p /var/log/supervisor \
    && chmod +x /start.sh

COPY . /var/www/html

RUN composer install --no-ansi --no-interaction --no-progress --no-scripts --optimize-autoloader \
    && npm install \
    # && npm run prod \
    && cp .env.example .env \
    && php artisan key:generate \
    && chown -Rf nginx:nginx /var/www/html

EXPOSE 443 80

CMD ["/start.sh"]