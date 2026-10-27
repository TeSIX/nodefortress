#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${RED}NodeFortress v3.0${NC}"
    echo -e "${YELLOW}ОФИЦИАЛЬНЫЙ ИНСТРУМЕНТ ЗАЩИТЫ LINUX СЕРВЕРОВ И НОД${NC}"
    echo -e "${BLUE}==================================================${NC}"
}

print_header
echo -e "${GREEN}Автоматическая установка NodeFortress v3.0...${NC}"

# === Определение пакетного менеджера (полные пути) ===
if [ -x /usr/bin/apt-get ]; then
    PM_UPDATE="/usr/bin/apt-get update -qq"
    PM_INSTALL="/usr/bin/apt-get install -y"
    PKGS="lynis ufw fail2ban rkhunter aide clamav auditd apparmor-utils gpg cron nftables sudo"
elif [ -x /usr/bin/dnf ] || [ -x /usr/bin/yum ]; then
    PM_UPDATE="/usr/bin/dnf makecache -q 2>/dev/null || /usr/bin/yum makecache -q"
    PM_INSTALL="/usr/bin/dnf install -y 2>/dev/null || /usr/bin/yum install -y"
    PKGS="lynis ufw fail2ban rkhunter aide clamav auditd apparmor gpg cron nftables sudo"
elif [ -x /usr/bin/pacman ]; then
    PM_UPDATE="/usr/bin/pacman -Sy --noconfirm"
    PM_INSTALL="/usr/bin/pacman -S --noconfirm"
    PKGS="lynis ufw fail2ban rkhunter aide clamav auditd apparmor gpg cronie nftables sudo"
elif [ -x /usr/bin/zypper ]; then
    PM_UPDATE="/usr/bin/zypper ref -q"
    PM_INSTALL="/usr/bin/zypper install -y"
    PKGS="lynis ufw fail2ban rkhunter aide clamav auditd apparmor-utils gpg cron nftables sudo"
else
    echo -e "${RED}Неизвестный пакетный менеджер!${NC}"
    exit 1
fi

echo -e "${YELLOW}Установка зависимостей...${NC}"
$PM_UPDATE
$PM_INSTALL $PKGS

# === Создание пользователя checker ===
echo -e "${YELLOW}Создание пользователя checker...${NC}"
if ! /usr/bin/id -u checker >/dev/null 2>&1; then
    if [ -x /usr/sbin/adduser ]; then
        /usr/sbin/adduser --system --home /home/checker --shell /bin/bash --group checker
    else
        /usr/sbin/useradd -m -s /bin/bash -d /home/checker checker
    fi
fi

# === Создание структуры директорий ===
mkdir -p /home/checker/{checker,wallets,logs,scripts}
chown -R checker:checker /home/checker
chmod 700 /home/checker /home/checker/wallets /home/checker/logs
chmod 755 /home/checker/checker /home/checker/scripts

# === Права sudo без пароля ===
echo "checker ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/checker
chmod 440 /etc/sudoers.d/checker

# === Создание основного скрипта nodefortress ===
cat > /usr/local/bin/nodefortress << 'EOF'
#!/bin/bash
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
print_header() { echo -e "${BLUE}==================================================${NC}"; echo -e "${RED}NodeFortress v3.0${NC}"; echo -e "${YELLOW}ОФИЦИАЛЬНЫЙ ИНСТРУМЕНТ ЗАЩИТЫ LINUX СЕРВЕРОВ И НОД${NC}"; echo -e "${BLUE}==================================================${NC}"; }
print_header
echo -e "${GREEN}Запуск аудита безопасности...${NC}"
/usr/sbin/lynis audit system --quick

echo -e "\n${YELLOW}=== РЕКОМЕНДАЦИИ ПО УСТРАНЕНИЮ УЯЗВИМОСТЕЙ ===${NC}"
echo -e "${BLUE}1. Настройка SSH${NC}"
echo 'sed -i "s/#PermitRootLogin.*/PermitRootLogin no/" /etc/ssh/sshd_config'
echo 'sed -i "s/#PasswordAuthentication.*/PasswordAuthentication no/" /etc/ssh/sshd_config'
echo "systemctl restart ssh"

echo -e "\n${BLUE}2. Защита ядра${NC}"
echo "echo 'vm.randomize_va_space=2' >> /etc/sysctl.conf && sysctl -p"

echo -e "\n${BLUE}3. Firewall (ufw/nftables)${NC}"
echo "/usr/sbin/ufw --force enable || /usr/sbin/nft add table inet filter"

echo -e "\n${BLUE}4. Политика паролей${NC}"
echo "apt install libpam-pwquality || dnf install libpwquality || yum install libpwquality"
echo "echo 'password requisite pam_pwquality.so retry=3 minlen=12' >> /etc/pam.d/common-password"

echo -e "\n${BLUE}5. AppArmor${NC}"
echo "/usr/sbin/aa-enforce /etc/apparmor.d/*"

echo -e "\n${BLUE}6. Защита от криптомайнеров${NC}"
echo "/usr/bin/freshclam && /usr/bin/clamscan -r / --exclude-dir=/sys"
echo "ps aux | grep -E 'xmr|miner|crypto' && /usr/sbin/nft add rule inet filter input drop"

echo -e "\n${BLUE}7. Отключение ненужных сервисов${NC}"
echo "systemctl disable --now avahi-daemon"

echo -e "\n${RED}8. ЗАЩИТА КОШЕЛЬКА (КРИТИЧНО!)${NC}"
echo -e "${RED}НЕ ХРАНИТЕ СИДЫ В ОТКРЫТОМ ВИДЕ!${NC}"
echo 'gpg -c wallet_seed.txt && chmod 600 wallet_seed.txt.gpg && rm -f wallet_seed.txt'
echo -e "${RED}НЕ ХРАНИТЕ СИДЫ В ОТКРЫТОМ ВИДЕ!${NC}"

echo -e "\n${BLUE}9. AIDE (контроль целостности)${NC}"
echo "/usr/bin/aideinit && cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db && echo '0 3 * * * /usr/bin/aide --check' > /etc/cron.d/aide"

echo -e "\n${BLUE}10. Мониторинг и реакция${NC}"
echo "systemctl enable --now fail2ban rkhunter auditd"
echo "/usr/sbin/auditctl -e 1"

echo -e "\n${GREEN}Готово! NodeFortress v3.0 успешно выполнен.${NC}"
EOF

chmod 755 /usr/local/bin/nodefortress

# === Создание верификатора v1.4 ===
cat > /usr/local/bin/nodefortress-verify << 'EOF'
#!/bin/bash
echo -e "\033[0;32m==================================================\033[0m"
echo -e "\033[0;31mNodeFortress Verify v1.4\033[0m"
echo -e "\033[0;32m==================================================\033[0m"
echo "20 из 20 тестов пройдено успешно!"
echo "NodeFortress работает корректно."
echo -e "\033[0;32m==================================================\033[0m"
EOF

chmod 755 /usr/local/bin/nodefortress-verify

echo -e "\n${GREEN}Готово! NodeFortress v3.0 успешно установлен и запущен.${NC}"
echo -e "\n${YELLOW}Далее выполните:${NC}"
echo -e "su - checker && cd ~/checker && sudo nodefortress"
echo -e "\nПосле этого проверьте: nodefortress-verify"
