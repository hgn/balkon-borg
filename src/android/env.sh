#!/bin/bash
export BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ENV_DIR="$BASE_DIR/env"

# Java
export JAVA_HOME="$ENV_DIR/java"

# Android SDK
export ANDROID_HOME="$ENV_DIR/android-sdk"
export ANDROID_SDK_ROOT="$ENV_DIR/android-sdk"

# Path anpassen
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ENV_DIR/flutter/bin:$PATH"

# Verhindert, dass Flutter globale Chrome-Pfade etc. nutzt (optional)
export CHROME_EXECUTABLE=""
