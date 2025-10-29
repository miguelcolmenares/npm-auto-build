FROM node:20-alpine

# Install git for committing changes
RUN apk add --no-cache git

WORKDIR /app

# Copy the action files
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]