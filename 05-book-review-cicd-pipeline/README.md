# Project 05 — Book Review App: Full CI/CD Pipeline

## What This Project Does

This project implements a production-grade CI/CD system for the Book Review application using a **two-repository architecture** in Azure DevOps. Instead of one big repository doing everything, the infrastructure code and the application code live in separate repositories, each with its own pipeline. This mirrors how real platform and development teams operate — the infra team owns the infrastructure repo, the dev team owns the application repo, and a DevOps engineer manages both pipelines.

The infrastructure pipeline uses Terraform to provision Azure VMs and a MySQL database. The application pipeline uses Ansible to deploy and configure the application on those VMs. All secrets — SSH keys, database credentials, Azure credentials — are stored in Azure DevOps secure storage and injected at pipeline runtime. Nothing sensitive ever touches source control.

## Architecture

```
Two separate repositories, two separate pipelines:

book-review-infra (repo)                book-review-app (repo)
─────────────────────────               ─────────────────────────
Triggered by: changes in /terraform     Triggered by: push to main

         ↓                                        ↓
  Azure DevOps Pipeline                  Azure DevOps Pipeline
         ↓                                        ↓
  terraform init                         pip install ansible
  terraform plan                         Download SSH key (Secure File)
  terraform apply                        ansible-playbook deploy.yml
         ↓                                        ↓
  Azure VMs + MySQL created    ──IPs──▶  App deployed to those VMs
                                         (PM2 manages the Node.js process)
```

---

## Phase 1 — Infrastructure Provisioning (book-review-infra)

### What Terraform provisions

Terraform reads the `terraform/` directory and creates all the Azure resources needed to run the application: two Ubuntu VMs (frontend and backend), an Azure MySQL database, networking, public IPs, and NSG rules. All of this happens automatically — no clicking in the Azure Portal.

### The infrastructure pipeline (azure-pipelines.yml)

**Why a path trigger?** The pipeline only runs when files inside `terraform/` change. If someone updates the README or adds a test file, this pipeline does not run. This prevents unnecessary infra changes.

```yaml
trigger:
  paths:
    include:
      - terraform/*

steps:
  - task: TerraformInstaller@0
    inputs:
      terraformVersion: 'latest'
    # Installs the correct version of Terraform on the pipeline agent

  - task: TerraformTaskV2@2
    inputs:
      provider: 'azurerm'
      command: 'init'
      backendServiceArm: '<service-connection-name>'
    # Initialises Terraform — downloads providers, connects to the Azure
    # backend where remote state is stored

  - task: TerraformTaskV2@2
    inputs:
      provider: 'azurerm'
      command: 'apply'
      environmentServiceNameAzureRM: '<service-connection-name>'
    # Applies the Terraform plan — creates or updates Azure resources
    # Azure credentials come from the Service Connection, never from code
```

### Setting up the pipeline in Azure DevOps

1. Go to **Pipelines → New Pipeline → GitHub (YAML)**
2. Select the `book-review-infra` repository
3. Choose **"Existing Azure Pipelines YAML file"**
4. Set the path to `azure-pipelines.yaml`
5. Click **Run** — Terraform provisions all Azure resources automatically

---

## Phase 2 — Handing Off the VM IPs to the App Team

**Why this step exists:** After Terraform runs, it outputs the public IP addresses of the newly created VMs. The app team needs these IPs to configure Ansible's inventory — telling it which servers to deploy to. This handoff is deliberate; in real organisations, the platform team owns the infrastructure and the app team owns the deployment, and they communicate through outputs like this.

The IPs are copied from the pipeline logs into the Ansible inventory file:

```ini
# ansible/inventory.ini
[frontend]
<frontend-vm-public-ip>

[backend]
<backend-vm-public-ip>
```

Database connection details are stored as Ansible Vault-encrypted variables — the actual values are never written in plaintext in any file:

```yaml
# ansible/group_vars/backend.yaml
db_host: <mysql-host>
db_name: bookreviews
db_user: "{{ vault_db_user }}"        # decrypted at runtime from Ansible Vault
db_password: "{{ vault_db_password }}" # decrypted at runtime from Ansible Vault
```

---

## Phase 3 — Application Deployment (book-review-app)

### What Ansible deploys

Ansible connects to each VM over SSH, pulls the application code, installs Node.js dependencies, configures the MySQL connection, and starts the application using PM2. PM2 is a process manager that keeps Node.js apps running in the background, restarts them if they crash, and starts them automatically on VM reboot.

### The application pipeline (azure-pipelines.yml)

**Why store the SSH key as a Secure File?** The pipeline needs an SSH private key to connect to the VMs. Secure Files in Azure DevOps Library is the correct storage mechanism — the file is encrypted at rest and is never visible in pipeline logs. It is downloaded to the agent at runtime and deleted after the pipeline finishes.

```yaml
trigger:
  branches:
    include:
      - main
# Every push to main triggers a full redeployment

steps:
  - script: pip install ansible
    # Install Ansible on the pipeline agent

  - task: DownloadSecureFile@1
    name: sshKey
    inputs:
      secureFile: 'id_rsa'
    # Download the SSH private key from Azure DevOps Library (Secure Files)
    # This key was uploaded there manually — it never exists in the repository

  - script: |
      chmod 600 $(sshKey.secureFilePath)
      # Set correct permissions — SSH refuses to use keys with open permissions

      ansible-playbook -i ansible/inventory.ini \
        ansible/deploy.yml \
        --private-key $(sshKey.secureFilePath) \
        -e "ansible_ssh_common_args='-o StrictHostKeyChecking=no'"
      # Run the deployment playbook against the servers in the inventory
    displayName: 'Deploy application with Ansible'
```

---

