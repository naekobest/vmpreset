# curl -o setup.sh https://raw.githubusercontent.com/naekobest/vmpreset/refs/heads/master/preset.sh
# chmod +x setup.sh
# sudo bash ./setup.sh
#!/bin/bash

set -e

# Farbdefinitionen
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # Keine Farbe

function info {
  echo -e "${BLUE}==> $1${NC}"
}

function success {
  echo -e "${GREEN}✔ $1${NC}"
}

function warning {
  echo -e "${YELLOW}⚠ $1${NC}"
}

function error {
  echo -e "${RED}✘ $1${NC}" >&2
}

info "Starte Ubuntu Server Setup..."

if sudo apt update && sudo apt upgrade -y; then
  success "Update & Upgrade erfolgreich abgeschlossen."
else
  error "Fehler bei Update & Upgrade!"
  exit 1
fi

while true; do
  read -p "Bitte neuen Hostnamen eingeben (nur Buchstaben, Zahlen, Bindestriche): " hostname
  if echo "$hostname" | grep -Eq '^[a-zA-Z0-9-]+$'; then
    info "Hostname wird gesetzt auf: $hostname"
    break
  else
    warning "Ungültiger Hostname. Bitte nur Buchstaben, Zahlen und Bindestriche verwenden."
  fi
done

echo "$hostname" | sudo tee /etc/hostname > /dev/null
if sudo hostnamectl set-hostname "$hostname"; then
  success "Hostname gesetzt."
else
  error "Fehler beim Setzen des Hostnamens!"
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

info "Füge User $current_user zur sudo-Gruppe hinzu..."
if sudo usermod -aG sudo "$current_user"; then
  success "User $current_user hat jetzt sudo Rechte."
else
  error "Fehler beim Hinzufügen von sudo-Rechten!"
  exit 1
fi

info "Installiere qemu-guest-agent..."
if sudo apt install -y qemu-guest-agent; then
  sudo systemctl enable qemu-guest-agent
  sudo systemctl start qemu-guest-agent
  success "qemu-guest-agent erfolgreich installiert und gestartet."
else
  error "Fehler bei der Installation von qemu-guest-agent!"
  exit 1
fi

info "Installiere Docker und Docker Compose..."

if ! command -v docker >/dev/null 2>&1; then
  sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt update
  if ! sudo apt install -y docker-ce docker-ce-cli containerd.io; then
    error "Fehler bei der Docker Installation!"
    exit 1
  fi
  success "Docker erfolgreich installiert."
else
  warning "Docker ist bereits installiert."
fi

DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep -Po '"tag_name": "\K.*?(?=")')
info "Installiere Docker Compose Version $DOCKER_COMPOSE_VERSION..."
if sudo curl -L "https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose; then
  sudo chmod +x /usr/local/bin/docker-compose
  success "Docker Compose installiert."
else
  error "Fehler bei der Installation von Docker Compose!"
  exit 1
fi

info "Füge User $current_user zur Docker-Gruppe hinzu..."
if sudo usermod -aG docker "$current_user"; then
  success "User $current_user ist jetzt Mitglied der Docker-Gruppe."
else
  error "Fehler beim Hinzufügen des Users zu Docker-Gruppe!"
  exit 1
fi

info "Installiere cifs-utils..."
if sudo apt install -y cifs-utils; then
  success "cifs-utils installiert."
else
  error "Fehler bei der Installation von cifs-utils!"
  exit 1
fi

info "Erstelle Verzeichnisse unter /mnt/pve..."
for dir in docker data media photos; do
  target="/mnt/pve/$dir"
  if [ ! -d "$target" ]; then
    sudo mkdir -p "$target"
    sudo chown "$current_user":"$current_user" "$target"
    success "Verzeichnis $target erstellt."
  else
    warning "Verzeichnis $target existiert bereits."
  fi
done

cred_file="/home/$current_user/.smbcredentials"
if [ ! -f "$cred_file" ]; then
  info "Erstelle Datei $cred_file mit Zugangsdaten..."
  sudo -u "$current_user" bash -c "cat > $cred_file" <<EOF
username=proxmox
password=J275gTkpTMyD
EOF
  sudo chmod 600 "$cred_file"
  success "Datei $cred_file erstellt und Berechtigungen gesetzt."
else
  warning "Datei $cred_file existiert bereits."
fi

info "Füge CIFS-Mounts zur /etc/fstab hinzu..."

