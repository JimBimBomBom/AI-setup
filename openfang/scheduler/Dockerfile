FROM alpine:3.20

# Install Python and required tools
RUN apk add --no-cache python3 py3-pip curl jq tzdata

# Create log directory
RUN mkdir -p /var/log

# Scripts are mounted at runtime:
# ./scheduler:/scheduler:ro
# ./workflows:/workflows:ro

ENTRYPOINT ["python3", "/scheduler/scheduler.py"]
