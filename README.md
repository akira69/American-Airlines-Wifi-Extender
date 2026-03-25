# AA Wi-Fi Extender

AA Wi-Fi Extender is a macOS utility for quickly cycling Wi-Fi state and generating a randomized MAC address command while testing captive-portal style flows such as `aainflight.com`.

## What it does

- Shows Wi-Fi power state in the sidebar
- Lets you set default values for:
  - SSID
  - Portal URL
  - Timer duration
- Generates a randomized MAC address command for the active Wi-Fi interface
- Prepares connect/disconnect Wi-Fi commands using the detected Wi-Fi interface
- Runs commands directly or with administrator privileges
- Includes an in-app portal web view and countdown timer overlay

## Current behavior

- The app auto-detects the Wi-Fi interface instead of assuming `en0`
- "Run as Admin" uses the standard macOS administrator prompt via AppleScript
- The UI is optimized for compact MacBook-height layouts
- The app icon and in-app branding are custom assets included in the repo

## Requirements

- macOS
- Xcode

This project is currently set up as an Xcode project, not a Swift Package.

## Open and run

1. Open `American Airlines Wifi Extender.xcodeproj` in Xcode
2. Select the `American Airlines Wifi Extender` scheme
3. Build and run

## Notes

- Wi-Fi commands rely on standard macOS tools such as `networksetup` and `ifconfig`
- Privileged commands will prompt for admin credentials
- The repo still contains earlier helper-tool code and packaging experiments, but the current admin execution path does not depend on the helper daemon

## Repo

GitHub: `https://github.com/akira69/American-Airlines-Wifi-Extender`
