#!/data/data/com.termux/files/usr/bin/bash

# Termux Android Build Environment Setup Script
# Revised for ARM64/Termux compatibility
# Fixes aapt2 architecture mismatch and ensures correct environment variables

set -e  # Exit on error

echo "================================================"
echo "Termux Android Build Environment Setup (Fixed)"
echo "================================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_info() {
    echo -e "${YELLOW}[i]${NC} $1"
}

# Step 1: Update and upgrade packages
print_info "Updating and upgrading Termux packages..."
pkg update -y && pkg upgrade -y
print_status "Packages updated successfully"
echo ""

# Step 2: Install required packages
# Added: aapt2 (native binary), android-tools (adb/zipalign), unzip, zip
print_info "Installing dependencies (Java 21, aapt2, tools)..."
pkg install wget openjdk-21 aapt2 android-tools unzip zip -y
print_status "Required packages installed"
echo ""

# Verify Java installation & Set JAVA_HOME
print_info "Configuring Java..."
export JAVA_HOME="/data/data/com.termux/files/usr/lib/jvm/openjdk-21"
if ! grep -q "JAVA_HOME" ~/.bashrc; then
    echo "export JAVA_HOME=$JAVA_HOME" >> ~/.bashrc
    print_status "JAVA_HOME added to .bashrc"
fi

if java -version 2>&1 | grep -q "openjdk"; then
    print_status "Java installed: $(java -version 2>&1 | head -n 1)"
else
    print_error "Java installation failed"
    exit 1
fi
echo ""

# Step 3: Install Android SDK
print_info "Installing Android SDK..."
if [ ! -d "$HOME/android-sdk" ]; then
    # Using existing community installer script as it handles the cmdline-tools structure well
    wget -O ~/install-android-sdk.sh https://raw.githubusercontent.com/Sohil876/termux-sdk-installer/main/installer.sh
    chmod +x ~/install-android-sdk.sh
    # Run in non-interactive mode if possible, or user must interact
    bash ~/install-android-sdk.sh -i
    print_status "Android SDK installed"
else
    print_info "Android SDK already exists, skipping installation"
fi

# Ensure ANDROID_HOME is set for this session
export ANDROID_HOME=$HOME/android-sdk

# Step 4: Accept Android SDK licenses
print_info "Accepting Android SDK licenses..."
yes | sdkmanager --licenses > /dev/null 2>&1
print_status "Licenses accepted"
echo ""

# Step 5: Install Platform and Build Tools
# Explicitly installing build-tools 35.0.0 to match API 35 (Android 15)
print_info "Installing Android platform (API 35) and Build Tools..."
yes | sdkmanager "platforms;android-35" "build-tools;35.0.0"
print_status "Android platform and build tools installed"
echo ""

# Step 6: Install Gradle 8.10.2
GRADLE_VERSION="8.10.2"
print_info "Installing Gradle ${GRADLE_VERSION}..."

if [ ! -d "$ANDROID_HOME/gradle" ]; then
    wget -O $ANDROID_HOME/gradle-${GRADLE_VERSION}-bin.zip https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip
    unzip -q $ANDROID_HOME/gradle-${GRADLE_VERSION}-bin.zip -d $ANDROID_HOME/
    mv $ANDROID_HOME/gradle-${GRADLE_VERSION}/ $ANDROID_HOME/gradle/
    rm $ANDROID_HOME/gradle-${GRADLE_VERSION}-bin.zip
    print_status "Gradle installed"
else
    print_info "Gradle already exists, skipping installation"
fi

# Step 7: Add Gradle to PATH
if ! grep -q "ANDROID_HOME/gradle/bin" ~/.bashrc; then
    echo 'export PATH=${PATH}:${ANDROID_HOME}/gradle/bin' >> ~/.bashrc
    print_status "Gradle added to PATH"
fi
export PATH=${PATH}:${ANDROID_HOME}/gradle/bin

# Verify Gradle
if gradle -v 2>&1 | grep -q "Gradle"; then
    print_status "Gradle verified"
else
    print_error "Gradle installation failed"
    exit 1
fi
echo ""

# Step 8: Fix aapt2 Architecture Mismatch (CRITICAL FIX)
print_info "Configuring Native aapt2..."
mkdir -p ~/.gradle
GRADLE_PROPERTIES="$HOME/.gradle/gradle.properties"
NATIVE_AAPT2="/data/data/com.termux/files/usr/bin/aapt2"

if [ -f "$NATIVE_AAPT2" ]; then
    # We must tell Gradle to use the Termux aapt2, NOT the Google x86 one
    if grep -q "android.aapt2FromMavenOverride" "$GRADLE_PROPERTIES" 2>/dev/null; then
        sed -i "s|android.aapt2FromMavenOverride=.*|android.aapt2FromMavenOverride=$NATIVE_AAPT2|" "$GRADLE_PROPERTIES"
    else
        echo "android.aapt2FromMavenOverride=$NATIVE_AAPT2" >> "$GRADLE_PROPERTIES"
    fi
    print_status "aapt2 overridden with native binary: $NATIVE_AAPT2"
else
    print_error "Native aapt2 binary not found in expected path!"
    exit 1
fi
echo ""

# Final summary
echo "================================================"
echo -e "${GREEN}Setup completed successfully!${NC}"
echo "================================================"
echo "Installed Components:"
echo "  - Java: $(java -version 2>&1 | head -n 1)"
echo "  - Gradle: ${GRADLE_VERSION}"
echo "  - Android API: 35 (Android 15)"
echo "  - Build Tools: 35.0.0"
echo "  - Native Tools: aapt2, zipalign (via android-tools)"
echo ""
echo "Configuration:"
echo "  - SDK Location: $ANDROID_HOME"
echo "  - Gradle Fix: ~/.gradle/gradle.properties updated for ARM64"
echo ""
echo -e "${GREEN}Ready to build!${NC}"
echo "Please restart your terminal or run: source ~/.bashrc"
echo ""
