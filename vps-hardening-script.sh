#!/bin/bash
# VPS Ubuntu 24.04 Security Hardening Script v1.0.3
# Author: Maks Leto (bizneslmv-wq)
# GitHub: https://github.com/bizneslmv-wq/vps-security-hardening
# License: MIT
################################################################################

set -e

# Colors and logging
RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' BLUE='\033[0;34m' NC='\033[0m'
LOG_FILE="/var/log/vps-hardening-$(date +%Y%m%d-%H%M%S).log"

# ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ ДЛЯ ОТЧЕТА
declare -A CONFIG=(
    ["SSH_PORT"]=""
    ["HTTP_ENABLED"]="no"
    ["HTTPS_ENABLED"]="no"
    ["CUSTOM_PORTS"]=""
    ["BANTIME"]="2592000"  # 30 дней по умолчанию!
    ["FINDTIME"]="86400"   # 24 часа
    ["MAXRETRY"]="3"
    ["COMPONENTS"]=""
)

log() { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"; }
success() { echo -e "${GREEN}[✓]${NC} $1" | tee -a "$LOG_FILE"; CONFIG["COMPONENTS"]+="$1 | "; }
error() { echo -e "${RED}[✗]${NC} $1" | tee -a "$LOG_FILE"; exit 1; }
warning() { echo -e "${YELLOW}[!]${NC} $1" | tee -a "$LOG_FILE"; }

check_root() { [[ $EUID -ne 0 ]] && error "Запуск от root (sudo)"; }
check_ubuntu() { [[ ! $(lsb_release -rs 2>/dev/null || echo "unknown") = "24.04" ]] && warning "Рекомендуется Ubuntu 24.04"; }

show_banner() {
    clear
    cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║       🚀 VPS Ubuntu 24.04 Security Hardening v1.0.3          ║
║                        by bizneslmv-wq                       ║
║              https://github.com/bizneslmv-wq                 ║
╚═══════════════════════════════════════════════════════════════╝
EOF
}

setup_ssh_port() {
    if [[ -z "${CONFIG[SSH_PORT]}" ]]; then
        echo -e "\n${YELLOW}🔐 НАСТРОЙКА SSH ПОРТА:${NC}"
        read -p "SSH порт для VPS [56123]: " SSH_PORT_INPUT
        CONFIG[SSH_PORT]=${SSH_PORT_INPUT:-56123}
        
        if ! [[ "${CONFIG[SSH_PORT]}" =~ ^[0-9]+$ ]] || [[ "${CONFIG[SSH_PORT]}" -lt 1024 ]] || [[ "${CONFIG[SSH_PORT]}" -gt 65535 ]]; then
            error "❌ Неверный порт SSH: ${CONFIG[SSH_PORT]} (1024-65535)"
        fi
        
        success "✅ SSH порт: ${CONFIG[SSH_PORT]} (UFW + Fail2ban)"
    fi
}

show_menu() {
    echo -e "\n${YELLOW}SSH: ${GREEN}${CONFIG[SSH_PORT]:-не_задан}${NC} | Fail2ban: ${CONFIG[MAXRETRY]:-3}→${CONFIG[BANTIME]:-30дн} | Лог: $LOG_FILE"
    echo -e "\n${YELLOW}Выберите:${NC}"
    cat << EOF
  1) 📦 Система
  2) 🔐 SSH (${CONFIG[SSH_PORT]:-порт})
  3) 🛡️ UFW (откроет SSH)
  4) ⚡ Fail2ban ${RED}(3→30 дней!)${NC}
  5) 🛠️ Kernel
  6) 📊 Auditd
  7) 🚫 Сервисы
  8) ${GREEN}🎉 ВСЁ сразу${NC}
  9) ❌ Выход
EOF
    read -p "► " choice
}

update_system() { log "📦 Обновление..."; apt update && apt full-upgrade -y && apt autoremove -y; success "Система обновлена"; }

