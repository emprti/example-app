#!/bin/bash

# Set custom webroot
if [ ! -z "$WEBROOT" ]; then
 sed -i "s#root /var/www/html;#root ${WEBROOT};#g" /etc/nginx/conf.d/default.conf
else
 webroot=/var/www/html
fi

# Enable custom nginx config files if they exist
if [ -f /var/www/html/conf/nginx.conf ]; then
  cp /var/www/html/conf/nginx.conf /etc/nginx/nginx.conf
fi

if [ -f /var/www/html/conf/nginx-site.conf ]; then
  cp /var/www/html/conf/nginx-site.conf /etc/nginx/conf.d/default.conf
fi

if [ -f /var/www/html/conf/nginx-site-ssl.conf ]; then
  cp /var/www/html/conf/nginx-site-ssl.conf /etc/nginx/conf.d/default-ssl.conf
fi

# Don't display PHP errors
echo php_flag[display_errors] = off >> /usr/local/etc/php-fpm.d/www.conf

# Don't display Version Details
sed -i "s/server_tokens on;/server_tokens off;/g" /etc/nginx/nginx.conf
sed -i "s/expose_php = On/expose_php = Off/g" /usr/local/etc/php-fpm.conf


# Pass real-ip to logs when behind ELB, etc
sed -i "s/#real_ip_header X-Forwarded-For;/real_ip_header X-Forwarded-For;/" /etc/nginx/conf.d/default.conf
sed -i "s/#set_real_ip_from/set_real_ip_from/" /etc/nginx/conf.d/default.conf
sed -i "s#172.16.0.0/12#$REAL_IP_FROM#" /etc/nginx/conf.d/default.conf

# Do the same for SSL sites
if [ -f /etc/nginx/conf.d/default-ssl.conf ]; then
sed -i "s/#real_ip_header X-Forwarded-For;/real_ip_header X-Forwarded-For;/" /etc/nginx/conf.d/default-ssl.conf
sed -i "s/#set_real_ip_from/set_real_ip_from/" /etc/nginx/conf.d/default-ssl.conf
sed -i "s#172.16.0.0/12#$REAL_IP_FROM#" /etc/nginx/conf.d/default-ssl.conf
fi

# Set the desired timezone
if [ ! -z "" ]; then
  echo "date.timezone="$TZ > /usr/local/etc/php/conf.d/timezone.ini
  rm -f /etc/localtime && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone
fi

# Display errors in docker logs
if [ ! -z "$PHP_ERRORS_STDERR" ]; then
  echo "log_errors = On" >> /usr/local/etc/php/conf.d/docker-vars.ini
  echo "error_log = /dev/stderr" >> /usr/local/etc/php/conf.d/docker-vars.ini
fi

# Increase the memory_limit
if [ ! -z "$PHP_MEM_LIMIT" ]; then
 sed -i "s/memory_limit = 128M/memory_limit = ${PHP_MEM_LIMIT}M/g" /usr/local/etc/php/conf.d/docker-vars.ini
fi

# Increase the post_max_size
if [ ! -z "$PHP_POST_MAX_SIZE" ]; then
 sed -i "s/post_max_size = 100M/post_max_size = ${PHP_POST_MAX_SIZE}M/g" /usr/local/etc/php/conf.d/docker-vars.ini
fi

# Increase the upload_max_filesize
if [ ! -z "$PHP_UPLOAD_MAX_FILESIZE" ]; then
 sed -i "s/upload_max_filesize = 100M/upload_max_filesize= ${PHP_UPLOAD_MAX_FILESIZE}M/g" /usr/local/etc/php/conf.d/docker-vars.ini
fi

# Use redis as session storage
if [ ! -z "$PHP_REDIS_SESSION_HOST" ]; then
 sed -i 's/session.save_handler = files/session.save_handler = redis\nsession.save_path = "tcp:\/\/'${PHP_REDIS_SESSION_HOST}':6379"/g' /usr/local/etc/php/php.ini
fi

# Run custom scripts
if [[ "$RUN_SCRIPTS" == "1" ]] ; then
  if [ -d "/var/www/html/scripts/" ]; then
    # make scripts executable incase they aren't
    chmod -Rf 750 /var/www/html/scripts/*; sync;
    # run scripts in number order
    for i in `ls /var/www/html/scripts/`; do /var/www/html/scripts/$i ; done
  else
    echo "Can't find script directory"
  fi
fi

# Start supervisord and services
exec /usr/bin/supervisord -n -c /etc/supervisord.conf
