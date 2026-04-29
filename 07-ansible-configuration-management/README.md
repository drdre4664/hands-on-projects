# Project 07 — Ansible Configuration Management: EpicBook Role-Based Deployment

## What This Project Does

This project demonstrates how to use Ansible to automate the configuration of remote servers and deploy an application — consistently, repeatably, and safely. Without Ansible, setting up multiple servers means SSH-ing into each one and running commands manually, which is error-prone and impossible to scale. Ansible solves this by letting you describe the desired state of your servers in YAML playbooks and then enforcing that state automatically across any number of hosts.

The project uses a **role-based structure** — one of Ansible's most important best practices. Instead of writing one long playbook, the configuration is split into three focused roles: `common` (base server setup), `nginx` (web server installation and configuration), and `epicbook` (application deployment). Each role is self-contained and reusable.

The key principle demonstrated is **idempotency**: running the same playbook twice produces exactly the same result as running it once. The second run makes zero changes — Ansible only acts when something is not already in the desired state.

## Architecture

```
Ansible Control Node (your machine or CI runner)
        |
        |── ansible.cfg        ← tells Ansible where to find inventory and keys
        |── site.yml           ← the master playbook that calls all roles
        |── inventory/
        │     ├── dev          ← list of dev server IPs + variables
        │     └── prod         ← list of prod server IPs + variables
        |
        └── roles/
              ├── common/      ← applied to ALL servers: packages, users, firewall
              ├── nginx/       ← applied to web servers: install, template config, enable
              └── epicbook/    ← applied to web servers: clone repo, npm install, systemd

                    ↓ SSH over port 22 ↓

        [Web Server 1]         [Web Server 2]
        EpicBook + Nginx       EpicBook + Nginx
        (dev environment)      (dev environment)
```

---

## Project Structure

```
07-ansible-configuration-management/
├── site.yml                          # Master playbook
├── ansible.cfg                       # Ansible configuration
├── inventory/
│   ├── dev                           # Dev server list and variables
│   └── prod                          # Prod server list and variables
└── roles/
    ├── common/
    │   └── tasks/main.yml            # System packages, deploy user, UFW firewall
    ├── nginx/
    │   ├── tasks/main.yml            # Install Nginx, deploy config, enable service
    │   ├── handlers/main.yml         # Reload/restart Nginx when config changes
    │   ├── templates/nginx.conf.j2   # Jinja2 template — dynamic config per host
    │   └── defaults/main.yml         # Default variable values
    └── epicbook/
        ├── tasks/main.yml            # Clone repo, npm install, deploy systemd service
        ├── handlers/main.yml         # Restart app when service file changes
        └── defaults/main.yml         # Default repo URL, port, app directory
```

---

## Configuration Files

### ansible.cfg

```ini
[defaults]
inventory        = ./inventory/dev
remote_user      = ubuntu
private_key_file = ~/.ssh/id_rsa
host_key_checking = False
roles_path       = ./roles

[privilege_escalation]
become       = True
become_method = sudo
become_user  = root
```

**Why `become: True`?** Ansible connects as a regular user (`ubuntu`) and then escalates to root with sudo for tasks that require system-level access (installing packages, writing to `/etc/`, managing services). This is more secure than connecting directly as root.

### inventory/dev

```ini
[webservers]
web1 ansible_host=10.0.1.10
web2 ansible_host=10.0.1.11

[appservers]
app1 ansible_host=10.0.2.10
app2 ansible_host=10.0.2.11

[all:vars]
ansible_python_interpreter=/usr/bin/python3
env=dev
```

### site.yml — Master Playbook

```yaml
---
# Play 1: Run the common role on every server in the inventory
- name: Apply base configuration to all servers
  hosts: all
  become: true
  roles:
    - common

# Play 2: Set up Nginx and deploy the app on web servers only
- name: Deploy EpicBook to web servers
  hosts: webservers
  become: true
  roles:
    - nginx
    - epicbook
```

---

## Role Details

### roles/common/tasks/main.yml

```yaml
---
# Update the apt package index — ensures we install the latest versions
- name: Update apt cache
  apt:
    update_cache: yes
    cache_valid_time: 3600   # only update if cache is older than 1 hour
  when: ansible_os_family == "Debian"

# Install a standard set of utilities on every server
- name: Install common system packages
  apt:
    name: [curl, git, vim, htop, unzip, python3-pip]
    state: present             # "present" = install if not already installed (idempotent)

# Create a dedicated non-root deploy user for running the application
- name: Create deploy user
  user:
    name: deploy
    shell: /bin/bash
    groups: sudo
    append: yes
    create_home: yes

# Configure UFW firewall — deny everything by default, then allow only what is needed
- name: Allow SSH through firewall
  ufw:
    rule: allow
    port: "22"
    proto: tcp

- name: Allow HTTP through firewall
  ufw:
    rule: allow
    port: "80"
    proto: tcp

- name: Enable UFW with default deny policy
  ufw:
    state: enabled
    policy: deny
```

### roles/nginx/tasks/main.yml

