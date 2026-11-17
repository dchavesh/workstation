#!/usr/bin/env bash
# Question: can an Android emulator run inside the WSL distro, with no window,
# and be driven from the command line the way an agent would drive it?
#
# Writes data/runs/<time>-android-emulator/: result.json and, if the emulator
# booted, screen.png (what the emulator's screen showed).
#
# It installs Google's command-line Android SDK (about 5 GB) in the lab user's
# home and accepts the SDK licences there.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

readonly TEST_NAME="android-emulator"
readonly QUESTION="Can an Android emulator run inside the WSL distro, headless, and be driven by adb?"
readonly LAB_SCREEN="/var/tmp/android-screen.png"

settings() {
  cat <<'IN_LAB'
readonly TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip"
readonly IMAGE="system-images;android-35;google_apis;x86_64"
readonly BOOT_TIMEOUT_SECONDS=420
readonly SCREEN="/var/tmp/android-screen.png"
export ANDROID_HOME="$HOME/android"
readonly SDK_BIN="$ANDROID_HOME/cmdline-tools/latest/bin"
export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"
IN_LAB
}

# Phase 1: install the SDK and let the user open /dev/kvm. The group change
# only counts for sessions started afterwards, hence the restart before phase 2.
install_sdk() {
  settings
  cat <<'IN_LAB'
rm -f "$SCREEN"
started=$(date +%s)
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq openjdk-21-jre-headless unzip libpulse0 libnss3 \
  libxkbfile1 libxcb-cursor0 libgl1 libx11-xcb1 libxcomposite1 libxcursor1 libxi6 libxtst6 libxrandr2 libxdamage1 >/dev/null 2>&1
fact system_packages_installed "$(yes_no true)"
sudo usermod -aG kvm "$(id -un)"
mkdir -p "$ANDROID_HOME/cmdline-tools" && cd "$ANDROID_HOME"
if [[ ! -x "$SDK_BIN/sdkmanager" ]]; then
  curl -fsSLo tools.zip "$TOOLS_URL" && unzip -q -o tools.zip -d cmdline-tools && mv cmdline-tools/cmdline-tools cmdline-tools/latest
fi
yes | "$SDK_BIN/sdkmanager" --licenses >/dev/null 2>&1
fact sdk_installed "$(yes_no "$SDK_BIN/sdkmanager" "platform-tools" "emulator" "$IMAGE")"
fact install_seconds "$(( $(date +%s) - started ))"
fact sdk_size_mb "$(du -sm "$ANDROID_HOME" 2>/dev/null | cut -f1)"
fact device_created "$(echo no | "$SDK_BIN/avdmanager" create avd --force -n labtest -k "$IMAGE" >/dev/null 2>&1 && echo true || echo false)"
fact system_image "$IMAGE"
IN_LAB
}

# Phase 2: boot the emulator with no window and drive it with adb.
boot_and_drive() {
  settings
  cat <<'IN_LAB'
emulator_running() { pgrep -f qemu-system >/dev/null; }
fact user_in_kvm_group "$(yes_no sh -c 'id -nG | tr " " "\n" | grep -qx kvm')"
fact acceleration "$(emulator -accel-check 2>&1 | grep -m1 -i 'kvm')"
boot_started=$(date +%s)
nohup emulator -avd labtest -no-window -no-audio -no-boot-anim -no-snapshot -gpu swiftshader_indirect -memory 2048 \
  >/var/tmp/android-emulator.log 2>&1 </dev/null &
booted=false
while (( $(date +%s) - boot_started < BOOT_TIMEOUT_SECONDS )); do
  if [[ "$(adb shell getprop sys.boot_completed 2>/dev/null </dev/null | tr -d '\r')" == 1 ]]; then booted=true; break; fi
  sleep 5
  if (( $(date +%s) - boot_started > 30 )) && ! emulator_running; then break; fi
done
fact booted "$booted"
fact boot_seconds "$(( $(date +%s) - boot_started ))"
fact emulator_memory_mb "$(ps -eo rss,args | awk '/qemu-system/ && !/awk/ {s += $1} END {print int(s / 1024)}')"
if [[ "$booted" == true ]]; then
  fact android_version "$(adb shell getprop ro.build.version.release </dev/null | tr -d '\r')"
  fact key_press_worked "$(yes_no adb shell input keyevent KEYCODE_HOME)"
  fact screen_tap_worked "$(yes_no adb shell input tap 540 1200)"
  adb exec-out screencap -p >"$SCREEN" </dev/null
  fact screenshot_bytes "$(stat -c %s "$SCREEN" 2>/dev/null || echo 0)"
  fact installed_apps "$(adb shell pm list packages </dev/null | wc -l)"
fi
adb emu kill >/dev/null 2>&1 </dev/null
fact emulator_log_boot_line "$(grep -m1 -i 'boot completed' /var/tmp/android-emulator.log 2>/dev/null)"
IN_LAB
}

save_screenshot() {
  local run_dir="$TEST_REPO_DIR/data/runs/$TEST_RUN_STAMP-$TEST_NAME"
  if wsl.exe -d "$TEST_LAB_NAME" --cd / -- cat "$LAB_SCREEN" </dev/null >"$run_dir/screen.png" 2>/dev/null && [[ -s "$run_dir/screen.png" ]]; then
    echo "screenshot: data/runs/$TEST_RUN_STAMP-$TEST_NAME/screen.png"
  else
    rm -f "$run_dir/screen.png"
  fi
}

main() {
  reset_facts
  as_user install_sdk
  restart_lab
  as_user boot_and_drive
  write_test_record "$TEST_NAME" "$QUESTION"
  save_screenshot
}

main "$@"
