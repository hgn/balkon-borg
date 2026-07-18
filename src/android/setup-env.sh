#!/bin/bash
set -e

# Verzeichnisse definieren
BASE_DIR="$(pwd)"
ENV_DIR="$BASE_DIR/env"
JAVA_DIR="$ENV_DIR/java"
ANDROID_HOME="$ENV_DIR/android-sdk"
FLUTTER_DIR="$ENV_DIR/flutter"

mkdir -p "$ENV_DIR"

echo "=== 1. Lade und installiere Java JDK 17 ==="
if [ ! -d "$JAVA_DIR" ]; then
    mkdir -p "$JAVA_DIR"
    wget -qO- "https://download.java.net/java/GA/jdk17.0.2/dfd4a8d0985749f896bed50d7138ee7f/8/GPL/openjdk-17.0.2_linux-x64_bin.tar.gz" | tar -xz -C "$JAVA_DIR" --strip-components=1
else
    echo "Java bereits installiert."
fi

echo "=== 2. Lade und installiere Android SDK Command-line Tools ==="
if [ ! -d "$ANDROID_HOME/cmdline-tools/latest" ]; then
    mkdir -p "$ANDROID_HOME/cmdline-tools"
    # Lade die Android CMD-Line Tools herunter (Linux)
    wget -qO cmdline-tools.zip "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
    unzip -q cmdline-tools.zip -d "$ANDROID_HOME/cmdline-tools"
    rm cmdline-tools.zip
    # Verschiebe die Tools in den "latest" Ordner, wie es sdkmanager erfordert
    mv "$ANDROID_HOME/cmdline-tools/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
else
    echo "Android CMD-Line Tools bereits installiert."
fi

# Setze temporäre Variablen für den sdkmanager
export JAVA_HOME="$JAVA_DIR"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"

echo "=== 3. Akzeptiere Lizenzen und installiere Android SDK Komponenten ==="
yes | sdkmanager --licenses > /dev/null 2>&1 || true
sdkmanager "platform-tools" "platforms;android-36" "build-tools;28.0.3" "build-tools;34.0.0"

echo "=== 4. Lade und installiere Flutter SDK ==="
if [ ! -d "$FLUTTER_DIR" ]; then
    wget -qO flutter.tar.xz "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.24.0-stable.tar.xz"
    tar xf flutter.tar.xz -C "$ENV_DIR"
    rm flutter.tar.xz
else
    echo "Flutter bereits installiert."
fi

echo "=== 5. Erstelle env.sh Datei ==="
cat <<EOF > "$BASE_DIR/env.sh"
#!/bin/bash
export BASE_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
export ENV_DIR="\$BASE_DIR/env"

# Java
export JAVA_HOME="\$ENV_DIR/java"

# Android SDK
export ANDROID_HOME="\$ENV_DIR/android-sdk"
export ANDROID_SDK_ROOT="\$ENV_DIR/android-sdk"

# Path anpassen
export PATH="\$JAVA_HOME/bin:\$ANDROID_HOME/cmdline-tools/latest/bin:\$ANDROID_HOME/platform-tools:\$ENV_DIR/flutter/bin:\$PATH"

# Verhindert, dass Flutter globale Chrome-Pfade etc. nutzt (optional)
export CHROME_EXECUTABLE=""
EOF

echo "Setup abgeschlossen!"
echo "Bitte führe nun 'source env.sh' aus, um die Umgebungsvariablen in deinem Terminal zu aktivieren."
echo "Danach kannst du 'flutter doctor --android-licenses' ausführen, um finale Android-Lizenzen zu akzeptieren."
