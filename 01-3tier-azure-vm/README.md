# Project 01 — 3-Tier App Deployment on Azure VM

## Overview

Provisioned an Azure cloud VM from scratch and deployed a 3-tier application (UI + API + PostgreSQL) using Docker Compose. Docker installation was fully automated using a Cloud-Init bootstrap script injected at VM creation time — zero manual setup required on first boot.

## Architecture

```
Browser → port 80
    ↓
UI container (Nginx)
    ↓  internal Docker network
API container (Node.js) — port 3000
    ↓  internal Docker network
PostgreSQL container
```

## Step 1 — Create the Azure VM with Cloud-Init

In Azure Portal → Create VM → Advanced tab → Custom Data, paste the script below. Docker installs automatically on first boot with no manual steps needed.

```bash
#!/bin/bash
apt update && apt upgrade -y
apt install -y apt-transport-https ca-certificates curl software-properties-common

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  | tee /etc/apt/sources.list.d/docker.list

apt update
apt install -y docker-ce docker-ce-cli containerd.io
systemctl start docker
systemctl enable docker
```

**VM settings used:**
- Authentication: SSH key-based (recommended for production; password auth is an option for quick lab environments but is not used in any production project here)
- Inbound ports opened at creation: 22 (SSH), 80 (HTTP)
- Public IP: assigned

## Step 2 — Configure Azure NSG Rules

After VM creation, add the following rules in the Network Security Group:

- Inbound rule: allow port 3000 (application API access)
- Outbound rule: allow port 3000

## Step 3 — Transfer Application Code to the VM

```bash
# Replace <your-username> and <vm-public-ip> with your actual values
# Transfer all app files to the VM
scp -r * <your-username>@<vm-public-ip>:/home/<your-username>

# SSH into the VM
ssh <your-username>@<vm-public-ip>
```

## Step 4 — Grant Docker Permissions (no sudo needed)

```bash
sudo usermod -aG docker $USER
newgrp docker
docker ps    # verify Docker is running without sudo
```

## Step 5 — Update Frontend Config to Point to the VM's Public IP

```json
// ui/config.json
{
  "API_URL": "http://<vm-public-ip>:3000/"
}
```

## Step 6 — Install Docker Compose and Launch the Stack

```bash
sudo apt install -y docker-compose
docker-compose up --build
```

Expected output:

```
basic-3tier-ui  | 2025/03/14 20:08:30 [notice] 1#1: start worker process 22
basic-3tier-api | Connected to PostgreSQL Database
basic-3tier-api | Database initialized
basic-3tier-api | Server running on port 3000
```

## Step 7 — Verify the Deployment

```bash
# Check all containers are running
docker ps

# Open in browser
# http://<vm-public-ip>:80/

# Troubleshoot if needed
docker logs <container_name>
```

## Key Concepts Demonstrated

- **Cloud-Init** — Zero-touch Docker installation at VM boot; no manual configuration steps
- **Azure NSG** — Controlled port exposure: only required ports are opened
- **Secure File Transfer** — `scp` for remote file transfer over SSH
- **Docker Permissions** — Adding user to the `docker` group eliminates the need for `sudo`
- **Docker Compose** — Single command orchestrates the full 3-tier stack
- **Environment-Driven Config** — Frontend API URL set by environment (public IP injection)

---

**Tools:** Docker · Docker Compose · Azure VM · Cloud-Init · NSG · SSH · SCP · PostgreSQL
