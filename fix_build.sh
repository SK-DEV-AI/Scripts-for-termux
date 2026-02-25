#!/data/data/com.termux/files/usr/bin/bash

# ==============================================================================
# KOKOROS MASTER SETUP (TERMUX EDITION)
# Handles Dependencies, Patches, Models, and Environment
# ==============================================================================

# --- CONFIGURATION ---
ONNX_VERSION="1.23.2" # Latest stable for Android as of late 2025
ONNX_LIB_DIR="$HOME/onnx_libs"
ENV_FILE="$HOME/kokoros_env.sh"
PROJECT_DIR=$(pwd)

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}   KOKOROS ANDROID: ZERO TO HERO         ${NC}"
echo -e "${BLUE}=========================================${NC}"

# --- 1. PRE-FLIGHT CHECKS ---

# Check if we are inside the project
if [ ! -f "Cargo.toml" ]; then
    echo -e "${RED}[ERROR] Cargo.toml not found!${NC}"
    echo "Please run this script INSIDE the 'Kokoros' folder."
    exit 1
fi

# Check Architecture
ARCH=$(uname -m)
if [ "$ARCH" != "aarch64" ]; then
    echo -e "${RED}[ERROR] Detected architecture: $ARCH${NC}"
    echo "This script is optimized for aarch64 (ARM64) Android devices."
    read -p "Press Enter to continue at your own risk..."
fi

# --- 2. SYSTEM DEPENDENCIES ---
echo -e "${YELLOW}[1/6] Installing Termux Packages...${NC}"
pkg update -y
pkg install -y rust git cmake clang build-essential sox wget unzip pkg-config libopus python pip

# Optional: Install python reqs if the user wants to use the python examples later
if [ -f "scripts/requirements.txt" ]; then
    echo -e "   -> Installing Python dependencies..."
    pip install -r scripts/requirements.txt --ignore-installed > /dev/null 2>&1
fi

# --- 3. MODEL & VOICE DATA DOWNLOADS ---
echo -e "${YELLOW}[2/6] Downloading Models & Voices...${NC}"

# Make repo scripts executable just in case
chmod +x *.sh 2>/dev/null
chmod +x scripts/*.sh 2>/dev/null

if [ -f "./download_all.sh" ]; then
    echo -e "   -> Executing project's download_all.sh..."
    bash ./download_all.sh
elif [ -f "scripts/download_models.sh" ] && [ -f "scripts/download_voices.sh" ]; then
    echo -e "   -> download_all.sh missing, running sub-scripts..."
    bash scripts/download_models.sh
    bash scripts/download_voices.sh
else
    echo -e "${RED}[WARNING] Could not find download scripts.${NC}"
    echo "   You may need to download checkpoints/kokoro-v1.0.onnx manually."
fi

# --- 4. MANUAL ONNX RUNTIME SETUP ---
echo -e "${YELLOW}[3/6] Setting up ONNX Runtime (Android v${ONNX_VERSION})...${NC}"
mkdir -p "$ONNX_LIB_DIR"

if [ -f "$ONNX_LIB_DIR/libonnxruntime.so" ]; then
    echo -e "${GREEN}   -> Library already exists in $ONNX_LIB_DIR${NC}"
else
    echo -e "   -> Downloading AAR..."
    wget -q --show-progress "https://repo1.maven.org/maven2/com/microsoft/onnxruntime/onnxruntime-android/${ONNX_VERSION}/onnxruntime-android-${ONNX_VERSION}.aar" -O onnxruntime.aar
    
    echo -e "   -> Extracting shared object..."
    unzip -p onnxruntime.aar jni/arm64-v8a/libonnxruntime.so > "$ONNX_LIB_DIR/libonnxruntime.so"
    rm onnxruntime.aar
fi

# --- 5. RUST CRATE FETCH & SMART PATCH ---
echo -e "${YELLOW}[4/6] Fetching & Patching Crates...${NC}"
cargo fetch

REGISTRY_DIR="$HOME/.cargo/registry/src"

# Patch ort-sys (Fix directory detection)
ORT_FILE=$(find "$REGISTRY_DIR" -wholename "*/ort-sys-*/src/internal/dirs.rs" 2>/dev/null | head -n 1)
if [ ! -z "$ORT_FILE" ]; then
    if ! grep -q "target_os = \"android\"" "$ORT_FILE"; then
        sed -i 's/target_os = "linux"/any(target_os = "linux", target_os = "android")/g' "$ORT_FILE"
        echo -e "${GREEN}   -> Patched ort-sys.${NC}"
    fi
fi

# Patch audiopus_sys (Fix linker error)
AUDIO_FILE=$(find "$REGISTRY_DIR" -wholename "*/audiopus_sys-*/build.rs" 2>/dev/null | head -n 1)
if [ ! -z "$AUDIO_FILE" ]; then
    if ! grep -q "target_os = \"android\"" "$AUDIO_FILE"; then
        sed -i '/false \/\/ Final fallback/i \    #[cfg(target_os = "android")]\n    { return false; }' "$AUDIO_FILE"
        sed -i 's/all(unix, target_env = "gnu")/all(unix, target_env = "gnu"), target_os = "android"/g' "$AUDIO_FILE"
        echo -e "${GREEN}   -> Patched audiopus_sys.${NC}"
    fi
fi

# --- 6. ENVIRONMENT GENERATION ---
echo -e "${YELLOW}[5/6] Generating Environment Config...${NC}"

cat <<EOF > "$ENV_FILE"
# KOKOROS TERMUX ENV
export ORT_STRATEGY=system
export ORT_LIB_LOCATION=$ONNX_LIB_DIR
export ORT_PREFER_DYNAMIC_LINK=1
export PKG_CONFIG_PATH=\$PREFIX/lib/pkgconfig
export RUSTFLAGS="-C target-cpu=native"
export LD_LIBRARY_PATH=$ONNX_LIB_DIR:\$LD_LIBRARY_PATH

# Alias for easy running (Smart Pinning)
alias koko-server='echo "Finding best cores..."; CORES=\$(grep -r . /sys/devices/system/cpu/cpu*/cpufreq/cpuinfo_max_freq | sort -t: -k2 -nr | head -n 2 | cut -d/ -f6 | sed "s/cpu//" | paste -sd, -); su -c "OMP_NUM_THREADS=2 taskset -c \$CORES ./target/release/koko openai"'

echo "✅ Environment Loaded!"
EOF

chmod +x "$ENV_FILE"

# --- 7. CONCLUSION ---
echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}   READY TO BUILD!${NC}"
echo -e "${BLUE}=========================================${NC}"
echo -e "We skipped the project's default 'install.sh' because it tries"
echo -e "to write to /usr/local/bin (which fails on Termux)."
echo ""
echo -e "1. Load the environment:"
echo -e "   ${YELLOW}source $ENV_FILE${NC}"
echo ""
echo -e "2. Build the release binary:"
echo -e "   ${YELLOW}cargo build --release${NC}"
echo ""
echo -e "3. Run the server (Requires Root for CPU pinning):"
echo -e "   ${YELLOW}koko-server${NC}"

