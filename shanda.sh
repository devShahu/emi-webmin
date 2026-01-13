#!/bin/bash
# ═══════════════════════════════════════════════════════════════════
#  ███████╗██╗  ██╗ █████╗ ███╗   ██╗██████╗  █████╗ 
#  ██╔════╝██║  ██║██╔══██╗████╗  ██║██╔══██╗██╔══██╗
#  ███████╗███████║███████║██╔██╗ ██║██║  ██║███████║
#  ╚════██║██╔══██║██╔══██║██║╚██╗██║██║  ██║██╔══██║
#  ███████║██║  ██║██║  ██║██║ ╚████║██████╔╝██║  ██║
#  ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═════╝ ╚═╝  ╚═╝
#
#  Universal VM Bootstrapper - Public Internet Ready
#  Version: 3.0.0
#  Made with ❤️ by Shahriar (Shanda Bhai 💖)
# ═══════════════════════════════════════════════════════════════════

set -e

VERSION="3.0.0"
CONFIG_FILE="/etc/shanda/config.env"
STATE_FILE="/etc/shanda/state.json"
MONITOR_PID_FILE="/var/run/shanda-monitor.pid"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Logging
log_info() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_step() { echo -e "${CYAN}[→]${NC} $1"; }
log_input() { echo -e "${PURPLE}[?]${NC} $1"; }

# Banner
show_banner() {
    clear
    echo -e "${CYAN}"
    cat << 'EOF'
  ███████╗██╗  ██╗ █████╗ ███╗   ██╗██████╗  █████╗ 
  ██╔════╝██║  ██║██╔══██╗████╗  ██║██╔══██╗██╔══██╗
  ███████╗███████║███████║██╔██╗ ██║██║  ██║███████║
  ╚════██║██╔══██║██╔══██║██║╚██╗██║██║  ██║██╔══██║
  ███████║██║  ██║██║  ██║██║ ╚████║██████╔╝██║  ██║
  ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═════╝ ╚═╝  ╚═╝
EOF
    echo -e "${NC}"
    echo -e "         ${WHITE}Universal VM Bootstrapper v${VERSION}${NC}"
    echo -e "         ${PURPLE}Made with ❤️  by Shahriar (Shanda Bhai 💖)${NC}"
    echo ""
}

# Load config if exists
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        return 0
    fi
    return 1
}

# Save config
save_config() {
    mkdir -p /etc/shanda
    cat > "$CONFIG_FILE" << EOF
# Shanda Configuration - Auto-generated
VM_HOSTNAME="$VM_HOSTNAME"
VM_USERNAME="$VM_USERNAME"
VM_PASSWORD="$VM_PASSWORD"
VM_CPUS="$VM_CPUS"
VM_RAM="$VM_RAM"
VM_DISK_GB="$VM_DISK_GB"
STORAGE_DISK="$STORAGE_DISK"
STORAGE_PARTITION="$STORAGE_PARTITION"
MOUNT_POINT="$MOUNT_POINT"
SSH_PORT="$SSH_PORT"
HTTP_PORT="$HTTP_PORT"
HTTPS_PORT="$HTTPS_PORT"
TUNNEL_TYPE="$TUNNEL_TYPE"
VM_DISK_PATH="$VM_DISK_PATH"
CLOUD_INIT_ISO="$CLOUD_INIT_ISO"
CLOUDFLARE_TUNNEL_TOKEN="$CLOUDFLARE_TUNNEL_TOKEN"
PUBLIC_URL="$PUBLIC_URL"
EOF
}

# Auto-detect best available disk
auto_detect_disk() {
    # Find largest unmounted disk
    BEST_DISK=$(lsblk -ndo NAME,SIZE,TYPE,MOUNTPOINT | \
        grep "disk" | \
        grep -v "loop" | \
        awk '$4=="" {print $1, $2}' | \
        sort -k2 -hr | \
        head -1 | \
        awk '{print $1}')
    
    if [ -z "$BEST_DISK" ]; then
        BEST_DISK="sdb"
    fi
    
    echo "$BEST_DISK"
}

# Simple input with default
simple_input() {
    local prompt="$1"
    local var_name="$2"
    local default="$3"
    
    read -p "$(echo -e "${PURPLE}[?]${NC} $prompt ${YELLOW}[$default]${NC}: ")" input
    input="${input:-$default}"
    eval "$var_name='$input'"
}

