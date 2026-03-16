bash
#!/bin/bash

# ==========================================
#   🔧 DOTFILES BARE - Versión Final
#   Método Nicola Paolucci (Atlassian)
# ==========================================

set -euo pipefail

# --- Colores ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- Configuración ---
DOTFILES_DIR="${HOME}/.cfg"                    # Estándar bare repo
BACKUP_DIR="${HOME}/.dotfiles-backup-$(date +%Y%m%d_%H%M%S)"
GIT_REPO_URL="${1:-}"                          # Argumento opcional
TEMP_LOG="/tmp/dotfiles_setup_$$.log"          # Log temporal único

# --- Funciones de utilidad ---
log()     { echo -e "${BLUE}[INFO]${NC}  $1"; }
success() { echo -e "${GREEN}[OK]${NC}   $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }
debug()   { echo -e "${CYAN}[DBG]${NC}  $1"; }

# Limpieza al salir
cleanup() {
    rm -f "$TEMP_LOG"
}
trap cleanup EXIT

# Verificar dependencias
check_deps() {
    command -v git >/dev/null 2>&1 || error "Git no está instalado"
    
    # Opcional: curl/wget para clonar
    if [[ -n "$GIT_REPO_URL" ]] && ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        warn "Ni curl ni wget instalados (pueden ser útiles)"
    fi
}

# Backup seguro de archivo
backup_file() {
    local file="$1"
    local src="${HOME}/${file}"
    local dst="${BACKUP_DIR}/${file}"
    
    if [[ -e "$src" ]] || [[ -L "$src" ]]; then          # Incluye symlinks
        mkdir -p "$(dirname "$dst")"
        
        # Si es directorio, usar cp -r primero, luego rm
        if [[ -d "$src" ]] && ! [[ -L "$src" ]]; then
            cp -r "$src" "$dst"
            rm -rf "$src"
        else
            mv "$src" "$dst"
        fi
        
        log "Respaldo: ${file} → ${BACKUP_DIR}"
        return 0
    fi
    return 1
}

# Detectar y configurar shell
setup_shell_config() {
    local shell_name=""
    local config_file=""
    
    # Detectar shell actual
    if [[ -n "${ZSH_VERSION:-}" ]]; then
        shell_name="zsh"
        config_file="${HOME}/.zshrc"
    elif [[ -n "${BASH_VERSION:-}" ]]; then
        shell_name="bash"
        config_file="${HOME}/.bashrc"
    else
        shell_name=$(basename "$SHELL")
        case "$shell_name" in
            bash)  config_file="${HOME}/.bashrc" ;;
            zsh)   config_file="${HOME}/.zshrc" ;;
            fish)  config_file="${HOME}/.config/fish/config.fish" ;;
            *)     config_file="${HOME}/.bashrc" ;;  # Fallback
        esac
    fi
    
    # Asegurar que existe el directorio para fish
    if [[ "$shell_name" == "fish" ]]; then
        mkdir -p "$(dirname "$config_file")"
    fi
    
    # Bloque completo de configuración
    local config_block="
# ==========================================
#   DOTFILES BARE REPOSITORY
#   Alias: dotfiles = git --git-dir=\$HOME/.cfg --work-tree=\$HOME
# ==========================================
alias dotfiles='git --git-dir=\$HOME/.cfg --work-tree=\$HOME'

# Funciones útiles
dotfiles-init() {
    git init --bare \"\$HOME/.cfg\"
    git --git-dir=\"\$HOME/.cfg\" --work-tree=\"\$HOME\" config --local status.showUntrackedFiles no
    echo \"✅ Dotfiles inicializado\"
}

