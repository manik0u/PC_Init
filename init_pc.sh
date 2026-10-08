#!/usr/bin/env bash
##############################
### init_pc.sh ###
##############################
# Initialisation / configuration d'un PC Linux (Custom)
# Fusion des approches Manikou_Init et ubuntu-config.
# Distributions cibles : Fedora (dnf) et Ubuntu/Debian (apt).
# Objectif : un script idempotent, relançable sans casser la machine.
# Modules : mise à jour système, paquets natifs, .deb locaux, snap, flatpak,
#           appimages, dotfiles, configuration GNOME, configuration système, nettoyage.
# Usage : sudo ./init_pc.sh [--sans-paquets]
# Listes de paquets : paquets.list (commun) + paquets_apt.list / paquets_dnf.list
# Listes applicatives (syntaxe add:/del:) : flatpak.list, snap.list, appimage.list,
#           localdeb.list (apt uniquement), gnome.list (commandes gsettings)
# PS: Tout ce qui touche au dossier personnel cible l'utilisateur qui a invoqué sudo
#     (SUDO_USER), pas root.
##############################

set -euo pipefail

#### Variables
rep_script=$(cd "$(dirname "$0")" && pwd)
log="/tmp/init_pc_$(date +%Y%m%d_%H%M%S).log"
# Utilisateur et dossier personnel ciblés (SUDO_USER quand le script est lancé via sudo)
# PC_HOME_CIBLE permet de surcharger le dossier ciblé (tests, cas particuliers)
utilisateur_cible=${SUDO_USER:-$(id -un)}
home_cible=${PC_HOME_CIBLE:-$(getent passwd "$utilisateur_cible" | cut -d: -f6)}
rep_applications="$home_cible/Applications"
rep_appimages="$rep_applications/AppImages"
rep_localdebs="$rep_applications/LocalDEBS"
# Activation des modules (1 pour activer, 0 pour désactiver)
module_maj_systeme=1
module_installation_paquets=1
module_localdeb=1
module_snap=1
module_flatpak=1
module_appimage=1
module_dotfiles=1
module_gnome=1
module_configuration_systeme=1
module_nettoyage=1
# Option --sans-paquets : désactive tout ce qui nécessite root
if [ "${1:-}" = "--sans-paquets" ]; then
    module_maj_systeme=0
    module_installation_paquets=0
    module_localdeb=0
    module_snap=0
    module_nettoyage=0
fi

#### Fonctions
# log : affiche un message et l'écrit dans le journal
log() { printf '%s\n' "$1" | tee -a "$log"; }
# log_cmd : exécute une commande en journalisant sa sortie
log_cmd() { "$@" >>"$log" 2>&1; }
# est_root : indique si le script est exécuté en root
est_root() { [ "$(id -u)" -eq 0 ]; }
# lire_liste_add_del : lit un fichier add:/del: et appelle les traitements passés en argument
#   $1: fichier de liste, $2: fonction add(action), $3: fonction del(action)
lire_liste_add_del() {
    local fichier=$1 action
    while read -r action; do
        case "$action" in
            add:*) traiter_add "${action#add:}" ;;
            del:*) traiter_del "${action#del:}" ;;
        esac
    done < <(grep -vE '^[[:space:]]*(#|$)' "$fichier")
}
traiter_add() { :; }
traiter_del() { :; }

# detecter_gestionnaire : détecte le gestionnaire de paquets
#   $gestionnaire : "dnf" (Fedora) ou "apt" (Ubuntu/Debian)
gestionnaire=""
detecter_gestionnaire() {
    if command -v dnf >/dev/null; then
        gestionnaire=dnf
    elif command -v apt-get >/dev/null; then
        gestionnaire=apt
    else
        echo "ERREUR: ni dnf ni apt-get trouvés. Distributions supportées: Fedora, Ubuntu/Debian." >&2
        exit 1
    fi
}

# maj_systeme : met à jour la liste des paquets puis le système
maj_systeme() {
    if [ "$gestionnaire" = dnf ]; then
        log_cmd dnf upgrade -y --refresh
    else
        log_cmd apt-get update
        log_cmd apt-get upgrade -y
    fi
}

# nettoyage_systeme : supprime les paquets orphelins
nettoyage_systeme() {
    if [ "$gestionnaire" = dnf ]; then
        log_cmd dnf autoremove -y
    else
        log_cmd apt-get autoremove -y
    fi
}

#### Pré-requis
detecter_gestionnaire
log "Gestionnaire de paquets détecté: $gestionnaire"
log "Utilisateur ciblé pour le dossier personnel: $utilisateur_cible ($home_cible)"
[ -d "$home_cible" ] || { echo "ERREUR: le dossier personnel de $utilisateur_cible est introuvable." >&2; exit 1; }
touch "$log" || { echo "ERREUR: impossible d'écrire le journal $log." >&2; exit 1; }

log "=== Initialisation PC ($(hostname -s)) - $(date +%c) ==="