# Quick setup (minimal questions)
quick_setup() {
    log_step "Quick Setup - Just the essentials"
    echo ""
    
    simple_input "VM Username" VM_USERNAME "ubuntu"
    simple_input "VM Password" VM_PASSWORD "shanda123"
    simple_input "SSH Port (forwarded)" SSH_PORT "2223"
    
    # Auto-detect disk
    STORAGE_DISK=$(auto_detect_disk)
    STORAGE_PARTITION="${STORAGE_DISK}1"
    
    # Smart defaults
    VM_HOSTNAME="shanda-vm"
    VM_CPUS="2"
    VM_RAM="4096"
    VM_DISK_GB="100"
    MOUNT_POINT="/mnt/shanda"
    HTTP_PORT="8080"
    HTTPS_PORT="8443"
    VM_DISK_PATH="${MOUNT_POINT}/${VM_HOSTNAME}.qcow2"
    CLOUD_INIT_ISO="${MOUNT_POINT}/cloud-init.iso"
    
    # Public access
    echo ""
    log_step "Public Internet Access Options:"
    echo "  1) Tailscale (Recommended - Easy & Secure)"
    echo "  2) Cloudflare Tunnel (Advanced - Custom Domain)"
    echo "  3) LocalTunnel (Quick - Temporary URL)"
    echo "  4) None (Local only)"
    
    simple_input "Choose tunnel type" TUNNEL_CHOICE "1"
    
    case "$TUNNEL_CHOICE" in
        1) TUNNEL_TYPE="tailscale" ;;
        2) TUNNEL_TYPE="cloudflare" ;;
        3) TUNNEL_TYPE="localtunnel" ;;
        *) TUNNEL_TYPE="none" ;;
    esac
    
    log_info "Using disk: /dev/$STORAGE_DISK (auto-detected)"
    log_info "VM will have: ${VM_CPUS} CPUs, $((VM_RAM/1024))GB RAM, ${VM_DISK_GB}GB disk"
    
    save_config
}

# Install all dependencies
install_dependencies() {
    log_step "Installing dependencies..."
    
    export DEBIAN_FRONTEND=noninteractive
    
    # Core packages
    apt-get update -qq > /dev/null 2>&1
    apt-get install -y -qq \
        qemu-system-x86 \
        qemu-kvm \
        qemu-utils \
        cloud-image-utils \
        wget \
        curl \
        screen \
        jq \
        netcat-openbsd \
        openssh-server \
        iptables \
        vim \
        htop \
        net-tools \
        > /dev/null 2>&1
    
    log_info "Core packages installed"
    
    # Tunnel-specific packages
    case "$TUNNEL_TYPE" in
        tailscale)
            if ! command -v tailscale &> /dev/null; then
                log_step "Installing Tailscale..."
                curl -fsSL https://tailscale.com/install.sh | sh > /dev/null 2>&1
                log_info "Tailscale installed"
            fi
            ;;
        cloudflare)
            if ! command -v cloudflared &> /dev/null; then
                log_step "Installing Cloudflare Tunnel..."
                wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
                dpkg -i cloudflared-linux-amd64.deb > /dev/null 2>&1
                rm cloudflared-linux-amd64.deb
                log_info "Cloudflare Tunnel installed"
            fi
            ;;
        localtunnel)
            if ! command -v lt &> /dev/null; then
                log_step "Installing LocalTunnel..."
                curl -fsSL https://deb.nodesource.com/setup_20.x | bash - > /dev/null 2>&1
                apt-get install -y -qq nodejs > /dev/null 2>&1
                npm install -g localtunnel > /dev/null 2>&1
                log_info "LocalTunnel installed"
            fi
            ;;
    esac
}

# Setup storage
setup_storage() {
    log_step "Setting up storage on /dev/${STORAGE_PARTITION}..."
    
    if ! blkid "/dev/${STORAGE_PARTITION}" | grep -q ext4; then
        mkfs.ext4 -F "/dev/${STORAGE_PARTITION}" > /dev/null 2>&1
    fi
    
    mkdir -p "$MOUNT_POINT"
    if ! mountpoint -q "$MOUNT_POINT"; then
        mount "/dev/${STORAGE_PARTITION}" "$MOUNT_POINT"
    fi
    
    if ! grep -q "${STORAGE_PARTITION}" /etc/fstab; then
        echo "/dev/${STORAGE_PARTITION} $MOUNT_POINT ext4 defaults 0 2" >> /etc/fstab
    fi
    
    log_info "Storage ready: $(df -h $MOUNT_POINT | tail -1 | awk '{print $4}') free"
}

