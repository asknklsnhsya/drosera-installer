#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# ------------------------------------------------------------
# 0. Check required environment variables
# ------------------------------------------------------------
for var in GITHUB_EMAIL GITHUB_USERNAME YOUR_PRIVATE_KEY YOUR_PUBLIC_IP; do
  if [ -z "${!var:-}" ]; then
    echo "❌ Error: Environment variable '$var' is not set." >&2
    echo "   Usage:" >&2
    echo "     GITHUB_EMAIL=you@example.com \\" >&2
    echo "     GITHUB_USERNAME=yourgithubname \\" >&2
    echo "     YOUR_PRIVATE_KEY=0xabc123… \\" >&2
    echo "     YOUR_PUBLIC_IP=1.2.3.4 \\" >&2
    echo "     curl -sSL https://raw.githubusercontent.com/<USERNAME>/drosera-installer/main/install.sh \\" >&2
    echo "       | sudo bash" >&2
    exit 1
  fi
done

# ------------------------------------------------------------
# 1. System updates & essentials
# ------------------------------------------------------------
apt-get update && apt-get upgrade -y
apt-get install -y \
  curl ufw iptables build-essential git wget lz4 jq make gcc nano \
  automake autoconf tmux htop nvme-cli libgbm1 pkg-config \
  libssl-dev libleveldb-dev tar clang bsdmainutils ncdu unzip \
  ca-certificates gnupg lsb-release

# ------------------------------------------------------------
# 2. Install Docker
# ------------------------------------------------------------
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io \
                   docker-buildx-plugin docker-compose-plugin
systemctl enable docker && systemctl start docker

# ------------------------------------------------------------
# 3. Install Drosera CLI (droseraup) & ensure it's on PATH
# ------------------------------------------------------------
curl -L https://app.drosera.io/install | bash
for p in "$HOME/.drosera/bin" "$HOME/.local/bin" "/usr/local/bin"; do
  if [[ -x "$p/droseraup" ]]; then
    export PATH="$PATH:$p"
    break
  fi
done
if ! command -v droseraup >/dev/null 2>&1; then
  echo "❌ droseraup not found after installation!" >&2
  exit 1
fi
droseraup

# ------------------------------------------------------------
# 4. Install Foundry & Bun
# ------------------------------------------------------------
curl -L https://foundry.paradigm.xyz | bash
export PATH="$PATH:$HOME/.foundry/bin"
foundryup

curl -fsSL https://bun.sh/install | bash
export PATH="$PATH:$HOME/.bun/bin"
bun --version

# ------------------------------------------------------------
# 5. Build & deploy your Trap
# ------------------------------------------------------------
cd /root
mkdir -p my-drosera-trap && cd my-drosera-trap
git config --global user.email  "${GITHUB_EMAIL}"
git config --global user.name   "${GITHUB_USERNAME}"
forge init -t drosera-network/trap-foundry-template
bun install
forge build
export DROSERA_PRIVATE_KEY="${YOUR_PRIVATE_KEY}"
drosera apply --yes

# ------------------------------------------------------------
# 6. Install & register the Operator
# ------------------------------------------------------------
cd /root
curl -LO https://github.com/drosera-network/releases/releases/download/v1.16.2/drosera-operator-v1.16.2-x86_64-unknown-linux-gnu.tar.gz
tar -xvf drosera-operator-v1.16.2-x86_64-unknown-linux-gnu.tar.gz
cp drosera-operator /usr/bin/
drosera-operator --version
docker pull ghcr.io/drosera-network/drosera-operator:latest
drosera-operator register \
  --eth-rpc-url https://ethereum-holesky-rpc.publicnode.com \
  --eth-private-key "${YOUR_PRIVATE_KEY}"

# ------------------------------------------------------------
# 7. Clone & launch the Drosera-Network dashboard backend
# ------------------------------------------------------------
git clone https://github.com/0xmoei/Drosera-Network /root/Drosera-Network
cd /root/Drosera-Network
cp .env.example .env
sed -i "s/your_evm_private_key/${YOUR_PRIVATE_KEY}/" .env
sed -i "s/your_vps_public_ip/${YOUR_PUBLIC_IP}/" .env
docker compose up -d

echo "✅ Done! Drosera trap, operator, and dashboard are all up."
echo "   View logs: cd /root/Drosera-Network && docker compose logs -f"

