FROM python:3.11-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
RUN pip install --no-cache-dir \
    flask \
    flask-cors \
    requests

# Create app directory
WORKDIR /app

# Copy application files
COPY app.py /app/
COPY mock_data.py /app/
COPY routes/ /app/routes/

# Create data directory
RUN mkdir -p /data

# Expose port
EXPOSE 8006

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8006/api2/json/version || exit 1

# Run application
CMD ["python", "app.py"]