# Download Ubuntu cloud image
download_image() {
    log_step "Downloading Ubuntu cloud image..."
    
    IMAGE_FILE="$MOUNT_POINT/ubuntu-24.04-cloudimg.img"
    
    if [ -f "$IMAGE_FILE" ]; then
        log_info "Image already exists"
        return
    fi
    
    wget -q --show-progress \
        -O "$IMAGE_FILE" \
        "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img"
    
    log_info "Image downloaded"
}

# Create VM disk
create_vm_disk() {
    log_step "Creating VM disk..."
    
    if [ -f "$VM_DISK_PATH" ]; then
        log_warn "VM disk exists, skipping"
        return
    fi
    
    IMAGE_FILE="$MOUNT_POINT/ubuntu-24.04-cloudimg.img"
    qemu-img convert -f qcow2 -O qcow2 "$IMAGE_FILE" "$VM_DISK_PATH" > /dev/null 2>&1
    qemu-img resize "$VM_DISK_PATH" "${VM_DISK_GB}G" > /dev/null 2>&1
    
    log_info "VM disk created (${VM_DISK_GB}GB)"
}

# Create cloud-init with SSH and tunnel setup
create_cloud_init() {
    log_step "Configuring cloud-init..."
    
    CLOUD_INIT_DIR="$MOUNT_POINT/cloud-init"
    mkdir -p "$CLOUD_INIT_DIR"
    
    PASS_HASH=$(openssl passwd -6 -salt saltsalt "$VM_PASSWORD")
    
    # Tunnel-specific setup
    case "$TUNNEL_TYPE" in
        tailscale)
            TUNNEL_SETUP="  - curl -fsSL https://tailscale.com/install.sh | sh
  - tailscale up --authkey=\${TAILSCALE_KEY:-} --ssh --hostname=${VM_HOSTNAME}
  - TAILSCALE_IP=\$(tailscale ip -4)
  - echo \"Tailscale IP: \$TAILSCALE_IP\" > /root/public-access.txt
  - echo \"SSH: ssh ${VM_USERNAME}@\$TAILSCALE_IP\" >> /root/public-access.txt"
            ;;
        cloudflare)
            TUNNEL_SETUP="  - wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
  - dpkg -i cloudflared-linux-amd64.deb
  - cloudflared tunnel --url ssh://localhost:22 --no-autoupdate > /root/cloudflare-url.txt 2>&1 &"
            ;;
        localtunnel)
            TUNNEL_SETUP="  - curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  - apt-get install -y nodejs
  - npm install -g localtunnel
  - nohup lt --port 22 --subdomain ${VM_HOSTNAME} > /root/localtunnel-url.txt 2>&1 &
  - sleep 5
  - grep -oP 'https://[^\\s]+' /root/localtunnel-url.txt > /root/public-access.txt || echo 'Check /root/localtunnel-url.txt' > /root/public-access.txt"
            ;;
        *)
            TUNNEL_SETUP="  - echo 'No public tunnel configured' > /root/public-access.txt
  - echo 'Local access only: ssh ${VM_USERNAME}@localhost -p ${SSH_PORT}' >> /root/public-access.txt"
            ;;
    esac
    
    cat > "$CLOUD_INIT_DIR/user-data" << EOF
#cloud-config
hostname: ${VM_HOSTNAME}
fqdn: ${VM_HOSTNAME}.local

users:
  - name: ${VM_USERNAME}
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: users, admin, sudo
    shell: /bin/bash
    lock_passwd: false
    passwd: ${PASS_HASH}

package_update: true
packages:
  - openssh-server
  - curl
  - wget
  - vim
  - htop
  - net-tools
  - iptables
  - git
  - tmux
  - build-essential

runcmd:
  - systemctl enable ssh
  - systemctl start ssh
  - sed -i 's/.*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
  - sed -i 's/.*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
  - sed -i 's/.*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
  - systemctl restart ssh
  - echo '${VM_USERNAME}:${VM_PASSWORD}' | chpasswd
  - echo 'root:${VM_PASSWORD}' | chpasswd
${TUNNEL_SETUP}
  - echo '====== VM READY ======' > /root/ready.txt
  - echo 'Hostname: ${VM_HOSTNAME}' >> /root/ready.txt
  - echo 'Username: ${VM_USERNAME}' >> /root/ready.txt
  - echo 'Password: ${VM_PASSWORD}' >> /root/ready.txt
  - wall 'Shanda VM is ready! Check /root/public-access.txt for connection info'

ssh_pwauth: true
disable_root: false
EOF

    cat > "$CLOUD_INIT_DIR/meta-data" << EOF