configure_ssh() {
    setup_ssh_port
    log "🔐 SSH → ${CONFIG[SSH_PORT]}..."
    cp /etc/ssh/sshd_config /root/sshd_config.backup 2>/dev/null || true
    sed -i "s/^#*Port .*/Port ${CONFIG[SSH_PORT]}/" /etc/ssh/sshd_config
    sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
    sed -i 's/^#*MaxAuthTries.*/MaxAuthTries 3/' /etc/ssh/sshd_config
    
    sshd -t >/dev/null 2>&1 && { systemctl restart ssh; success "SSH: ${CONFIG[SSH_PORT]}, ключи"; } || { cp /root/sshd_config.backup /etc/ssh/sshd_config; error "SSH ошибка"; }
}

configure_firewall() {
    setup_ssh_port
    log "🛡️ UFW..."
    ufw --force enable >/dev/null 2>&1
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow "${CONFIG[SSH_PORT]}"/tcp
    success "UFW: SSH ${CONFIG[SSH_PORT]} открыт"
    
    read -p "HTTP 80? [n]: " h; [[ $h =~ ^[Yy]$ ]] && { ufw allow 80/tcp; CONFIG[HTTP_ENABLED]=yes; success "HTTP 80"; }
    read -p "HTTPS 443? [n]: " s; [[ $s =~ ^[Yy]$ ]] && { ufw allow 443/tcp; CONFIG[HTTPS_ENABLED]=yes; success "HTTPS 443"; }
    read -p "Доп. порты: " c; [[ -n "$c" ]] && { CONFIG[CUSTOM_PORTS]="$c"; IFS=',' read -ra ports <<< "$c"; for p in "${ports[@]}"; do ufw allow "${p%/tcp}"/tcp; done; success "Порты: $c"; }
    
    ufw reload
    echo; ufw status | head -15
}

# 🔥 НОВЫЙ Fail2ban с баном на 30 дней!
configure_fail2ban() {
    setup_ssh_port
    log "⚡ ${RED}МОЩНЫЙ Fail2ban${NC} (3 попытки = ${CONFIG[BANTIME]} сек = 30 дней!)"
    
    apt install -y fail2ban
    
    echo -e "${YELLOW}⚠️  НАСТРОЙКИ БЕЗОПАСНОСТИ:${NC}"
    echo "  • ${CONFIG[MAXRETRY]:-3} попыток = бан на ${CONFIG[BANTIME]:-2592000} сек"
    echo "  • ${CONFIG[FINDTIME]:-86400} сек = 24 часа (период анализа)"
    
    read -p "Бан (сек) [${CONFIG[BANTIME]} = 30 дней]: " bt
    CONFIG[BANTIME]=${bt:-${CONFIG[BANTIME]}}
    
    read -p "Период (сек) [${CONFIG[FINDTIME]} = 24ч]: " ft
    CONFIG[FINDTIME]=${ft:-${CONFIG[FINDTIME]}}
    
    read -p "Попытки [${CONFIG[MAXRETRY]}]: " mr
    CONFIG[MAXRETRY]=${mr:-${CONFIG[MAXRETRY]}}
    
    # МОЩНАЯ Fail2ban конфигурация!
    mkdir -p /etc/fail2ban/jail.d
    cat > /etc/fail2ban/jail.d/sshd.conf << EOF
[sshd]
enabled = true
port = ${CONFIG[SSH_PORT]}
bantime = ${CONFIG[BANTIME]}
findtime = ${CONFIG[FINDTIME]}
maxretry = ${CONFIG[MAXRETRY]}
backend = auto
EOF
    
    systemctl restart fail2ban && systemctl enable fail2ban
    
    # Показать силу!
    BAN_DAYS=$((CONFIG[BANTIME]/86400))
    success "🔥 Fail2ban: ${CONFIG[MAXRETRY]} попыток → ${BAN_DAYS} ДНЕЙ БАН! (порт ${CONFIG[SSH_PORT]})"
}

configure_kernel() { log "🛠️ Kernel..."; cat >> /etc/sysctl.conf << 'EOF'
net.ipv4.tcp_syncookies=1
net.ipv4.conf.all.rp_filter=1
net.ipv4.conf.all.accept_redirects=0
EOF; sysctl -p; success "Kernel hardening"; }

