#!/bin/bash
# VPS Ubuntu 24.04 Security Script v2.2
# Author: Maks Leto (bizneslmv-wq)
# GitHub: https://github.com/bizneslmv-wq/vps-security-hardening
################################################################################

set -e

RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' BLUE='\033[0;34m' NC='\033[0m'
LOG_FILE="/var/log/vps-security-$(date +%Y%m%d-%H%M%S).log"

log() { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"; }
success() { echo -e "${GREEN}[✓]${NC} $1" | tee -a "$LOG_FILE"; }
error() { echo -e "${RED}[✗]${NC} $1" | tee -a "$LOG_FILE"; exit 1; }

SSH_PORT=""
ADDITIONAL_PORTS=()

check_root() { [[ $EUID -ne 0 ]] && error "Запуск от root (sudo)"; }

show_banner() {
    clear
    cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║           🚀 VPS Ubuntu 24.04 Security Script v2.2           ║
║                        by bizneslmv-wq                       ║
╚═══════════════════════════════════════════════════════════════╝
EOF
}

main() {
    check_root
    show_banner
    
    # ┌─── 1. ОБНОВЛЕНИЕ СИСТЕМЫ ─────────────────────┐
    echo -e "\n${YELLOW}🔄 Устанавливаю: Обновление системы...${NC}"
    log "Обновление системы (security)..."
    apt update
    apt upgrade -y --allow-downgrades -o Dir::Etc::SourceList::Mode=force-confdef
    apt autoremove -y
    success "Система обновлена"
    
    # ┌─── 2. СМЕНА SSH ПОРТА ───────────────────────┐
    echo -e "\n${YELLOW}🔐 Устанавливаю: Новый SSH порт...${NC}"
    echo -e "\n${YELLOW}🔐 Смена SSH порта:${NC}"
    read -p "Новый SSH порт [56123]: " SSH_PORT_INPUT
    SSH_PORT=${SSH_PORT_INPUT:-56123}
    
    if ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]] || [[ "$SSH_PORT" -lt 1024 ]] || [[ "$SSH_PORT" -gt 65535 ]]; then
        error "Неверный порт: $SSH_PORT (1024-65535)"
    fi
    
    log "Смена SSH на порт $SSH_PORT..."
    sed -i "s/^#*Port .*/Port $SSH_PORT/" /etc/ssh/sshd_config
    systemctl restart ssh
    success "SSH порт: $SSH_PORT"
    
    # ┌─── 3. СМЕНА ПАРОЛЯ ROOT ─────────────────────┐
    echo -e "\n${YELLOW}🔑 Устанавливаю: Новый пароль root...${NC}"
    echo -e "\n${YELLOW}🔑 Смена пароля root:${NC}"
    read -s -p "Новый пароль root: " NEW_PASS
    echo
    read -s -p "Повторите пароль: " NEW_PASS2
    echo
    
    [[ "$NEW_PASS" != "$NEW_PASS2" ]] && error "Пароли не совпадают"
    [[ ${#NEW_PASS} -lt 8 ]] && error "Пароль < 8 символов"
    
    echo "root:$NEW_PASS" | chpasswd
    success "Пароль root изменён"
    
    # ┌─── 4. UFW FIREWALL ───────────────────────────┐
    echo -e "\n${YELLOW}🛡️ Устанавливаю: UFW Firewall...${NC}"
    echo -e "\n${YELLOW}🛡️ UFW Firewall:${NC}"
    log "Включение UFW..."
    
    ufw --force enable
    ufw default deny incoming
    ufw default allow outgoing
    
    # ТОЛЬКО SSH порт автоматически!
    ufw allow "$SSH_PORT"/tcp
    success "SSH порт $SSH_PORT добавлен"
    
    # 🔥 ИНТЕРАКТИВНЫЙ ЦИКЛ ПОРТОВ!
    echo -e "\n${YELLOW}Дополнительные порты для UFW:${NC}"
    echo -e "${GREEN}SSH $SSH_PORT уже добавлен${NC}"
    echo
    
    while true; do
        read -p "${YELLOW}Добавить ещё порт? (y/n): ${NC}" ADD_MORE
        [[ "$ADD_MORE" =~ ^[nN]$ ]] && break
        
        if [[ "$ADD_MORE" =~ ^[yY]$ ]]; then
            read -p "${YELLOW}Введите номер порта: ${NC}" PORT_INPUT
            
            if [[ "$PORT_INPUT" =~ ^[0-9]+$ ]] && [[ "$PORT_INPUT" -ge 1 ]] && [[ "$PORT_INPUT" -le 65535 ]]; then
                if [[ "$PORT_INPUT" != "$SSH_PORT" ]]; then
                    ufw allow "$PORT_INPUT"/tcp
                    ADDITIONAL_PORTS+=("$PORT_INPUT")
                    success "Порт $PORT_INPUT/tcp добавлен"
                else
                    echo -e "${YELLOW}Порт $PORT_INPUT уже используется SSH${NC}"
                fi
            else
                echo -e "${YELLOW}Неверный порт: $PORT_INPUT (1-65535)${NC}"
            fi
        else
            echo -e "${YELLOW}Введи y или n${NC}"
        fi
        echo
    done
    
    ufw reload
    echo -e "\n${GREEN}UFW статус:${NC}"
    ufw status
    
    # ┌─── 5. ЗАПРЕТ PING ───────────────────────────┐
    echo -e "\n${YELLOW}🚫 Устанавливаю: Запрет ping...${NC}"
    log "Запрет ping (ICMP)..."
    echo "net.ipv4.icmp_echo_ignore_all = 1" >> /etc/sysctl.conf
    sysctl -p
    success "Ping запрещён"
    
    # ┌─── 6. FAIL2BAN + KERNEL (БЕЗ ВОПРОСА!) ───────┐
    echo -e "\n${YELLOW}⚡ Устанавливаю: Fail2ban + Kernel...${NC}"
    log "Установка Fail2ban..."
    apt install -y fail2ban
    cat > /etc/fail2ban/jail.d/sshd.conf << EOF
[sshd]
enabled = true
port = $SSH_PORT
bantime = 2592000
findtime = 86400
maxretry = 3
EOF
    systemctl restart fail2ban && systemctl enable fail2ban
    success "Fail2ban: 3→30 дней (SSH $SSH_PORT)"
    
    log "Kernel hardening..."
    echo "net.ipv4.tcp_syncookies = 1" >> /etc/sysctl.conf
    sysctl -p
    success "Kernel: SYN flood защита"
    
    # ┌─── 7. ФИНАЛЬНЫЙ ОТЧЁТ ───────────────────────┐
    echo -e "\n${GREEN}📋 ПОКАЗЫВАЮ финальный отчёт...${NC}"
    show_final_report
}

show_final_report() {
    clear
    cat << EOF
${GREEN}🎉 НАСТРОЙКА ЗАВЕРШЕНА! v2.2${NC}

${YELLOW}📋 ВСЁ УСТАНОВЛЕНО:${NC}

🔐 ${GREEN}SSH:${NC}
  • Порт: ${YELLOW}$SSH_PORT${NC}
  • Команда: ${GREEN}ssh -p $SSH_PORT root@IP${NC}

🔑 ${GREEN}Root:${NC}
  • Пароль: ${GREEN}✓ ИЗМЕНЁН${NC}

🛡️ ${GREEN}UFW:${NC}
  • deny incoming | allow outgoing
  • Открытые порты:
    ${GREEN}  • $SSH_PORT/tcp${NC} ${YELLOW}(SSH)${NC}
EOF
    
    if [ ${#ADDITIONAL_PORTS[@]} -gt 0 ]; then
        for port in "${ADDITIONAL_PORTS[@]}"; do
            echo "    ${GREEN}  • $port/tcp${NC}"
        done
    else
        echo "    ${YELLOW}  • (доп. порты не добавлены)${NC}"
    fi
    
    cat << EOF

🚫 ${GREEN}Сеть:${NC}
  • Ping: ${RED}ЗАПРЕЩЁН${NC}

⚡ ${GREEN}Fail2ban:${NC}
  • SSH $SSH_PORT: ${YELLOW}3→30 дней${NC}

🛠️ ${GREEN}Kernel:${NC}
  • SYN flood: ${GREEN}✓${NC}

${YELLOW}📊 Лог:${NC} $LOG_FILE

${GREEN}✅ VPS полностью готов!${NC}
EOF
}

main "$@"