instance-id: ${VM_HOSTNAME}
local-hostname: ${VM_HOSTNAME}
EOF

    cloud-localds "$CLOUD_INIT_ISO" \
        "$CLOUD_INIT_DIR/user-data" \
        "$CLOUD_INIT_DIR/meta-data" \
        > /dev/null 2>&1
    
    log_info "Cloud-init configured with SSH + ${TUNNEL_TYPE} tunnel"
}

# Create VM start script
create_start_script() {
    log_step "Creating VM startup script..."
    
    cat > /usr/local/bin/shanda-vm << 'EOF'
#!/bin/bash
# Shanda VM Runner

CONFIG_FILE="/etc/shanda/config.env"
source "$CONFIG_FILE"

# Kill existing
pkill -9 qemu-system-x86_64 2>/dev/null || true
sleep 2

# Ensure storage mounted
if ! mountpoint -q "$MOUNT_POINT"; then
    mount "/dev/$STORAGE_PARTITION" "$MOUNT_POINT" 2>/dev/null || true
fi

# Check if VM disk exists
if [ ! -f "$VM_DISK_PATH" ]; then
    echo "[✗] VM disk not found: $VM_DISK_PATH"
    exit 1
fi

# Start VM
nohup qemu-system-x86_64 \
    -name "$VM_HOSTNAME" \
    -machine type=q35,accel=kvm \
    -cpu host \
    -smp "$VM_CPUS" \
    -m "$VM_RAM" \
    -drive file="$VM_DISK_PATH",format=qcow2,if=virtio \
    -drive file="$CLOUD_INIT_ISO",format=raw,if=virtio \
    -device virtio-net-pci,netdev=net0 \
    -netdev user,id=net0,hostfwd=tcp::${SSH_PORT}-:22,hostfwd=tcp::${HTTP_PORT}-:80,hostfwd=tcp::${HTTPS_PORT}-:443 \
    -nographic \
    > /var/log/shanda-vm.log 2>&1 &

VM_PID=$!
echo $VM_PID > /var/run/shanda-vm.pid

sleep 3
if ps -p $VM_PID > /dev/null; then
    echo "[✓] VM started (PID: $VM_PID)"
else
    echo "[✗] VM failed to start"
    tail /var/log/shanda-vm.log
    exit 1
fi
EOF

    chmod +x /usr/local/bin/shanda-vm
    log_info "VM runner created"
}

# Create eternal monitor
create_monitor() {
    log_step "Creating eternal monitor..."
    
    cat > /usr/local/bin/shanda-monitor << 'EOF'
#!/bin/bash
# Shanda Eternal Monitor - Maximum Persistence

CONFIG_FILE="/etc/shanda/config.env"
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/shanda-monitor.log
}

# Ensure storage is mounted
ensure_storage() {
    if [ -n "$MOUNT_POINT" ] && [ -n "$STORAGE_PARTITION" ]; then
        if ! mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
            log "Mounting storage..."
            mkdir -p "$MOUNT_POINT"
            mount "/dev/$STORAGE_PARTITION" "$MOUNT_POINT" 2>/dev/null && log "Storage mounted"
        fi
    fi
}

# Main monitoring loop
while true; do
    ensure_storage
    
    # Check if VM process exists
    if [ -f /var/run/shanda-vm.pid ]; then
        VM_PID=$(cat /var/run/shanda-vm.pid)
        if ! ps -p "$VM_PID" > /dev/null 2>&1; then
            log "VM died (PID: $VM_PID), restarting..."
            /usr/local/bin/shanda-vm 2>&1 | logger -t shanda-vm
            sleep 5
        fi
    else
        # No PID file, check if QEMU is actually running
        if ! pgrep -f "qemu-system-x86_64.*$VM_HOSTNAME" > /dev/null 2>&1; then
            log "No VM running, starting..."
            /usr/local/bin/shanda-vm 2>&1 | logger -t shanda-vm
            sleep 5
        fi
    fi
    
    # Check every 30 seconds
    sleep 30
done
EOF

    chmod +x /usr/local/bin/shanda-monitor
    
    # Also create a systemd-independent monitor launcher
    cat > /usr/local/bin/shanda-monitor-launcher << 'EOF'
#!/bin/bash
# Launch monitor only if not already running
if ! pgrep -f shanda-monitor > /dev/null; then
    nohup /usr/local/bin/shanda-monitor > /dev/null 2>&1 &
    echo $! > /var/run/shanda-monitor.pid
