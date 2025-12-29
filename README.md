<div align="center">

# 🚀 VPS Ubuntu 24.04 Security Hardening Script

**Интерактивный bash скрипт для полной защиты VPS Ubuntu 24.04.X**

🔒 **SSH Hardening** | 🛡️ **UFW Firewall** | ⚡ **Fail2ban** | 🛠️ **Kernel Hardening**

</div>

## 🚀 Быстрый старт (3 команды)

1. Скачать скрипт `curl -O https://raw.githubusercontent.com/bizneslmv-wq/vps-security-hardening/main/vps-hardening-script.sh`

2. Права на выполнение `chmod +x vps-hardening-script.sh`

3. Запустить sudo `./vps-hardening-script.sh`


**Выберите `8` (ВСЁ сразу) → Ответьте на вопросы → VPS защищён!** 🎉

## ✨ Что делает скрипт

| Компонент | Защита от | Результат |
|-----------|-----------|-----------|
| **🔐 SSH** | Brute-force, root login | Порт ????? + ключи only |
| **🛡️ UFW** | DDoS, port scanning | `deny incoming` + нужные порты |
| **⚡ Fail2ban** | Авто-брутфорс | 3 попытки → 1 час бан |
| **🛠️ Kernel** | SYN flood, spoofing | `tcp_syncookies=1` |
| **📊 Auditd** | Несанкц. изменения | Мониторинг `/etc/ssh/sshd_config` |
| **🚫 Services** | Ненужные сервисы | `cups`, `avahi-daemon` off |

## 📱 Пример выполнения


