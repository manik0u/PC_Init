# Manikou_Init

Initialisation et configuration d'un PC Linux via un script idempotent, pour le groupe Experimentations AI.

**Distributions supportées : Fedora (dnf) et Ubuntu/Debian (apt)** — le gestionnaire de paquets est détecté automatiquement (priorité à `dnf`).

## Structure

```
├── init_pc.sh          Script principal (relançable sans casser la machine)
├── paquets.list        Paquets communs, un par ligne (# = commentaire)
├── paquets_dnf.list    Paquets spécifiques Fedora (fusionnés à la liste commune)
├── paquets_apt.list    Paquets spécifiques Ubuntu/Debian (fusionnés à la liste commune)
├── dotfiles/           Fichiers liés symboliquement dans $HOME
└── .gitlab-ci.yml      Lint shellcheck à chaque push (runner taggé shell)
```

## Usage

```sh
git clone https://git.example.com/experimentations-ai/Manikou_Init.git
cd Manikou_Init
sudo ./init_pc.sh                # tout : maj système, paquets, dotfiles, config
./init_pc.sh --sans-paquets      # seulement dotfiles + config (dotfiles sans root)
```

Un journal de chaque exécution est écrit dans `/tmp/init_pc_<date>.log`.

## Modules

| Module | Rôle | Sans root ? |
|--------|------|-------------|
| `module_maj_systeme` | Fedora : `dnf upgrade -y --refresh` / Ubuntu : `apt-get update` + `upgrade` | non |
| `module_installation_paquets` | installe `paquets.list` + `paquets_<gestionnaire>.list` | non |
| `module_dotfiles` | lie chaque fichier de `dotfiles/` dans `$HOME` (existant sauvegardé en `.avant_init_<date>`) | oui |
| `module_configuration_systeme` | alias système dans `/etc/profile.d/pc_init.sh` (valide sur les deux distributions) | non |

Les modules s'activent/désactivent par les variables `module_*` en tête de `init_pc.sh`.

## Étendre

- Nouveau paquet : une ligne dans `paquets.list` (ou dans `paquets_apt.list`/`paquets_dnf.list` si le nom diffère, ex. `vim` / `vim-enhanced`).
- Nouveau dotfile : un fichier dans `dotfiles/`.
- Nouvelle distribution : ajouter une branche dans `detecter_gestionnaire`, `maj_systeme` et `installer_paquets`, et un fichier `paquets_<gestionnaire>.list` si besoin.
- Nouvelle configuration système : un bloc idempotent (tester l'existence avant d'écrire) dans le module concerné.
