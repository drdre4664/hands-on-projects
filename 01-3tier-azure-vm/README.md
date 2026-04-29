# 3-Tier App Deployment on Azure VM

Provisioned a cloud VM from scratch and deployed a 3-tier application
(UI + API + database) using Docker Compose, with automated Docker
installation handled at VM boot time via Cloud-Init.

## What Was Built

- Azure VM configured with a Cloud-Init `user_data` script to install Docker automatically on first boot — zero manual setup required
- Azure NSG inbound/outbound rules opened for ports 22, 80, and 3000
- Application code transferred to the VM using `scp`
- Frontend config updated dynamically to point to the VM's public IP
- Full stack launched with `docker-compose up --build` and verified via `docker ps` and browser access

## Tools

Docker · Docker Compose · Azure VM · Cloud-Init · NSG · SCP · SSH