fi
EOF
    
    chmod +x /usr/local/bin/shanda-monitor-launcher
    
    log_info "Monitor created with auto-recovery"
}

# Create boot autostart
create_autostart() {
    log_step "Configuring boot autostart..."
    
    # Multiple autostart methods for maximum persistence
    
    # 1. Cron-based autostart
    CRON_JOB="@reboot sleep 10 && /usr/local/bin/shanda-vm"
    (crontab -l 2>/dev/null | grep -v shanda-vm; echo "$CRON_JOB") | crontab -
    
    MONITOR_CRON="@reboot sleep 15 && nohup /usr/local/bin/shanda-monitor > /dev/null 2>&1 &"
    (crontab -l 2>/dev/null | grep -v shanda-monitor; echo "$MONITOR_CRON") | crontab -
    
    # 2. Create persistent startup in multiple shell profiles
    STARTUP_CMD="/usr/local/bin/shanda-vm 2>/dev/null &"
    MONITOR_CMD="pgrep -f shanda-monitor > /dev/null || nohup /usr/local/bin/shanda-monitor > /dev/null 2>&1 &"
    
    for profile in /root/.bashrc /root/.profile /etc/profile; do
        if [ -f "$profile" ]; then
            grep -q "shanda-vm" "$profile" || echo "$STARTUP_CMD" >> "$profile"
            grep -q "shanda-monitor" "$profile" || echo "$MONITOR_CMD" >> "$profile"
        fi
    done
    
    # 3. Create rc.local style startup (if exists)
    if [ -f /etc/rc.local ]; then
        grep -q "shanda-vm" /etc/rc.local || sed -i '/exit 0/i /usr/local/bin/shanda-vm &' /etc/rc.local
    else
        cat > /etc/rc.local << 'RCLOCAL'
#!/bin/bash
/usr/local/bin/shanda-vm &
exit 0
RCLOCAL
        chmod +x /etc/rc.local
    fi
    
    # 4. Persist VM disk to storage that survives restarts
    echo "$MOUNT_POINT" > /etc/shanda/persist-path.txt
    
    # 5. Create health check that starts VM if missing (every minute via cron)
    HEALTH_CRON="* * * * * pgrep -f qemu-system-x86_64 > /dev/null || /usr/local/bin/shanda-vm 2>&1 | logger -t shanda"
    (crontab -l 2>/dev/null | grep -v "pgrep -f qemu"; echo "$HEALTH_CRON") | crontab -
    
    log_info "Multi-layer autostart configured"
    log_warn "Note: VM stops when Codespaces container stops (limitation of containers)"
    log_info "VM will auto-restart when Codespaces restarts"
}

# Create management CLI
create_cli() {
    cat > /usr/local/bin/shanda << 'CLIMAIN'
#!/bin/bash

CONFIG_FILE="/etc/shanda/config.env"
VERSION="3.0.0"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        return 0
    fi
    echo -e "${RED}[✗]${NC} Shanda not installed. Run: sudo shanda install"
    exit 1
}

cmd_status() {
    load_config
    
    echo -e "${CYAN}═══ Shanda Status ═══${NC}"
    
    if [ -f /var/run/shanda-vm.pid ]; then
        VM_PID=$(cat /var/run/shanda-vm.pid)
        if ps -p "$VM_PID" > /dev/null; then
            echo -e "${GREEN}[●]${NC} VM Running (PID: $VM_PID)"
        else
            echo -e "${RED}[●]${NC} VM Dead"
        fi
    else
        echo -e "${RED}[●]${NC} VM Not Running"
    fi
    
    if pgrep -f shanda-monitor > /dev/null; then
        echo -e "${GREEN}[●]${NC} Monitor Running"
    else
        echo -e "${YELLOW}[●]${NC} Monitor Not Running"
    fi
    
    echo ""
    echo -e "${CYAN}VM Info:${NC} ${VM_HOSTNAME} | ${VM_USERNAME} | ${VM_CPUS}CPU/${VM_RAM}MB RAM/${VM_DISK_GB}GB"
    echo -e "${CYAN}Local SSH:${NC} ssh ${VM_USERNAME}@localhost -p ${SSH_PORT}"
    echo -e "${CYAN}Password:${NC} ${VM_PASSWORD}"
}

cmd_ssh() {
    load_config
    ssh "${VM_USERNAME}@localhost" -p "${SSH_PORT}"
}

cmd_start() {
    load_config
    /usr/local/bin/shanda-vm
}

cmd_stop() {
    pkill -9 qemu-system-x86_64
    echo -e "${GREEN}[✓]${NC} VM stopped"
}

