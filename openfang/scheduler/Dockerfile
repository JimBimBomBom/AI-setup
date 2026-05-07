FROM alpine:3.20

# Install required packages:
# - curl: API calls to OpenFang and Discord webhooks
# - jq: JSON parsing for workflow registration
# - tzdata: Timezone support for scheduling
# - dcron: Cron daemon (Alpine's crond)
RUN apk add --no-cache curl jq tzdata

# Create necessary directories and files
RUN mkdir -p /var/spool/cron/crontabs && \
    mkdir -p /var/log && \
    touch /var/log/scheduler.log && \
    chmod 644 /var/log/scheduler.log

# Create the root crontab file
# This ensures crond has a file to work with immediately
RUN touch /var/spool/cron/crontabs/root && \
    chmod 600 /var/spool/cron/crontabs/root

# Note: Scripts are mounted at runtime via docker volume
# ./scheduler:/scheduler:ro - the entrypoint and run-workflow.sh
# ./workflows:/workflows:ro - the workflow JSON files

# The entrypoint.sh handles:
# 1. Waiting for OpenFang API
# 2. Registering workflows
# 3. Creating cron schedule
# 4. Starting crond

ENTRYPOINT ["sh", "/scheduler/entrypoint.sh"]
