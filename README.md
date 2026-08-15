<div align="center">

<img src="https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white" />
<img src="https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white" />
<img src="https://img.shields.io/badge/Kotlin-7F52FF?style=for-the-badge&logo=kotlin&logoColor=white" />
<img src="https://img.shields.io/badge/Android-3DDC84?style=for-the-badge&logo=android&logoColor=white" />

<br/><br/>

<h1>🚨 Rescue Me</h1>

<p><strong>An automatic accident-detection app that senses a crash and alerts your emergency contacts — with live GPS — before you even reach for your phone.</strong></p>

<p>
  <img src="https://img.shields.io/badge/Status-Active%20Development-brightgreen" />
  <img src="https://img.shields.io/badge/Platform-Android-3DDC84" />
  <img src="https://img.shields.io/badge/License-MIT-green.svg" />
</p>

<br/>

```
Sensors detect the impact. A countdown gives you a chance to cancel.
If you don't respond, help is already on the way.
```

</div>

---

## 📋 Table of Contents

- [✨ Features](#-features)
- [🏗️ Architecture](#️-architecture)
- [📱 Screens](#-screens)
- [🧠 Detection Logic](#-detection-logic)
- [🚀 Getting Started](#-getting-started)
- [🔐 Permissions](#-permissions)
- [📴 OEM Background Restrictions](#-oem-background-restrictions)
- [🛠️ Tech Stack](#️-tech-stack)
- [📁 Project Structure](#-project-structure)
- [🤝 Contributing](#-contributing)

---

## ✨ Features

### 🛡️ Automatic Protection
| Feature | Description |
|--------|-------------|
| 📡 **Sensor Fusion Detection** | Combines accelerometer, gyroscope, and ambient noise readings within a rolling time window to confirm a real accident and reject false positives |
| 🔄 **Background & Foreground Monitoring** | A dedicated Android foreground service keeps watching for impacts even when the app is closed or the screen is off |
| ⏱️ **Countdown Alarm** | A 30-second full-screen alarm gives you a chance to mark yourself safe before alerts go out |
| 🔁 **Boot-Persistent Monitoring** | A boot receiver automatically restarts the monitoring service after the phone reboots, if it was previously enabled |

### 📨 Emergency Response
| Feature | Description |
|--------|-------------|
| 📍 **Live Location SMS** | Sends an SMS with precise GPS coordinates, a resolved address, and a Google Maps link to every emergency contact |
| 📞 **Automatic Calling** | Sequentially calls emergency contacts after the SMS alert is sent |
| 🧑‍🤝‍🧑 **Emergency Contacts Manager** | Add, edit, and remove contacts who should be notified during an accident |
| 🆘 **Manual SOS** | A one-tap SOS button for sending alerts without waiting for sensor detection |

### ⚙️ Reliability & Setup
| Feature | Description |
|--------|-------------|
| 🔋 **Battery Optimization Guard** | Detects when battery optimization could kill background monitoring and offers a one-tap fix |
| 📱 **OEM-Aware Setup Guide** | Ships manufacturer-specific instructions (and deep links) for OPPO, Vivo, Xiaomi, Realme, and OnePlus devices |
| 📊 **Live Sensor Dashboard** | View real-time accelerometer, gyroscope, and noise readings with 30-second peak/low tracking |
| 🔔 **Persistent Notifications** | Ongoing "shield active" notification confirms monitoring is running |

---

## 🏗️ Architecture

```
┌───────────────────────────────────────────────────────────────┐
│                          Flutter App                          │
│                                                                │
│  ┌───────────┐  ┌────────────┐  ┌────────────┐  ┌──────────┐ │
│  │  Splash / │  │   Home /   │  │  Sensors   │  │ Contacts │ │
│  │  Setup    │  │  SOS/Alarm │  │  Screen    │  │ Screen   │ │
│  └─────┬─────┘  └──────┬─────┘  └─────┬──────┘  └────┬─────┘ │
│        │               │               │              │       │
│        └───────────────┴───────────────┴──────────────┘       │
│                          │                                     │
│         ┌────────────────┼────────────────┐                   │
│         │                │                │                   │
│  ┌──────▼──────┐  ┌──────▼──────┐  ┌──────▼──────┐            │
│  │ SMSService  │  │ CallService │  │LocationServ.│            │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘            │
│         │                │                │                   │
│         └────────── MethodChannels ────────┘                  │
└───────────────────────────┬─────────────────────────────────── ┘
                            │
┌───────────────────────────▼─────────────────────────────────── ┐
│                      Android (Kotlin)                          │
│                                                                 │
│  ┌────────────────────────┐   ┌───────────────────────────┐    │
│  │ AccidentMonitoring      │   │  AlarmForeground           │    │
│  │ Service (sensors)       │──▶│  Service (countdown)       │    │
│  └────────────┬─────────────┘  └──────────────┬─────────────┘    │
│               │                                │                  │
│  ┌────────────▼─────────────┐   ┌──────────────▼─────────────┐    │
│  │ BootReceiver              │   │  AlarmActionReceiver        │    │
│  │ (restart after reboot)    │   │  ("I'M SAFE" action)        │    │
│  └────────────────────────────┘   └──────────────────────────┘    │
│                                                                 │
│  SharedPreferences (native + Flutter, kept in sync)             │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📱 Screens

<details>
<summary><strong>🚦 Onboarding Flow</strong></summary>

```
Splash Screen (animated)
   └── checks "is_setup" flag
         ├── Setup Screen (first launch)
         │     ├── Requests SMS, Location, Phone, Mic, Notification permissions
         │     ├── Detects restricted OEM (OPPO/Vivo/Xiaomi/OnePlus)
         │     └── Shows manufacturer-specific setup dialog
         └── Main Screen (returning user)
```
</details>

<details>
<summary><strong>🏠 Main Flow</strong></summary>

```
Main Screen (bottom navigation)
   ├── Home
   │     ├── Shield toggle — start/stop background monitoring
   │     ├── Radar animation while active
   │     ├── Battery optimization warning banner
   │     ├── Contacts / Sensor / Location stat cards
   │     └── Floating SEND SOS button
   │
   ├── Sensors
   │     └── Live accelerometer / gyroscope / noise readings,
   │         refreshed every 2s with 30s peak-range tracking
   │
   ├── Contacts
   │     └── Add / edit / remove emergency contacts
   │
   └── Settings
         ├── Permission status checklist
         ├── Device setup guide (OEM-specific)
         └── Disable battery optimization shortcut
```
</details>

<details>
<summary><strong>🚨 Accident Flow</strong></summary>

```
Sensor thresholds crossed (accel + gyro [+ noise])
   └── Accident confirmed within detection window
         ├── Screen turns on, full-screen alarm dialog
         ├── 30-second countdown with siren + haptics
         ├── Native foreground alarm notification with "I'M SAFE" action
         │
         ├── If user taps "I'M SAFE" → alarm cancelled, no alert sent
         └── If countdown expires (or "SEND SOS NOW" tapped)
               ├── SMS with GPS + Maps link sent to all contacts
               ├── Emergency contacts called sequentially
               └── SOS Screen — animated confirmation of dispatched alerts
```
</details>

---

## 🧠 Detection Logic

An accident is only confirmed when multiple independent sensors agree within a short time window — this avoids false triggers from a single bump or loud noise.

| Sensor | Threshold | Role |
|--------|-----------|------|
| Accelerometer | > 45 m/s² (smoothed over 5 samples) | Detects sudden impact force |
| Gyroscope | > 4 rad/s | Detects abnormal rotation/tumbling |
| Noise Meter | > 90 dB | Detects a loud crash sound (foreground detection only) |

Each sensor records its own trigger timestamp. Timestamps older than **2 seconds** automatically expire, so a stale spike from one sensor can never combine with an unrelated spike from another to create a false positive. An accident is confirmed only when the required sensors have all triggered **within the same 2-second window**.

---

## 🚀 Getting Started

### Prerequisites

- Flutter `>=3.27.0`
- Dart SDK `>=3.6.0`
- Android Studio / an Android device or emulator (SDK 23+)

### Installation

```bash
# 1. Clone the repo
git clone https://github.com/<your-org>/msg_bypas.git
cd msg_bypas

# 2. Install dependencies
flutter pub get

# 3. Run on a connected device
flutter run
```

> ⚠️ Accident detection relies on real motion, rotation, and (optionally) audio sensors — an **emulator will not produce realistic results**. Test on a physical device.

### Building a release APK

```bash
flutter build apk --release
```

---

## 🔐 Permissions

Rescue Me requests a broad permission set because it must work reliably **in the background, with the screen off, without user interaction**:

| Permission | Purpose |
|-----------|---------|
| `SEND_SMS` / `READ_SMS` / `RECEIVE_SMS` | Send the emergency alert message |
| `CALL_PHONE` | Automatically call emergency contacts |
| `ACCESS_FINE_LOCATION` / `ACCESS_BACKGROUND_LOCATION` | Attach live GPS coordinates to alerts |
| `RECORD_AUDIO` | Noise-based crash detection |
| `FOREGROUND_SERVICE*` | Keep accident monitoring alive in the background |
| `POST_NOTIFICATIONS` | Show the "shield active" and countdown alerts |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | Prevent the OS from killing the monitoring service |
| `RECEIVE_BOOT_COMPLETED` | Restart monitoring automatically after a reboot |
| `SYSTEM_ALERT_WINDOW` / `USE_FULL_SCREEN_INTENT` / `DISABLE_KEYGUARD` | Wake and unlock the screen for the alarm dialog |

---

## 📴 OEM Background Restrictions

Aggressive battery managers on certain Android skins can silently kill background services. Rescue Me detects these devices and walks the user through the fix:

| Manufacturer | Required Steps |
|--------------|-----------------|
| **OPPO / Realme** | Disable battery optimization, allow all permissions, enable background activity, lock app in Recents |
| **Vivo** | Background App Management → allow high battery usage, enable Auto-start |
| **Xiaomi / Redmi** | Battery Saver → No restrictions, enable Autostart |
| **OnePlus** | Disable battery optimization, enable Auto-start |

These flows are triggered automatically on first launch and re-offered from **Settings → Device Setup Guide** if skipped.

---

## 🛠️ Tech Stack

### Flutter / Dart
| Package | Purpose |
|---------|---------|
| `sensors_plus` | Accelerometer & gyroscope streams |
| `noise_meter` | Ambient noise level (dB) monitoring |
| `audioplayers` | Looping siren alarm playback |
| `geolocator` / `geocoding` | GPS location + reverse-geocoded address |
| `permission_handler` | Runtime permission requests |
| `shared_preferences` | Local state, mirrored with native Android prefs |
| `device_info_plus` | Manufacturer/OEM detection |
| `android_intent_plus` | Deep links into OEM-specific settings screens |

### Native Android (Kotlin)
| Component | Purpose |
|-----------|---------|
| `AccidentMonitoringService` | Foreground service running sensor fusion detection |
| `AlarmForegroundService` | Foreground service driving the countdown alarm & notification |
| `BootReceiver` | Restarts monitoring after device reboot |
| `AlarmActionReceiver` | Handles the "I'M SAFE" notification action |
| `SmsReceiver` | Native SMS handling support |
| `MainActivity` | Hosts all `MethodChannel`s bridging Flutter ↔ native SMS, calls, alarms, and OEM settings |

---

## 📁 Project Structure

```
msg_bypas/
│
├── 📂 android/
│   └── app/src/main/kotlin/com/buxhiisd/msg_bypas/
│       ├── MainActivity.kt              ← MethodChannel bridge (SMS, calls, alarm, service, OEM)
│       ├── AccidentMonitoringService.kt ← Background sensor-fusion detection
│       ├── AlarmForegroundService.kt    ← Countdown alarm + notification
│       ├── AlarmActionReceiver.kt       ← "I'M SAFE" action handler
│       └── BootReceiver.kt              ← Restarts monitoring on reboot
│
└── 📂 lib/
    ├── main.dart                        ← App entry point
    ├── screens/
    │   ├── splash_screen.dart
    │   ├── setup_screen.dart
    │   ├── main_screen.dart             ← Bottom nav shell
    │   ├── home_screen.dart             ← Shield toggle, detection, SOS
    │   ├── sensorsscreen.dart           ← Live sensor dashboard
    │   ├── emergencycontactscreen.dart
    │   ├── settings_scrren.dart
    │   └── sos_screen.dart              ← Post-alert confirmation
    └── services/
        ├── sms_service.dart             ← SMS sending with OEM retry logic
        ├── call_service.dart            ← Sequential emergency calling
        ├── location_service.dart        ← GPS + address + message formatting
        ├── permission_service.dart
        ├── oppo_vivo_helper.dart        ← OEM detection & settings deep links
        └── contacts_notifier.dart       ← Global contact-change listener
```

---

## 🤝 Contributing

Contributions are welcome! Here's how to get started:

```bash
# 1. Fork the repository
# 2. Create your feature branch
git checkout -b feature/your-feature-name

# 3. Commit your changes
git commit -m "feat: add your feature description"

# 4. Push to your branch
git push origin feature/your-feature-name

# 5. Open a Pull Request
```

### 📌 Planned Features
- [ ] iOS support (currently Android-focused)
- [ ] Configurable detection thresholds per user
- [ ] Cloud backup of emergency contacts
- [ ] In-app crash history log
- [ ] Wearable integration for detection

---

## 📄 License

This project is licensed under the **MIT License** — see the LICENSE file for details.

---

<div align="center">

**Stay safe. Let Rescue Me watch your back.**

⭐ **Star this repo** if you found it useful!

</div>
