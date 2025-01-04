FROM alpine:3.21

# Install necessary packages
RUN apk update && apk add --no-cache \
    bash \
    curl \
    git \
    sudo \
    openjdk8-jre \
    tzdata \
    ca-certificates \
    libc6-compat \
    && rm -rf /var/cache/apk/*

# Create a non-root user for the runner
RUN addgroup -S github && adduser -S github -G github

# Grant sudo privileges to the github user if needed
RUN echo "github ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Switch to the github user
USER github

# Set the working directory
WORKDIR /home/github/actions-runner

# Download the GitHub Actions runner package
ENV GH_RUNNER_VERSION=${GH_RUNNER_VERSION}
ENV GH_RUNNER_HASH=${GH_RUNNER_HASH}
ENV GH_RUNNER_ARCH=${GH_RUNNER_ARCH}

ENV GH_RUNNER_URL=https://github.com/actions/runner/releases/download/v${GH_RUNNER_VERSION}/actions-runner-{$GH_RUNNER_ARCH}-${GH_RUNNER_VERSION}.tar.gz

RUN curl -o actions-runner.tar.gz -L ${GH_RUNNER_URL} \
    && echo "${GH_RUNNER_HASH}  actions-runner.tar.gz" | sha256sum -c - \
    && tar xzf actions-runner.tar.gz \
    && rm actions-runner.tar.gz

# Copy the entrypoint script into the container
COPY entrypoint.sh /home/github/actions-runner/entrypoint.sh
RUN chmod +x /home/github/actions-runner/entrypoint.sh

# Define environment variables for runner configuration
ENV RUNNER_NAME=raspberry-pi-runner
ENV RUNNER_LABELS=self-hosted,raspberry-pi,docker
ENV RUNNER_WORKDIR=_work

# Mount volumes for runner data and logs (handled in docker-compose.yml)
VOLUME ["/home/github/actions-runner"]

# Entrypoint to configure and run the runner
ENTRYPOINT ["/home/github/actions-runner/entrypoint.sh"]
