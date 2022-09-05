# args for current script
export BROKER_HOST=""
export CERTS_PATH=""
export CLIENT_ID=""
export REGION=""
export DEVICE_NAME=""
user="$USER"
INSTALLATION_PATH="/opt/localproxy-agent"
UNINSTALL_MODE=0

# global vars
service_filename="localproxy-agent.service"

function usage() {
    local code=0
    if [ ! -z "$1" ]; then code=$1; fi
    echo -e "$0 OPTIONS\n"
    echo "OPTIONS"
    echo -e "    --broker-host, -b\thostname of the aws broker"
    echo -e "    --certs-dir, -d\tpath to the directory containing the certs"
    echo -e "    --client-id, -c\tclient id for mqtt connection"
    echo -e "    --region, -r\taws region (such as eu-west-1)"
    echo -e "    --device-name, -n\tname of the iot core thing created in aws"
    echo -e "    --help, -h\tdisplay this help message"
    echo -e "    --install-path, -p\t(default: /opt/localproxy-agent) the installation folder where the agent source code will be installed"
    echo -e "    --user, -u\t\t(default: root) the linux user of the device to use to run the systemd service"
    echo -e "    --uninstall, -U\t\tuninstall mode, uninstalls the service and related files"
    exit $code
}

function parseArgv() {
    while true; do
        case "$1" in
            --broker-host | -b) BROKER_HOST="$2"; shift 2; ;;
            --certs-dir | -d) CERTS_PATH="$2"; shift 2; ;;
            --client-id | -c) CLIENT_ID="$2"; shift 2; ;;
            --region | -r) REGION="$2"; shift 2; ;;
            --device-name | -n) DEVICE_NAME="$2"; shift 2; ;;
            --help | -h) usage; ;;
            --install-path | -p) INSTALLATION_PATH="$2"; shift 2; ;;
            --user | -u) user="$2"; shift 2; ;;
            --uninstall | -U) UNINSTALL_MODE=1; shift; ;;
            --) shift; break; ;;
            *) break;
        esac
    done
}

function validateFlags() {
    if [ -z "$BROKER_HOST" ]; then echo "env BROKER_HOST is missing"; usage 1; fi
    if [ -z "$CERTS_PATH" ]; then echo "env CERTS_PATH is missing"; usage 1; fi
    if [ -z "$CLIENT_ID" ]; then echo "env CLIENT_ID is missing"; usage 1; fi
    if [ -z "$REGION" ]; then echo "env REGION is missing"; usage 1; fi
    if [ -z "$DEVICE_NAME" ]; then echo "env DEVICE_NAME is missing"; usage 1; fi
}

function applySystemdReplacements() {
    echo "customizing systemd file..."
    local file="$1"
    cp localproxy-agent.service "$file"
    sed -i "s|\${{BROKER_HOST}}|${BROKER_HOST}|g" "$file"
    sed -i "s|\${{CERTS_PATH}}|$CERTS_PATH|g" "$file"
    sed -i "s|\${{CLIENT_ID}}|$CLIENT_ID|g" "$file"
    sed -i "s|\${{REGION}}|$REGION|g" "$file"
    sed -i "s|\${{DEVICE_NAME}}|$DEVICE_NAME|g" "$file"
    sed -i "s|\${{USER}}|$user|g" "$file"
    sed -i "s|\${{INSTALLATION_PATH}}|$INSTALLATION_PATH|g" "$file"
}

function uninstallSystemdService() {
    echo "uninstalling systemd service..."
    if [ -z "$service_filename" ]; then echo "service file name is empty"; exit 1; fi
    systemctl stop "$service_filename"
    systemctl disable "$service_filename"
    rm -rf "/etc/systemd/system/$service_filename"* 2>/dev/null
    rm -rf "/usr/lib/systemd/system/$service_filename"* 2>/dev/null
    systemctl daemon-reload
    rm -rf "$INSTALLATION_PATH"
    removeBuildContainer "localproxy-agent"
    docker rmi -f "localproxy-agent"
    echo "service successfully uninstalled"
}

function installSystemdService() {
    echo "installing systemd service"
    local temp="/tmp/copy.service"
    applySystemdReplacements "$temp"
    cp -f "$temp" "/etc/systemd/system/$service_filename"
    rm "$temp"
    systemctl enable "$service_filename"
    systemctl start "$service_filename"
}

function removeBuildContainer() {
    local container="$1"
    docker stop "$container"
    docker rm -f "$container"
}

function installSource() {
    rm -rf "$INSTALLATION_PATH"
    mkdir -p "$INSTALLATION_PATH"
    local image="localproxy-agent"
    docker build --no-cache -t "$image" .
    container_id="$(docker run -d "$image" sleep infinity)"
    sleep 3
    docker cp "$container_id:/app/build" "$INSTALLATION_PATH/build"
    docker cp "$container_id:/app/package.json" "$INSTALLATION_PATH/package.json"
    docker cp "$container_id:/app/node_modules" "$INSTALLATION_PATH/node_modules"
    # chown after node modules installation
    chown -R "$user" "$INSTALLATION_PATH"
    chmod u+rwx "$INSTALLATION_PATH"
    removeBuildContainer "$container_id"
}

function main() {
    parseArgv $@
    if [ `id -u` -ne 0 ]; then echo "must run as root"; exit 1; fi
    uninstallSystemdService
    if [ $UNINSTALL_MODE -eq 1 ]; then exit; fi
    validateFlags
    installSource
    installSystemdService
}

main $@