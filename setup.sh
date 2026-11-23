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
apt install -y golang git libpam0g-dev iptables build-essential nano ufw curl net-tools

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

# 5. Abrir puertos en UFW Firewall
echo "5/7 🛡️ Configurando Firewall (UFW)..."
ufw allow 7300/tcp || true
ufw allow 7300/udp || true
ufw allow 7080/tcp || true
ufw allow 7443/tcp || true
ufw allow 80/tcp || true
ufw allow 443/tcp || true

# 6. Crear menú de administración /usr/local/bin/menu-bhttp
echo "6/7 🎮 Instalando menú de administración 'menu-bhttp'..."
cat << 'MENU_EOF' > /usr/local/bin/menu-bhttp
#!/usr/bin/env bash
set -euo pipefail
if [[ "${EUID}" -ne 0 ]]; then echo "❌ Ejecutar como root." >&2; exit 1; fi

REPO_URL="https://github.com/08kenneth/BHTTP.git"
REPO_DIR="/root/BHTTP"
BHTTP_SERVICE="/etc/systemd/system/btun-bhttp.service"
BTUN_ENV="/etc/btun/server.env"

show_menu() {
    clear
    echo "=================================================="
    echo "   🚀 ADMINISTRADOR BHTTP / BTUN (08kenneth/BHTTP)  "
    echo "=================================================="
    bhttp_cur=$(grep -E '--listen' "$BHTTP_SERVICE" 2>/dev/null | sed -E 's/.*--listen ([^ ]+).*/\1/' || echo "N/A")
    btun_cur=$(grep -E 'BTUN_TCP_LISTEN' "$BTUN_ENV" 2>/dev/null | cut -d'=' -f2 || echo "N/A")
    echo " 📡 Config: BHTTP=[$bhttp_cur] | BTUN=[$btun_cur]"
    echo "=================================================="
    echo "1) Agregar / Cambiar Puertos BHTTP"
    echo "2) Cambiar Puerto Nativo BTUN"
    echo "3) 🔍 Ver Puertos Actualmente en Uso (Sockets Activos)"
    echo "4) Crear Nuevo Usuario"
    echo "5) Cambiar Contraseña de Usuario"
    echo "6) Eliminar Usuario"
    echo "7) Listar Usuarios Existentes"
    echo "8) 🔄 Actualizar Cambios desde GitHub (git pull + recompilar)"
    echo "9) 🧹 Reiniciar / Descartar Cambios Locales (git reset)"
    echo "10) Ver Estado de Servicios y Logs de Error"
    echo "11) Reiniciar Todos los Servicios"
    echo "0) Salir"
    echo "=================================================="
    read -p "Selecciona una opción [0-11]: " option
    echo ""
}

show_active_ports() {
    echo "=================================================="
    echo "   📡 PUERTOS Y SOCKETS ACTUALMENTE ESCUCHANDO    "
    echo "=================================================="
    if command -v ss >/dev/null 2>&1; then
        ss -tulpn | grep -E 'LISTEN|UNCONN' || ss -tulpn
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tulpn
    fi
}

add_bhttp_ports() {
    read -p "Ingresa los puertos BHTTP (ejemplo: 80,8080,7080): " ports
    [[ -z "$ports" ]] && return
    listen_arg=""
    IFS=',' read -ra ADDR <<< "$ports"
    for p in "${ADDR[@]}"; do
        p=$(echo "$p" | xargs)
        if [[ -n "$p" ]]; then
            [[ -z "$listen_arg" ]] && listen_arg="0.0.0.0:$p" || listen_arg="$listen_arg,0.0.0.0:$p"
            command -v ufw >/dev/null 2>&1 && ufw allow "$p"/tcp >/dev/null 2>&1 || true
        fi
    done
    sed -i -E "s|--listen [^ ]+|--listen $listen_arg|g" "$BHTTP_SERVICE"
    systemctl daemon-reload && systemctl restart btun-bhttp
    echo "✅ Puertos BHTTP actualizados a: $listen_arg"
}

