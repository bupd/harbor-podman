**Harbor on Podman**

This document provides a minimal, engineer‑oriented guide to deploy Harbor using Podman and podman‑compose. It covers system preparation, repository setup, configuration, TLS certificate generation and the setup.

## 1. Prerequisites & System Preparation

1. **Update base system**
   ```bash
   sudo -i
   dnf update -y
   ```

2. **Enable EPEL and install dependencies**
   ```bash
   dnf install -y epel-release
   dnf install -y \
     podman podman-docker buildah podman-compose \
     python3-pip wget tar gzip git \
     policycoreutils-python-utils
   ```

3. **Configure Podman**
   - Basic settings
   ```bash
   systemctl enable --now podman.socket
   # sed -i 's/unqualified-search-registries = \["registry.access.redhat.com", "registry.redhat.io", "docker.io"\]/unqualified-search-registries = ["docker.io"]/g' /etc/containers/registries.conf
   ```
   Allow containers to manage cgroups:
   ```bash
   setsebool -P container_manage_cgroup true
   ```

4. **Clone your Git repository**
   ```bash
   cd /opt
   git clone https://github.com/bupd/harbor-podman.git
   ```

5. **SELinux configuration**
   Set the correct label on persistent data directory:
   ```bash
   semanage fcontext -a -t svirt_sandbox_file_t ".(/.*)?"
   restorecon -R .
   ```

5. **Firewall (firewalld)**
   ```bash
   sudo firewall-cmd --add-port=443/tcp
   sudo firewall-cmd --add-port=443/tcp --permanent
   ```
## 3. TLS Certificate Generation

Generate a self‑signed certificate valid for 10 years:
```bash
mkdir -p ./cert
openssl req -newkey rsa:4096 -nodes -x509 -days 3650 \
  -subj "/C=CH/ST=Bern/L=Bern/O=bupd.xyz/CN=harbor.bupd.xyz" \
  -keyout ./cert/harbor.key \
  -out    ./cert/harbor.crt
```

Apply ownership:
```bash
chown -R 1000:1000 .
```

## 4. Prepare harbor.yml and set passwords

   - Copy template:
     ```bash
     cd .
     cp harbor.yml.tmpl harbor.yml
     ```
   - Update Harbor hostname:
     ```bash
     sed -i 's|^hostname:.*|hostname: 192.168.0.4|' harbor.yml
     ```
   - Generate random passwords for admin and database:
     ```bash
     sed -i "s|^harbor_admin_password:.*|harbor_admin_password: \"$(openssl rand -base64 30)\"|" harbor.yml
     sed -i "/^database:/ { n; n; s|^  password:.*|  password: \"$(openssl rand -base64 30)\"| }" harbor.yml
     ```

## 5. Run the modified Installer for Podman

1. **Run it with or without included trivy-setup**
   ```bash
   ./install.sh --with-trivy
   ```

2. **Verify**
   ```bash
   podman ps -a
   podman logs harbor-core
   ```

## Detailed Explanation of Key Adjustments here

- **`container_manage_cgroup`**: Allows Podman to manage cgroups under SELinux enforcement.
- **SELinux file context**: The `svirt_sandbox_file_t` label authorizes container runtimes to read/write the data directory.
- **Password randomization**: Avoids default weak credentials; injected via `openssl rand -base64`.
- **Installer script**:
  - Removed Docker/docker-compose checks to prevent hard failures under Podman.
  - Overrode `DOCKER_COMPOSE` to invoke `podman-compose` transparently.
- **Compose file tweaks**:
  - Stripped repetitive `logging` blocks to maintain podman compatibility.
  - Explicit `networks` stanza ensures containers attach to the correct overlay.

