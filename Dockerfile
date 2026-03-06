# Stage 1: Build the React frontend
FROM node:20-alpine AS frontend-builder
WORKDIR /app/frontend

# Install dependencies
COPY frontend/package.json ./
RUN npm install

# Copy the rest of the frontend source code
COPY frontend/ ./

# Build the Vite React app (Outputs to /app/frontend/dist)
RUN npm run build

# Stage 2: Setup Python Backend and serve
FROM python:3.11-slim
WORKDIR /app

# Install Python dependencies
COPY backend/requirements.txt ./backend/
RUN pip install --no-cache-dir -r backend/requirements.txt

# Copy the Python backend source code
COPY backend/ ./backend/

# Copy the built React app from Stage 1 into the backend/static directory
COPY --from=frontend-builder /app/frontend/dist /app/backend/static

# Cloud Run sets the PORT environment variable. We default to 8080 if not set.
ENV PORT=8080
EXPOSE $PORT

# Run the FastAPI application using Uvicorn
CMD ["sh", "-c", "uvicorn backend.main:app --host 0.0.0.0 --port ${PORT}"]