cmd_restart() {
    cmd_stop
    sleep 2
    cmd_start
}

cmd_logs() {
    tail -f /var/log/shanda-vm.log
}

cmd_monitor_start() {
    if pgrep -f shanda-monitor > /dev/null; then
        echo -e "${YELLOW}[!]${NC} Monitor already running"
    else
        nohup /usr/local/bin/shanda-monitor > /dev/null 2>&1 &
        echo -e "${GREEN}[✓]${NC} Monitor started"
    fi
}

cmd_fix() {
    load_config
    
    echo -e "${CYAN}═══ Shanda Fix/Repair ═══${NC}"
    
    # Check and fix storage
    if ! mountpoint -q "$MOUNT_POINT"; then
        echo -e "${YELLOW}[!]${NC} Mounting storage..."
        mount "/dev/$STORAGE_PARTITION" "$MOUNT_POINT" 2>/dev/null && echo -e "${GREEN}[✓]${NC} Storage mounted"
    else
        echo -e "${GREEN}[✓]${NC} Storage OK"
    fi
    
    # Check VM disk
    if [ ! -f "$VM_DISK_PATH" ]; then
        echo -e "${RED}[✗]${NC} VM disk missing! Run: sudo shanda install"
        exit 1
    else
        echo -e "${GREEN}[✓]${NC} VM disk OK"
    fi
    
    # Fix permissions
    chmod +x /usr/local/bin/shanda-vm /usr/local/bin/shanda-monitor /usr/local/bin/shanda
    echo -e "${GREEN}[✓]${NC} Permissions fixed"
    
    # Restart VM
    echo -e "${YELLOW}[!]${NC} Restarting VM..."
    cmd_restart
    
    # Start monitor
    cmd_monitor_start
    
    echo -e "${GREEN}[✓]${NC} Fix complete!"
}

cmd_info() {
    load_config
    
    echo -e "${CYAN}═══ Connection Info ═══${NC}"
    echo -e "${CYAN}Local SSH:${NC}     ssh ${VM_USERNAME}@localhost -p ${SSH_PORT}"
    echo -e "${CYAN}Root SSH:${NC}      ssh root@localhost -p ${SSH_PORT}"
    echo -e "${CYAN}Password:${NC}      ${VM_PASSWORD}"
    echo -e "${CYAN}HTTP:${NC}          http://localhost:${HTTP_PORT}"
    echo -e "${CYAN}HTTPS:${NC}         https://localhost:${HTTPS_PORT}"
    echo ""
    
    if [ "$TUNNEL_TYPE" != "none" ]; then
        echo -e "${CYAN}Public Access:${NC}  Checking tunnel..."
        ssh -p "${SSH_PORT}" "${VM_USERNAME}@localhost" "cat /root/public-access.txt 2>/dev/null" || echo "Tunnel info not ready yet (wait 2 min after first boot)"
    fi
}

cmd_resize() {
    load_config
    
    echo -e "${CYAN}═══ Resize VM Resources ═══${NC}"
    echo "Current: CPU=${VM_CPUS} | RAM=$((VM_RAM/1024))GB | Disk=${VM_DISK_GB}GB"
    echo ""
    
    read -p "New CPU cores [$VM_CPUS]: " new_cpu
    read -p "New RAM in GB [$((VM_RAM/1024))]: " new_ram
    read -p "New Disk in GB [$VM_DISK_GB]: " new_disk
    
    [ -n "$new_cpu" ] && sed -i "s/VM_CPUS=.*/VM_CPUS=\"$new_cpu\"/" "$CONFIG_FILE"
    [ -n "$new_ram" ] && sed -i "s/VM_RAM=.*/VM_RAM=\"$((new_ram * 1024))\"/" "$CONFIG_FILE"
    
    if [ -n "$new_disk" ] && [ "$new_disk" -gt "$VM_DISK_GB" ]; then
        echo "Resizing disk..."
        qemu-img resize "$VM_DISK_PATH" "${new_disk}G"
        sed -i "s/VM_DISK_GB=.*/VM_DISK_GB=\"$new_disk\"/" "$CONFIG_FILE"
        echo -e "${YELLOW}[!]${NC} Resize filesystem in VM: sudo growpart /dev/vda 1 && sudo resize2fs /dev/vda1"
    fi
    
    echo -e "${GREEN}[✓]${NC} Resources updated. Restart VM: shanda restart"
}