configure_auditd() { log "📊 Auditd..."; apt install -y auditd; systemctl enable --now auditd; auditctl -w /etc/ssh/sshd_config -p wa -k ssh; success "Auditd"; }

disable_services() { log "🚫 Сервисы..."; for s in cups avahi-daemon; do systemctl disable $s 2>/dev/null || true; systemctl stop $s 2>/dev/null || true; success "$s off"; done; }

show_detailed_report() {
    clear
    BAN_DAYS=$((CONFIG[BANTIME]/86400))
    cat << EOF
    
${GREEN}🎉 НАСТРОЙКА ЗАВЕРШЕНА!${NC} ${YELLOW}v1.0.3${NC}
${BLUE}═══════════════════════════════════════════════════════════════${NC}

${GREEN}📋 ИТОГОВЫЙ ОТЧЕТ:${NC}

🔐 ${YELLOW}SSH:${NC}
  • Порт: ${GREEN}${CONFIG[SSH_PORT]}${NC}
  • Root: ${RED}🚫 ОТКЛЮЧЁН${NC}
  • Пароли: ${RED}🚫 ОТКЛЮЧЁН${NC} (только ключи!)
  • Макс. попытки: ${YELLOW}3${NC}

🛡️ ${YELLOW}UFW:${NC}
  • По умолчанию: ${RED}DENY IN${NC} | ${GREEN}ALLOW OUT${NC}
  • Открыто:
    ${GREEN}• ${CONFIG[SSH_PORT]}/tcp${NC} (SSH)
EOF
    
    [[ "${CONFIG[HTTP_ENABLED]}" == "yes" ]] && echo "    ${GREEN}• 80/tcp${NC} (HTTP)"
    [[ "${CONFIG[HTTPS_ENABLED]}" == "yes" ]] && echo "    ${GREEN}• 443/tcp${NC} (HTTPS)"
    [[ -n "${CONFIG[CUSTOM_PORTS]}" ]] && echo "    ${YELLOW}• ${CONFIG[CUSTOM_PORTS]}${NC}"

    cat << EOF

⚡ ${RED}Fail2ban СУПЕРЗАЩИТА:${NC}
  • SSH: ${CONFIG[SSH_PORT]}
  • ${YELLOW}${CONFIG[MAXRETRY]}${NC} попыток → ${RED}${BAN_DAYS} ДНЕЙ${NC} БАН! 🔥
  • Анализ: ${CONFIG[FINDTIME]} сек (${CONFIG[FINDTIME]/3600}ч)

🛠️ ${YELLOW}Kernel:${NC}
  • SYN flood: ${GREEN}✓${NC}
  • IP spoofing: ${GREEN}✓${NC}

📊 ${YELLOW}Мониторинг:${NC} Auditd ${GREEN}✓${NC}

🚫 ${YELLOW}Отключено:${NC} cups, avahi-daemon ${GREEN}✓${NC}

${BLUE}═══════════════════════════════════════════════════════════════${NC}
${YELLOW}📊 Лог:${NC} $LOG_FILE
${YELLOW}💾 Backup:${NC} /root/sshd_config.backup

${RED}⚠️ SSH:${NC} ${GREEN}ssh -p ${CONFIG[SSH_PORT]} user@IP${NC} ${RED}(КЛЮЧИ!)${NC}

${GREEN}🏆 VPS - КРЕПОСТЬ! Никто не пройдёт!${NC} 🔥🔒
EOF
}

main() {
    check_root; check_ubuntu; show_banner
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
            8) update_system; configure_ssh; configure_firewall; configure_fail2ban; configure_kernel; configure_auditd; disable_services; show_detailed_report; exit 0 ;;
            9) [[ -n "${CONFIG[SSH_PORT]}" ]] && show_detailed_report || echo "${YELLOW}Настройки не применены${NC}"; exit 0 ;;
            *) error "1-9";;
        esac
        echo -e "\n${YELLOW}Enter...${NC}"; read
    done
}

main "$@"
