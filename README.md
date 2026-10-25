# Computer_Init

Initialisation et configuration d'un PC Linux via un script idempotent.

**Distributions supportées : Fedora (dnf) et Ubuntu/Debian (apt)** — le gestionnaire de paquets est détecté automatiquement (priorité à `dnf`).

> **Source :** Ce projet est inspiré de [fedora-config](https://github.com/aaaaadrien/fedora-config).

## Structure

```
├── init_pc.sh          Script principal (relançable sans casser la machine)
├── paquets.list        Paquets natifs communs
├── paquets_dnf.list    Paquets spécifiques Fedora (fusionnés à la liste commune)
├── paquets_apt.list    Paquets spécifiques Ubuntu/Debian
├── localdeb.list       Paquets .deb locaux téléchargés (add:/del: URL)
├── snap.list           Snaps (add:/del:, ignoré si snap absent)
├── flatpak.list        Flatpaks (add:/del:, flathub ajouté si absent)
├── appimage.list       Appimages téléchargées (add:/del: URL)
├── gnome.list          Commandes gsettings (add:)
├── dotfiles/           Fichiers liés symboliquement dans le dossier personnel
└── .gitlab-ci.yml      Lint shellcheck à chaque push (runner taggé shell)
```

## Usage

```sh
git clone <git-repo-url>
cd Computer_Init
sudo ./init_pc.sh                # tout : maj, paquets, localdeb, snap, flatpak, appimages, dotfiles, GNOME, config, nettoyage
./init_pc.sh --sans-paquets      # modules sans root : appimages, dotfiles, GNOME
```

Un journal de chaque exécution est écrit dans `/tmp/init_pc_<date>.log`.
Tout ce qui touche au dossier personnel cible l'utilisateur qui a invoqué `sudo` (`SUDO_USER`), pas root ; `HOME_CIBLE` permet de surcharger le dossier ciblé.

## Modules

| Module | Rôle | Sans root ? |
|--------|------|-------------|
| `module_maj_systeme` | Fedora : `dnf upgrade -y --refresh` / Ubuntu : `apt-get update` + `upgrade` | non |
| `module_installation_paquets` | installe `paquets.list` + `paquets_<gestionnaire>.list` | non |
| `module_localdeb` | télécharge et installe les `.deb` de `localdeb.list` dans `$HOME/Applications/LocalDEBS` | non, apt uniquement |
| `module_snap` | installe/supprime les snaps de `snap.list` | non, ignoré si snap absent |
| `module_flatpak` | installe/supprime les flatpaks de `flatpak.list`, ajoute flathub si absent, override système exposant `xdg-config/gtk-3.0` et `gtk-4.0` aux sandbox (thème sombre) | non |
| `module_appimage` | télécharge les appimages de `appimage.list` dans `$HOME/Applications/AppImages`, puis force `GTK_THEME=Adwaita:dark` sur les fichiers de bureau AppImage | oui |
| `module_dotfiles` | lie chaque fichier de `dotfiles/` dans le dossier personnel (existant sauvegardé) | oui |
| `module_gnome` | applique les `gsettings` de `gnome.list` en tant qu'utilisateur ciblé | oui (session graphique recommandée) |
| `module_configuration_systeme` | alias système dans `/etc/profile.d/init_pc.sh` | non |
| `module_nettoyage` | `dnf autoremove` / `apt-get autoremove` | non |

Les modules s'activent/désactivent par les variables `module_*` en tête de `init_pc.sh`.

> **Thème sombre des AppImages** : les AppImages embarquent leur propre GTK et ignorent les réglages système (thème, etc.), donc le thème doit être présent au lancement. `module_appimage` ajoute `GTK_THEME=Adwaita:dark` au préfixe `env` de la ligne `Exec` de chaque fichier de bureau AppImage de `~/.local/share/applications/`. L'étape est idempotente et auto-réparatrice : Gear Lever réécrit ces fichiers de bureau à chaque mise à jour (en perdant le préfixe `env`), relancer le script restaure le thème. Alternative manuelle : le champ « Variables d'environnement » de l'UI Gear Lever.

## Syntaxe des listes applicatives

```
add:élément    # installe l'élément s'il est absent (idempotent)
del:élément    # supprime l'élément s'il est présent
# commentaire  # ignoré
```

Pour `localdeb.list` et `appimage.list`, l'élément est une URL directe vers le fichier (`.deb` ou `.AppImage`).

## Étendre

- Nouveau paquet natif : une ligne dans `paquets.list` (ou `paquets_apt.list`/`paquets_dnf.list` si le nom diffère).
- Nouvelle application : `add:` dans la liste du canal souhaité (`flatpak.list`, `snap.list`, `appimage.list`, `localdeb.list`).
- Nouveau réglage GNOME : `add:gsettings ...` dans `gnome.list`.
- Nouveau dotfile : un fichier dans `dotfiles/`.
- Nouvelle distribution : ajouter une branche dans `detecter_gestionnaire`, `maj_systeme`, `nettoyage_systeme` et le module paquets.
