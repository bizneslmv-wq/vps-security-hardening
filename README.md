# vps-security-hardening
Interactive bash script for Ubuntu 24.04 VPS security hardening

<div align="center">

# 🚀 VPS Ubuntu 24.04 Security Hardening

[![GitHub stars](https://img.shields.io/github/stars/bizneslmv-wq/vps-security-hardening?style=social)](https://github.com/bizneslmv-wq/vps-security-hardening/stargazers/)
[![License](https://img.shields.io/github/license/bizneslmv-wq/vps-security-hardening)](LICENSE)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04-orange?logo=ubuntu)](https://ubuntu.com/)

**Интерактивный скрипт защиты VPS Ubuntu 24.04 за 5 минут**

🔒 SSH | 🛡️ Firewall | ⚡ Fail2ban | 🛠️ Kernel

</div>

## 🚀 Быстрый старт

curl -O https://raw.githubusercontent.com/bizneslmv-wq/vps-security-hardening/main/vps-hardening-script.sh
chmod +x vps-hardening-script.sh
sudo ./vps-hardening-script.sh


**Выберите `8` (ВСЕ сразу) → Ответьте вопросы → Готово!** 🎉

## ✨ Что делает

| Компонент | Защита от |
|-----------|-----------|
| **SSH** | Brute-force, root login |
| **UFW** | DDoS, port scanning |
| **Fail2ban** | Авто-блокировка |
| **Kernel** | SYN flood, spoofing |

## 📱 Пример

SSH порт : [Enter]
Root login? [y/N]: y
HTTP(80)? [n]: y
Fail2ban [3600s]: [Enter]

[✓] SSH: порт 56123 + ключи
[✓] UFW: deny incoming
[✓] Fail2ban: 3→1ч бан
🎉 VPS защищен!


---
**by [bizneslmv-wq](https://github.com/bizneslmv-wq)** | **MIT License**
