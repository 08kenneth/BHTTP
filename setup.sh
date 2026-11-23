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
echo "1/6 🔄 Instalando dependencias del sistema..."
apt update -y
apt install -y golang git libpam0g-dev iptables build-essential nano ufw curl

# 2. Clonar o actualizar el repositorio
REPO_DIR="/root/BHTTP"
if [[ ! -d "$REPO_DIR" ]]; then
    echo "2/6 ⬇️ Clonando repositorio desde GitHub..."
    git clone https://github.com/08kenneth/BHTTP.git "$REPO_DIR"
else
    echo "2/6 ⬇️ Actualizando repositorio desde GitHub..."
    cd "$REPO_DIR" && git pull || true
fi

cd "$REPO_DIR"

# 3. Dar permisos y compilar
echo "3/6 ⚙️ Compilando binarios de Go (btun-server, bilola-server, xhttp)..."
chmod +x build-btun.sh deploy/btun/install.sh

CGO_ENABLED=1 ./build-btun.sh
ARCH=$(go env GOARCH)
go build -trimpath -ldflags="-s -w" -o build/bilola-server-linux-$ARCH ./cmd/bilola-server
go build -trimpath -ldflags="-s -w" -o build/bilola-xhttp-server-linux-$ARCH ./cmd/xhttp-server

# 4. Desplegar servicios systemd
echo "4/6 🚀 Desplegando servicios systemd de BTUN..."
./deploy/btun/install.sh

# 5. Abrir puertos en UFW Firewall
echo "5/6 🛡️ Configurando Firewall (UFW)..."
ufw allow 7300/tcp || true
ufw allow 7300/udp || true
ufw allow 7080/tcp || true
ufw allow 7443/tcp || true
ufw allow 80/tcp || true
ufw allow 443/tcp || true

# 6. Crear menú de administración /usr/local/bin/menu-bhttp
echo "6/6 🎮 Instalando menú de administración 'menu-bhttp'..."
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
    echo "1) Agregar / Cambiar Puertos BHTTP"
    echo "2) Cambiar Puerto Nativo BTUN (7300)"
    echo "3) Crear Nuevo Usuario"
    echo "4) Cambiar Contraseña de Usuario"
    echo "5) Eliminar Usuario"
    echo "6) Listar Usuarios Existentes"
    echo "7) Actualizar Servidor desde GitHub (08kenneth/BHTTP)"
    echo "8) Ver Estado de Servicios"
    echo "9) Reiniciar Servicios"
    echo "0) Salir"
    echo "=================================================="
    read -p "Selecciona una opción [0-9]: " option
    echo ""
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
    echo "✅ Puertos actualizados a: $listen_arg"
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
    cd "$REPO_DIR" && git pull
    CGO_ENABLED=1 ./build-btun.sh
    ARCH=$(go env GOARCH)
    go build -trimpath -ldflags="-s -w" -o build/bilola-server-linux-$ARCH ./cmd/bilola-server
    go build -trimpath -ldflags="-s -w" -o build/bilola-xhttp-server-linux-$ARCH ./cmd/xhttp-server
    ./deploy/btun/install.sh
    systemctl daemon-reload && systemctl restart btun-protocol btun-routing btun-bhttp btun-xhttp
    echo "✅ Servidor actualizado desde GitHub."
}

status_services() { systemctl status btun-protocol btun-bhttp --no-pager; }
restart_services() { systemctl restart btun-protocol btun-routing btun-bhttp btun-xhttp; echo "✅ Servicios reiniciados."; }

while true; do
    show_menu
    case "$option" in
        1) add_bhttp_ports ;; 2) change_btun_port ;; 3) add_user ;; 4) change_password ;;
        5) delete_user ;; 6) list_users ;; 7) update_from_github ;; 8) status_services ;;
        9) restart_services ;; 0) exit 0 ;;
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