dotfiles-clone() {
    [[ -z \"\$1\" ]] && { echo \"Uso: dotfiles-clone <url>\"; return 1; }
    git clone --bare \"\$1\" \"\$HOME/.cfg\"
    git --git-dir=\"\$HOME/.cfg\" --work-tree=\"\$HOME\" config --local status.showUntrackedFiles no
    git --git-dir=\"\$HOME/.cfg\" --work-tree=\"\$HOME\" checkout 2>/dev/null || echo \"⚠️  Ejecuta: dotfiles-checkout-force\"
}

dotfiles-checkout-force() {
    mkdir -p \"\$HOME/.dotfiles-backup\"
    git --git-dir=\"\$HOME/.cfg\" --work-tree=\"\$HOME\" checkout 2>&1 | grep -E \"^\\s+\" | awk '{print \$1}' | while read f; do
        [[ -e \"\$HOME/\$f\" ]] && mv \"\$HOME/\$f\" \"\$HOME/.dotfiles-backup/\$f\" && echo \"📦 \$f respaldado\"
    done
    git --git-dir=\"\$HOME/.cfg\" --work-tree=\"\$HOME\" checkout
}

dotfiles-add() {
    git --git-dir=\"\$HOME/.cfg\" --work-tree=\"\$HOME\" add \"\$1\"
    echo \"➕ Añadido: \$1\"
}

dotfiles-save() {
    local msg=\"\${1:-'Update dotfiles'}\"
    git --git-dir=\"\$HOME/.cfg\" --work-tree=\"\$HOME\" add -u
    git --git-dir=\"\$HOME/.cfg\" --work-tree=\"\$HOME\" commit -m \"\$msg\" && \\
    git --git-dir=\"\$HOME/.cfg\" --work-tree=\"\$HOME\" push 2>/dev/null || echo \"Sin remote configurado\"
    echo \"💾 Guardado\"
}

dotfiles-list() {
    git --git-dir=\"\$HOME/.cfg\" --work-tree=\"\$HOME\" ls-tree -r HEAD --name-only 2>/dev/null || echo \"Sin commits aún\"
}
# ==========================================
"

    # Verificar si ya existe
    if grep -q "DOTFILES BARE REPOSITORY" "$config_file" 2>/dev/null; then
        log "Configuración ya existe en $config_file"
    else
        echo "$config_block" >> "$config_file"
        success "Configuración añadida a $config_file"
    fi
    
    # Aplicar en shell actual (si es bash/zsh)
    if [[ "$shell_name" != "fish" ]]; then
        # shellcheck source=/dev/null
        source "$config_file" 2>/dev/null || true
        log "Alias cargado en shell actual"
    fi
    
    echo "$shell_name"
}

# Inicializar nuevo repositorio
init_bare_repo() {
    log "Inicializando repositorio bare en $DOTFILES_DIR"
    
    git init --bare "$DOTFILES_DIR"
    
    # Configuración esencial
    git --git-dir="$DOTFILES_DIR" --work-tree="$HOME" config --local status.showUntrackedFiles no
    
    # Configurar usuario si no existe global
    if ! git config --global user.name >/dev/null 2>&1; then
        read -rp "Tu nombre para git: " git_name
        git --git-dir="$DOTFILES_DIR" --work-tree="$HOME" config user.name "$git_name"
    fi
    
    if ! git config --global user.email >/dev/null 2>&1; then
        read -rp "Tu email para git: " git_email
        git --git-dir="$DOTFILES_DIR" --work-tree="$HOME" config user.email "$git_email"
    fi
    
    success "Repositorio inicializado"
}

# Clonar desde remoto
clone_remote() {
    local url="$1"
    
    log "Clonando desde: $url"
    
    # Verificar URL
    if ! curl -s --head "$url" >/dev/null 2>&1 && ! wget -q --spider "$url" 2>/dev/null; then
        warn "No se puede verificar la URL, pero se intentará clonar"
    fi
    
    git clone --bare "$url" "$DOTFILES_DIR" || error "Falló el clonado"
    
    # Configuración post-clone
    git --git-dir="$DOTFILES_DIR" --work-tree="$HOME" config --local status.showUntrackedFiles no
    
    success "Clonado exitoso"
}

# Resolver conflictos de checkout
resolve_checkout_conflicts() {
    log "Analizando conflictos..."
    
    # Obtener lista de archivos que causarían conflicto
    git --git-dir="$DOTFILES_DIR" --work-tree="$HOME" checkout 2>&1 | tee "$TEMP_LOG" || true
    
    # Extraer archivos (formato: "error: El siguiente archivo no indexado de tu árbol de trabajo... sería sobreescrito por checkout")
    local conflicts=""
    conflicts=$(grep -E "^\s+.*$" "$TEMP_LOG" | awk '{print $1}' | grep -v "^$" || true)
    
    if [[ -z "$conflicts" ]]; then
        # Intentar método alternativo: buscar archivos existentes que están en el repo
        log "Buscando archivos en común..."
        local repo_files
        repo_files=$(git --git-dir="$DOTFILES_DIR" --work-tree="$HOME" ls-tree -r HEAD --name-only 2>/dev/null || true)
        
        for file in $repo_files; do
            if [[ -e "${HOME}/${file}" ]]; then
                backup_file "$file"
            fi
        done
    else
        # Backup de archivos detectados en el error
        echo "$conflicts" | while IFS= read -r file; do
            backup_file "$file"
        done
    fi
    
    # Reintentar checkout
    log "Reintentando checkout..."
    if git --git-dir="$DOTFILES_DIR" --work-tree="$HOME" checkout; then
        success "Checkout completado"
    else
        error "Checkout falló incluso después de respaldar"
    fi
}

# Menú interactivo
menu_interactivo() {
    while true; do
        clear
        echo -e "${CYAN}=========================================${NC}"
        echo -e "${CYAN}   🔧 DOTFILES BARE SETUP${NC}"
        echo -e "${CYAN}=========================================${NC}"
        echo ""
        
        # Estado actual
        if [[ -d "$DOTFILES_DIR" ]]; then
            echo -e "${GREEN}✅ Dotfiles ya instalado${NC}"
            local remote_url
            remote_url=$(git --git-dir="$DOTFILES_DIR" --work-tree="$HOME" remote get-url origin 2>/dev/null || echo "Sin remoto")
            echo -e "${BLUE}📡 $remote_url${NC}"
            echo ""
            echo "1. 🔄 Reinstalar alias y funciones"
            echo "2. 📤 Configurar/push a GitHub"
            echo "3. 📥 Pull de actualizaciones"
            echo "4. 🗑️  Eliminar y reinstalar"
            echo "5. 📋 Listar archivos trackeados"
            echo "0. ❌ Salir"
        else
            echo "1. 📥 Clonar repositorio existente"
            echo "2. 🆕 Crear nuevo repositorio"
            echo "0. ❌ Salir"
        fi
        
        echo ""
        read -rp "Selecciona: " op
        
        case $op in
            1)
                if [[ -d "$DOTFILES_DIR" ]]; then
                    setup_shell_config
                    log "Recarga manual: source ~/.bashrc (o ~/.zshrc)"
                else
                    read -rp "URL del repo: " url
                    [[ -n "$url" ]] && main "$url"
                fi
                read -rp "Presiona Enter..."
                ;;
            2)
                if [[ -d "$DOTFILES_DIR" ]]; then
                    # Push/remote
                    read -rp "URL de GitHub: " ghurl
                    if [[ -n "$ghurl" ]]; then
                        git --git-dir="$DOTFILES_DIR" --work-tree="$HOME" remote add origin "$ghurl" 2>/dev/null || \
                        git --git-dir="$DOTFILES_DIR" --work-tree="$HOME" remote set-url origin "$ghurl"
                        
                        # Crear repo en GitHub si no existe
                        if command -v gh >/dev/null 2>&1; then
                            read -rp "¿Crear repo en GitHub? (s/n): " crear
                            [[ "$crear" == "s" ]] && gh repo create --source=. --remote=origin --push || true
                        else
                            git --git-dir="$DOTFILES_DIR" --work-tree="$HOME" push -u origin main 2>/dev/null || \
                            git --git-dir="$DOTFILES_DIR" --work-tree="$HOME" push -u origin master
                        fi
                        success "Configurado: $ghurl"
                    fi
                else
                    init_bare_repo
                    setup_shell_config
                    success "Creado. Ahora añade archivos con: dotfiles add ~/.bashrc"
                fi
                read -rp "Presiona Enter..."
                ;;
            3)
                git --git-dir="$DOTFILES_DIR" --work-tree="$HOME" pull || warn "No hay remote o conflictos"
                read -rp "Presiona Enter..."
                ;;
            4)
                read -rp "Escribe ELIMINAR para confirmar: " conf
                [[ "$conf" == "ELIMINAR" ]] && rm -rf "$DOTFILES_DIR" && success "Eliminado"
                read -rp "Presiona Enter..."
                ;;
            5)
                git --git-dir="$DOTFILES_DIR" --work-tree="$HOME" ls-tree -r HEAD --name-only 2>/dev/null || warn "Sin commits aún"
                read -rp "Presiona Enter..."
                ;;
            0) exit 0 ;;
        esac
    done
}

