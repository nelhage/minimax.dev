FROM debian:stretch
ENV hugo_version=0.72.0

RUN apt-get update && apt-get -y install curl

RUN curl -Lo /hugo.tgz \
 "https://github.com/gohugoio/hugo/releases/download/v$hugo_version/hugo_extended_${hugo_version}_Linux-64bit.tar.gz" && \
 tar -C /usr/bin -xzf /hugo.tgz hugo && \
 rm /hugo.tgz

COPY . /build
WORKDIR /build
RUN /usr/bin/hugo --minify --cleanDestinationDir

FROM nginx
ADD nginx.conf /etc/nginx/nginx.conf
COPY --from=0 /build/public /opt/www/minimax.dev
