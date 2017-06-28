#!/bin/bash

# Disable Strict Host checking for non interactive git clones

mkdir -p -m 0700 /root/.ssh
echo -e "Host *\n\tStrictHostKeyChecking no\n" >> /root/.ssh/config

if [ ! -z "$SSH_KEY" ]; then
 echo $SSH_KEY > /root/.ssh/id_rsa.base64
 base64 -d /root/.ssh/id_rsa.base64 > /root/.ssh/id_rsa
 chmod 600 /root/.ssh/id_rsa
fi

# Set custom webroot
if [ ! -z "$WEBROOT" ]; then
 sed -i "s#root /data/www;#root ${WEBROOT};#g" /etc/nginx/sites-available/default.conf
else
 webroot=/data/www
fi

# Display PHP error's or not
if [[ "$ERRORS" != "1" ]] ; then
 echo php_flag[display_errors] = off >> /usr/local/etc/php-fpm.conf
else
 echo php_flag[display_errors] = on >> /usr/local/etc/php-fpm.conf
fi

# Display Version Details or not
if [[ "$HIDE_NGINX_HEADERS" == "0" ]] ; then
 sed -i "s/server_tokens off;/server_tokens on;/g" /etc/nginx/nginx.conf
else
 sed -i "s/expose_php = On/expose_php = Off/g" /usr/local/etc/php-fpm.conf
fi

# Pass real-ip to logs when behind ELB, etc
if [[ "$REAL_IP_HEADER" == "1" ]] ; then
 sed -i "s/#real_ip_header X-Forwarded-For;/real_ip_header X-Forwarded-For;/" /etc/nginx/sites-available/default.conf
 sed -i "s/#set_real_ip_from/set_real_ip_from/" /etc/nginx/sites-available/default.conf
 if [ ! -z "$REAL_IP_FROM" ]; then
  sed -i "s#172.16.0.0/12#$REAL_IP_FROM#" /etc/nginx/sites-available/default.conf
 fi
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

if [ ! -z "$PUID" ]; then
  if [ -z "$PGID" ]; then
    PGID=${PUID}
  fi
  deluser nginx
  addgroup -g ${PGID} nginx
  adduser -D -S -h /var/cache/nginx -s /sbin/nologin -G nginx -u ${PUID} nginx
else
  # Always chown webroot for better mounting
  chown -Rf nginx.nginx /data/www
fi

mkdir -p /etc/default
env >> /etc/default/locale
cat /etc/default/locale | sed -n '/^\([a-zA-Z0-9_]*\)=\(.*\)$/p' | sed 's/^\([a-zA-Z0-9_]*\)=\(.*\)$/export \1="\2"/g' > /project_env.sh

chown nginx.nginx /project_env.sh
chmod +x /project_env.sh

rm -rf /var/spool/cron/crontabs && mkdir -m 0644 -p /var/spool/cron/crontabs
[ "$(ls -A /etc/cron.d)" ] && cp -f /etc/cron.d/* /var/spool/cron/crontabs/ || true
chmod -R 0644 /var/spool/cron/crontabs

# Start supervisord and services
exec /usr/bin/supervisord -n -c /etc/supervisord.conf