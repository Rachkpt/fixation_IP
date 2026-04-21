# fixation_IP
fixe les IP

# Configuration IP Fixe sur Ubuntu Server (VM Proxmox)

Ce guide explique comment attribuer une adresse IP fixe à une machine virtuelle Ubuntu Server tournant sous Proxmox, en utilisant **Netplan**.

Créer le fichier de configuration Netplan

sudo nano /etc/netplan/01-netcfg.yaml

sudo chmod 600 /etc/netplan/01-netcfg.yaml

sudo netplan tr

Appliquer définitivement

sudo netplan apply

## ⚠️ Important : Désactiver cloud-init

Si votre VM a été créée à partir d'un template cloud, `cloud-init` peut écraser votre configuration réseau à chaque démarrage.

```bash
sudo touch /etc/cloud/cloud-init.disabled
echo 'network: {config: disabled}' | sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
