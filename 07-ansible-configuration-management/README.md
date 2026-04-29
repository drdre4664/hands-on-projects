# Ansible Configuration Management — EpicBook Role-Based Deployment

## Overview

Automated the configuration and deployment of the EpicBook application across multiple environments using Ansible roles. Implemented a structured role-based approach with reusable roles for common system configuration, Nginx web server setup, and EpicBook application deployment. Demonstrated idempotency by verifying zero changes on re-run.

## Architecture

```
Ansible Control Node
        |
        |— inventory/
        |     ├── dev
        |     └── prod
        |
        |— roles/
        |     ├── common/       (system deps, users, firewall)
        |     ├── nginx/        (install, configure, enable)
        |     └── epicbook/     (clone, install, service)
        |
        └— site.yml  ——>  [Web Server 1]  [Web Server 2]
                               |                |
                          [EpicBook App]  [EpicBook App]
                               |                |
                          [Nginx Proxy]  [Nginx Proxy]
```

## Assignment Objectives

- Create Ansible roles: common, nginx, epicbook
- Use Jinja2 templates for Nginx virtual host configuration
- Implement handlers to restart Nginx only when config changes
- Use variables and defaults for environment-specific configuration
- Deploy EpicBook app with proper service management
- Verify idempotency: re-running the playbook shows changed=0

## Project Structure

```
07-ansible-configuration-management/
├── site.yml
├── ansible.cfg
├── inventory/
│   ├── dev
│   └── prod
└── roles/
    ├── common/
    │   ├── tasks/
    │   │   └── main.yml
    │   └── vars/
    │       └── main.yml
    ├── nginx/
    │   ├── tasks/
    │   │   └── main.yml
    │   ├── handlers/
    │   │   └── main.yml
    │   ├── templates/
    │   │   └── nginx.conf.j2
    │   └── defaults/
    │       └── main.yml
    └── epicbook/
        ├── tasks/
        │   └── main.yml
        ├── handlers/
        │   └── main.yml
        └── defaults/
            └── main.yml
```

## Ansible Configuration

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

### site.yml

```yaml
---
- name: Configure all servers
  hosts: all
  become: true
  roles:
    - common

- name: Configure web servers with Nginx and EpicBook
  hosts: webservers
  become: true
  roles:
    - nginx
    - epicbook
```

### roles/common/tasks/main.yml

```yaml
---
- name: Update apt cache
  apt:
    update_cache: yes
    cache_valid_time: 3600
  when: ansible_os_family == "Debian"

- name: Install common dependencies
  apt:
    name:
      - curl
      - git
      - vim
      - htop
      - unzip
      - python3-pip
    state: present

- name: Create deploy user
  user:
    name: deploy
    shell: /bin/bash
    groups: sudo
    append: yes
    create_home: yes

- name: Set timezone to UTC
  timezone:
    name: UTC

- name: Configure UFW — allow SSH
  ufw:
    rule: allow
    port: "22"
    proto: tcp

- name: Configure UFW — allow HTTP
  ufw:
    rule: allow
    port: "80"
    proto: tcp

- name: Enable UFW
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
    update_cache: yes

- name: Deploy Nginx virtual host config from Jinja2 template
  template:
    src: nginx.conf.j2
    dest: /etc/nginx/sites-available/epicbook
    owner: root
    group: root
    mode: '0644'
  notify: Reload Nginx

- name: Enable site — symlink to sites-enabled
  file:
    src: /etc/nginx/sites-available/epicbook
    dest: /etc/nginx/sites-enabled/epicbook
    state: link
  notify: Reload Nginx

- name: Remove default Nginx site
  file:
    path: /etc/nginx/sites-enabled/default
    state: absent
  notify: Reload Nginx

- name: Ensure Nginx is started and enabled
  service:
    name: nginx
    state: started
    enabled: yes
```

### roles/nginx/handlers/main.yml

```yaml
---
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

    location / {
        proxy_pass http://127.0.0.1:{{ epicbook_port }};
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_cache_bypass $http_upgrade;
    }

    access_log /var/log/nginx/epicbook_access.log;
    error_log  /var/log/nginx/epicbook_error.log;
}
```

### roles/nginx/defaults/main.yml

```yaml
---
epicbook_port: 3000
nginx_worker_processes: auto
```

### roles/epicbook/tasks/main.yml

```yaml
---
- name: Install Node.js and npm
  apt:
    name:
      - nodejs
      - npm
    state: present

- name: Create app directory
  file:
    path: "{{ epicbook_app_dir }}"
    state: directory
    owner: deploy
    group: deploy
    mode: '0755'

- name: Clone EpicBook repository
  git:
    repo: "{{ epicbook_repo_url }}"
    dest: "{{ epicbook_app_dir }}"
    version: "{{ epicbook_branch }}"
    force: yes
  become_user: deploy
  notify: Restart EpicBook

- name: Install npm dependencies
  npm:
    path: "{{ epicbook_app_dir }}"
    state: present
  become_user: deploy

- name: Deploy systemd service file
  template:
    src: epicbook.service.j2
    dest: /etc/systemd/system/epicbook.service
    mode: '0644'
  notify:
    - Reload systemd
    - Restart EpicBook

- name: Ensure EpicBook service is started and enabled
  service:
    name: epicbook
    state: started
    enabled: yes
```

### roles/epicbook/handlers/main.yml

```yaml
---
- name: Restart EpicBook
  service:
    name: epicbook
    state: restarted

- name: Reload systemd
  systemd:
    daemon_reload: yes
```

### roles/epicbook/defaults/main.yml

```yaml
---
epicbook_repo_url: "https://github.com/pravinmishraaws/epicbook.git"
epicbook_branch: "main"
epicbook_app_dir: "/opt/epicbook"
epicbook_port: 3000
epicbook_env: "production"
```

## Deployment Steps

```bash
# 1. Test connectivity
ansible all -m ping

# 2. Syntax check
ansible-playbook site.yml --syntax-check

# 3. Dry run
ansible-playbook site.yml --check

# 4. Deploy to dev
ansible-playbook site.yml -i inventory/dev

# First run output:
# web1 : ok=18  changed=12  unreachable=0  failed=0
# web2 : ok=18  changed=12  unreachable=0  failed=0

# 5. Verify idempotency — run again
ansible-playbook site.yml -i inventory/dev

# Second run (idempotency confirmed):
# web1 : ok=18  changed=0   unreachable=0  failed=0
# web2 : ok=18  changed=0   unreachable=0  failed=0

# 6. Deploy to production
ansible-playbook site.yml -i inventory/prod

# 7. Run specific tags
ansible-playbook site.yml --tags nginx
ansible-playbook site.yml --tags epicbook

# 8. Ad-hoc checks
ansible webservers -m service -a "name=nginx state=status"
ansible all -m shell -a "systemctl status epicbook"
```

## Key Concepts Demonstrated

- **Role-Based Structure** — Reusable roles: common, nginx, epicbook
- **Jinja2 Templates** — Dynamic Nginx config generated per host using variables
- **Handlers** — Nginx reloads only when configuration actually changes
- **Idempotency** — Re-running produces zero changes (changed=0)
- **Variables & Defaults** — Environment-specific values via defaults and inventory
- **Service Management** — systemd service managed by Ansible
- **Privilege Escalation** — become: true for system-level tasks
- **Multi-Environment** — Separate dev and prod inventories

---

**Tools:** Ansible · Nginx · Node.js · systemd · Jinja2 · Ubuntu