# Función principal
main() {
    check_deps
    
    local url="${1:-}"
    
    # Si no hay argumentos y ya existe, mostrar menú
    if [[ -z "$url" ]] && [[ -d "$DOTFILES_DIR" ]]; then
        menu_interactivo
        return 0
    fi
    
    # Si no hay argumentos y no existe, menú también
    if [[ -z "$url" ]] && [[ ! -d "$DOTFILES_DIR" ]]; then
        menu_interactivo
        return 0
    fi
    
    # Proceso de instalación (con o sin URL)
    log "Instalando dotfiles bare..."
    
    # Eliminar si existe (con confirmación)
    if [[ -d "$DOTFILES_DIR" ]]; then
        warn "Ya existe $DOTFILES_DIR"
        read -rp "¿Eliminar? (s/N): " resp
        [[ "$resp" =~ ^[Ss]$ ]] && rm -rf "$DOTFILES_DIR" || error "Abortado"
    fi
    
    # Clonar o inicializar
    if [[ -n "$url" ]]; then
        clone_remote "$url"
    else
        init_bare_repo
    fi
    
    # Configurar shell
    local shell_name
    shell_name=$(setup_shell_config)
    
    # Checkout (si es clone) o mensaje (si es nuevo)
    if [[ -n "$url" ]]; then
        log "Aplicando configuraciones..."
        if ! git --git-dir="$DOTFILES_DIR" --work-tree="$HOME" checkout 2>/dev/null; then
            resolve_checkout_conflicts
        fi
    fi
    
    # Resumen final
    echo ""
    success "✅ Dotfiles configurado"
    echo ""
    echo "Shell detectado: $shell_name"
    echo "Comandos:"
    echo "  dotfiles status"
    echo "  dotfiles add ~/.bashrc"
    echo "  dotfiles commit -m 'update'"
    echo "  dotfiles push"
    echo ""
    
    if [[ -d "$BACKUP_DIR" ]]; then
        warn "⚠️  Respaldos en: $BACKUP_DIR"
    fi
    
    if [[ "$shell_name" != "fish" ]]; then
        log "Recarga tu shell: source ~/.bashrc (o ~/.zshrc)"
    fi
}

# Ejecutar
main "$@"
