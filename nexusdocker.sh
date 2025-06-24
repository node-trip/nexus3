#!/bin/bash

# === Colors ===
YELLOW='\033[1;33m'
GREEN='\033[1;32m'
RED='\033[1;31m'
NC='\033[0m'

# === Root check ===
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Please run this script as root (sudo)${NC}"
  exit 1
fi

# === Welcome banner ===
clear
echo -e "${YELLOW}==================================================${NC}"
echo -e "${GREEN}=       🚀 Nexus Multi-Node Docker Setup       =${NC}"
echo -e "${YELLOW}=  Telegram: @nodetrip                        =${NC}"
echo -e "${YELLOW}=  Modified for Docker & Ubuntu 22 support    =${NC}"
echo -e "${YELLOW}==================================================${NC}\n"

# === Working directory ===
WORKDIR="/root/nexus-prover-docker"
echo -e "${GREEN}[*] Working directory: $WORKDIR${NC}"
mkdir -p "$WORKDIR"
cd "$WORKDIR" || exit 1

# === Install Docker if not present ===
if ! command -v docker &>/dev/null; then
    echo -e "${GREEN}[*] Installing Docker...${NC}"
    apt update
    apt install -y ca-certificates curl gnupg lsb-release
    
    # Add Docker's official GPG key
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    # Set up the repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker Engine
    apt update
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Start and enable Docker
    systemctl start docker
    systemctl enable docker
    
    echo -e "${GREEN}[✓] Docker installed successfully${NC}"
else
    echo -e "${GREEN}[✓] Docker is already installed${NC}"
fi

# === Create Dockerfile ===
echo -e "${GREEN}[*] Creating Dockerfile...${NC}"
cat > "$WORKDIR/Dockerfile" << 'EOF'
FROM ubuntu:24.04

# Install dependencies
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y \
    screen \
    curl \
    wget \
    build-essential \
    pkg-config \
    libssl-dev \
    git-all \
    protobuf-compiler \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:$PATH"
RUN /root/.cargo/bin/rustup target add riscv32i-unknown-none-elf

# Install Nexus CLI
RUN yes | curl -s https://cli.nexus.xyz/ | bash

# Find and install nexus-network binary
RUN NEXUS_BIN=$(find / -type f -name "nexus-network" -perm /u+x 2>/dev/null | head -n 1) && \
    if [ -x "$NEXUS_BIN" ]; then \
        cp "$NEXUS_BIN" /usr/local/bin/ && \
        chmod +x /usr/local/bin/nexus-network; \
    else \
        echo "nexus-network binary not found" && exit 1; \
    fi

# Create working directory
WORKDIR /nexus-prover

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
EOF

# === Create entrypoint script ===
echo -e "${GREEN}[*] Creating entrypoint script...${NC}"
cat > "$WORKDIR/entrypoint.sh" << 'EOF'
#!/bin/bash

# Colors
YELLOW='\033[1;33m'
GREEN='\033[1;32m'
RED='\033[1;31m'
NC='\033[0m'

# Check if NODE_ID is provided
if [ -z "$NODE_ID" ]; then
    echo -e "${RED}[!] NODE_ID environment variable is required${NC}"
    exit 1
fi

echo -e "${GREEN}[*] Starting Nexus node with ID: $NODE_ID${NC}"

# Create log file
LOG_FILE="/nexus-prover/nexus_$NODE_ID.log"
touch "$LOG_FILE"

# Start nexus-network and log output
exec nexus-network start --node-id "$NODE_ID" 2>&1 | tee "$LOG_FILE"
EOF

# === Build Docker image ===
echo -e "${GREEN}[*] Building Docker image...${NC}"
docker build -t nexus-prover:latest "$WORKDIR"

if [ $? -ne 0 ]; then
    echo -e "${RED}[!] Docker image build failed${NC}"
    exit 1
fi

echo -e "${GREEN}[✓] Docker image built successfully${NC}"

# === Ask user how many nodes ===
echo -e "${YELLOW}[?] How many node IDs do you want to run? (1-10)${NC}"
read -rp "> " NODE_COUNT
if ! [[ "$NODE_COUNT" =~ ^[1-9]$|^10$ ]]; then
  echo -e "${RED}[!] Invalid number. Choose between 1 to 10.${NC}"
  exit 1
fi

# === Read node IDs ===
NODE_IDS=()
for ((i=1;i<=NODE_COUNT;i++)); do
  echo -e "${YELLOW}Enter node-id #$i:${NC}"
  read -rp "> " NODE_ID
  if [ -z "$NODE_ID" ]; then
    echo -e "${RED}[!] Empty node-id. Aborting.${NC}"
    exit 1
  fi
  NODE_IDS+=("$NODE_ID")
done

# === Create docker-compose.yml ===
echo -e "${GREEN}[*] Creating docker-compose.yml...${NC}"
cat > "$WORKDIR/docker-compose.yml" << 'EOF'
version: '3.8'

services:
EOF

# Add services for each node
for ((i=0;i<NODE_COUNT;i++)); do
  NODE_ID="${NODE_IDS[$i]}"
  SERVICE_NAME="nexus-node-$((i+1))"
  
  cat >> "$WORKDIR/docker-compose.yml" << EOF
  $SERVICE_NAME:
    image: nexus-prover:latest
    container_name: nexus-container-$((i+1))
    environment:
      - NODE_ID=$NODE_ID
    volumes:
      - ./logs:/nexus-prover
    restart: unless-stopped
    stdin_open: true
    tty: true