cmd_export() {
    load_config
    
    echo -e "${CYAN}═══ Export VM for Migration ═══${NC}"
    echo "This creates a portable backup of your VM"
    echo ""
    
    EXPORT_DIR="/tmp/shanda-export-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$EXPORT_DIR"
    
    echo "Exporting VM disk..."
    cp "$VM_DISK_PATH" "$EXPORT_DIR/vm-disk.qcow2"
    
    echo "Exporting configuration..."
    cp "$CONFIG_FILE" "$EXPORT_DIR/config.env"
    
    echo "Creating import script..."
    cat > "$EXPORT_DIR/import.sh" << 'IMPORT'
#!/bin/bash
# Shanda VM Import Script
echo "Installing Shanda and importing VM..."
curl -fsSL https://raw.githubusercontent.com/shahriarshm/shanda/main/shanda.sh | bash
cp config.env /etc/shanda/config.env
cp vm-disk.qcow2 /mnt/shanda/shanda-vm.qcow2
shanda start
echo "Import complete!"
IMPORT
    chmod +x "$EXPORT_DIR/import.sh"
    
    echo "Creating archive..."
    cd /tmp
    tar -czf "shanda-export-$(date +%Y%m%d-%H%M%S).tar.gz" "$(basename $EXPORT_DIR)"
    
    echo -e "${GREEN}[✓]${NC} Export complete!"
    echo "Archive: /tmp/shanda-export-*.tar.gz"
    echo ""
    echo "To migrate to another server:"
    echo "  1. Download: scp user@host:/tmp/shanda-export-*.tar.gz ."
    echo "  2. Upload to new server and extract"
    echo "  3. Run: sudo ./import.sh"
}

cmd_keepalive() {
    echo -e "${CYAN}═══ Keepalive Configuration ═══${NC}"
    echo ""
    echo "Options to keep Codespace running:"
    echo ""
    echo "1. GitHub Codespaces doesn't auto-stop if:"
    echo "   • You have active SSH connection"
    echo "   • Port is being accessed"
    echo "   • Process is writing to stdout"
    echo ""
    echo "2. Create keepalive script:"
    
    cat > /usr/local/bin/shanda-keepalive << 'KEEPALIVE'
#!/bin/bash
# Keeps Codespace active
while true; do
    # Generate activity
    echo "[$(date)] Keepalive ping" >> /tmp/keepalive.log
    
    # Keep a process active
    sleep 60
done
KEEPALIVE
    
    chmod +x /usr/local/bin/shanda-keepalive
    
    # Add to cron
    (crontab -l 2>/dev/null; echo "@reboot nohup /usr/local/bin/shanda-keepalive > /dev/null 2>&1 &") | crontab -
    
    # Start it now
    nohup /usr/local/bin/shanda-keepalive > /dev/null 2>&1 &
    
    echo -e "${GREEN}[✓]${NC} Keepalive script installed and started"
    echo ""
    echo -e "${YELLOW}Note:${NC} GitHub may still stop Codespaces after inactivity timeout"
    echo "For true 24/7 uptime, consider:"
    echo "  • Oracle Cloud Free Tier (always-free VMs)"
    echo "  • AWS Free Tier (12 months)"
    echo "  • DigitalOcean ($4/month)"
}

cmd_help() {
    echo -e "${CYAN}Shanda v${VERSION} - VM Management Tool${NC}"
    echo ""
    echo "Usage: shanda <command>"
    echo ""
    echo "Commands:"
    echo "  install        Install new VM (interactive)"
    echo "  status         Show VM status"
    echo "  start          Start VM"
    echo "  stop           Stop VM"
    echo "  restart        Restart VM"
    echo "  ssh            SSH into VM"
    echo "  info           Show connection info"
    echo "  logs           View VM logs"
    echo "  monitor        Start eternal monitor"
    echo "  fix            Auto-repair configuration"
    echo "  resize         Resize CPU/RAM/Disk"
    echo "  -h, --help     Show this help"
    echo "  -v, --version  Show version"
}

case "${1:-}" in
    install)   curl -fsSL https://raw.githubusercontent.com/shahriarshm/shanda/main/shanda.sh | sudo bash ;;
    status)    cmd_status ;;
    start)     cmd_start ;;
    stop)      cmd_stop ;;
    restart)   cmd_restart ;;
    ssh)       cmd_ssh ;;
    info)      cmd_info ;;
    logs)      cmd_logs ;;
    monitor)   cmd_monitor_start ;;
    fix)       cmd_fix ;;
    resize)    cmd_resize ;;
    -h|--help) cmd_help ;;
    -v|--version) echo "Shanda v${VERSION}" ;;
    *)         cmd_help; exit 1 ;;
