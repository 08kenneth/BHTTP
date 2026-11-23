#!/usr/bin/env bash
# ===================================================================
# INSTALADOR AUTOMÁTICO BTUN / BHTTP - REPOSITORIO 08kenneth/BHTTP
# ===================================================================

set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
    echo "❌ Error: Este instalador debe ejecutarse como root (sudo)." >&2
    exit 1
fi

echo "================================================================="
echo "   🚀 INICIANDO INSTALACIÓN AUTOMÁTICA DE BHTTP / BTUN           "
echo "   📦 Repositorio: https://github.com/08kenneth/BHTTP.git        "
echo "================================================================="

# 1. Actualizar e instalar dependencias del sistema
echo "1/7 🔄 Instalando dependencias del sistema..."
apt update -y
apt install -y golang git libpam0g-dev iptables build-essential nano ufw curl net-tools shadow-utils || apt install -y golang git libpam0g-dev iptables build-essential nano ufw curl net-tools passwd

# 2. Clonar o actualizar el repositorio
REPO_DIR="/root/BHTTP"
if [[ ! -d "$REPO_DIR" ]]; then
    echo "2/7 ⬇️ Clonando repositorio desde GitHub..."
    git clone https://github.com/08kenneth/BHTTP.git "$REPO_DIR"
else
    echo "2/7 ⬇️ Actualizando repositorio desde GitHub..."
    cd "$REPO_DIR" && git pull || true
fi

cd "$REPO_DIR"

# 3. Dar permisos y compilar
echo "3/7 ⚙️ Compilando binarios de Go (btun-server, bilola-server, xhttp)..."
chmod +x build-btun.sh deploy/btun/install.sh

CGO_ENABLED=1 ./build-btun.sh
ARCH=$(go env GOARCH)
go build -trimpath -ldflags="-s -w" -o build/bilola-server-linux-$ARCH ./cmd/bilola-server
go build -trimpath -ldflags="-s -w" -o build/bilola-xhttp-server-linux-$ARCH ./cmd/xhttp-server

# 4. Desplegar servicios systemd
echo "4/7 🚀 Desplegando servicios systemd de BTUN..."
./deploy/btun/install.sh

# Ajustar target por defecto de BHTTP a SSH (127.0.0.1:22)
sed -i 's/127.0.0.1:7300/127.0.0.1:22/g' /etc/systemd/system/btun-bhttp.service

# Habilitar autenticación por contraseña en OpenSSH
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
grep -q "^UseDNS" /etc/ssh/sshd_config || echo "UseDNS no" >> /etc/ssh/sshd_config
systemctl restart sshd || systemctl restart ssh

# Habilitar IP Forwarding
sysctl -w net.ipv4.ip_forward=1
grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

# 5. Abrir puertos en UFW Firewall
echo "5/7 🛡️ Configurando Firewall (UFW)..."
ufw allow 7300/tcp || true
ufw allow 7300/udp || true
ufw allow 7080/tcp || true
ufw allow 7443/tcp || true
ufw allow 80/tcp || true
ufw allow 443/tcp || true

# 6. Crear menú de administración /usr/local/bin/ktun
echo "6/7 🎮 Instalando menú de administración 'ktun'..."
cat << 'MENU_EOF' > /usr/local/bin/ktun
#!/usr/bin/env bash
set -euo pipefail
if [[ "${EUID}" -ne 0 ]]; then echo "❌ Ejecutar como root." >&2; exit 1; fi

REPO_URL="https://github.com/08kenneth/BHTTP.git"
REPO_DIR="/root/BHTTP"
BHTTP_SERVICE="/etc/systemd/system/btun-bhttp.service"
BTUN_ENV="/etc/btun/server.env"
LIMITS_FILE="/etc/security/limits.conf"

# Colores ANSI Estilo Azul Profesional
CYAN='\033[0;36m'
BLUE='\033[1;34m'
LBLUE='\033[1;36m'
GREEN='\033[1;32m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m' # No Color