```yaml
---
- name: Install Nginx
  apt:
    name: nginx
    state: present

# Deploy the virtual host config from a Jinja2 template.
# The template uses variables like ansible_hostname and epicbook_port
# so the config is tailored to each host automatically.
- name: Deploy Nginx virtual host config from template
  template:
    src: nginx.conf.j2
    dest: /etc/nginx/sites-available/epicbook
    mode: '0644'
  notify: Reload Nginx    # only reload Nginx if this task actually changed something

# Create a symlink to enable the site
- name: Enable the epicbook site
  file:
    src: /etc/nginx/sites-available/epicbook
    dest: /etc/nginx/sites-enabled/epicbook
    state: link
  notify: Reload Nginx

# Remove the default Nginx page so our app is what loads on port 80
- name: Remove default Nginx site
  file:
    path: /etc/nginx/sites-enabled/default
    state: absent
  notify: Reload Nginx

- name: Ensure Nginx is started and enabled on boot
  service:
    name: nginx
    state: started
    enabled: yes
```

### roles/nginx/handlers/main.yml

```yaml
---
# Handlers only run if a task that notified them actually made a change.
# If the config file was already correct and unchanged, this handler never runs.
- name: Reload Nginx
  service:
    name: nginx
    state: reloaded

- name: Restart Nginx
  service:
    name: nginx
    state: restarted
```

### roles/nginx/templates/nginx.conf.j2

```jinja2
server {
    listen 80;
    server_name {{ ansible_hostname }};
    # ansible_hostname is a fact Ansible collects automatically from each host

    location / {
        proxy_pass http://127.0.0.1:{{ epicbook_port }};
        # epicbook_port comes from roles/nginx/defaults/main.yml (default: 3000)
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

### roles/epicbook/tasks/main.yml

```yaml
---
- name: Install Node.js and npm
  apt:
    name: [nodejs, npm]
    state: present

- name: Create application directory
  file:
    path: "{{ epicbook_app_dir }}"
    state: directory
    owner: deploy
    group: deploy
    mode: '0755'

# Clone the repository as the deploy user (not root)
- name: Clone EpicBook repository
  git:
    repo: "{{ epicbook_repo_url }}"
    dest: "{{ epicbook_app_dir }}"
    version: "{{ epicbook_branch }}"
    force: yes
  become_user: deploy
  notify: Restart EpicBook   # if code changed, restart the app

- name: Install npm dependencies
  npm:
    path: "{{ epicbook_app_dir }}"
    state: present
  become_user: deploy

# Deploy a systemd unit file so the app starts on boot and restarts on crash
- name: Deploy systemd service file
  template:
    src: epicbook.service.j2
    dest: /etc/systemd/system/epicbook.service
    mode: '0644'
  notify:
    - Reload systemd
    - Restart EpicBook

- name: Ensure EpicBook service is running and enabled on boot
  service:
    name: epicbook
    state: started
    enabled: yes
```

---

## Step-by-Step Deployment

### Step 1 — Test connectivity to all hosts

**Why:** Before running a playbook, verify Ansible can reach all target servers. The `ping` module connects via SSH and returns `pong` — it confirms the connection works and Python is available on the remote host.

```bash
ansible all -m ping
# Expected: web1 | SUCCESS => {"ping": "pong"}
```

### Step 2 — Run a syntax check

**Why:** YAML indentation errors can cause a playbook to fail partway through. The syntax check catches these before any changes are made to any server.

```bash
ansible-playbook site.yml --syntax-check
```

### Step 3 — Do a dry run (check mode)

**Why:** Check mode simulates the playbook without making any changes. It tells you what would be changed on each host, letting you review the impact before committing.

```bash
ansible-playbook site.yml --check
```

### Step 4 — Deploy to the dev environment

```bash
ansible-playbook site.yml -i inventory/dev
```

First run output — everything is new, so many tasks report `changed`:

```
PLAY RECAP:
web1 : ok=18  changed=12  unreachable=0  failed=0
web2 : ok=18  changed=12  unreachable=0  failed=0
```

### Step 5 — Run again to verify idempotency

**Why:** This is the most important verification step. A well-written playbook makes zero changes on a second run — because the system is already in the desired state. If `changed` is non-zero on the second run, it means a task is not idempotent and needs to be fixed.

```bash
ansible-playbook site.yml -i inventory/dev
```

Second run output — idempotency confirmed:

```
PLAY RECAP:
web1 : ok=18  changed=0  unreachable=0  failed=0
web2 : ok=18  changed=0  unreachable=0  failed=0
```

### Step 6 — Deploy to production

```bash
ansible-playbook site.yml -i inventory/prod
# The same playbook runs against a different inventory — no code changes needed
```

---

## What I Learned

- **Idempotency** is Ansible's core value proposition. You can run the same playbook 100 times and the result is always the same. This makes it safe to run in CI/CD pipelines on every deployment.
- **Handlers** prevent unnecessary service restarts. Nginx only reloads if its configuration file actually changed — not on every playbook run.
- **Jinja2 templates** make configuration files dynamic. The same template produces a different Nginx config for each host by substituting in host facts and variables.
- **Role separation** makes configuration manageable. The `common` role runs on every server; `nginx` and `epicbook` only run on web servers. Adding a new server type means creating a new role — not modifying existing ones.
- **Inventory separation** (dev vs prod) means the same playbook can target completely different environments. Promoting a deployment from dev to prod is just changing the `-i` flag.

---

**Tools Used:** Ansible · Nginx · Node.js · systemd · Jinja2 · Ubuntu
