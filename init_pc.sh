#!/usr/bin/env bash
##############################
### init_pc.sh ###
##############################
# Initialisation / configuration d'un PC Linux (Custom)
# Distributions cibles : Fedora (dnf) et Ubuntu/Debian (apt).
# Objectif : un script idempotent, relançable sans casser la machine.
# Modules : mise à jour système, installation de paquets,
#           déploiement des dotfiles (liens symboliques), configuration système.
# Usage : sudo ./init_pc.sh [--sans-paquets]
# PS: Les paquets sont listés dans paquets.list (commun) complété par
#     paquets_apt.list / paquets_dnf.list si présents (un par ligne, # = commentaire).
# PS2: Les dotfiles à déployer sont dans le répertoire dotfiles/ du dépôt.
##############################

set -euo pipefail

#### Variables
rep_script=$(cd "$(dirname "$0")" && pwd)
fichier_paquets="$rep_script/paquets.list"
rep_dotfiles="$rep_script/dotfiles"
log="/tmp/init_pc_$(date +%Y%m%d_%H%M%S).log"
# Activation des modules (1 pour activer, 0 pour désactiver)
module_maj_systeme=1
module_installation_paquets=1
module_dotfiles=1
module_configuration_systeme=1
# Option --sans-paquets : désactive la mise à jour système et l'installation de paquets
if [ "${1:-}" = "--sans-paquets" ]; then
    module_maj_systeme=0
    module_installation_paquets=0
fi

#### Fonctions
# log : affiche un message et l'écrit dans le journal
log() { printf '%s\n' "$1" | tee -a "$log"; }
# log_cmd : exécute une commande en journalisant sa sortie
log_cmd() { "$@" >>"$log" 2>&1; }
# est_root : indique si le script est exécuté en root
est_root() { [ "$(id -u)" -eq 0 ]; }

# detecter_gestionnaire : détecte le gestionnaire de paquets et définit les commandes
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

# installer_paquets : installe la liste de paquets passée en argument
installer_paquets() {
    if [ "$gestionnaire" = dnf ]; then
        log_cmd dnf install -y "$@"
    else
        log_cmd apt-get install -y --no-install-recommends "$@"
    fi
}

#### Pré-requis
detecter_gestionnaire
log "Gestionnaire de paquets détecté: $gestionnaire"
if ! est_root && { [ "$module_maj_systeme" -eq 1 ] || [ "$module_installation_paquets" -eq 1 ]; }; then
    echo "ERREUR: la mise à jour et l'installation de paquets nécessitent root (sudo ./init_pc.sh)." >&2
    exit 1
fi
[ -f "$fichier_paquets" ] || { echo "ERREUR: $fichier_paquets absent." >&2; exit 1; }
[ -d "$rep_dotfiles" ] || { echo "ERREUR: $rep_dotfiles absent." >&2; exit 1; }
touch "$log" || { echo "ERREUR: impossible d'écrire le journal $log." >&2; exit 1; }

log "=== Initialisation PC ($(hostname -s)) - $(date +%c) ==="

### Module : mise à jour système
if [ "$module_maj_systeme" -eq 1 ]; then
    log ">> Mise à jour du système ($gestionnaire)"
    maj_systeme
    log "Mise à jour terminée."
fi

### Module : installation des paquets (idempotent : le gestionnaire saute les paquets déjà installés)
if [ "$module_installation_paquets" -eq 1 ]; then
    if ! est_root; then
        echo "ERREUR: l'installation de paquets nécessite root." >&2
        exit 1
    fi
    log ">> Installation des paquets ($gestionnaire)"
    # Liste commune + liste spécifique à la distribution si elle existe
    mapfile -t liste_paquets < <(grep -vE '^[[:space:]]*(#|$)' "$fichier_paquets")
    fichier_paquets_distro="$rep_script/paquets_${gestionnaire}.list"
    if [ -f "$fichier_paquets_distro" ]; then
        mapfile -t -O "${#liste_paquets[@]}" liste_paquets < <(grep -vE '^[[:space:]]*(#|$)' "$fichier_paquets_distro")
        log "Liste spécifique $fichier_paquets_distro ajoutée."
    fi
    log "Paquets à installer : ${liste_paquets[*]}"
    installer_paquets "${liste_paquets[@]}"
    log "Installation des paquets terminée."
fi

### Module : déploiement des dotfiles (liens symboliques dans $HOME)
if [ "$module_dotfiles" -eq 1 ]; then
    log ">> Déploiement des dotfiles de $rep_dotfiles vers $HOME"
    for dotfile in "$rep_dotfiles"/.??* "$rep_dotfiles"/*; do
        [ -e "$dotfile" ] || continue
        cible="$HOME/$(basename "$dotfile")"
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

### Module : configuration système (exemples sûrs et idempotents, à étendre selon les besoins)
if [ "$module_configuration_systeme" -eq 1 ]; then
    log ">> Configuration système"
    # Alias de base : créés une seule fois dans /etc/profile.d (valide Fedora et Ubuntu/Debian)
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

log "=== Initialisation terminée - journal: $log ==="