show_menu() {
    clear
    echo -e "${BLUE}========================================================================${NC}"
    echo -e "${LBLUE}       ██████╗ ██╗██╗      ██████╗ ██╗      █████╗                   ${NC}"
    echo -e "${LBLUE}       ██╔══██╗██║██║     ██╔═══██╗██║     ██╔══██╗                  ${NC}"
    echo -e "${LBLUE}       ██████╔╝██║██║     ██║   ██║██║     ███████║                  ${NC}"
    echo -e "${LBLUE}       ██╔══██╗██║██║     ██║   ██║██║     ██╔══██║                  ${NC}"
    echo -e "${LBLUE}       ██████╔╝██║███████╗╚██████╔╝███████╗██║  ██║                  ${NC}"
    echo -e "${BLUE}========================================================================${NC}"
    echo -e "${CYAN}             🚀 PANEL DE ADMINISTRACIÓN BHTTP & BTUN                    ${NC}"
    echo -e "${CYAN}                📦 Repositorio: 08kenneth/BHTTP                          ${NC}"
    echo -e "${BLUE}========================================================================${NC}"

    # Extraer puertos limpios sin IP, sin corchetes y sin comas
    bhttp_raw=$(grep -E '--listen' "$BHTTP_SERVICE" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i ~ /--listen/) print $(i+1)}' | tr -d '\\' | xargs || echo "N/A")
    bhttp_clean=$(echo "$bhttp_raw" | sed -E 's/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+://g' | tr ',' ' ' | xargs)

    target_raw=$(grep -E '--target' "$BHTTP_SERVICE" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i ~ /--target/) print $(i+1)}' | tr -d '\\' | xargs || echo "127.0.0.1:22")

    btun_raw=$(grep -E '^BTUN_TCP_LISTEN=' "$BTUN_ENV" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'" || echo "7300")
    btun_clean=$(echo "$btun_raw" | sed -E 's/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+://g' | tr ',' ' ' | xargs)

    [[ -z "$bhttp_clean" ]] && bhttp_clean="N/A"
    [[ -z "$btun_clean" ]] && btun_clean="7300"

    echo -e "  ${YELLOW}📡 PUERTOS ACTIVOS${NC} : ${BOLD}BHTTP: ${bhttp_clean}${NC} | ${BOLD}BTUN: ${btun_clean}${NC}"
    echo -e "  ${YELLOW}🎯 DESTINO BHTTP  ${NC} : ${BOLD}${target_raw}${NC}"
    echo -e "${BLUE}========================================================================${NC}"
    echo -e " ${LBLUE}1)${NC} 🌐 Configurar Puertos BHTTP"
    echo -e " ${LBLUE}2)${NC} 🔄 Cambiar Destino BHTTP (SSH 22 vs BTUN 7300)"
    echo -e " ${LBLUE}3)${NC} 📡 Cambiar Puerto Nativo BTUN"
    echo -e " ${LBLUE}4)${NC} 🔍 Ver Puertos y Sockets Escuchando en Tiempo Real"
    echo -e "${BLUE}------------------------------------------------------------------------${NC}"
    echo -e " ${LBLUE}5)${NC} 👤 Crear Usuario ${CYAN}(con Días de Expiración y Límite)${NC}"
    echo -e " ${LBLUE}6)${NC} 📅 Modificar Días de Expiración de Usuario"
    echo -e " ${LBLUE}7)${NC} 🔒 Modificar Límite de Conexiones Simultáneas"
    echo -e " ${LBLUE}8)${NC} 🔑 Cambiar Contraseña de Usuario"
    echo -e " ${LBLUE}9)${NC} ❌ Eliminar Usuario"
    echo -e " ${LBLUE}10)${NC} 📋 Listar Usuarios ${CYAN}(con Cronómetro y Días Restantes)${NC}"
    echo -e "${BLUE}------------------------------------------------------------------------${NC}"
    echo -e " ${LBLUE}11)${NC} 🔄 Actualizar desde GitHub ${CYAN}(git pull + recompilar)${NC}"
    echo -e " ${LBLUE}12)${NC} 🧹 Reiniciar / Descartar Cambios Locales ${CYAN}(git reset)${NC}"
    echo -e " ${LBLUE}13)${NC} 📊 Ver Estado de Servicios y Logs"
    echo -e " ${LBLUE}14)${NC} 🔄 Reiniciar Servicios"
    echo -e " ${LBLUE}0)${NC} 🚪 Salir"
    echo -e "${BLUE}========================================================================${NC}"
    read -p "Selecciona una opción [0-14]: " option
    echo ""
}

pause() {
    echo ""
    read -p "Presiona ENTER para volver al menú principal..." _
}

show_active_ports() {
    echo -e "${BLUE}========================================================================${NC}"
    echo -e "${LBLUE}   📡 PUERTOS Y SOCKETS ACTUALMENTE ESCUCHANDO                          ${NC}"
    echo -e "${BLUE}========================================================================${NC}"
    if command -v ss >/dev/null 2>&1; then
        ss -tulpn | grep -E 'LISTEN|UNCONN' || ss -tulpn
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tulpn
    fi
    pause
}

