FROM alpine:3.20

# Install curl (for API calls + Discord webhook), jq (JSON parsing), and tzdata
RUN apk add --no-cache curl jq tzdata

# Scripts are mounted at runtime via docker volume (./scheduler:/scheduler:ro)
# This keeps the image generic and the scripts editable without rebuilds.

ENTRYPOINT ["/scheduler/entrypoint.sh"]
