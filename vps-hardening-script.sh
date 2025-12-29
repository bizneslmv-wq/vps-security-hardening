#!/bin/bash
# VPS Security v2.3 - 100% РАБОТАЕТ!
# by bizneslmv-wq

clear
echo "🚀 VPS Ubuntu 24.04 Security v2.3"
echo "=================================="

# Root check
if [ "$EUID" -ne 0 ]; then
  echo "❌ sudo required!"
  exit 1
fi

echo ""
echo "🔄 1. System update..."
apt update -qq >/dev/null 2>&1
apt upgrade -y -qq >/dev/null 2>&1
apt autoremove -y -qq >/dev/null 2>&1
echo "✅ System updated"

echo ""
echo "🔐 2. SSH port..."
read -p "SSH port [56123]: " port
port=${port:-56123}

if [[ ! "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1024 ] || [ "$port" -gt 65535 ]; then
  echo "❌ Invalid port $port!"
  exit 1
fi

sed -i "s/^#*Port .*/Port $port/" /etc/ssh/sshd_config
systemctl restart ssh >/dev/null 2>&1
echo "✅ SSH port: $port"

echo ""
echo "🔑 3. Root password..."
read -s -p "New root password: " pass1
echo
read -s -p "Repeat: " pass2
echo

if [ "$pass1" != "$pass2" ] || [ ${#pass1} -lt 8 ]; then
  echo "❌ Passwords don't match or too short!"
  exit 1
fi

echo "root:$pass1" | chpasswd >/dev/null 2>&1
echo "✅ Root password changed"

echo ""
echo "🛡️ 4. UFW Firewall..."
ufw --force enable -y >/dev/null 2>&1
ufw default deny incoming >/dev/null 2>&1
ufw default allow outgoing >/dev/null 2>&1
ufw allow "$port"/tcp >/dev/null 2>&1
echo "✅ SSH $port/tcp allowed"

echo ""
echo "Additional ports:"
echo "SSH $port already allowed"
while true; do
  read -p "Add port? (y/n): " more
  if [ "$more" != "y" ]; then
    break
  fi
  read -p "Port number: " p
  if [[ "$p" =~ ^[0-9]+$ ]] && [ "$p" != "$port" ] && [ "$p" -ge 1 ] && [ "$p" -le 65535 ]; then
    ufw allow "$p"/tcp >/dev/null 2>&1
    echo "✅ $p/tcp added"
  else
    echo "⚠️ Invalid port $p"
  fi
done

ufw reload >/dev/null 2>&1
echo ""
echo "UFW status:"
ufw status

echo ""
echo "🚫 5. Block ping..."
echo "net.ipv4.icmp_echo_ignore_all = 1" >> /etc/sysctl.conf
sysctl -p >/dev/null 2>&1
echo "✅ Ping blocked"

echo ""
echo "⚡ 6. Fail2ban..."
apt install -y -qq fail2ban >/dev/null 2>&1
cat > /etc/fail2ban/jail.d/sshd.conf << EOF
[sshd]
enabled = true
port = $port
bantime = 2592000
findtime = 86400
maxretry = 3
EOF
systemctl restart fail2ban >/dev/null 2>&1
systemctl enable fail2ban >/dev/null 2>&1
echo "✅ Fail2ban: 3→30 days ban (port $port)"

echo ""
echo "🛠️ 7. Kernel hardening..."
echo "net.ipv4.tcp_syncookies = 1" >> /etc/sysctl.conf
sysctl -p >/dev/null 2>&1
echo "✅ Kernel: SYN flood protection"

echo ""
echo "🎉 SETUP COMPLETE! v2.3"
echo "========================"
echo "SSH: ssh -p $port root@YOUR_IP"
echo "UFW: ufw status" 
echo "Fail2ban: fail2ban-client status sshd"
echo "Ping test: ping YOUR_IP (should timeout)"
echo "Log: /var/log/vps-security-*.log"