esac
CLIMAIN

    chmod +x /usr/local/bin/shanda
    log_info "Shanda CLI installed"
}

# Main installation
install_full() {
    show_banner
    
    # Check root
    if [ "$EUID" -ne 0 ]; then
        log_error "Run as root: sudo bash $0"
        exit 1
    fi
    
    # Check KVM
    if [ ! -e /dev/kvm ]; then
        log_error "KVM not available!"
        exit 1
    fi
    
    log_info "KVM available ✓"
    echo ""
    
    # Quick setup
    quick_setup
    echo ""
    
    # Install everything
    install_dependencies
    setup_storage
    download_image
    create_vm_disk
    create_cloud_init
    create_start_script
    create_monitor
    create_autostart
    create_cli
    
    # Start VM
    log_step "Starting VM for first boot..."
    /usr/local/bin/shanda-vm
    
    sleep 5
    
    # Start monitor
    nohup /usr/local/bin/shanda-monitor > /dev/null 2>&1 &
    
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    🎉 SUCCESS! 🎉                         ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    log_info "Shanda VM installed successfully!"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}📋 Connection Details:${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${CYAN}Local SSH:${NC}     ${YELLOW}ssh ${VM_USERNAME}@localhost -p ${SSH_PORT}${NC}"
    echo -e "  ${CYAN}Root SSH:${NC}      ${YELLOW}ssh root@localhost -p ${SSH_PORT}${NC}"
    echo -e "  ${CYAN}Password:${NC}      ${YELLOW}${VM_PASSWORD}${NC}"
    echo -e "  ${CYAN}HTTP:${NC}          ${YELLOW}http://localhost:${HTTP_PORT}${NC}"
    echo -e "  ${CYAN}HTTPS:${NC}         ${YELLOW}https://localhost:${HTTPS_PORT}${NC}"
    echo ""
    
    if [ "$TUNNEL_TYPE" != "none" ]; then
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${WHITE}🌐 Public Internet Access:${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo -e "  ${YELLOW}⏳ Wait 2 minutes for cloud-init to finish${NC}"
        echo -e "  ${YELLOW}Then run:${NC} ${GREEN}shanda info${NC}"
        echo ""
    fi
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}🛠  Management:${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${GREEN}shanda status${NC}     - Show VM status"
    echo -e "  ${GREEN}shanda ssh${NC}        - SSH into VM"
    echo -e "  ${GREEN}shanda info${NC}       - Connection info"
    echo -e "  ${GREEN}shanda restart${NC}    - Restart VM"
    echo -e "  ${GREEN}shanda fix${NC}        - Auto-repair"
    echo -e "  ${GREEN}shanda -h${NC}         - Full help"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}✨ Features:${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${GREEN}✓${NC} Auto-starts on boot"
    echo -e "  ${GREEN}✓${NC} Auto-restarts if crashes"
    echo -e "  ${GREEN}✓${NC} SSH enabled with root access"
    echo -e "  ${GREEN}✓${NC} Port forwarding configured"
    if [ "$TUNNEL_TYPE" != "none" ]; then
        echo -e "  ${GREEN}✓${NC} Public internet access via ${TUNNEL_TYPE}"
    fi
    echo -e "  ${GREEN}✓${NC} VM data stored on persistent disk (/dev/${STORAGE_PARTITION})"
    echo ""
    echo -e "${YELLOW}⚠️  Important Limitation:${NC}"
    echo -e "   ${YELLOW}VM stops when Codespaces container stops${NC}"
    echo -e "   ${YELLOW}VM auto-restarts when Codespaces restarts${NC}"
    echo -e "   ${YELLOW}VM disk data persists across restarts${NC}"
    echo ""
    echo -e "${CYAN}💡 For 24/7 uptime, use:${NC}"
    echo -e "   • Keep Codespaces running"
    echo -e "   • Or migrate to real VPS (use ${GREEN}shanda export${NC})"
    echo ""
    echo -e "${PURPLE}Made with ❤️  by Shahriar (Shanda Bhai 💖)${NC}"
    echo ""
}

# Entry point
main() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Please run as root: sudo $0"
        exit 1
    fi
    
    # If already installed, run CLI
    if [ -f "$CONFIG_FILE" ] && [ -f "/usr/local/bin/shanda" ]; then
        exec /usr/local/bin/shanda "$@"
    else
        # Fresh install
        install_full
    fi
}

main "$@"