## Phase 4 — Lab: Static HTML Deployment via Pipeline

Before building the full pipeline, this foundational lab demonstrated the core concept of pipeline-triggered deployments: a push to `main` automatically copies a file to a remote server and restarts the web server. Understanding this simple flow is the foundation for everything that comes after.

```yaml
trigger:
  - main

pool:
  name: "self-hosted-agent-pool"
  # Using a self-hosted agent — a VM with the required tools pre-installed

variables:
  sshService: 'ssh-to-nginx-vm'
  webRoot: '/var/www/html'

stages:
  - stage: DeployHTML
    jobs:
      - job: Deploy
        steps:
          - task: SSH@0
            inputs:
              sshEndpoint: '$(sshService)'
              runOptions: 'inline'
              inline: |
                sudo chown -R www-data:www-data /var/www/html
                sudo chmod -R 775 /var/www/html
            # Fix permissions so the pipeline can write to the web root

          - task: CopyFilesOverSSH@0
            inputs:
              sshEndpoint: '$(sshService)'
              sourceFolder: '$(Build.SourcesDirectory)'
              contents: 'index.html'
              targetFolder: '$(webRoot)'
            # Copy the HTML file from the pipeline workspace to the server

          - task: SSH@0
            inputs:
              sshEndpoint: '$(sshService)'
              runOptions: 'inline'
              inline: sudo systemctl restart nginx
            # Restart Nginx so it picks up the new file
```

---

## Phase 5 — Lab: React App with Build → Test → Deploy Stages

This lab introduced multi-stage pipelines with **stage gating**: the Deploy stage only runs if the Test stage passed. If any test fails, the pipeline stops and the broken build never reaches the server.

```yaml
trigger:
  - main

pool:
  vmImage: 'ubuntu-latest'

variables:
  sshService: 'ssh-to-nginx-vm'
  artifactName: 'react-build'
  webRoot: '/var/www/html'

stages:

  - stage: BuildReactApp
    jobs:
      - job: Build
        steps:
          - task: NodeTool@0
            inputs:
              versionSpec: '20.x'
          - script: npm install
          - script: npm run build
            # Compile the React app into static files
          - task: PublishBuildArtifacts@1
            inputs:
              pathToPublish: 'build'
              artifactName: '$(artifactName)'
            # Store the compiled output so later stages can download it

  - stage: TestReactApp
    dependsOn: BuildReactApp
    condition: succeeded()   # only run if Build passed
    jobs:
      - job: Test
        steps:
          - task: NodeTool@0
            inputs:
              versionSpec: '20.x'
          - script: npm install
          - script: npm run test -- --watchAll=false
            # Run all tests once — pipeline fails here if tests fail

  - stage: DeployToVM
    dependsOn: TestReactApp
    condition: succeeded()   # only deploy if tests passed
    jobs:
      - job: Deploy
        steps:
          - task: DownloadBuildArtifacts@0
            inputs:
              artifactName: '$(artifactName)'
              downloadPath: '$(Pipeline.Workspace)'
            # Download the compiled React build from the Build stage

          - task: CopyFilesOverSSH@0
            inputs:
              sshEndpoint: '$(sshService)'
              sourceFolder: '$(Pipeline.Workspace)/$(artifactName)'
              contents: '**'
              targetFolder: '$(webRoot)'
            # Copy all compiled files to the web server

          - task: SSH@0
            inputs:
              sshEndpoint: '$(sshService)'
              runOptions: 'inline'
              inline: |
                echo 'server {
                  listen 80;
                  root /var/www/html;
                  index index.html;
                  location / { try_files $uri /index.html; }
                }' | sudo tee /etc/nginx/sites-available/default
                sudo systemctl restart nginx
            # Write the Nginx config and restart to serve the React app
```

---

## Prerequisites — One-time Setup

### 1. Create an Azure Service Principal

The pipeline needs permission to create and manage Azure resources. A Service Principal is an identity (like a service account) with limited permissions.

```bash
az ad sp create-for-rbac \
  --name "devops-sp" \
  --role Contributor \
  --scopes /subscriptions/<your-subscription-id>/resourceGroups/<your-rg-name>
```

The output (`appId`, `password`, `tenant`) is registered in Azure DevOps as a **Service Connection** — it is never stored in code.

### 2. Register the Service Connection

Azure DevOps → **Project Settings → Service Connections → New → Azure Resource Manager → Service Principal (automatic)**

### 3. Upload the SSH key to Azure DevOps Library

**Pipelines → Library → Secure Files → Upload `id_rsa`**

The SSH private key is stored encrypted in Azure DevOps. It is never committed to Git.

### 4. Create the SSH Service Connection

**Project Settings → Service Connections → New → SSH**
- **Host:** VM public IP
- **Port:** 22
- **Username:** `azureuser`
- **Authentication:** SSH key (private key from Secure Files)
- **Name:** `ssh-to-nginx-vm`

---

## What I Learned

- **Two-repo separation** enforces clean team boundaries. Infrastructure engineers own provisioning; application engineers own deployments. Neither needs access to the other's codebase.
- **Path triggers** prevent unnecessary pipeline runs. The infra pipeline only fires when Terraform files change.
- **Azure Secure Files** is the correct way to handle SSH keys in a pipeline. The key is encrypted at rest, never visible in logs, and deleted from the agent after use.
- **Multi-stage pipelines with `condition: succeeded()`** create quality gates. A broken build or failed test physically cannot reach production.
- **PM2** is essential for running Node.js apps in production on Linux. It handles crash recovery and VM-reboot persistence automatically.

---

**Tools Used:** Terraform · Ansible · Azure DevOps · Azure VMs · MySQL · PM2 · Nginx · GitHub · SSH · Service Principal
