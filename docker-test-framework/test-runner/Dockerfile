FROM python:3.11-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    bash \
    git \
    docker.io \
    ansible \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
RUN pip install --no-cache-dir \
    pytest \
    pytest-html \
    pytest-xvfb \
    pyyaml \
    requests \
    jinja2 \
    paramiko \
    netaddr

# Create working directories
RUN mkdir -p /results /test-data

# Set working directory
WORKDIR /workspace

# Default command
CMD ["/bin/bash"]