### Module : mise à jour système
if [ "$module_maj_systeme" -eq 1 ]; then
    if ! est_root; then
        echo "ERREUR: la mise à jour système nécessite root (sudo ./init_pc.sh)." >&2
        exit 1
    fi
    log ">> Mise à jour du système ($gestionnaire)"
    maj_systeme
    log "Mise à jour terminée."
fi

### Module : installation des paquets natifs (idempotent : le gestionnaire saute les paquets déjà installés)
if [ "$module_installation_paquets" -eq 1 ]; then
    if ! est_root; then
        echo "ERREUR: l'installation de paquets nécessite root." >&2
        exit 1
    fi
    log ">> Installation des paquets ($gestionnaire)"
    # Liste commune + liste spécifique à la distribution si elle existe
    fichier_paquets="$rep_script/paquets.list"
    mapfile -t liste_paquets < <(grep -vE '^[[:space:]]*(#|$)' "$fichier_paquets")
    fichier_paquets_distro="$rep_script/paquets_${gestionnaire}.list"
    if [ -f "$fichier_paquets_distro" ]; then
        mapfile -t -O "${#liste_paquets[@]}" liste_paquets < <(grep -vE '^[[:space:]]*(#|$)' "$fichier_paquets_distro")
        log "Liste spécifique $fichier_paquets_distro ajoutée."
    fi
    log "Paquets à installer : ${liste_paquets[*]}"
    if [ "$gestionnaire" = dnf ]; then
        log_cmd dnf install -y "${liste_paquets[@]}"
    else
        log_cmd apt-get install -y --no-install-recommends "${liste_paquets[@]}"
    fi
    log "Installation des paquets terminée."
fi

### Module : paquets .deb locaux téléchargés (apt uniquement)
#   add:URL_installe_le_fichier_s_il_est_absent   del:URL_supprime_paquet_et_fichier
if [ "$module_localdeb" -eq 1 ]; then
    log ">> Gestion des paquets .deb locaux"
    fichier_localdeb="$rep_script/localdeb.list"
    if [ "$gestionnaire" != apt ]; then
        log "Information: module localdeb ignoré ($gestionnaire détecté, les .deb ne s'installent que via apt)."
    elif [ ! -f "$fichier_localdeb" ]; then
        log "Information: $fichier_localdeb absent, rien à faire."
    else
        mkdir -p "$rep_localdebs"
        chown "$utilisateur_cible" "$rep_localdebs" 2>/dev/null || true
        traiter_add() {
            local url=$1 fichier="${1##*/}"
            if [ -e "$rep_localdebs/$fichier" ]; then
                log "OK: $fichier déjà présent."
                return
            fi
            log "Installation du .deb local $fichier"
            log_cmd curl -fsSL -o "$rep_localdebs/$fichier" "$url"
            chown "$utilisateur_cible" "$rep_localdebs/$fichier"
            log_cmd apt-get install -y "$rep_localdebs/$fichier"
        }
        traiter_del() {
            local url=$1 fichier="${1##*/}" nom_paquet
            if [ ! -e "$rep_localdebs/$fichier" ]; then
                return
            fi
            nom_paquet=$(dpkg-deb --field "$rep_localdebs/$fichier" package)
            log "Suppression du paquet local $nom_paquet ($fichier)"
            log_cmd apt-get remove -y "$nom_paquet"
            rm -f "$rep_localdebs/$fichier"
        }
        lire_liste_add_del "$fichier_localdeb"
        log "Gestion des .deb locaux terminée."
    fi
fi

### Module : paquets snap (ignoré si snap absent, cas Fedora typique)
if [ "$module_snap" -eq 1 ]; then
    log ">> Gestion des paquets snap"
    fichier_snap="$rep_script/snap.list"
    if ! command -v snap >/dev/null; then
        log "Information: snap absent, module ignoré."
    elif [ ! -f "$fichier_snap" ]; then
        log "Information: $fichier_snap absent, rien à faire."
    else
        if ! est_root; then
            echo "ERREUR: la gestion des snaps nécessite root." >&2
            exit 1
        fi
        traiter_add() {
            if snap info "$1" | grep -q installed; then
                log "OK: snap $1 déjà installé."
            else
                log "Installation du snap $1"
                log_cmd snap install "$1" --classic
            fi
        }
        traiter_del() {
            if snap info "$1" | grep -q installed; then
                log "Suppression du snap $1"
                log_cmd snap remove "$1"
            fi
        }
        lire_liste_add_del "$fichier_snap"
        log "Gestion des snaps terminée."
    fi
fi

### Module : paquets flatpak (flathub ajouté si absent)
if [ "$module_flatpak" -eq 1 ]; then
    log ">> Gestion des paquets flatpak"
    fichier_flatpak="$rep_script/flatpak.list"
    if ! command -v flatpak >/dev/null; then
        log "Information: flatpak absent, module ignoré."
    elif [ ! -f "$fichier_flatpak" ]; then
        log "Information: $fichier_flatpak absent, rien à faire."
    else
        if ! est_root; then
            echo "ERREUR: la gestion des flatpaks nécessite root." >&2
            exit 1
        fi
        if ! flatpak remotes | grep -q flathub; then
            log "Ajout du dépôt flathub"
            log_cmd flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
        fi
        traiter_add() {
            if flatpak info "$1" >/dev/null 2>&1; then
                log "OK: flatpak $1 déjà installé."
            else
                log "Installation du flatpak $1"
                log_cmd flatpak install -y flathub "$1"
            fi
        }
        traiter_del() {
            if flatpak info "$1" >/dev/null 2>&1; then
                log "Suppression du flatpak $1"
                log_cmd flatpak uninstall -y "$1"
            fi
        }
        lire_liste_add_del "$fichier_flatpak"
        log "Gestion des flatpaks terminée."
    fi
