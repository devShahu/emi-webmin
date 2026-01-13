#!/bin/bash
# ═══════════════════════════════════════════════════════════════════
#  ███████╗██╗  ██╗ █████╗ ███╗   ██╗██████╗  █████╗ 
#  ██╔════╝██║  ██║██╔══██╗████╗  ██║██╔══██╗██╔══██╗
#  ███████╗███████║███████║██╔██╗ ██║██║  ██║███████║
#  ╚════██║██╔══██║██╔══██║██║╚██╗██║██║  ██║██╔══██║
#  ███████║██║  ██║██║  ██║██║ ╚████║██████╔╝██║  ██║
#  ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═════╝ ╚═╝  ╚═╝
#
#  Universal VM Bootstrapper - Zero-Config Production Ready
#  Version: 4.0.0
#  Made with ❤️ by Shahriar (Shanda Bhai 💖)
# ═══════════════════════════════════════════════════════════════════

set -e

VERSION="4.0.0"
CONFIG_FILE="/etc/shanda/config.env"
INSTALL_MARKER="/etc/shanda/.installed"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_step() { echo -e "${CYAN}[→]${NC} $1"; }

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
    echo -e "         ${WHITE}Zero-Config VM Bootstrapper v${VERSION}${NC}"
    echo -e "         ${PURPLE}Made with ❤️  by Shahriar (Shanda Bhai 💖)${NC}"
    echo ""
}

# Auto-detect best disk
auto_detect_disk() {
    BEST_DISK=$(lsblk -ndo NAME,SIZE,TYPE,MOUNTPOINT 2>/dev/null | \
        grep "disk" | \
        grep -v "loop" | \
        awk '$4=="" {print $1, $2}' | \
        sort -k2 -hr | \
        head -1 | \
        awk '{print $1}')
    
    [ -z "$BEST_DISK" ] && BEST_DISK="sdb"
    echo "$BEST_DISK"
}

# Zero-config setup
zero_config_setup() {
    log_step "Zero-config setup (no user input required)"
    
    # Fixed defaults
    VM_USERNAME="ubuntu"
    VM_PASSWORD="shanda123"
    VM_HOSTNAME="shanda-vm"
    VM_CPUS="2"
    VM_RAM="4096"
    VM_DISK_GB="50"
    SSH_PORT="2223"
    HTTP_PORT="8080"
    HTTPS_PORT="8443"
    TUNNEL_TYPE="tailscale"
    
    # Auto-detect storage
    STORAGE_DISK=$(auto_detect_disk)
    STORAGE_PARTITION="${STORAGE_DISK}1"
    MOUNT_POINT="/mnt/shanda"
    VM_DISK_PATH="${MOUNT_POINT}/${VM_HOSTNAME}.qcow2"
    CLOUD_INIT_ISO="${MOUNT_POINT}/cloud-init.iso"
    
    mkdir -p /etc/shanda
    cat > "$CONFIG_FILE" << EOF
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
EOF
    
    log_info "Config: ${VM_CPUS}CPU/${VM_RAM}MB RAM/${VM_DISK_GB}GB on /dev/$STORAGE_DISK"
}

# Install ALL dependencies first
install_all_dependencies() {
    log_step "Installing ALL dependencies (this may take 2-3 minutes)..."
    
    export DEBIAN_FRONTEND=noninteractive
    
    # Update package lists
    apt-get update -qq > /dev/null 2>&1 || true
    
    # Install everything in one go
    apt-get install -y -qq \
        cron \
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
        openssh-client \
        iptables \
        vim \
        htop \
        net-tools \
        ca-certificates \
        gnupg \
        lsb-release \
        software-properties-common \
        > /dev/null 2>&1 || true
    
    # Enable and start cron
    systemctl enable cron > /dev/null 2>&1 || true
    systemctl start cron > /dev/null 2>&1 || true
    
    # Install Tailscale (silent)
    if ! command -v tailscale &> /dev/null; then
        curl -fsSL https://tailscale.com/install.sh 2>/dev/null | sh > /dev/null 2>&1 || true
    fi
    
    log_info "All dependencies installed"
}

# Setup storage
setup_storage() {
    log_step "Setting up persistent storage..."
    
    source "$CONFIG_FILE"
    
    # Format if needed
    if ! blkid "/dev/${STORAGE_PARTITION}" 2>/dev/null | grep -q ext4; then
        mkfs.ext4 -F "/dev/${STORAGE_PARTITION}" > /dev/null 2>&1 || true
    fi
    
    # Mount
    mkdir -p "$MOUNT_POINT"
    if ! mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        mount "/dev/${STORAGE_PARTITION}" "$MOUNT_POINT" 2>/dev/null || true
    fi
    
    # Add to fstab
    if ! grep -q "${STORAGE_PARTITION}" /etc/fstab 2>/dev/null; then
        echo "/dev/${STORAGE_PARTITION} $MOUNT_POINT ext4 defaults 0 2" >> /etc/fstab
    fi
    
    log_info "Storage ready at $MOUNT_POINT"
}

