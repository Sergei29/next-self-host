# Next.js Self Hosting Example

This repo shows how to deploy a Next.js app and a PostgreSQL database on a Ubuntu Linux server using Docker and Nginx. It showcases using several features of Next.js like caching, ISR, environment variables, and more.

[**📹 Watch the tutorial (45m)**](https://www.youtube.com/watch?v=sIVL4JMqRfc)

[![Self Hosting Video Thumbnail](https://img.youtube.com/vi/sIVL4JMqRfc/0.jpg)](https://www.youtube.com/watch?v=sIVL4JMqRfc)

## Prerequisites

1. Purchase a domain name
2. Purchase a Linux Ubuntu server (e.g. [droplet](https://www.digitalocean.com/products/droplets))
3. Create an `A` DNS record pointing to your server IPv4 address

## Quickstart

1. **SSH into your server**:

   ```bash
   ssh root@your_server_ip
   ```

   If you are on ASW EC2 instance:
   - Get your EC2 public IP address,
   - paste here your `.pem` key that u get from your EC2 instance
   - run `chmod 400 my-ec2-key.pem` 
   - run: for example if your EC2 public IP is `3.92.105.24`
   ```sh
   ssh -i my-ec2-key.pem ubuntu@3.92.105.24
   ```
   - once in there you may need update apt and install node:
   ```sh
   sudo apt update && sudo apt upgrade -y
   curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
   sudo apt install -y nodejs
   ```
   - verify if installed by:
   ```sh
   node -v
   npm -v
   ```

2. **Download the deployment script**:

   ```bash
   curl -o ~/deploy.sh https://raw.githubusercontent.com/leerob/next-self-host/main/deploy.sh
   ```

   You can then modify the email and domain name variables inside of the script to use your own.

3. **Run the deployment script**:

   ```bash
   chmod +x ~/deploy.sh
   ./deploy.sh
   ```

## Supported Features

This demo tries to showcase many different Next.js features.

- Image Optimization
- Streaming
- Talking to a Postgres database
- Caching
- Incremental Static Regeneration
- Reading environment variables
- Using Middleware
- Running code on server startup
- A cron that hits a Route Handler

## Deploy Script

I've included a Bash script which does the following:

1. Installs all the necessary packages for your server
1. Installs Docker, Docker Compose, and Nginx
1. Clones this repository
1. Generates an SSL certificate
1. Builds your Next.js application from the Dockerfile
1. Sets up Nginx and configures HTTPS and rate limting
1. Sets up a cron which clears the database every 10m
1. Creates a `.env` file with your Postgres database creds

Once the deployment completes, your Next.js app will be available at:

```
http://your-provided-domain.com
```

Both the Next.js app and PostgreSQL database will be up and running in Docker containers. To set up your database, you could install `npm` inside your Postgres container and use the Drizzle scripts, or you can use `psql`:

```bash
docker exec -it myapp-db-1 sh
apk add --no-cache postgresql-client
psql -U myuser -d mydatabase -c '
CREATE TABLE IF NOT EXISTS "todos" (
  "id" serial PRIMARY KEY NOT NULL,
  "content" varchar(255) NOT NULL,
  "completed" boolean DEFAULT false,
  "created_at" timestamp DEFAULT now()
);'
```

For pushing subsequent updates, I also provided an `update.sh` script as an example.

## Running Locally

If you want to run this setup locally using Docker, you can follow these steps:

```bash
docker-compose up -d
```

This will start both services and make your Next.js app available at `http://localhost:3000` with the PostgreSQL database running in the background. We also create a network so that our two containers can communicate with each other.

If you want to view the contents of the local database, you can use Drizzle Studio:

```bash
bun run db:studio
```

## Helpful Commands

- `docker-compose ps` – check status of Docker containers
- `docker-compose logs web` – view Next.js output logs
- `docker-compose logs cron` – view cron logs
- `docker-compose down` - shut down the Docker containers
- `docker-compose up -d` - start containers in the background
- `sudo systemctl restart nginx` - restart nginx
- `docker exec -it myapp-web-1 sh` - enter Next.js Docker container
- `docker exec -it myapp-db-1 psql -U myuser -d mydatabase` - enter Postgres db

## How to fix if run out of disk storage

1. Check disk usage
`df -h`
Look at / and /var/lib/docker. Likely it’s almost 100%.

2. Free up space:
```sh
sudo docker system prune -a --volumes
```
- `-a` removes all unused images, not just dangling ones.
- `--volumes` removes unused volumes (be careful if you have data volumes you need).
  
3. Check logs
```sh
sudo journalctl --disk-usage
sudo journalctl --vacuum-size=200M
```
Old system logs can take GBs.

4. Remove unnecessary files

- Node caches: `rm -rf ~/.npm ~/.cache`
- Old builds: `rm -rf ~/myapp/build or temporary files in /tmp.`

5. Rebuild Docker image
- After cleaning or expanding:
```sh
cd ~/myapp
sudo docker-compose build --no-cache
sudo docker-compose up -d
```

## Other Resources

- [Kubernetes Example](https://github.com/ezeparziale/nextjs-k8s)
- [Redis Cache Adapter for Next.js](https://github.com/vercel/next.js/tree/canary/examples/cache-handler-redis)
- [ipx – Image optimization library](https://github.com/unjs/ipx)
- [OrbStack - Fast Docker desktop client](https://orbstack.dev/)

## About the deploy script:

### 1️⃣ Swap
```sh
if [ ! -f /swapfile ]; then
  sudo fallocate -l $SWAP_SIZE /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
fi
```
#### What it is:

- Swap is a portion of disk space that the operating system uses as “virtual RAM.”
- If your physical RAM is full, the system can temporarily move inactive memory pages to swap.

#### How it helps here:

- Your EC2 instance might be small (e.g., 1–2 GB RAM).
- Building Docker images, installing packages, or running Node.js + Postgres can consume a lot of memory.
- Swap prevents “out of memory” errors during heavy operations like:
- - `bun install`
- - Docker image builds
- - Running multiple containers at once

### 2️⃣ Nginx

```sh
sudo apt install nginx -y
```
#### What it is:

- Nginx is a web server and reverse proxy.
- It listens on ports 80 (HTTP) and 443 (HTTPS) and forwards incoming requests to your application (Next.js running on port 3000 inside Docker).

#### Role in this script:

- Acts as a reverse proxy: client → Nginx → Docker container.
- Handles: 
- - HTTPS termination (SSL/TLS)
- - Rate limiting (limit_req)
- - Buffering control for streaming responses
- Without Nginx, your Next.js app would need to handle HTTPS itself — which is less common in production.

### 3️⃣ Certbot and python3-certbot-nginx
```sh
sudo apt install certbot python3-certbot-nginx -y
```
#### What they are:

- `certbot`: a client tool to get free SSL/TLS certificates from Let’s Encrypt.
- `python3-certbot-nginx`: a plugin for Certbot to automatically configure Nginx with SSL.

#### What they do in this script:

- Certbot generates a certificate for your domain (`template.bloblick.click`) and sets up Nginx to serve HTTPS traffic.
- It automates the verification process using the ACME protocol.

### 4️⃣ How SSL certificate request works
```sh
sudo certbot --nginx -d $DOMAIN_NAME -m $EMAIL --agree-tos --non-interactive --redirect
```
#### Step-by-step:

1. Certbot tells Let’s Encrypt: “I want a certificate for this domain.”
2. Let’s Encrypt performs domain verification:
- - Confirms your domain points to your EC2 instance (via HTTP challenge).
- - Creates a temporary file under /.well-known/acme-challenge/ that the CA tries to fetch.
3. If verification succeeds, Let’s Encrypt issues the certificate.
4. Certbot automatically configures Nginx to:
- - Use the new certificate (fullchain.pem & privkey.pem)
- - Redirect HTTP → HTTPS (--redirect flag)
5. Now your site serves encrypted traffic over HTTPS.

### 5️⃣ Cronjob for SSL renewal
```sh
( crontab -l 2>/dev/null; echo "0 */12 * * * certbot renew --quiet && systemctl reload nginx" ) | crontab -
```
#### How it works:

- Let’s Encrypt certificates are valid for 90 days.
- Certbot can renew them automatically.
- The cronjob does the following every 12 hours (`0 */12 * * *`):
- - Run `certbot renew --quiet` → checks all certificates and renews any that are near expiration.
- - Reload Nginx configuration to start using the new certificate (`systemctl reload nginx`).

#### Why it helps:

- You don’t have to manually renew your certificate.
- Ensures HTTPS stays valid and users never get certificate warnings.

| Component                           | Role in deployment                                                                |
| ----------------------------------- | --------------------------------------------------------------------------------- |
| **Swap**                            | Prevents out-of-memory errors during heavy operations (Docker, Node.js, Postgres) |
| **Nginx**                           | Reverse proxy, handles HTTPS, rate limiting, and buffering                        |
| **Certbot + python3-certbot-nginx** | Automatically gets free SSL certificates and configures Nginx                     |
| **SSL certificate request**         | Validates domain ownership with Let’s Encrypt, installs certificate for HTTPS     |
| **Cronjob**                         | Automatically renews certificates every 12 hours and reloads Nginx                |

### About pruning the containers
- How can we preserve the postgres database data between pruning for example ?

#### 🔹 How Docker stores Postgres data

- When you run Postgres in Docker, the container itself is disposable.
- The actual database files (your tables, rows, indexes) are stored in a Docker volume.
- If you only remove/rebuild containers, your data is safe as long as the volume is preserved.
- If you prune with `--volumes`, Docker deletes unused volumes, and that means your database is gone.

#### 🔹 Typical setup (docker-compose.yml)

In most `docker-compose.yml` setups you’ll see something like:

```yml
services:
  db:
    image: postgres:15
    environment:
      POSTGRES_USER: myuser
      POSTGRES_PASSWORD: mypass
      POSTGRES_DB: mydatabase
    volumes:
      - postgres_data:/var/lib/postgresql/data

volumes:
  postgres_data:
```
- 👉 Here, `postgres_data` is a named volume that stores your Postgres files.
- Even if you remove and rebuild containers, the volume persists.

#### 🔹 What happens with prune

- `docker system prune -a` → removes unused images and stopped containers, but keeps named volumes.
- `docker system prune -a --volumes` → also deletes **unused volumes**. If your Postgres volume isn’t in use at the moment, it will be removed → 💀 **data loss**.

#### 🔹 How to keep your database data

- ✅ Option 1: Use named volumes (best practice)

Make sure your `docker-compose.yml` has:

```yml
volumes:
  postgres_data:
```

And Postgres uses it:

```yml
volumes:
  - postgres_data:/var/lib/postgresql/data
```
As long as this volume is named, Docker will keep it unless you explicitly delete it.

- ✅ Option 2: Backup before prune

Before pruning with `--volumes`, you can dump the database:

```sh
# From inside container
docker exec -t myapp-db-1 pg_dump -U myuser mydatabase > backup.sql

# Or directly from host
docker exec -t myapp-db-1 pg_dumpall -U myuser > full_backup.sql
```

Then later restore:

```sh
docker exec -i myapp-db-1 psql -U myuser -d mydatabase < backup.sql
```

- ✅ Option 3: Map Postgres data to host directory

Instead of a Docker-managed volume, mount a host folder:

```sh
volumes:
  - ./postgres_data:/var/lib/postgresql/data
```

Now your database lives in ./postgres_data on your EC2.
Even if you prune everything, the host files are still there.

#### ⚠️ TL;DR

- `docker system prune -a` is safe → your Postgres data stays.
- `docker system prune -a --volumes` is dangerous → you’ll lose DB data unless:
- - You use named volumes (postgres_data), and don’t delete them.
- - Or you backup before pruning.
- - Or you mount to host directory.