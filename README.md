# fixation_IP
fixe les IP

# Configuration IP Fixe sur Ubuntu Server (VM Proxmox)

Ce guide explique comment attribuer une adresse IP fixe à une machine virtuelle Ubuntu Server tournant sous Proxmox, en utilisant **Netplan**.

## 📋 Prérequis

- Une VM Ubuntu Server (18.04 ou ultérieur) sur Proxmox
- Accès `root` ou `sudo` à la VM
- Connaître les informations réseau suivantes :
  - Adresse IP souhaitée
  - Masque de sous-réseau (notation CIDR)
  - Passerelle par défaut
  - Serveurs DNS

## ⚠️ Important : Désactiver cloud-init

Si votre VM a été créée à partir d'un template cloud, `cloud-init` peut écraser votre configuration réseau à chaque démarrage.

```bash
sudo touch /etc/cloud/cloud-init.disabled
echo 'network: {config: disabled}' | sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
