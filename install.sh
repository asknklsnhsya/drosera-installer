#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# ------------------------------------------------------------
# 0. Usage & parameter check
# ------------------------------------------------------------
if [ "$#" -ne 4 ]; then
  cat <<EOF >&2
❌  Usage:
     curl -sSL https://raw.githubusercontent.com/<USERNAME>/drosera-installer/main/install.sh \\
       | sudo bash -s -- \\
         <GITHUB_EMAIL> <GITHUB_USERNAME> <DROSERA_PRIVATE_KEY> <YOUR_PUBLIC_IP>
     
   Example:
     curl -sSL https://raw.githubusercontent.com/alice/drosera-installer/main/install.sh \\
       | sudo bash -s -- \\
         alice@example.com alice 0xabc123… 1.2.3.4
EOF
  exit 1
fi

GITHUB_EMAIL="$1"
GITHUB_USERNAME="$2"
DROSERA_PRIVATE_KEY="$3"
YOUR_PUBLIC_IP="$4"

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
# 2. Docker install
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
# 3. Install Drosera CLI (droseraup) & ensure on PATH
# ------------------------------------------------------------
curl -L https://app.drosera.io/install | bash
for p in "$HOME/.drosera/bin" "$HOME/.local/bin" "/usr/local/bin"; do
  if [[ -x "$p/droseraup" ]]; then
    export PATH="$PATH:$p"
    break
  fi
done
command -v droseraup >/dev/null 2>&1 || { echo "❌ droseraup install failed" >&2; exit 1; }
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
# 5. Build & deploy your Trap (non-interactive)
# ------------------------------------------------------------
cd /root
mkdir -p my-drosera-trap && cd my-drosera-trap
git config --global user.email  "${GITHUB_EMAIL}"
git config --global user.name   "${GITHUB_USERNAME}"
forge init -t drosera-network/trap-foundry-template
bun install
forge build

export DROSERA_PRIVATE_KEY="${DROSERA_PRIVATE_KEY}"
printf 'ofc\n' | drosera apply

# ------------------------------------------------------------
# 6. Install & register the Operator
# ------------------------------------------------------------
cd /root
curl -LO https://github.com/drosera-network/releases/releases/download/v1.16.2/drosera-operator-v1.16.2-x86_64-unknown-linux-gnu.tar.gz
tar -xzf drosera-operator-v1.16.2-x86_64-unknown-linux-gnu.tar.gz
cp drosera-operator /usr/bin/
drosera-operator --version
docker pull ghcr.io/drosera-network/drosera-operator:latest
drosera-operator register \
  --eth-rpc-url https://ethereum-holesky-rpc.publicnode.com \
  --eth-private-key "${DROSERA_PRIVATE_KEY}"

# ------------------------------------------------------------
# 7. Clone & launch the Drosera-Network dashboard
# ------------------------------------------------------------
git clone https://github.com/0xmoei/Drosera-Network /root/Drosera-Network
cd /root/Drosera-Network
cp .env.example .env
sed -i "s/your_evm_private_key/${DROSERA_PRIVATE_KEY}/" .env
sed -i "s/your_vps_public_ip/${YOUR_PUBLIC_IP}/" .env
docker compose up -d

echo "✅ All done!  
• Drosera Trap deployed  
• Operator registered  
• Dashboard backend running  
Check logs with: cd /root/Drosera-Network && docker compose logs -f"
