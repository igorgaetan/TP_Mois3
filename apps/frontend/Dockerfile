FROM nginx:1.27-alpine

COPY public /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

RUN mkdir -p /var/cache/nginx /var/run /var/log/nginx \
 && chown -R 101:101 /var/cache/nginx /var/run /var/log/nginx

USER 101

EXPOSE 8080