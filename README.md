# fixation_IP

Donne une **adresse IP fixe et permanente** à une VM Ubuntu Server (ex. VM Proxmox), avec **Netplan**.

Un script pose quelques questions, vérifie les réponses, puis applique tout seul.

---

## 🚀 Utilisation rapide

```bash
git clone https://github.com/Rachkpt/fixation_IP.git
cd fixation_IP/script
sudo bash fixe_ip.sh
```

L'interface réseau est détectée automatiquement. Le script demande :

```
IP fixe (ex. 10.2.3.237) :
Masque en CIDR (ex. 24 pour 255.255.255.0, 22 pour 255.255.252.0) [22] :
Gateway [10.2.0.1] :
DNS, séparés par une virgule [8.8.8.8,1.1.1.1] :
```

Les valeurs déjà en place sont proposées par défaut : appuie sur Entrée pour les garder.

### Ce que le script vérifie

- l'IP et le masque sont valides ;
- la gateway est dans le même réseau que l'IP ;
- l'IP n'est pas la gateway elle-même ;
- l'IP ne répond pas déjà sur le réseau (sinon il avertit d'un conflit).

Il affiche la configuration complète et **ne modifie rien sans ta confirmation**.

### Ce qu'il fait ensuite

1. met de côté les anciens fichiers Netplan (sauvegarde dans `/root/netplan-backup-…`) ;
2. écrit `/etc/netplan/01-netcfg.yaml` (droits 600) ;
3. désactive la réécriture réseau de cloud-init (sinon l'IP revient au redémarrage) ;
4. vérifie la syntaxe avec `netplan generate` (si elle est refusée, l'ancienne config est restaurée) ;
5. applique avec `netplan apply` et vérifie que l'IP est bien active.

### Tester sans rien modifier

```bash
DRY_RUN=1 bash fixe_ip.sh
```

---

## ⚠️ Connexion SSH

Si tu es connecté en SSH et que l'IP change, **ta session va se couper** : reconnecte-toi sur la nouvelle IP (le script te l'affiche).

---

## 🔁 Revenir en arrière

```bash
sudo cp /root/netplan-backup-XXXX/*.yaml /etc/netplan/
sudo netplan apply
```

Remplace `XXXX` par le dossier affiché à la fin du script.

---

## 🔍 Vérifier

```bash
ip -4 addr show       # l'IP fixe doit apparaître
ip route              # la ligne "default via ..." doit pointer sur la gateway
```

---

## 📝 Configuration manuelle (sans le script)

Équivalent de ce que le script écrit dans `/etc/netplan/01-netcfg.yaml` :

```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    ens18:                        # ⚠️ ton interface (voir : ip -o link show)
      dhcp4: no
      addresses:
        - 10.2.3.237/22           # IP fixe + masque CIDR
      routes:
        - to: default
          via: 10.2.0.1           # gateway
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
```

Puis : `sudo chmod 600 /etc/netplan/01-netcfg.yaml && sudo netplan apply`

Et désactiver cloud-init pour que le réseau ne soit plus réécrit :

```bash
sudo touch /etc/cloud/cloud-init.disabled
echo 'network: {config: disabled}' | sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
```

---

## 📁 Contenu

- `script/fixe_ip.sh` — le script interactif
- `script/edit.txt` — exemple de configuration Netplan
