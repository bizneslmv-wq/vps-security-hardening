#!/bin/bash
# VPS Ubuntu 24.04 Security Hardening Script v1.0.0
# Author: Maks Leto (bizneslmv-wq)
# GitHub: https://github.com/bizneslmv-wq/vps-security-hardening
# License: MIT
################################################################################

set -e

# Colors and logging
RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' BLUE='\033[0;34m' NC='\033[0m'
LOG_FILE="/var/log/vps-hardening-$(date +%Y%m%d-%H%M%S).log"

log() { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"; }
success() { echo -e "${GREEN}[✓]${NC} $1" | tee -a "$LOG_FILE"; }
error() { echo -e "${RED}[✗]${NC} $1" | tee -a "$LOG_FILE"; exit 1; }
warning() { echo -e "${YELLOW}[!]${NC} $1" | tee -a "$LOG_FILE"; }

# Checks
check_root() {
    [[ $EUID -ne 0 ]] && { error "Запуск от root (sudo)"; exit 1; }
}

check_ubuntu() {
    [[ ! $(lsb_release -rs) = "24.04" ]] && warning "Рекомендуется Ubuntu 24.04"
}

# Banner
show_banner() {
    clear
    cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║       🚀 VPS Ubuntu 24.04 Security Hardening v1.0.0          ║
║                        by bizneslmv-wq                       ║
║              https://github.com/bizneslmv-wq                 ║
╚═══════════════════════════════════════════════════════════════╝
EOF
}

# Menu
show_menu() {
    echo -e "\n${YELLOW}Выберите компоненты:${NC}"
    cat << EOF
  1) 📦 Обновление системы
  2) 🔐 SSH Hardening
  3) 🛡️ UFW Firewall
  4) ⚡ Fail2ban
  5) 🛠️ Kernel Hardening
  6) 📊 Auditd
  7) 🚫 Отключить сервисы
  8) ${GREEN}🎉 ВСЁ сразу${NC}
  9) ❌ Выход
EOF
    read -p "► " choice
}

# Port validation
validate_port() {
    [[ "$1" =~ ^[0-9]+$ ]] && [[ "$1" -ge 1024 ]] && [[ "$1" -le 65535 ]]
}

# 1. System update
update_system() {
    log "📦 Обновление системы..."
    apt update
    apt full-upgrade -y
    apt autoremove -y
    success "Система обновлена"
}

# 2. SSH Hardening
configure_ssh() {
    log "🔐 Настройка SSH..."
    
    read -p "SSH порт [56123]: " SSH_PORT
    SSH_PORT=${SSH_PORT:-56123}
    
    [[ ! validate_port "$SSH_PORT" ]] && { error "Неверный порт: $SSH_PORT"; return 1; }
    
    # Backup
    cp /etc/ssh/sshd_config /root/sshd_config.backup
    
    # Configure
    sed -i "s/^#*Port .*/Port $SSH_PORT/" /etc/ssh/sshd_config
    sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
    sed -i 's/^#*MaxAuthTries.*/MaxAuthTries 3/' /etc/ssh/sshd_config
    sed -i 's/^#*MaxSessions.*/MaxSessions 5/' /etc/ssh/sshd_config
    sed -i 's/^#*X11Forwarding.*/X11Forwarding no/' /etc/ssh/sshd_config
    
    # Test & restart
    sshd -t >/dev/null 2>&1 || {
        warning "SSH config error, rollback..."
        cp /root/sshd_config.backup /etc/ssh/sshd_config
        return 1
    }
    
    systemctl restart ssh
    success "SSH: порт $SSH_PORT, ключи only"
}

# 3. UFW Firewall
configure_firewall() {
    log "🛡️ Настройка UFW..."
    
    # Enable UFW
    ufw --force enable
    ufw default deny incoming
    ufw default allow outgoing
    
    # SSH port
    ufw allow "${SSH_PORT:-56123}"/tcp
    
    # Additional ports
    echo -e "\n${YELLOW}Дополнительные порты:${NC}"
    read -p "HTTP (80)? [n]: " HTTP_PORT
    [[ $HTTP_PORT =~ ^[Yy]$ ]] && ufw allow 80/tcp
    
    read -p "HTTPS (443)? [n]: " HTTPS_PORT  
    [[ $HTTPS_PORT =~ ^[Yy]$ ]] && ufw allow 443/tcp
    
    read -p "Custom ports (comma sep): " CUSTOM_PORTS
    IFS=',' read -ra PORTS <<< "$CUSTOM_PORTS"
    for port in "${PORTS[@]}"; do
        [[ -n $port ]] && ufw allow "${port%/tcp}/tcp"
    done
    
    ufw reload
    success "Firewall настроен:"
    ufw status | head -15
}