add_bhttp_ports() {
    echo -e "${CYAN}=== CONFIGURAR PUERTOS BHTTP ===${NC}"
    read -p "Ingresa los puertos BHTTP (ejemplo: 80 8080 7080): " ports
    if [[ -n "$ports" ]]; then
        listen_arg=""
        ports_clean=$(echo "$ports" | tr ',' ' ')
        for p in $ports_clean; do
            p=$(echo "$p" | xargs)
            if [[ "$p" =~ ^[0-9]+$ ]]; then
                [[ -z "$listen_arg" ]] && listen_arg="0.0.0.0:$p" || listen_arg="$listen_arg,0.0.0.0:$p"
                command -v ufw >/dev/null 2>&1 && ufw allow "$p"/tcp >/dev/null 2>&1 || true
            fi
        done
        if [[ -n "$listen_arg" ]]; then
            sed -i -E "s|--listen [^ ]+|--listen $listen_arg|g" "$BHTTP_SERVICE"
            systemctl daemon-reload && systemctl restart btun-bhttp
            echo -e "${GREEN}✅ Puertos BHTTP actualizados a: $listen_arg${NC}"
        else
            echo -e "${RED}❌ Puertos no válidos.${NC}"
        fi
    fi
    pause
}

toggle_bhttp_target() {
    echo -e "${CYAN}=== CAMBIAR DESTINO DE BHTTP ===${NC}"
    echo "1) Apuntar a SSH (127.0.0.1:22)    [Para Apps SSH_BHTTP]"
    echo "2) Apuntar a BTUN Core (127.0.0.1:7300) [Para Apps BTUN_BHTTP]"
    read -p "Selecciona [1 o 2]: " target_opt
    if [[ "$target_opt" == "1" ]]; then
        sed -i 's|--target [^ ]*|--target 127.0.0.1:22|g' "$BHTTP_SERVICE"
        systemctl daemon-reload && systemctl restart btun-bhttp
        echo -e "${GREEN}✅ BHTTP ahora apunta a OpenSSH (127.0.0.1:22).${NC}"
    elif [[ "$target_opt" == "2" ]]; then
        sed -i 's|--target [^ ]*|--target 127.0.0.1:7300|g' "$BHTTP_SERVICE"
        systemctl daemon-reload && systemctl restart btun-bhttp
        echo -e "${GREEN}✅ BHTTP ahora apunta a BTUN Core (127.0.0.1:7300).${NC}"
    fi
    pause
}

change_btun_port() {
    echo -e "${CYAN}=== CAMBIAR PUERTO NATIVO BTUN ===${NC}"
    read -p "Nuevo puerto BTUN (ej: 7300): " new_port
    if [[ "$new_port" =~ ^[0-9]+$ ]]; then
        sed -i -E "s|^BTUN_TCP_LISTEN=.*|BTUN_TCP_LISTEN=0.0.0.0:$new_port|g" "$BTUN_ENV"
        sed -i -E "s|^BTUN_UDP_LISTEN=.*|BTUN_UDP_LISTEN=0.0.0.0:$new_port|g" "$BTUN_ENV"
        command -v ufw >/dev/null 2>&1 && ufw allow "$new_port"/tcp >/dev/null 2>&1 && ufw allow "$new_port"/udp >/dev/null 2>&1 || true
        systemctl restart btun-protocol
        echo -e "${GREEN}✅ Puerto BTUN actualizado a $new_port.${NC}"
    else
        echo -e "${RED}❌ Error: El puerto debe ser un número.${NC}"
    fi
    pause
}

add_user() {
    echo -e "${CYAN}=== CREAR NUEVO USUARIO ===${NC}"
    read -p "Nombre de usuario: " username
    [[ -z "$username" ]] && { pause; return; }
    if id "$username" &>/dev/null; then
        echo -e "${YELLOW}⚠️ El usuario '$username' ya existe.${NC}"
        pause; return
    fi
    read -p "Contraseña: " password
    [[ -z "$password" ]] && { pause; return; }
    read -p "Días de validez (ejemplo: 30): " days
    [[ -z "$days" || ! "$days" =~ ^[0-9]+$ ]] && days=30
    read -p "Límite de conexiones simultáneas (ejemplo: 2): " maxlogins
    [[ -z "$maxlogins" || ! "$maxlogins" =~ ^[0-9]+$ ]] && maxlogins=2

    useradd -m "$username" && echo "$username:$password" | chpasswd

    # Establecer fecha de expiración
    exp_date=$(date -d "+$days days" +%Y-%m-%d)
    chage -E "$exp_date" "$username"

    # Establecer límite de conexiones en limits.conf
    sed -i "/^$username /d" "$LIMITS_FILE"
    echo "$username hard maxlogins $maxlogins" >> "$LIMITS_FILE"

    echo -e "${GREEN}✅ Usuario '$username' creado con éxito.${NC}"
    echo -e "📅 Expiración: $exp_date ($days días)"
    echo -e "🔒 Límite conexiones: $maxlogins simultáneas"
    pause
}

