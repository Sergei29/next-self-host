#!/bin/bash
set -euo pipefail

# ========================
# Configuration
# ========================
POSTGRES_USER="myuser"
POSTGRES_PASSWORD=$(openssl rand -base64 12)  # Generate a random 12-character password
POSTGRES_DB="mydatabase"
SECRET_KEY="my-secret"          # for the demo app
NEXT_PUBLIC_SAFE_KEY="safe-key" # for the demo app
DOMAIN_NAME="template.bloblick.click" # replace with your own
EMAIL="sergejs.basangovs@gmail.com"   # replace with your own

REPO_URL="https://github.com/Sergei29/next-self-host.git" # HTTPS to avoid SSH issues
APP_DIR="$HOME/myapp"
SWAP_SIZE="1G"

echo "🚀 Starting deployment for $DOMAIN_NAME ..."

# ========================
# System update & swap
# ========================
sudo apt update && sudo apt upgrade -y

if [ ! -f /swapfile ]; then
  echo "🟢 Adding swap space..."
  sudo fallocate -l $SWAP_SIZE /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
else
  echo "ℹ️ Swap file already exists, skipping..."
fi

# ========================
# Install Docker & Docker Compose
# ========================
if ! command -v docker &> /dev/null; then
  echo "🟢 Installing Docker..."
  sudo apt install apt-transport-https ca-certificates curl software-properties-common -y
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
  sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" -y
  sudo apt update
  sudo apt install docker-ce -y
  sudo systemctl enable docker
  sudo systemctl start docker
else
  echo "ℹ️ Docker already installed."
fi

if ! command -v docker-compose &> /dev/null; then
  echo "🟢 Installing Docker Compose..."
  sudo curl -L "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  sudo chmod +x /usr/local/bin/docker-compose
  sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
else
  echo "ℹ️ Docker Compose already installed."
fi

docker-compose --version || { echo "❌ Docker Compose installation failed."; exit 1; }

# ========================
# Clone or update app repo
# ========================
if [ -d "$APP_DIR/.git" ]; then
  echo "🟢 Updating existing repo in $APP_DIR ..."
  cd "$APP_DIR"
  git pull origin main || git pull
else
  echo "🟢 Cloning repo from $REPO_URL ..."
  rm -rf "$APP_DIR"
  git clone "$REPO_URL" "$APP_DIR"
  cd "$APP_DIR"
fi

# ========================
# Create .env file
# ========================
cat > "$APP_DIR/.env" <<EOL
POSTGRES_USER=$POSTGRES_USER
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
POSTGRES_DB=$POSTGRES_DB
DATABASE_URL=postgres://$POSTGRES_USER:$POSTGRES_PASSWORD@db:5432/$POSTGRES_DB
DATABASE_URL_EXTERNAL=postgres://$POSTGRES_USER:$POSTGRES_PASSWORD@localhost:5432/$POSTGRES_DB
SECRET_KEY=$SECRET_KEY
NEXT_PUBLIC_SAFE_KEY=$NEXT_PUBLIC_SAFE_KEY
EOL

echo "🟢 .env file created at $APP_DIR/.env"

# ========================
# Nginx + SSL
# ========================
sudo apt install nginx certbot python3-certbot-nginx -y

# Create Nginx config
sudo tee /etc/nginx/sites-available/myapp > /dev/null <<EOL
limit_req_zone \$binary_remote_addr zone=mylimit:10m rate=10r/s;

server {
    listen 80;
    server_name $DOMAIN_NAME;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name $DOMAIN_NAME;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    limit_req zone=mylimit burst=20 nodelay;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_buffering off;
        proxy_set_header X-Accel-Buffering no;
    }
}
EOL

sudo ln -sf /etc/nginx/sites-available/myapp /etc/nginx/sites-enabled/myapp
sudo nginx -t && sudo systemctl restart nginx

echo "🟢 Requesting SSL certificate for $DOMAIN_NAME ..."
sudo certbot --nginx -d $DOMAIN_NAME -m $EMAIL --agree-tos --non-interactive --redirect

# ========================
# Start Docker containers
# ========================
cd "$APP_DIR"

if [ ! -f "docker-compose.yml" ]; then
  echo "❌ docker-compose.yml not found in $APP_DIR. Deployment aborted."
  exit 1
fi

echo "🟢 Starting Docker containers..."
sudo docker-compose up --build -d

if ! sudo docker-compose ps | grep "Up" >/dev/null; then
  echo "❌ Docker containers failed to start. Check logs with 'docker-compose logs'."
  exit 1
fi

# Wait a few seconds for Postgres to be ready
echo "⏳ Waiting 10 seconds for Postgres to initialize..."
sleep 10

# Run Drizzle migrations
echo "🟢 Running Drizzle migrations..."
sudo docker-compose exec web bun x drizzle-kit push --config ./drizzle.config.ts || {
    echo "❌ Migrations failed. Check the container logs."
    exit 1
}


# ========================
# Cronjob for SSL renewal
# ========================
( crontab -l 2>/dev/null; echo "0 */12 * * * certbot renew --quiet && systemctl reload nginx" ) | crontab -

echo "✅ Deployment complete!"
echo "🌍 App available at: https://$DOMAIN_NAME"
echo "🐘 Postgres running in Docker (internal container: db)"
echo "📄 .env file created at $APP_DIR/.env"
