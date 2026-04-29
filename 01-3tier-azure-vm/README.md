# Project 01 — 3-Tier Application Deployment on Azure VM

## What This Project Does

This project demonstrates how to provision a cloud virtual machine on Microsoft Azure from scratch and deploy a full 3-tier web application on it using Docker Compose — without installing anything manually. The entire environment bootstraps itself through a Cloud-Init script that runs automatically the moment the VM first boots.

The application stack consists of three layers: a frontend served by Nginx, a Node.js API backend, and a PostgreSQL database. All three run as separate Docker containers that communicate with each other over an internal Docker network — the database is never exposed to the internet.

## Architecture

```
User's Browser
      |
   port 80 (HTTP)
      |
 [UI Container — Nginx]          ← serves the frontend, reverse proxies to API
      |
  internal Docker network
      |
 [API Container — Node.js]       ← handles business logic, talks to DB
      |
  internal Docker network
      |
 [Database — PostgreSQL]         ← data layer, not reachable from outside
```

Only port 80 is exposed publicly. The API and database communicate entirely on Docker's internal network, never accessible from the internet.

---

## Step 1 — Create the Azure VM with Cloud-Init

**Why:** Rather than SSH-ing in after VM creation and manually running installation commands, Cloud-Init lets us inject a startup script into the VM at creation time. Azure runs this script automatically on first boot — so by the time the VM is ready, Docker is already installed and running.

In the **Azure Portal**, go to: **Create VM → Management tab → Custom Data**, and paste the script below.

```bash
#!/bin/bash
# Update the package list and upgrade existing packages
apt update && apt upgrade -y

# Install dependencies needed to add the Docker repository
apt install -y apt-transport-https ca-certificates curl software-properties-common

# Add Docker's official GPG key so the system trusts packages from Docker's repo
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Add the Docker apt repository to the system's software sources
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  | tee /etc/apt/sources.list.d/docker.list

# Install Docker Engine
apt update
apt install -y docker-ce docker-ce-cli containerd.io

# Start Docker and ensure it restarts automatically if the VM reboots
systemctl start docker
systemctl enable docker
```

**VM configuration used:**
- **Region:** East US (or nearest to you)
- **Image:** Ubuntu 22.04 LTS
- **Authentication:** SSH key pair
- **Inbound ports opened at creation:** 22 (SSH access), 80 (HTTP for the app)
- **Public IP:** Enabled so we can access the app from a browser

---

## Step 2 — Open Port 3000 in the Network Security Group

**Why:** Azure VMs are protected by a Network Security Group (NSG) — a firewall that blocks all inbound traffic by default except what you explicitly allow. Port 80 was opened at VM creation, but the Node.js API runs on port 3000 internally. We need to allow that port for direct API testing.

In the Azure Portal, navigate to the VM → **Networking** → **Add inbound port rule**:
- **Destination port:** 3000
- **Protocol:** TCP
- **Action:** Allow

---

## Step 3 — Copy the Application Code to the VM

**Why:** The application source code lives on your local machine. We use `scp` (Secure Copy Protocol, which runs over SSH) to transfer all files to the VM securely in a single command.

```bash
# Copy everything from your current local directory to the VM's home folder
# Replace <your-username> and <vm-public-ip> with your actual values
scp -r * <your-username>@<vm-public-ip>:/home/<your-username>

# Then SSH into the VM to continue working directly on it
ssh <your-username>@<vm-public-ip>
```

---

## Step 4 — Add Your User to the Docker Group

**Why:** By default, the Docker daemon requires `sudo` to run commands. Adding your user to the `docker` group grants permission to run Docker without `sudo` — which is required for Docker Compose to work correctly without elevated privileges.

```bash
# Add current user to the docker group
sudo usermod -aG docker $USER

# Apply the group change immediately without logging out
newgrp docker

# Confirm Docker works without sudo
docker ps
```

---

## Step 5 — Update the Frontend API URL

**Why:** The frontend needs to know where to send API requests. Since we are running on a cloud VM with a public IP (not localhost), we must update the config file to point to the VM's public IP address before building the containers.

```json
// ui/config.json
{
  "API_URL": "http://<vm-public-ip>:3000/"
}
```

---

## Step 6 — Install Docker Compose and Launch the Stack

**Why:** Docker Compose reads the `docker-compose.yml` file and starts all three containers (UI, API, DB) in the correct order with a single command. Without Compose, you would need to run three separate `docker run` commands and manually configure networking between them.

```bash
# Install Docker Compose
sudo apt install -y docker-compose

# Build images and start all containers in the background
docker-compose up --build
```

When all three services start successfully, you will see output like:

```
basic-3tier-ui  | nginx: worker process started
basic-3tier-api | Connected to PostgreSQL Database
basic-3tier-api | Database initialized
basic-3tier-api | Server running on port 3000
```

This confirms the API has connected to the database and all three tiers are running.

---

## Step 7 — Verify the Deployment

**Why:** Before considering the deployment complete, we verify each layer is healthy.

```bash
# Check that all three containers are in "Up" status
docker ps

# View logs for a specific container to diagnose any issues
docker logs <container_name>
```

Then open a browser and navigate to `http://<vm-public-ip>` — the application should be live.

---

## What I Learned

- **Cloud-Init** eliminates manual post-provisioning steps. The VM is application-ready the moment it boots.
- **Azure NSGs** act as a firewall layer — explicit rules are required for every port you want to expose. This reinforces least-privilege network access.
- **SCP** is the secure, SSH-based way to transfer files to a remote server. Never use unencrypted methods like FTP.
- **Docker group permissions** matter for automation — `sudo` requirements break scripted deployments.
- **Docker Compose** turns a multi-container deployment into a single command, handling container networking, startup ordering, and dependency management automatically.

---

**Tools Used:** Azure VM · Cloud-Init · Docker · Docker Compose · Nginx · Node.js · PostgreSQL · NSG · SSH · SCP
