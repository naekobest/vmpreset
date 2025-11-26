#!/bin/bash

set -e

echo "Starte Ubuntu Server Setup..."

if sudo apt update && sudo apt upgrade -y; then
  echo "Update & Upgrade erfolgreich abgeschlossen."
else
  echo "Fehler bei Update & Upgrade!" >&2
  exit 1
fi

while true; do
  read -p "Bitte neuen Hostnamen eingeben (nur Buchstaben, Zahlen, Bindestriche): " hostname
  if [[ "$hostname" =~ ^[a-zA-Z0-9-]+$ ]]; then
    echo "Hostname wird gesetzt auf: $hostname"
    break
  else
    echo "Ungültiger Hostname. Bitte nur Buchstaben, Zahlen und Bindestriche verwenden."
  fi
done

echo "$hostname" | sudo tee /etc/hostname > /dev/null
if sudo hostnamectl set-hostname "$hostname"; then
  echo "Hostname gesetzt."
else
  echo "Fehler beim Setzen des Hostnamens!" >&2
  exit 1
fi

if ! grep -q "127.0.1.1 $hostname" /etc/hosts; then
  echo "127.0.1.1 $hostname" | sudo tee -a /etc/hosts > /dev/null
fi

if [ "$SUDO_USER" ]; then
  current_user=$SUDO_USER
else
  current_user=$(whoami)
fi

echo "Füge User $current_user zur sudo-Gruppe hinzu..."
if sudo usermod -aG sudo "$current_user"; then
  echo "User $current_user hat jetzt sudo Rechte."
else
  echo "Fehler beim Hinzufügen von sudo-Rechten!" >&2
  exit 1
fi

echo "Installiere qemu-guest-agent..."
if sudo apt install -y qemu-guest-agent; then
  sudo systemctl enable qemu-guest-agent
  sudo systemctl start qemu-guest-agent
  echo "qemu-guest-agent erfolgreich installiert und gestartet."
else
  echo "Fehler bei der Installation von qemu-guest-agent!" >&2
  exit 1
fi

echo "Installiere Docker und Docker Compose..."

if ! command -v docker >/dev/null 2>&1; then
  sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt update
  if ! sudo apt install -y docker-ce docker-ce-cli containerd.io; then
    echo "Fehler bei der Docker Installation!" >&2
    exit 1
  fi
  echo "Docker erfolgreich installiert."
else
  echo "Docker ist bereits installiert."
fi

DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep -Po '"tag_name": "\K.*?(?=")')
echo "Installiere Docker Compose Version $DOCKER_COMPOSE_VERSION..."
if sudo curl -L "https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose; then
  sudo chmod +x /usr/local/bin/docker-compose
  echo "Docker Compose installiert."
else
  echo "Fehler bei der Installation von Docker Compose!" >&2
  exit 1
fi

echo "Füge User $current_user zur Docker-Gruppe hinzu..."
if sudo usermod -aG docker "$current_user"; then
  echo "User $current_user ist jetzt Mitglied der Docker-Gruppe."
else
  echo "Fehler beim Hinzufügen des Users zu Docker-Gruppe!" >&2
  exit 1
fi

echo "Installiere cifs-utils..."
if sudo apt install -y cifs-utils; then
  echo "cifs-utils installiert."
else
  echo "Fehler bei der Installation von cifs-utils!" >&2
  exit 1
fi

echo "Erstelle Verzeichnisse unter /mnt/pve..."
for dir in docker data media photos; do
  target="/mnt/pve/$dir"
  if [ ! -d "$target" ]; then
    sudo mkdir -p "$target"
    sudo chown "$current_user":"$current_user" "$target"
    echo "Verzeichnis $target erstellt."
  else
    echo "Verzeichnis $target existiert bereits."
  fi
done

cred_file="/home/$current_user/.smbcredentials"
if [ ! -f "$cred_file" ]; then
  echo "Erstelle Datei $cred_file mit Zugangsdaten..."
  sudo -u "$current_user" bash -c "cat > $cred_file" <<EOF
username=proxmox
password=J275gTkpTMyD
EOF
  sudo chmod 600 "$cred_file"
  echo "Datei $cred_file erstellt und Berechtigungen gesetzt."
else
  echo "Datei $cred_file existiert bereits."
fi

echo "Füge CIFS-Mounts zur /etc/fstab hinzu..."

fstab_lines=(
"//10.10.1.3/docker /mnt/pve/docker cifs credentials=$cred_file,iocharset=utf8,uid=1000,gid=1000,file_mode=0664,dir_mode=0775 0 0"
"//10.10.1.3/data /mnt/pve/data cifs credentials=$cred_file,iocharset=utf8,uid=1000,gid=1000,file_mode=0664,dir_mode=0775 0 0"
"//10.10.1.3/media /mnt/pve/media cifs credentials=$cred_file,iocharset=utf8,uid=1000,gid=1000,file_mode=0664,dir_mode=0775 0 0"
"//10.10.1.3/photos /mnt/pve/photos cifs credentials=$cred_file,iocharset=utf8,uid=1000,gid=1000,file_mode=0664,dir_mode=0775 0 0"
)

for line in "${fstab_lines[@]}"; do
  if ! grep -Fxq "$line" /etc/fstab; then
    echo "$line" | sudo tee -a /etc/fstab > /dev/null
    echo "Eintrag für Mount hinzugefügt: $line"
  else
    echo "Eintrag bereits vorhanden: $line"
  fi
done

echo "Mounten aller Einträge..."
if sudo mount -a; then
  echo "Mount erfolgreich."
else
  echo "Fehler beim Mounten!" >&2
  exit 1
fi

sudo systemctl daemon-reload

echo "Docker Version:"
docker --version
echo "Docker Compose Version:"
docker-compose --version

echo "Setup abgeschlossen. Bitte neu einloggen, damit Gruppenrechte wirksam werden."
