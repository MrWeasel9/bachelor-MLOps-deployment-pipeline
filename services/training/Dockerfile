# Use the official Python 3.10 slim image as a base
FROM python:3.10-slim

# Set the working directory inside the container
WORKDIR /app

# Copy the requirements file into the container
COPY requirements.txt .

# Install the Python dependencies
# This command is run only once when the image is built.
RUN pip install --no-cache-dir -r requirements.txt

# The container will run the script provided by the Kubernetes Job manifest
# CMD is not needed here as the Job's command will override it.
