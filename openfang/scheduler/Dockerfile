FROM alpine:3.20

# Install required packages:
# - curl: API calls to OpenFang and Discord webhooks
# - jq: JSON parsing for workflow registration
# - tzdata: Timezone support for scheduling
# - dcron: Cron daemon (Alpine's crond)
RUN apk add --no-cache curl jq tzdata

# Create log directory
RUN mkdir -p /var/log && touch /var/log/scheduler.log

# Note: Scripts are mounted at runtime via docker volume
# ./scheduler:/scheduler:ro - the entrypoint and run-workflow.sh
# ./workflows:/workflows:ro - the workflow JSON files

# The entrypoint.sh must be executable (chmod +x)
# This is handled by the volume mount from host

ENTRYPOINT ["sh", "/scheduler/entrypoint.sh"]
