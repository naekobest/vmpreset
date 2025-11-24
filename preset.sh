#!/bin/bash

# Ordner erstellen
mkdir -p /mnt/UNAS-{Docker,Data,Media,Photos}

# fstab-Einträge ergänzen
for name in Docker Data Media Photos; do
  entry="10.10.1.3:/var/nfs/shared/$(echo $name | tr '[:upper:]' '[:lower:]') /mnt/UNAS-$name nfs defaults 0 0"
  if ! grep -q "$entry" /etc/fstab; then
    echo "$entry" >> /etc/fstab
  fi
done

# Mounten der NFS-Shares
for name in Docker Data Media Photos; do
  mount /mnt/UNAS-$name
done