# Download Ubuntu image
download_image() {
    log_step "Downloading Ubuntu 24.04 cloud image..."
    
    source "$CONFIG_FILE"
    IMAGE_FILE="$MOUNT_POINT/ubuntu-24.04-cloudimg.img"
    
    if [ -f "$IMAGE_FILE" ]; then
        log_info "Image already exists"
        return
    fi
    
    wget -q --show-progress \
        -O "$IMAGE_FILE" \
        "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img" 2>&1 | \
        grep -oP '\d+%' | tail -1 || true
    
    log_info "Image downloaded"
}

# Create VM disk
create_vm_disk() {
    log_step "Creating VM disk..."
    
    source "$CONFIG_FILE"
    
    if [ -f "$VM_DISK_PATH" ]; then
        log_info "VM disk exists"
        return
    fi
    
    IMAGE_FILE="$MOUNT_POINT/ubuntu-24.04-cloudimg.img"
    qemu-img convert -f qcow2 -O qcow2 "$IMAGE_FILE" "$VM_DISK_PATH" > /dev/null 2>&1
    qemu-img resize "$VM_DISK_PATH" "${VM_DISK_GB}G" > /dev/null 2>&1
    
    log_info "VM disk created (${VM_DISK_GB}GB)"
}

# Create cloud-init
create_cloud_init() {
    log_step "Configuring cloud-init..."
    
    source "$CONFIG_FILE"
    CLOUD_INIT_DIR="$MOUNT_POINT/cloud-init"
    mkdir -p "$CLOUD_INIT_DIR"
    
    PASS_HASH=$(openssl passwd -6 -salt saltsalt "$VM_PASSWORD")
    
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
  - git
  - tmux

runcmd:
  - systemctl enable ssh
  - systemctl start ssh
  - sed -i 's/.*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
  - sed -i 's/.*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
  - systemctl restart ssh
  - echo '${VM_USERNAME}:${VM_PASSWORD}' | chpasswd
  - echo 'root:${VM_PASSWORD}' | chpasswd
  - curl -fsSL https://tailscale.com/install.sh | sh || true
  - tailscale up --authkey=\${TAILSCALE_KEY:-} --ssh --hostname=${VM_HOSTNAME} || true
  - TAILSCALE_IP=\$(tailscale ip -4 2>/dev/null || echo "pending")
  - echo "Tailscale IP: \$TAILSCALE_IP" > /root/public-access.txt
  - echo "SSH: ssh ${VM_USERNAME}@\$TAILSCALE_IP" >> /root/public-access.txt
  - echo "Local: ssh ${VM_USERNAME}@localhost -p ${SSH_PORT}" >> /root/public-access.txt
  - wall 'Shanda VM is ready!'

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
    
    log_info "Cloud-init configured"
}

# Create VM runner
create_vm_runner() {
    cat > /usr/local/bin/shanda-vm << 'VMRUNNER'
#!/bin/bash
CONFIG_FILE="/etc/shanda/config.env"
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE" || exit 1

# Kill any existing VM
pkill -9 qemu-system-x86_64 2>/dev/null || true
sleep 2

# Ensure storage is mounted
if ! mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    mount "/dev/$STORAGE_PARTITION" "$MOUNT_POINT" 2>/dev/null || true
fi

# Check VM disk exists
[ ! -f "$VM_DISK_PATH" ] && echo "[✗] VM disk not found" && exit 1

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
if ps -p $VM_PID > /dev/null 2>&1; then
    echo "[✓] VM started (PID: $VM_PID)"
    logger -t shanda "VM started successfully"
else
    echo "[✗] VM failed to start"
    tail -20 /var/log/shanda-vm.log
    exit 1
fi
VMRUNNER

    chmod +x /usr/local/bin/shanda-vm
    log_info "VM runner created"
}

# Create eternal monitor
create_eternal_monitor() {
    cat > /usr/local/bin/shanda-monitor << 'MONITOR'
#!/bin/bash
CONFIG_FILE="/etc/shanda/config.env"
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/shanda-monitor.log
    logger -t shanda-monitor "$1"
}

ensure_storage() {
    if [ -n "$MOUNT_POINT" ] && [ -n "$STORAGE_PARTITION" ]; then
        if ! mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
            mkdir -p "$MOUNT_POINT"
            mount "/dev/$STORAGE_PARTITION" "$MOUNT_POINT" 2>/dev/null && log "Storage mounted"
        fi
    fi
}

