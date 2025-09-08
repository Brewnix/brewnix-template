FROM python:3.9-slim

# Install required packages
RUN apt-get update && apt-get install -y \
    curl \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Create app directory
WORKDIR /app

# Copy mock data
COPY mock-data/mock-proxmox-data.json /app/mock-data/

# Copy mock server script
COPY mock-server.py /app/

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/api2/json/version || exit 1

# Start mock server
CMD ["python", "mock-server.py"]