fi

### Module : appimages (téléchargées dans $HOME/Applications/AppImages)
if [ "$module_appimage" -eq 1 ]; then
    log ">> Gestion des appimages"
    fichier_appimage="$rep_script/appimage.list"
    if [ ! -f "$fichier_appimage" ]; then
        log "Information: $fichier_appimage absent, rien à faire."
    else
        mkdir -p "$rep_appimages"
        chown "$utilisateur_cible" "$rep_appimages" 2>/dev/null || true
        traiter_add() {
            local url=$1 fichier="${1##*/}"
            if [ -e "$rep_appimages/$fichier" ]; then
                log "OK: appimage $fichier déjà présente."
                return
            fi
            log "Téléchargement de l'appimage $fichier"
            log_cmd curl -fsSL -o "$rep_appimages/$fichier" "$url"
            chmod +x "$rep_appimages/$fichier"
            chown "$utilisateur_cible" "$rep_appimages/$fichier"
        }
        traiter_del() {
            local fichier="${1##*/}"
            if [ -e "$rep_appimages/$fichier" ]; then
                log "Suppression de l'appimage $fichier"
                rm -f "$rep_appimages/$fichier"
            fi
        }
        lire_liste_add_del "$fichier_appimage"
        log "Gestion des appimages terminée."
    fi
fi

### Module : déploiement des dotfiles (liens symboliques dans le dossier personnel ciblé)
if [ "$module_dotfiles" -eq 1 ]; then
    rep_dotfiles="$rep_script/dotfiles"
    log ">> Déploiement des dotfiles de $rep_dotfiles vers $home_cible"
    for dotfile in "$rep_dotfiles"/.??* "$rep_dotfiles"/*; do
        [ -e "$dotfile" ] || continue
        cible="$home_cible/$(basename "$dotfile")"
        if [ -L "$cible" ]; then
            log "OK: $cible est déjà un lien symbolique."
        elif [ -e "$cible" ]; then
            sauvegarde="${cible}.avant_init_$(date +%Y%m%d_%H%M%S)"
            mv "$cible" "$sauvegarde"
            log "Existant sauvegardé: $cible -> $sauvegarde"
            ln -s "$dotfile" "$cible"
            log "Lien créé: $cible -> $dotfile"
        else
            ln -s "$dotfile" "$cible"
            log "Lien créé: $cible -> $dotfile"
        fi
    done
    log "Déploiement des dotfiles terminé."
fi

### Module : configuration GNOME (exécutée en tant qu'utilisateur ciblé, pas root)
if [ "$module_gnome" -eq 1 ]; then
    log ">> Configuration GNOME"
    fichier_gnome="$rep_script/gnome.list"
    if ! command -v gsettings >/dev/null; then
        log "Information: gsettings indisponible, module ignoré."
    elif [ ! -f "$fichier_gnome" ]; then
        log "Information: $fichier_gnome absent, rien à faire."
    else
        while read -r action; do
            case "$action" in
                add:*) commande=${action#add:} ;;
                *) continue ;;
            esac
            if sudo -u "$utilisateur_cible" env XDG_RUNTIME_DIR="/run/user/$(id -u "$utilisateur_cible")" bash -c "$commande" >/dev/null 2>>"$log"; then
                log "Appliqué: $commande"
            else
                log "AVERTISSEMENT: échec de « $commande » (session graphique requise pour certaines clés)."
            fi
        done < <(grep -vE '^[[:space:]]*(#|$)' "$fichier_gnome")
        log "Configuration GNOME terminée."
    fi
fi

### Module : configuration système (idempotent, à étendre selon les besoins)
if [ "$module_configuration_systeme" -eq 1 ]; then
    log ">> Configuration système"
    fichier_alias=/etc/profile.d/pc_init.sh
    if est_root; then
        if [ ! -f "$fichier_alias" ]; then
            printf '# Alias ajoutés par init_pc.sh (Manikou_Init)\nalias ls="ls --color=auto"\nalias ll="ls -alF"\n' > "$fichier_alias"
            chmod 644 "$fichier_alias"
            log "Alias système créés dans $fichier_alias."
        else
            log "OK: $fichier_alias existe déjà."
        fi
    else
        log "Information: configuration système ignorée sans root."
    fi
    log "Configuration système terminée."
fi

### Module : nettoyage des paquets orphelins
if [ "$module_nettoyage" -eq 1 ]; then
    if est_root; then
        log ">> Nettoyage des paquets orphelins"
        nettoyage_systeme
        log "Nettoyage terminé."
    fi
fi

log "=== Initialisation terminée - journal: $log ==="