EOF
done

# === Create logs directory ===
mkdir -p "$WORKDIR/logs"

# === Check Docker Compose command ===
if command -v docker-compose &>/dev/null; then
    COMPOSE_CMD="docker-compose"
elif docker compose version &>/dev/null; then
    COMPOSE_CMD="docker compose"
else
    echo -e "${RED}[!] Docker Compose not found${NC}"
    exit 1
fi

# === Start containers ===
echo -e "${GREEN}[*] Starting Docker containers...${NC}"
cd "$WORKDIR"
$COMPOSE_CMD up -d

if [ $? -eq 0 ]; then
    echo -e "${GREEN}[✓] All containers started successfully${NC}"
else
    echo -e "${RED}[!] Failed to start containers${NC}"
    exit 1
fi

# === Create management script ===
echo -e "${GREEN}[*] Creating management script...${NC}"
cat > "$WORKDIR/manage.sh" << EOF
#!/bin/bash

YELLOW='\033[1;33m'
GREEN='\033[1;32m'
RED='\033[1;31m'
NC='\033[0m'

# Detect Docker Compose command
if command -v docker-compose &>/dev/null; then
    COMPOSE_CMD="docker-compose"
elif docker compose version &>/dev/null; then
    COMPOSE_CMD="docker compose"
else
    echo -e "\${RED}[!] Docker Compose not found\${NC}"
    exit 1
fi

case "\$1" in
    "start")
        echo -e "\${GREEN}[*] Starting all Nexus containers...\${NC}"
        \$COMPOSE_CMD up -d
        ;;
    "stop")
        echo -e "\${YELLOW}[*] Stopping all Nexus containers...\${NC}"
        \$COMPOSE_CMD down
        ;;
    "restart")
        echo -e "\${YELLOW}[*] Restarting all Nexus containers...\${NC}"
        \$COMPOSE_CMD restart
        ;;
    "logs")
        if [ -z "\$2" ]; then
            echo -e "\${YELLOW}[*] Available containers:\${NC}"
            \$COMPOSE_CMD ps --format "table {{.Name}}\t{{.Status}}"
            echo -e "\${YELLOW}Usage: \$0 logs <container_number>\${NC}"
        else
            echo -e "\${GREEN}[*] Showing logs for nexus-container-\$2...\${NC}"
            docker logs -f "nexus-container-\$2"
        fi
        ;;
    "status")
        echo -e "\${GREEN}[*] Container status:\${NC}"
        \$COMPOSE_CMD ps
        ;;
    "cleanup")
        echo -e "\${YELLOW}[*] Stopping and removing all containers...\${NC}"
        \$COMPOSE_CMD down
        echo -e "\${YELLOW}[*] Removing Docker image...\${NC}"
        docker rmi nexus-prover:latest
        echo -e "\${GREEN}[✓] Cleanup completed\${NC}"
        ;;
    *)
        echo -e "\${YELLOW}Nexus Docker Management Script\${NC}"
        echo "Usage: \$0 {start|stop|restart|logs|status|cleanup}"
        echo ""
        echo "Commands:"
        echo "  start    - Start all containers"
        echo "  stop     - Stop all containers"
        echo "  restart  - Restart all containers"
        echo "  logs     - Show logs for specific container (usage: logs <number>)"
        echo "  status   - Show container status"
        echo "  cleanup  - Stop containers and remove image"
        ;;
esac
EOF

chmod +x "$WORKDIR/manage.sh"

# === Final instructions ===
echo -e "${YELLOW}\n=================================================${NC}"
echo -e "${GREEN}[✓] Nexus Docker setup completed successfully!${NC}"
echo -e "${YELLOW}=================================================${NC}"
echo -e "${GREEN}Working directory: $WORKDIR${NC}"
echo -e "${GREEN}Log files location: $WORKDIR/logs/${NC}"
echo ""
echo -e "${YELLOW}Management commands:${NC}"
echo -e "  ${GREEN}./manage.sh start${NC}     - Start all containers"
echo -e "  ${GREEN}./manage.sh stop${NC}      - Stop all containers"
echo -e "  ${GREEN}./manage.sh restart${NC}   - Restart all containers"
echo -e "  ${GREEN}./manage.sh logs <N>${NC}  - Show logs for container N"
echo -e "  ${GREEN}./manage.sh status${NC}    - Show container status"
echo -e "  ${GREEN}./manage.sh cleanup${NC}   - Complete cleanup"
echo ""
echo -e "${YELLOW}Direct Docker commands:${NC}"
echo -e "  ${GREEN}docker logs -f nexus-container-1${NC}  - Follow logs for container 1"
echo -e "  ${GREEN}docker exec -it nexus-container-1 bash${NC}  - Enter container shell"
echo ""
echo -e "${YELLOW}To check if nodes are working:${NC}"
echo -e "  ${GREEN}./manage.sh status${NC}"
echo -e "  ${GREEN}./manage.sh logs 1${NC} (for first container)"
echo ""
echo -e "${GREEN}Quick start:${NC}"
echo -e "  ${GREEN}cd $WORKDIR && ./manage.sh status${NC}"
echo -e "${YELLOW}=================================================${NC}"