change_user_expiration() {
    echo -e "${CYAN}=== MODIFICAR DÍAS DE EXPIRACIÓN ===${NC}"
    read -p "Nombre de usuario: " username
    if ! id "$username" &>/dev/null; then
        echo -e "${RED}❌ El usuario '$username' no existe.${NC}"
        pause; return
    fi
    read -p "Nuevos días de validez desde hoy (ejemplo: 30): " days
    if [[ "$days" =~ ^[0-9]+$ ]]; then
        exp_date=$(date -d "+$days days" +%Y-%m-%d)
        chage -E "$exp_date" "$username"
        echo -e "${GREEN}✅ Usuario '$username' actualizado. Expira el $exp_date ($days días restantes).${NC}"
    else
        echo -e "${RED}❌ Días no válidos.${NC}"
    fi
    pause
}

change_user_connections() {
    echo -e "${CYAN}=== MODIFICAR LÍMITE DE CONEXIONES ===${NC}"
    read -p "Nombre de usuario: " username
    if ! id "$username" &>/dev/null; then
        echo -e "${RED}❌ El usuario '$username' no existe.${NC}"
        pause; return
    fi
    read -p "Nuevo límite de conexiones simultáneas (ejemplo: 2): " maxlogins
    if [[ "$maxlogins" =~ ^[0-9]+$ ]]; then
        sed -i "/^$username /d" "$LIMITS_FILE"
        echo "$username hard maxlogins $maxlogins" >> "$LIMITS_FILE"
        echo -e "${GREEN}✅ Límite de '$username' established a $maxlogins conexiones simultáneas.${NC}"
    else
        echo -e "${RED}❌ Límite no válido.${NC}"
    fi
    pause
}

change_password() {
    echo -e "${CYAN}=== CAMBIAR CONTRASEÑA ===${NC}"
    read -p "Nombre de usuario: " username
    if ! id "$username" &>/dev/null; then
        echo -e "${RED}❌ El usuario '$username' no existe.${NC}"
        pause; return
    fi
    read -p "Nueva Contraseña: " password
    echo "$username:$password" | chpasswd
    echo -e "${GREEN}✅ Contraseña de '$username' actualizada.${NC}"
    pause
}

delete_user() {
    echo -e "${CYAN}=== ELIMINAR USUARIO ===${NC}"
    read -p "Nombre de usuario a eliminar: " username
    if id "$username" &>/dev/null; then
        userdel -r "$username" 2>/dev/null || userdel "$username"
        sed -i "/^$username /d" "$LIMITS_FILE"
        echo -e "${GREEN}✅ Usuario '$username' eliminado.${NC}"
    else
        echo -e "${RED}❌ El usuario '$username' no existe.${NC}"
    fi
    pause
}

list_users() {
    echo -e "${BLUE}====================================================================================================${NC}"
    echo -e "${LBLUE} 👤 USUARIOS REGISTRADOS | 📅 FECHA EXPIRACIÓN | ⏳ CRONÓMETRO (RESTA) | 🔒 LÍMITE CONEXIONES ${NC}"
    echo -e "${BLUE}====================================================================================================${NC}"
    now_sec=$(date +%s)
    awk -F: '$3 >= 1000 && $3 < 60000 {print $1}' /etc/passwd | while read -r user; do
        exp_str=$(chage -l "$user" 2>/dev/null | grep 'Account expires' | cut -d: -f2 | xargs || echo "Never")
        max_log=$(grep -E "^$user " "$LIMITS_FILE" 2>/dev/null | awk '{print $NF}' || echo "Sin Límite")
        if [[ "$exp_str" == "never" || "$exp_str" == "Never" ]]; then
            printf " 👤 %-15s | 📅 %-17s | ⏳ %-21s | 🔒 %s\n" "$user" "Sin Expiración" "Ilimitado" "$max_log"
        else
            exp_sec=$(date -d "$exp_str" +%s 2>/dev/null || echo "0")
            if [[ "$exp_sec" -gt 0 ]]; then
                diff_sec=$(( exp_sec - now_sec ))
                diff_days=$(( diff_sec / 86400 ))
                if [[ "$diff_days" -lt 0 ]]; then
                    status_days="${RED}❌ EXPIRADO (${diff_days}d)${NC}"
                else
                    status_days="${GREEN}🟢 ${diff_days} días restantes${NC}"
                fi
                printf " 👤 %-15s | 📅 %-17s | ⏳ %-28b | 🔒 %s\n" "$user" "$exp_str" "$status_days" "$max_log"
            else
                printf " 👤 %-15s | 📅 %-17s | ⏳ %-21s | 🔒 %s\n" "$user" "$exp_str" "Desconocido" "$max_log"
            fi
        fi
    done
    echo -e "${BLUE}====================================================================================================${NC}"
    pause
}

