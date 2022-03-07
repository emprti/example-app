FROM tangramor/nginx-php8-fpm

# copy source code
COPY . /var/www/html

# If there is a conf folder under /var/www/html, the start.sh will
# copy conf/nginx.conf to /etc/nginx/nginx.conf
# copy conf/nginx-site.conf to /etc/nginx/conf.d/default.conf
# copy conf/nginx-site-ssl.conf to /etc/nginx/conf.d/default-ssl.conf

# copy ssl cert files
# COPY conf/ssl /etc/nginx/ssl

# start.sh will set desired timezone with $TZ
# ENV TZ Asia/Shanghai

# China php composer mirror: https://mirrors.cloud.tencent.com/composer/
# ENV COMPOSERMIRROR="https://mirrors.cloud.tencent.com/composer/"
# China npm mirror: https://registry.npm.taobao.org
# ENV NPMMIRROR="https://registry.npm.taobao.org"

# start.sh will replace default web root from /var/www/html to $WEBROOT
ENV WEBROOT /var/www/html/public

# start.sh will use redis as session store with docker container name $PHP_REDIS_SESSION_HOST
# ENV PHP_REDIS_SESSION_HOST redis

# start.sh will create laravel storage folder structure if $CREATE_LARAVEL_STORAGE = 1
# ENV CREATE_LARAVEL_STORAGE "1"

# download required node/php packages, 
# some node modules need gcc/g++ to build
RUN apk add --no-cache --virtual .build-deps gcc g++ libc-dev make \
    && cd /var/www/html \
    # install node modules
    # && npm install \
    # install php composer packages
    && composer install --no-ansi --no-dev --no-interaction --no-progress --no-scripts --optimize-autoloader \
    # clean
    && apk del .build-deps \
    # build js/css
    # && npm run dev \
    # set .env
    # && cp .env.test .env \
    # change /var/www/html user/group
    && chown -Rf nginx.nginx /var/www/html