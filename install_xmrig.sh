#!/bin/bash

# Задаем переменные
XMRIG_VERSION="6.15.0"
XMRIG_DIR="/usr/local/xmrig"
XMRIG_BIN="$XMRIG_DIR/xmrig"
POOL="xmr-eu1.nanopool.org:14444"
WALLET="4A9SeKhwWx8DtAboVp1e1LdbgrRJxvjEFNh4VNw1NDng6ELLeKJPVrPQ9n9eNc4iLVC4BKeR4egnUL68D1qUmdJ7N3TaB5w"

# Создание директории для XMRig
sudo mkdir -p $XMRIG_DIR

# Загрузка и распаковка XMRig
wget https://github.com/xmrig/xmrig/releases/download/v$XMRIG_VERSION/xmrig-$XMRIG_VERSION-linux-x64.tar.gz -O /tmp/xmrig.tar.gz
tar -xzf /tmp/xmrig.tar.gz -C /tmp
sudo mv /tmp/xmrig-$XMRIG_VERSION/xmrig $XMRIG_BIN
sudo chmod +x $XMRIG_BIN

# Генерация конфигурационных файлов и системных служб для рабочих
for i in $(seq 1 10000); do
  CONFIG_FILE="/etc/xmrig/config_worker_$i.json"
  SERVICE_FILE="/etc/systemd/system/xmrig_worker_$i.service"
  
  # Создание конфигурационного файла
  cat <<EOF | sudo tee $CONFIG_FILE
{
  "autosave": true,
  "cpu": true,
  "pools": [
    {
      "url": "$POOL",
      "user": "$WALLET",
      "pass": "worker$i",
      "coin": "monero"
    }
  ],
  "api": {
    "enabled": false,
    "port": 0
  }
}
EOF

  # Создание системного сервиса для каждого рабочего
  echo "[Unit]
Description=XMRig Miner Worker $i
After=network.target

[Service]
ExecStart=$XMRIG_BIN --config $CONFIG_FILE
Nice=10
CPUQuota=90%

[Install]
WantedBy=multi-user.target" | sudo tee $SERVICE_FILE

  # Перезагрузка системного менеджера для распознавания нового сервиса
  sudo systemctl daemon-reload

  # Включение и запуск XMRig
  sudo systemctl enable xmrig_worker_$i
  sudo systemctl start xmrig_worker_$i
done