update_from_github() {
    echo -e "${CYAN}=== ACTUALIZAR CAMBIOS DESDE GITHUB (08kenneth/BHTTP) ===${NC}"
    if [[ ! -d "$REPO_DIR" ]]; then
        git clone "$REPO_URL" "$REPO_DIR"
    fi
    cd "$REPO_DIR"
    echo "⬇️ Descargando la última versión de GitHub..."
    git reset --hard HEAD || true
    git pull origin main || git pull origin master

    echo "⚙️ Recompilando binarios de Go..."
    chmod +x build-btun.sh deploy/btun/install.sh
    CGO_ENABLED=1 ./build-btun.sh
    ARCH=$(go env GOARCH)
    go build -trimpath -ldflags="-s -w" -o build/bilola-server-linux-$ARCH ./cmd/bilola-server
    go build -trimpath -ldflags="-s -w" -o build/bilola-xhttp-server-linux-$ARCH ./cmd/xhttp-server

    ./deploy/btun/install.sh
    systemctl daemon-reload
    systemctl restart btun-protocol btun-routing btun-bhttp btun-xhttp
    echo -e "${GREEN}✅ Servidor actualizado y reiniciado exitosamente desde GitHub.${NC}"
    pause
}

reset_local_changes() {
    echo -e "${CYAN}=== REINICIAR / DESCARTAR CAMBIOS LOCALES ===${NC}"
    read -p "¿Descartar todos los cambios locales y restaurar estado de Git? (s/n): " confirm
    if [[ "$confirm" =~ ^[Ss]$ ]]; then
        cd "$REPO_DIR"
        git reset --hard HEAD
        git clean -fd
        echo -e "${GREEN}✅ Cambios locales descartados. Repositorio limpio.${NC}"
    else
        echo "Operación cancelada."
    fi
    pause
}

status_services() {
    echo -e "${CYAN}=== ESTADO DE LOS SERVICIOS ===${NC}"
    systemctl status btun-protocol btun-bhttp --no-pager || true
    echo ""
    echo -e "${CYAN}=== ÚLTIMOS LOGS DE ERRORES EN BTUN ===${NC}"
    journalctl -u btun-protocol -n 15 --no-pager || true
    pause
}

restart_services() {
    echo -e "${CYAN}🔄 Reiniciando todos los servicios...${NC}"
    systemctl restart btun-protocol btun-routing btun-bhttp btun-xhttp
    echo -e "${GREEN}✅ Servicios reiniciados.${NC}"
    pause
}

while true; do
    show_menu
    case "$option" in
        1) add_bhttp_ports ;;
        2) toggle_bhttp_target ;;
        3) change_btun_port ;;
        4) show_active_ports ;;
        5) add_user ;;
        6) change_user_expiration ;;
        7) change_user_connections ;;
        8) change_password ;;
        9) delete_user ;;
        10) list_users ;;
        11) update_from_github ;;
        12) reset_local_changes ;;
        13) status_services ;;
        14) restart_services ;;
        0) echo -e "${GREEN}👋 ¡Hasta luego!${NC}"; exit 0 ;;
        *) echo -e "${RED}❌ Opción no válida.${NC}"; pause ;;
    esac
done
MENU_EOF

chmod +x /usr/local/bin/ktun
ln -sf /usr/local/bin/ktun /usr/local/bin/menu-bhttp

# Iniciar los servicios
systemctl daemon-reload
systemctl enable --now btun-protocol btun-routing btun-bhttp btun-xhttp

echo ""
echo "================================================================="
echo "  🎉 ¡INSTALACIÓN COMPLETADA CON ÉXITO!                          "
echo "  🎮 Para gestionar tu servidor (puertos, usuarios) escribe:     "
echo "      ktun                                                       "
echo "================================================================="
