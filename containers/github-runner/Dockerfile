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

# Create a non-root user for security
RUN groupadd -r github && useradd -r -g github github

# Grant sudo privileges to the github user
RUN echo "github ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Set working directory
WORKDIR /home/github/actions-runner

# Add the runner binary and entrypoint script (modify paths as needed)
COPY entrypoint.sh /home/github/actions-runner/entrypoint.sh
RUN chmod +x /home/github/actions-runner/entrypoint.sh

# Define environment variables for the runner
ENV RUNNER_NAME=raspberry-pi-runner
ENV RUNNER_LABELS=self-hosted,raspberry-pi,docker
ENV RUNNER_WORKDIR=_work

# Switch to the non-root user
USER github

# Set the entrypoint script
ENTRYPOINT ["/home/github/actions-runner/entrypoint.sh"]
