FROM alpine:3.23.2
LABEL authors="YourGameSpace"

RUN apk add --no-cache bash curl iproute2 jq arping busybox-suid

WORKDIR /app

COPY ipam-mac-scanner.sh /app/ipam-mac-scanner.sh
RUN chmod +x /app/ipam-mac-scanner.sh

COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

ENV RUN_AT_STARTUP=false
ENV API_APP_NAME="macscanner"
ENV USERNAME="macscanner"
ENV INTERFACE="eth0"
ENV IGNORED_TAGS="3,4"
ENV CRON_SCHEDULE="*/30 * * * *"

ENTRYPOINT ["/app/entrypoint.sh"]