# 4. Fail2ban
configure_fail2ban() {
    log "⚡ Установка Fail2ban..."
    
    apt install -y fail2ban
    
    read -p "Время бана (сек) [3600]: " BANTIME
    BANTIME=${BANTIME:-3600}
    
    read -p "Период проверки (сек) [600]: " FINDTIME
    FINDTIME=${FINDTIME:-600}
    
    read -p "Макс. попытки [3]: " MAXRETRY
    MAXRETRY=${MAXRETRY:-3}
    
    # SSH jail
    mkdir -p /etc/fail2ban/jail.d
    cat > /etc/fail2ban/jail.d/sshd.conf << EOF
[sshd]
enabled = true
port = ${SSH_PORT:-56123}
bantime = $BANTIME
findtime = $FINDTIME
maxretry = $MAXRETRY
EOF
    
    systemctl restart fail2ban
    systemctl enable fail2ban
    success "Fail2ban: $MAXRETRY попыток → $BANTIME сек"
}

# 5. Kernel Hardening
configure_kernel() {
    log "🛠️ Kernel hardening..."
    
    cat >> /etc/sysctl.conf << 'EOF'

# SYN flood protection
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_synack_retries = 2

# IP spoofing protection
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# ICMP protection
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0

# Connection tracking
net.netfilter.nf_conntrack_max = 262144
EOF
    
    sysctl -p
    success "Kernel hardening применён"
}

# 6. Auditd
configure_auditd() {
    log "📊 Установка Auditd..."
    
    apt install -y auditd audispd-plugins
    
    systemctl enable --now auditd
    
    # Monitor critical files
    auditctl -w /etc/ssh/sshd_config -p wa -k ssh-config
    auditctl -w /etc/ufw -p wa -k ufw-rules
    auditctl -w /etc/fail2ban -p wa -k fail2ban
    auditctl -w /etc/sudoers -p wa -k sudoers
    
    success "Auditd: мониторинг критических файлов"
}

# 7. Disable unnecessary services
disable_services() {
    log "🚫 Отключение ненужных сервисов..."
    
    for service in cups avahi-daemon iscsid; do
        if systemctl is-active --quiet $service; then
            systemctl disable --now $service
            success "$service отключён"
        fi
    done
}

# Summary
show_summary() {
    clear
    cat << EOF
${GREEN}🎉 НАСТРОЙКА ЗАВЕРШЕНА УСПЕШНО!${NC}

📋 РЕЗУЛЬТАТЫ:

🔐 ${YELLOW}SSH:${NC} порт ${SSH_PORT:-56123}, только ключи
🛡️ ${YELLOW}UFW:${NC} deny incoming, разрешены нужные порты
⚡ ${YELLOW}Fail2ban:${NC} ${MAXRETRY:-3}→${BANTIME:-3600}с бан
🛠️ ${YELLOW}Kernel:${NC} SYN flood, IP spoofing защита
📊 ${YELLOW}Auditd:${NC} мониторинг /etc/
🚫 ${YELLOW}Services:${NC} cups, avahi-daemon off

📊 ${YELLOW}Логи:${NC} $LOG_FILE
💾 ${YELLOW}Backup:${NC} /root/*.backup

${RED}⚠️ Подключение SSH:${NC} ${YELLOW}ssh -p ${SSH_PORT:-56123} user@IP${NC}

EOF
}

# Main loop
main() {
    check_root
    check_ubuntu
    show_banner
    
    while true; do
        show_menu
        case $choice in
            1) update_system ;;
            2) configure_ssh ;;
            3) configure_firewall ;;
            4) configure_fail2ban ;;
            5) configure_kernel ;;
            6) configure_auditd ;;
            7) disable_services ;;
            8) 
                update_system
                configure_ssh
                configure_firewall
                configure_fail2ban
                configure_kernel
                configure_auditd
                disable_services
                show_summary
                exit 0
                ;;
            9) show_summary; exit 0 ;;
            *) error "Выберите 1-9";;
        esac
        echo -e "\n${YELLOW}Нажмите Enter для продолжения...${NC}"
        read
    done
}

main "$@"