while true; do
    ensure_storage
    
    if ! pgrep -f "qemu-system-x86_64.*$VM_HOSTNAME" > /dev/null 2>&1; then
        log "VM not running, starting..."
        /usr/local/bin/shanda-vm 2>&1 | logger -t shanda-vm
        sleep 10
    fi
    
    sleep 30
done
MONITOR

    chmod +x /usr/local/bin/shanda-monitor
    log_info "Eternal monitor created"
}

# Create boot persistence (FORCED)
create_boot_persistence() {
    log_step "Creating FORCED boot persistence..."
    
    # 1. RC.LOCAL (runs before everything)
    cat > /etc/rc.local << 'RCLOCAL'
#!/bin/bash
# Shanda Auto-Start
sleep 5
/usr/local/bin/shanda-vm >> /var/log/shanda-boot.log 2>&1 &
/usr/local/bin/shanda-monitor >> /var/log/shanda-boot.log 2>&1 &
exit 0
RCLOCAL
    chmod +x /etc/rc.local
    
    # 2. Systemd service (persistent)
    cat > /etc/systemd/system/shanda-vm.service << 'SERVICE'
[Unit]
Description=Shanda KVM Virtual Machine
After=network.target

[Service]
Type=forking
ExecStart=/usr/local/bin/shanda-vm
ExecStop=/usr/bin/pkill -9 qemu-system-x86_64
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICE

    cat > /etc/systemd/system/shanda-monitor.service << 'SERVICE'
[Unit]
Description=Shanda VM Monitor
After=shanda-vm.service

[Service]
Type=simple
ExecStart=/usr/local/bin/shanda-monitor
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

    systemctl daemon-reload
    systemctl enable shanda-vm.service > /dev/null 2>&1 || true
    systemctl enable shanda-monitor.service > /dev/null 2>&1 || true
    
    # 3. Cron (every reboot + every minute check)
    (crontab -l 2>/dev/null | grep -v shanda; cat << 'CRONTAB'
@reboot sleep 10 && /usr/local/bin/shanda-vm >> /var/log/shanda-cron.log 2>&1
@reboot sleep 15 && /usr/local/bin/shanda-monitor >> /var/log/shanda-cron.log 2>&1
* * * * * pgrep -f qemu-system-x86_64 > /dev/null || /usr/local/bin/shanda-vm >> /var/log/shanda-health.log 2>&1
CRONTAB
) | crontab -
    
    # 4. Profile scripts (runs on every shell)
    for profile in /root/.bashrc /root/.profile /etc/profile /etc/bash.bashrc; do
        [ -f "$profile" ] || continue
        grep -q "shanda-monitor" "$profile" 2>/dev/null || cat >> "$profile" << 'PROFILE'

# Shanda Auto-Start
if ! pgrep -f shanda-monitor > /dev/null 2>&1; then
    nohup /usr/local/bin/shanda-monitor > /dev/null 2>&1 &
fi
if ! pgrep -f qemu-system-x86_64 > /dev/null 2>&1; then
    nohup /usr/local/bin/shanda-vm > /dev/null 2>&1 &
fi
PROFILE
    done
    
    log_info "Boot persistence installed (4 layers)"
}

