#!/bin/bash
# VPS Ubuntu 24.04 Security Script v2.2.1 (FIXED)
# Author: Maks Leto (bizneslmv-wq)
################################################################################

# Отключаем set -e для надёжности
set +e

RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' BLUE='\033[0;34m' NC='\033[0m'
LOG_FILE="/var/log/vps-security-$(date +%Y%m%d-%H%M%S).log"

log() { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE" 2>/dev/null; }
success() { echo -e "${GREEN}[✓]${NC} $1" | tee -a "$LOG_FILE" 2>/dev/null; }
error() { echo -e "${RED}[✗]${NC} $1" | tee -a "$LOG_FILE" 2>/dev/null; exit 1; }

SSH_PORT=""
ADDITIONAL_PORTS=()

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Запуск от root (sudo) требуется!${NC}"
        exit 1
    fi
}

show_banner() {
    clear
    cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║           🚀 VPS Ubuntu 24.04 Security Script v2.2.1         ║
║                        by bizneslmv-wq                       ║
╚═══════════════════════════════════════════════════════════════╝
EOF
}

main() {
    check_root
    show_banner
    
    echo -e "\n${YELLOW}🔄 1. Обновление системы...${NC}"
    log "Обновление системы..."
    apt update -qq
    DEBIAN_FRONTEND=noninteractive apt upgrade -y -qq --allow-downgrades
    apt autoremove -y -qq
    success "Система обновлена"
    
    echo -e "\n${YELLOW}🔐 2. Настройка SSH порта...${NC}"
    echo -e "\n${YELLOW}Введите новый SSH порт:${NC}"
    read -p "SSH порт [56123]: " SSH_PORT_INPUT
    SSH_PORT=${SSH_PORT_INPUT:-56123}
    
    if ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]] || [[ "$SSH_PORT" -lt 1024 ]] || [[ "$SSH_PORT" -gt 65535 ]]; then
        echo -e "${RED}Неверный порт: $SSH_PORT (1024-65535)${NC}"
        exit 1
    fi
    
    log "Смена SSH порта на $SSH_PORT..."
    sed -i "s/^#*Port .*/Port $SSH_PORT/" /etc/ssh/sshd_config
    systemctl restart ssh
    success "SSH порт изменён: $SSH_PORT"
    
    echo -e "\n${YELLOW}🔑 3. Смена пароля root...${NC}"
    echo -e "\n${YELLOW}Введите новый пароль root:${NC}"
    read -s -p "Пароль: " NEW_PASS
    echo
    read -s -p "Повторите: " NEW_PASS2
    echo
    
    if [[ "$NEW_PASS" != "$NEW_PASS2" ]]; then
        echo -e "${RED}Пароли не совпадают!${NC}"
        exit 1
    fi
    if [[ ${#NEW_PASS} -lt 8 ]]; then
        echo -e "${RED}Пароль слишком короткий (<8 символов)${NC}"
        exit 1
    fi
    
    echo "root:$NEW_PASS" | chpasswd
    success "Пароль root изменён"
    
    echo -e "\n${YELLOW}🛡️ 4. Настройка UFW Firewall...${NC}"
    echo -e "\n${YELLOW}Настройка UFW...${NC}"
    ufw --force enable -y
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow "$SSH_PORT"/tcp
    success "SSH порт $SSH_PORT открыт в UFW"
    
    echo -e "\n${GREEN}SSH $SSH_PORT уже добавлен в UFW${NC}"
    echo -e "\n${YELLOW}Дополнительные порты:${NC}"
    
    while true; do
        read -p "${YELLOW}Добавить порт? (y/n): ${NC}" ADD_MORE
        if [[ "$ADD_MORE" =~ ^[nN]$ ]]; then
            break
        fi
        
        if [[ "$ADD_MORE" =~ ^[yY]$ ]]; then
            read -p "${YELLOW}Номер порта: ${NC}" PORT_INPUT
            if [[ "$PORT_INPUT" =~ ^[0-9]+$ ]] && [[ "$PORT_INPUT" -ge 1 ]] && [[ "$PORT_INPUT" -le 65535 ]]; then
                if [[ "$PORT_INPUT" != "$SSH_PORT" ]]; then
                    ufw allow "$PORT_INPUT"/tcp
                    ADDITIONAL_PORTS+=("$PORT_INPUT")
                    success "Порт $PORT_INPUT/tcp добавлен"
                else
                    echo -e "${YELLOW}Порт $PORT_INPUT = SSH, пропускаю${NC}"
                fi
            else
                echo -e "${YELLOW}Неверный порт: $PORT_INPUT${NC}"
            fi
        fi
        echo
    done
    
    ufw reload
    echo -e "\n${GREEN}UFW статус:${NC}"
    ufw status
    
    echo -e "\n${YELLOW}🚫 5. Запрет ping...${NC}"
    log "Запрет ICMP (ping)..."
    echo "net.ipv4.icmp_echo_ignore_all = 1" >> /etc/sysctl.conf
    sysctl -p
    success "Ping запрещён"
    
    echo -e "\n${YELLOW}⚡ 6. Fail2ban + Kernel...${NC}"
    log "Установка Fail2ban..."
    apt install -y -qq fail2ban
    cat > /etc/fail2ban/jail.d/sshd.conf << EOF
[sshd]
enabled = true
port = $SSH_PORT
bantime = 2592000
findtime = 86400
maxretry = 3
EOF
    systemctl restart fail2ban
    systemctl enable fail2ban
    success "Fail2ban: 3→30 дней (порт $SSH_PORT)"
    
    log "Kernel hardening..."
    echo "net.ipv4.tcp_syncookies = 1" >> /etc/sysctl.conf
    sysctl -p
    success "Kernel: SYN flood защита"
    
    echo -e "\n${GREEN}📋 7. Финальный отчёт...${NC}"
    show_final_report
}

show_final_report() {
    clear
    cat << EOF
${GREEN}🎉 НАСТРОЙКА ЗАВЕРШЕНА! v2.2.1${NC}

${YELLOW}✅ ВСЁ УСТАНОВЛЕНО:${NC}

🔐 SSH: порт ${GREEN}$SSH_PORT${NC}
🔑 Root: пароль ${GREEN}ИЗМЕНЁН${NC}
🛡️ UFW: ${RED}deny incoming${NC}
   ${GREEN}• $SSH_PORT/tcp${NC} (SSH)

EOF
    
    if [ ${#ADDITIONAL_PORTS[@]} -gt 0 ]; then
        for port in "${ADDITIONAL_PORTS[@]}"; do
            echo "   ${GREEN}• $port/tcp${NC}"
        done
    else
        echo "   ${YELLOW}• доп. порты не добавлены${NC}"
    fi
    
    cat << EOF
🚫 Ping: ${RED}ЗАПРЕЩЁН${NC}
⚡ Fail2ban: ${YELLOW}3→30 дней${NC} (SSH $SSH_PORT)
🛠️ Kernel: ${GREEN}SYN защита${NC}

${YELLOW}📊 Лог:${NC} $LOG_FILE

${GREEN}✅ VPS готов к работе!${NC}
EOF
}

main "$@"
