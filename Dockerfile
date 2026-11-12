FROM node:25-alpine

# Install git, bash and github cli for committing changes and PR creation
RUN apk add --no-cache git bash github-cli

WORKDIR /app

# Copy the action files
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]