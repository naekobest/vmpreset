#!/bin/bash

# ZFS Pakete installieren (Debian/Ubuntu Beispiel)
apt update
apt install -y zfsutils-linux

# Danach wie gehabt Ordner erstellen, fstab anpassen, mounten
mkdir -p /mnt/UNAS-{Docker,Data,Media,Photos}

for name in Docker Data Media Photos; do
  entry="10.10.1.3:/var/nfs/shared/$(echo $name | tr '[:upper:]' '[:lower:]') /mnt/UNAS-$name nfs defaults 0 0"
  if ! grep -q "$entry" /etc/fstab; then
    echo "$entry" >> /etc/fstab
  fi
done

for name in Docker Data Media Photos; do
  mount /mnt/UNAS-$name
done
