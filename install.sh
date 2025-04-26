#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# 1. System updates & deps
apt-get update && apt-get upgrade -y
apt-get install -y curl ufw iptables build-essential git wget lz4 jq make gcc \
                   nano automake autoconf tmux htop nvme-cli libgbm1 \
                   pkg-config libssl-dev libleveldb-dev tar clang \
                   bsdmainutils ncdu unzip ca-certificates gnupg lsb-release

# 2. Docker install
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable docker && systemctl start docker

# 3. Install Drosera & tooling
curl -L https://app.drosera.io/install | bash
source /root/.bashrc
droseraup
curl -L https://foundry.paradigm.xyz | bash
source /root/.bashrc
foundryup
curl -fsSL https://bun.sh/install | bash
source /root/.bashrc

# 4. Build your trap
cd /root
mkdir -p my-drosera-trap && cd my-drosera-trap
git config --global user.email "${GITHUB_EMAIL}"
git config --global user.name "${GITHUB_USERNAME}"
forge init -t drosera-network/trap-foundry-template
bun install
forge build
export DROSERA_PRIVATE_KEY="${YOUR_PRIVATE_KEY}"
drosera apply --yes

# 5. Install & register the operator
cd /root
curl -LO https://github.com/drosera-network/releases/releases/download/v1.16.2/drosera-operator-v1.16.2-x86_64-unknown-linux-gnu.tar.gz
tar -xvf drosera-operator-v1.16.2-x86_64-unknown-linux-gnu.tar.gz
cp drosera-operator /usr/bin/
drosera-operator --version
docker pull ghcr.io/drosera-network/drosera-operator:latest
drosera-operator register \
  --eth-rpc-url https://ethereum-holesky-rpc.publicnode.com \
  --eth-private-key "${YOUR_PRIVATE_KEY}"

# 6. Launch the dashboard backend
git clone https://github.com/0xmoei/Drosera-Network /root/Drosera-Network
cd /root/Drosera-Network
cp .env.example .env
sed -i "s/your_evm_private_key/${YOUR_PRIVATE_KEY}/" .env
sed -i "s/your_vps_public_ip/${YOUR_PUBLIC_IP}/" .env
docker compose up -d

echo "✅ Done! Drosera node, operator, and dashboard are up. Check logs with: cd /root/Drosera-Network && docker compose logs -f"
