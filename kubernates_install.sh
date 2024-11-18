#!/bin/bash

# Остановка выполнения скрипта при ошибках
set -e

# отключение swap
sudo swapoff -a


# Обновление списка пакетов
sudo apt-get update -y



# Установка необходимых пакетов
sudo apt-get install -y apt-transport-https ca-certificates curl




# Создание директории для ключей, если она не существует
sudo mkdir -p /etc/apt/keyrings





# Получение ключа репозитория Kubernetes и его сохранение
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg






# Добавление источника для пакетов Kubernetes, если он не существует
if ! grep -q "kubernetes.list" /etc/apt/sources.list.d/kubernetes.list; then
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list > /dev/null
fi












# Обновление списка пакетов после добавления нового источника
sudo apt-get update -y

# Установка Kubernetes и containerd
sudo apt-get install -y kubelet kubeadm kubectl containerd

# Установка пакета в состояние удержания
sudo apt-mark hold kubelet kubeadm kubectl

# Загрузка необходимых модулей
for module in br_netfilter overlay; do
    if ! lsmod | grep "$module" &> /dev/null; then
        sudo modprobe "$module"
    fi
done

# Включение пересылки пакетов и обновление конфигурации
{
    echo "net.ipv4.ip_forward=1"
    echo "net.bridge.bridge-nf-call-iptables=1"
} | sudo tee -a /etc/sysctl.conf > /dev/null

# Применение новых настроек
sudo sysctl -p /etc/sysctl.conf


# iptables: Для обеспечения правильной работы сетевых фильтров
sudo apt-get install -y iptables


# Настройка конфигурации containerd
sudo mkdir -p /etc/containerd/

# Запись конфигурации в файл
cat <<EOF | sudo tee /etc/containerd/config.toml > /dev/null
version = 2
[plugins]
  [plugins."io.containerd.grpc.v1.cri"]
   [plugins."io.containerd.grpc.v1.cri".containerd]
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes]
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
          runtime_type = "io.containerd.runc.v2"
          [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
            SystemdCgroup = true
EOF

# Перезапуск сервиса containerd для применения изменений
sudo systemctl restart containerd

# Инициализация об установки ноды
echo "Установка ноды завершина"


#############################################################################################После выполнение действий на Masternode###############################################################################################

# Получение IP-адреса мастера
echo "Получение IP-адреса мастера для настройки --apiserver-advertise-address..."
export MASTER_IP=$(ip a | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1 | head -n 1)
echo "IP-адрес мастера: $MASTER_IP"

# Инициализация Kubernetes
sudo kubeadm init \
  --apiserver-advertise-address="$MASTER_IP" \
  --pod-network-cidr 10.244.0.0/16

# Настройка kubeconfig для доступа к Kubernetes
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Установка сетевого плагина Flannel
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# Информирование пользователя об успешном завершении
echo "Установка Kubernetes завершена успешно."