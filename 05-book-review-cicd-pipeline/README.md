# Book Review App — Full CI/CD Pipeline

Production-grade two-repository CI/CD architecture using Terraform,
Ansible, and Azure DevOps pipelines. Separates infrastructure and
application concerns — reflecting how platform and application teams
operate in professional engineering organisations.

## Architecture
```
book-review-infra (repo)             book-review-app (repo)
──────────────────────────           ──────────────────────────
Azure DevOps Pipeline                Azure DevOps Pipeline
        ↓                                    ↓
  Terraform apply                      Ansible deploy
        ↓                                    ↓
  Azure VMs + MySQL  ── IPs ──→   Frontend VM + Backend VM
                                      (PM2 process manager)
```

## Team Responsibility Split

| Role | Repository | Owns |
|---|---|---|
| Platform/Infra Team | `book-review-infra` | Terraform, Azure provisioning |
| App/Dev Team | `book-review-app` | Application code, Ansible deployment |
| DevOps Engineer | Both | Pipelines, secrets, service connections |

---

## Phase 1 — Infrastructure (book-review-infra)

### What Terraform provisions
- Frontend Azure VM (Ubuntu)
- Backend Azure VM (Ubuntu)
- Azure MySQL Database
- Networking, public IPs, NSG rules

### Infra pipeline (azure-pipelines.yml)
```yaml
trigger:
  paths:
    include:
      - terraform/*

steps:
  - task: TerraformInstaller@0
    inputs:
      terraformVersion: 'latest'

  - task: TerraformTaskV2@2
    inputs:
      provider: 'azurerm'
      command: 'init'
      backendServiceArm: '<service-connection>'

  - task: TerraformTaskV2@2
    inputs:
      provider: 'azurerm'
      command: 'apply'
      environmentServiceNameAzureRM: '<service-connection>'
```

Pipeline triggers ONLY when files inside `terraform/` change.

### Setting up the infra pipeline in Azure DevOps
1. Pipelines → New Pipeline → GitHub (YAML)
2. Select repo: `book-review-infra`
3. Choose: "Existing Azure Pipelines YAML file"
4. Path: `azure-pipelines.yaml`
5. Click Run — Terraform provisions all Azure resources

---

## Phase 2 — Manual IP Handoff

After Terraform applies, VM public IPs are copied from pipeline logs
into the Ansible inventory files (deliberate team boundary):
```ini
# ansible/inventory.ini
[frontend]
<frontend-vm-public-ip>

[backend]
<backend-vm-public-ip>
```
```yaml
# ansible/group_vars/backend.yaml
db_host: <mysql-host>
db_name: bookreviews
db_user: appuser
db_password: "{{ vault_db_password }}"
```

---

## Phase 3 — Application Deployment (book-review-app)

### What Ansible deploys
- Backend: pulls code, installs Node deps, configures MySQL, starts with PM2
- Frontend: pulls code, installs deps, builds Next.js, starts with PM2

### App pipeline (azure-pipelines.yml)
```yaml
trigger:
  branches:
    include:
      - main

steps:
  - script: pip install ansible

  - task: DownloadSecureFile@1
    name: sshKey
    inputs:
      secureFile: 'id_rsa'

  - script: |
      chmod 600 $(sshKey.secureFilePath)
      ansible-playbook -i ansible/inventory.ini \
        ansible/deploy.yml \
        --private-key $(sshKey.secureFilePath) \
        -e "ansible_ssh_common_args='-o StrictHostKeyChecking=no'"
    displayName: 'Deploy with Ansible'
```

Every push to `main` triggers a full redeploy of frontend + backend.

---

## Phase 4 — CI/CD Lab: Static HTML Deploy via Azure Pipelines

Before the full pipeline, a guided lab deployed a static HTML page
to a VM running Nginx — demonstrating the fundamentals of pipeline-triggered
deployments.
```yaml
trigger:
  - main

pool:
  name: "self-hosted-agent-pool"

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

          - task: CopyFilesOverSSH@0
            inputs:
              sshEndpoint: '$(sshService)'
              sourceFolder: '$(Build.SourcesDirectory)'
              contents: 'index.html'
              targetFolder: '$(webRoot)'

          - task: SSH@0
            inputs:
              sshEndpoint: '$(sshService)'
              runOptions: 'inline'
              inline: sudo systemctl restart nginx
```

## Phase 5 — CI/CD Lab: React App Deployment with Build + Test + Deploy Stages

Three-stage pipeline: Build → Test → Deploy (deploy only if tests pass).
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
          - task: PublishBuildArtifacts@1
            inputs:
              pathToPublish: 'build'
              artifactName: '$(artifactName)'

  - stage: TestReactApp
    dependsOn: BuildReactApp
    condition: succeeded()
    jobs:
      - job: Test
        steps:
          - task: NodeTool@0
            inputs:
              versionSpec: '20.x'
          - script: npm install
          - script: npm run test -- --watchAll=false

  - stage: DeployToVM
    dependsOn: TestReactApp
    condition: succeeded()
    jobs:
      - job: Deploy
        steps:
          - task: DownloadBuildArtifacts@0
            inputs:
              artifactName: '$(artifactName)'
              downloadPath: '$(Pipeline.Workspace)'

          - task: CopyFilesOverSSH@0
            inputs:
              sshEndpoint: '$(sshService)'
              sourceFolder: '$(Pipeline.Workspace)/$(artifactName)'
              contents: '**'
              targetFolder: '$(webRoot)'

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
```

---

## Security Practices Applied

| Secret | Where Stored |
|---|---|
| SSH private key | Azure DevOps Library → Secure File |
| SSH public key | Azure DevOps Library → Secure File |
| Azure credentials | Service Principal via DevOps Service Connection |
| DB passwords | Azure DevOps pipeline variables (marked secret) |

Nothing sensitive is ever committed to source control.

## Prerequisites Setup

### Create a Service Principal in Azure
```bash
az ad sp create-for-rbac \
  --name "devops-sp" \
  --role Contributor \
  --scopes /subscriptions/<subscription-id>/resourceGroups/<rg-name>
```

### Register in Azure DevOps
Project Settings → Service Connections → New → Azure Resource Manager
→ Service Principal (automatic)

### Upload SSH keys to Azure DevOps Library
Pipelines → Library → Secure Files → Upload `id_rsa` and `id_rsa.pub`

### Create SSH Service Connection (for VM access)
Project Settings → Service Connections → New → SSH
- Host: VM public IP
- Port: 22
- Username: azureuser
- Password: VM password
- Name: ssh-to-nginx-vm

## Key Concepts Demonstrated

- Two-repo architecture separating infra and application pipelines
- Terraform for full Azure infrastructure provisioning from code
- Ansible for repeatable, idempotent application deployment
- Azure DevOps YAML pipelines with GitHub branch triggers
- Multi-stage pipelines: Build → Test → Deploy (gate on test pass)
- Secure File and secret variable management
- PM2 for production Node.js process management on Linux
- Deliberate manual IP handoff modelling real team boundaries

## Tools

`Terraform` `Ansible` `Azure DevOps` `Azure VMs` `MySQL` `PM2` `Nginx` `GitHub` `SSH` `Service Principal`
