#!/bin/bash

# Script Vars
REPO_URL="git@github.com:Sergei29/next-self-host.git" # replace with your own repo if needed
APP_DIR=~/myapp

# Pull the latest changes from the Git repository
if [ -d "$APP_DIR" ]; then
  echo "Pulling latest changes from the repository..."
  cd $APP_DIR
  git pull origin main
else
  echo "Cloning repository from $REPO_URL..."
  git clone $REPO_URL $APP_DIR
  cd $APP_DIR
fi

# Build and restart the Docker containers from the app directory (~/myapp)
echo "Rebuilding and restarting Docker containers..."
sudo docker-compose down
sudo docker-compose up --build -d

# Check if Docker Compose started correctly
if ! sudo docker-compose ps | grep "Up"; then
  echo "Docker containers failed to start. Check logs with 'docker-compose logs'."
  exit 1
fi

# Wait a few seconds for Postgres to start
echo "⏳ Waiting 10 seconds for Postgres to initialize..."
sleep 10

# Sync Postgres user password (optional, ensures password matches .env)
POSTGRES_USER=$(grep POSTGRES_USER "$APP_DIR/.env" | cut -d '=' -f2)
POSTGRES_PASSWORD=$(grep POSTGRES_PASSWORD "$APP_DIR/.env" | cut -d '=' -f2)
echo "🟢 Syncing Postgres password..."
sudo docker-compose exec db psql -U postgres -c "ALTER USER $POSTGRES_USER WITH PASSWORD '$POSTGRES_PASSWORD';"

# Run Drizzle migrations
echo "🟢 Running Drizzle migrations..."
sudo docker-compose exec web bun x drizzle-kit push --config ./drizzle.config.ts || {
  echo "❌ Migrations failed. Check container logs."
  exit 1
}

# Output final message
echo "Update complete. Your Next.js app has been deployed with the latest changes."