fstab_lines=(
"//10.10.1.3/docker /mnt/pve/docker cifs credentials=$cred_file,iocharset=utf8,uid=1000,gid=1000,file_mode=0664,dir_mode=0775 0 0"
"//10.10.1.3/data /mnt/pve/data cifs credentials=$cred_file,iocharset=utf8,uid=1000,gid=1000,file_mode=0664,dir_mode=0775 0 0"
"//10.10.1.3/media /mnt/pve/media cifs credentials=$cred_file,iocharset=utf8,uid=1000,gid=1000,file_mode=0664,dir_mode=0775 0 0"
"//10.10.1.3/photos /mnt/pve/photos cifs credentials=$cred_file,iocharset=utf8,uid=1000,gid=1000,file_mode=0664,dir_mode=0775 0 0"
)

for line in "${fstab_lines[@]}"; do
  if ! grep -Fxq "$line" /etc/fstab; then
    echo "$line" | sudo tee -a /etc/fstab > /dev/null
    success "Eintrag für Mount hinzugefügt: $line"
  else
    warning "Eintrag bereits vorhanden: $line"
  fi
done

info "Mounten aller Einträge..."
if sudo mount -a; then
  success "Mount erfolgreich."
else
  error "Fehler beim Mounten!"
  exit 1
fi

sudo systemctl daemon-reload

compose_dir="/home/$current_user/komodo_periphery"
mkdir -p "$compose_dir"
sudo chown "$current_user":"$current_user" "$compose_dir"

compose_file="$compose_dir/docker-compose.yaml"

cat > "$compose_file" <<'EOF'
####################################
# 🦎 KOMODO COMPOSE - PERIPHERY 🦎 #
####################################

## This compose file will deploy:
##   1. Komodo Periphery

services:
  periphery:
    image: ghcr.io/moghtech/komodo-periphery:${COMPOSE_KOMODO_IMAGE_TAG:-latest}
    labels:
      komodo.skip: # Prevent Komodo from stopping with StopAllContainers
    restart: unless-stopped
    ## [https://komo.do/docs/connect-servers#configuration](https://komo.do/docs/connect-servers#configuration)
    environment:
      PERIPHERY_ROOT_DIRECTORY: ${PERIPHERY_ROOT_DIRECTORY:-/etc/komodo}
      ## Pass the same passkey as used by the Komodo Core connecting to this Periphery agent.
      PERIPHERY_PASSKEYS: I84vOL0sqQ9itfrjHaCM5yYdbfJEMPaw
      ## Make server run over https
      PERIPHERY_SSL_ENABLED: true
      ## Specify whether to disable the terminals feature
      ## and disallow remote shell access (inside the Periphery container).
      PERIPHERY_DISABLE_TERMINALS: false
      ## If the disk size is overreporting, can use one of these to 
      ## whitelist / blacklist the disks to filter them, whichever is easier.
      ## Accepts comma separated list of paths.
      ## Usually whitelisting just /etc/hostname gives correct size for single root disk.
      PERIPHERY_INCLUDE_DISK_MOUNTS: /etc/hostname
      # PERIPHERY_EXCLUDE_DISK_MOUNTS: /snap,/etc/repos
    volumes:
      ## Mount external docker socket
      - /var/run/docker.sock:/var/run/docker.sock
      ## Allow Periphery to see processes outside of container
      - /proc:/proc
      ## Specify the Periphery agent root directory.
      ## Must be the same inside and outside the container,
      ## or docker will get confused. See [https://github.com/moghtech/komodo/discussions/180](https://github.com/moghtech/komodo/discussions/180).
      ## Default: /etc/komodo.
      - ${PERIPHERY_ROOT_DIRECTORY:-/etc/komodo}:${PERIPHERY_ROOT_DIRECTORY:-/etc/komodo}
    ## If periphery is being run remote from the core server, ports need to be exposed
    # ports:
      - 8120:8120
    ## If you want to use a custom periphery config file, use command to pass it to periphery.
    # command: periphery --config-path ${PERIPHERY_ROOT_DIRECTORY:-/etc/komodo}/periphery.config.toml
EOF

success "Docker Compose Datei wurde erstellt unter $compose_file"

sudo -u "$current_user" docker-compose -f "$compose_file" up -d

success "Docker Compose Stack wurde gestartet."

success "Setup abgeschlossen. Bitte neu einloggen, damit Gruppenrechte wirksam werden."