change_btun_port() {
    read -p "Nuevo puerto BTUN (ej: 7300): " new_port
    [[ -z "$new_port" ]] && return
    sed -i -E "s|BTUN_TCP_LISTEN=0.0.0.0:[0-9]+|BTUN_TCP_LISTEN=0.0.0.0:$new_port|g" "$BTUN_ENV"
    sed -i -E "s|BTUN_UDP_LISTEN=0.0.0.0:[0-9]+|BTUN_UDP_LISTEN=0.0.0.0:$new_port|g" "$BTUN_ENV"
    command -v ufw >/dev/null 2>&1 && ufw allow "$new_port"/tcp >/dev/null 2>&1 && ufw allow "$new_port"/udp >/dev/null 2>&1 || true
    systemctl restart btun-protocol
    echo "✅ Puerto BTUN actualizado a $new_port."
}

add_user() {
    read -p "Usuario: " username
    [[ -z "$username" ]] && return
    read -p "Contraseña: " password
    [[ -z "$password" ]] && return
    useradd -m "$username" && echo "$username:$password" | chpasswd
    echo "✅ Usuario '$username' creado."
}

change_password() {
    read -p "Usuario: " username
    read -p "Nueva Contraseña: " password
    echo "$username:$password" | chpasswd
    echo "✅ Contraseña actualizada."
}

delete_user() {
    read -p "Usuario a eliminar: " username
    userdel -r "$username" 2>/dev/null || userdel "$username"
    echo "✅ Usuario eliminado."
}

list_users() {
    echo "=== USUARIOS REGISTRADOS ==="
    awk -F: '$3 >= 1000 && $3 < 60000 {print "👤 " $1}' /etc/passwd
}

update_from_github() {
    echo "=== ACTUALIZAR CAMBIOS DESDE GITHUB (08kenneth/BHTTP) ==="
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
    echo "✅ Servidor actualizado y reiniciado exitosamente desde GitHub."
}

reset_local_changes() {
    echo "=== REINICIAR / DESCARTAR CAMBIOS LOCALES ==="
    read -p "¿Descartar todos los cambios locales y restaurar estado de Git? (s/n): " confirm
    if [[ "$confirm" =~ ^[Ss]$ ]]; then
        cd "$REPO_DIR"
        git reset --hard HEAD
        git clean -fd
        echo "✅ Cambios locales descartados. Repositorio limpio."
    else
        echo "Operación cancelada."
    fi
}

status_services() {
    echo "=== ESTADO DE LOS SERVICIOS ==="
    systemctl status btun-protocol btun-bhttp --no-pager || true
    echo ""
    echo "=== ÚLTIMOS LOGS DE ERRORES EN BTUN ==="
    journalctl -u btun-protocol -n 15 --no-pager || true
}

restart_services() {
    echo "🔄 Reiniciando todos los servicios..."
    systemctl restart btun-protocol btun-routing btun-bhttp btun-xhttp
    echo "✅ Servicios reiniciados."
}

while true; do
    show_menu
    case "$option" in
        1) add_bhttp_ports ;; 2) change_btun_port ;; 3) show_active_ports ;; 4) add_user ;;
        5) change_password ;; 6) delete_user ;; 7) list_users ;; 8) update_from_github ;;
        9) reset_local_changes ;; 10) status_services ;; 11) restart_services ;; 0) exit 0 ;;
        *) echo "❌ Opción no válida." ;;
    esac
    read -p "Presiona ENTER para continuar..." null
done
MENU_EOF

chmod +x /usr/local/bin/menu-bhttp

# Iniciar los servicios
systemctl daemon-reload
systemctl enable --now btun-protocol btun-routing btun-bhttp btun-xhttp

echo ""
echo "================================================================="
echo "  🎉 ¡INSTALACIÓN COMPLETADA CON ÉXITO!                          "
echo "  🎮 Para gestionar tu servidor (puertos, usuarios) escribe:     "
echo "      menu-bhttp                                                 "
echo "================================================================="
