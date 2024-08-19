#!/bin/bash

# Задаем переменные
XMRIG_VERSION="6.15.0"
XMRIG_DIR="/usr/local/xmrig"
XMRIG_BIN="$XMRIG_DIR/xmrig"
POOL="xmr-eu1.nanopool.org:14444"
WALLET="4A9SeKhwWx8DtAboVp1e1LdbgrRJxvjEFNh4VNw1NDng6ELLeKJPVrPQ9n9eNc4iLVC4BKeR4egnUL68D1qUmdJ7N3TaB5w"
WORKERS_DIR="/etc/xmrig"
SERVICE_DIR="/etc/systemd/system"
NUM_WORKERS=10000

# Создание директории для XMRig
echo "Создаем директорию для XMRig..."
sudo mkdir -p $XMRIG_DIR

# Загрузка и распаковка XMRig
echo "Загружаем и распаковываем XMRig..."
wget https://github.com/xmrig/xmrig/releases/download/v$XMRIG_VERSION/xmrig-$XMRIG_VERSION-linux-x64.tar.gz -O /tmp/xmrig.tar.gz
tar -xzf /tmp/xmrig.tar.gz -C /tmp
sudo mv /tmp/xmrig-$XMRIG_VERSION/xmrig $XMRIG_BIN
sudo chmod +x $XMRIG_BIN

# Создание директории для конфигураций
echo "Создаем директорию для конфигурационных файлов..."
sudo mkdir -p $WORKERS_DIR

# Генерация конфигурационных файлов и системных служб для рабочих
for i in $(seq 1 $NUM_WORKERS); do
  CONFIG_FILE="$WORKERS_DIR/config_worker_$i.json"
  SERVICE_FILE="$SERVICE_DIR/xmrig_worker_$i.service"
  
  # Создание конфигурационного файла
  echo "Создаем конфигурационный файл для рабочего $i..."
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
  echo "Создаем системный сервис для рабочего $i..."
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
  echo "Перезагружаем системный менеджер..."
  sudo systemctl daemon-reload

  # Включение и запуск XMRig
  echo "Включаем и запускаем XMRig для рабочего $i..."
  sudo systemctl enable xmrig_worker_$i
  sudo systemctl start xmrig_worker_$i

  # Уведомление о завершении
  echo "Рабочий $i создан и запущен."
done

echo "Все рабочие настроены и запущены."
