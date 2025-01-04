FROM debian:bookworm-slim

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install required packages for .NET Core and the GitHub Actions runner
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    curl \
    git \
    libicu-dev \
    libc6-dev \
    libssl-dev \
    libkrb5-dev \
    tzdata \
    ca-certificates \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user for the runner
RUN addgroup -S github && adduser -S github -G github

# Grant sudo privileges to the github user if needed
RUN echo "github ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Set the working directory
WORKDIR /home/github/actions-runner

# Define build-time arguments
ARG GH_RUNNER_VERSION
ARG GH_RUNNER_HASH
ARG GH_RUNNER_ARCH

# Download the GitHub Actions runner package
ENV GH_RUNNER_URL=https://github.com/actions/runner/releases/download/v${GH_RUNNER_VERSION}/actions-runner-${GH_RUNNER_ARCH}-${GH_RUNNER_VERSION}.tar.gz

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

# Switch to the github user
USER github

# Entrypoint to configure and run the runner
ENTRYPOINT ["/home/github/actions-runner/entrypoint.sh"]
