# Manikou_Init

Initialisation et configuration d'un PC Linux (Debian/Ubuntu) via un script idempotent, pour le groupe Experimentations AI.

## Structure

```
├── init_pc.sh        Script principal (relançable sans casser la machine)
├── paquets.list      Paquets à installer, un par ligne (# pour un commentaire)
├── dotfiles/         Fichiers liés symboliquement dans $HOME
└── .gitlab-ci.yml    Lint shellcheck à chaque push (runner taggé shell)
```

## Usage

```sh
git clone https://git.example.com/experimentations-ai/Manikou_Init.git
cd Manikou_Init
sudo ./init_pc.sh                # tout : maj système, paquets, dotfiles, config
./init_pc.sh --sans-paquets      # seulement dotfiles + config (sans root pour les dotfiles)
```

Un journal de chaque exécution est écrit dans `/tmp/init_pc_<date>.log`.

## Modules

| Module | Rôle | Sans root ? |
|--------|------|-------------|
| `module_maj_systeme` | `apt-get update` + `upgrade` | non |
| `module_installation_paquets` | installe `paquets.list` (apt saute les paquets déjà présents) | non |
| `module_dotfiles` | lie chaque fichier de `dotfiles/` dans `$HOME` (existant sauvegardé en `.avant_init_<date>`) | oui |
| `module_configuration_systeme` | alias système dans `/etc/profile.d/pc_init.sh` | non |

Les modules s'activent/désactivent par les variables `module_*` en tête de `init_pc.sh`.

## Étendre

- Nouveau paquet : une ligne dans `paquets.list`.
- Nouveau dotfile : un fichier dans `dotfiles/`.
- Nouvelle configuration système : un bloc idempotent (tester l'existence avant d'écrire) dans le module concerné.