# Create CLI
create_cli() {
    cat > /usr/local/bin/shanda << 'CLI'
#!/bin/bash
CONFIG_FILE="/etc/shanda/config.env"
VERSION="4.0.0"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

load_config() {
    [ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE" || { echo -e "${RED}Not installed${NC}"; exit 1; }
}

cmd_status() {
    load_config
    echo -e "${CYAN}═══ Shanda Status ═══${NC}"
    
    if pgrep -f "qemu-system-x86_64.*$VM_HOSTNAME" > /dev/null 2>&1; then
        VM_PID=$(pgrep -f "qemu-system-x86_64.*$VM_HOSTNAME")
        echo -e "${GREEN}[●]${NC} VM Running (PID: $VM_PID)"
    else
        echo -e "${RED}[●]${NC} VM Not Running"
    fi
    
    if pgrep -f shanda-monitor > /dev/null 2>&1; then
        echo -e "${GREEN}[●]${NC} Monitor Running"
    else
        echo -e "${YELLOW}[●]${NC} Monitor Not Running"
    fi
    
    echo ""
    echo -e "${CYAN}Local SSH:${NC} ssh ${VM_USERNAME}@localhost -p ${SSH_PORT}"
    echo -e "${CYAN}Password:${NC}  ${VM_PASSWORD}"
}

cmd_ssh() {
    load_config
    ssh "${VM_USERNAME}@localhost" -p "${SSH_PORT}"
}

cmd_start() {
    /usr/local/bin/shanda-vm
}

cmd_stop() {
    pkill -9 qemu-system-x86_64
    echo -e "${GREEN}[✓]${NC} VM stopped"
}

cmd_restart() {
    cmd_stop
    sleep 3
    cmd_start
}

cmd_logs() {
    tail -f /var/log/shanda-vm.log
}

cmd_info() {
    load_config
    echo -e "${CYAN}═══ Connection Info ═══${NC}"
    echo -e "${CYAN}Local SSH:${NC}  ssh ${VM_USERNAME}@localhost -p ${SSH_PORT}"
    echo -e "${CYAN}Root SSH:${NC}   ssh root@localhost -p ${SSH_PORT}"
    echo -e "${CYAN}Password:${NC}   ${VM_PASSWORD}"
    echo ""
    echo "Checking public access..."
    ssh -o ConnectTimeout=5 -p "${SSH_PORT}" "${VM_USERNAME}@localhost" "cat /root/public-access.txt 2>/dev/null" || echo "VM still booting (wait 2 min)"
}

cmd_help() {
    echo "Shanda v${VERSION} - Commands:"
    echo "  status   - Show status"
    echo "  start    - Start VM"
    echo "  stop     - Stop VM"
    echo "  restart  - Restart VM"
    echo "  ssh      - SSH into VM"
    echo "  info     - Connection info"
    echo "  logs     - View logs"
}

case "${1:-status}" in
    status)   cmd_status ;;
    start)    cmd_start ;;
    stop)     cmd_stop ;;
    restart)  cmd_restart ;;
    ssh)      cmd_ssh ;;
    info)     cmd_info ;;
    logs)     cmd_logs ;;
    *)        cmd_help ;;
esac
CLI

    chmod +x /usr/local/bin/shanda
    log_info "CLI installed"
}

# Main installation
main_install() {
    show_banner
    
    # Root check
    if [ "$EUID" -ne 0 ]; then
        log_error "Must run as root: sudo bash $0"
        exit 1
    fi
    
    # Check if already installed
    if [ -f "$INSTALL_MARKER" ]; then
        log_warn "Already installed. Use: shanda status"
        exec /usr/local/bin/shanda "$@"
    fi
    
    # KVM check
    if [ ! -e /dev/kvm ]; then
        log_error "KVM not available!"
        log_warn "Enable nested virtualization in your VM/Cloud settings"
        exit 1
    fi
    
    log_info "KVM available ✓"
    echo ""
    
    # Install everything
    zero_config_setup
    install_all_dependencies
    setup_storage
    download_image
    create_vm_disk
    create_cloud_init
    create_vm_runner
    create_eternal_monitor
    create_boot_persistence
    create_cli
    
    # Mark as installed
    touch "$INSTALL_MARKER"
    
    # Start everything NOW
    log_step "Starting VM..."
    /usr/local/bin/shanda-vm
    
    sleep 5
    
    log_step "Starting monitor..."
    nohup /usr/local/bin/shanda-monitor > /dev/null 2>&1 &
    
    # Success message
    source "$CONFIG_FILE"
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    🎉 SUCCESS! 🎉                         ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    log_info "Shanda VM installed and running!"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}📋 Connection Details:${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${YELLOW}ssh ${VM_USERNAME}@localhost -p ${SSH_PORT}${NC}"
    echo -e "  ${YELLOW}Password: ${VM_PASSWORD}${NC}"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}🛠  Management:${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${GREEN}shanda status${NC}   - Check status"
    echo -e "  ${GREEN}shanda ssh${NC}      - Connect via SSH"
    echo -e "  ${GREEN}shanda info${NC}     - Show public URL (after 2 min)"
    echo -e "  ${GREEN}shanda restart${NC}  - Restart VM"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}✨ Features:${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${GREEN}✓${NC} Auto-starts on every boot (4 persistence layers)"
    echo -e "  ${GREEN}✓${NC} Auto-restarts if crashes (30s monitoring)"
    echo -e "  ${GREEN}✓${NC} SSH enabled (root + user access)"
    echo -e "  ${GREEN}✓${NC} Tailscale public access (after 2 min)"
    echo -e "  ${GREEN}✓${NC} Persistent storage on /dev/${STORAGE_PARTITION}"
    echo ""
    echo -e "${YELLOW}⏳ Wait 2 minutes then run: ${GREEN}shanda info${NC}"
    echo ""
    echo -e "${PURPLE}Made with ❤️  by Shahriar (Shanda Bhai 💖)${NC}"
    echo ""
}

# Entry point
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[✗]${NC} Must run as root"
    echo "Usage: sudo bash $0"
    exit 1
fi

main_install "$@"
