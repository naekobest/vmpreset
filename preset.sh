#!/bin/bash

# qemu-guest-agent installieren
apt-get update
apt-get install -y qemu-guest-agent

# ZFS Pakete installieren (Debian/Ubuntu Beispiel)
apt-get install -y nfs-common

# Ordner erstellen mit Groß-/Kleinschreibung
mkdir -p /mnt/pve/UNAS-{Docker,Data,Media,Photos}

# fstab-Einträge ergänzen mit Pfaden in Kleinbuchstaben
for name in Docker Data Media Photos; do
  lowername=$(echo "$name" | tr '[:upper:]' '[:lower:]')
  entry="10.10.1.3:/var/nfs/shared/${lowername} /mnt/pve/UNAS-${name} nfs defaults 0 0"
  if ! grep -q "$entry" /etc/fstab; then
    echo "$entry" >> /etc/fstab
  fi
done

# Mounten der NFS-Shares mit Groß-/Kleinschreibung
for name in Docker Data Media Photos; do
  mount /mnt/pve/UNAS-"$name"
done
