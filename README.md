# Grandma Pill Tracker

A simple, local-first checklist for eight medication entries, with editable names and configurable daily reminder times.

## Features

- Exactly eight pill slots.
- Grandma can edit each pill's display name.
- Check off each entry for the current day.
- Optional daily reminder per pill, with a selectable time.
- Stores names, reminder settings, and checkmarks locally on the device.
- Flutter project intended for Android and Windows from one codebase.

## Build

Install the Flutter SDK and enable Windows desktop support.

```sh
flutter pub get
flutter run -d windows
flutter run -d <your-android-device-id>
```

Create release builds:

```sh
flutter build windows --release
flutter build apk --release
```

## Reminder notes

Notifications need permission. Android may restrict background alarms depending on device settings and OS version. Windows notifications also depend on Windows notification settings. Test reminders on the actual devices before depending on them; this app does not guarantee delivery.

Set each reminder only using the schedule confirmed by the prescription label or a pharmacist/healthcare professional. The app does not recommend doses, decide whether a medicine should be taken, or confirm that a pill was swallowed.

## Privacy

This repository is public. Do not commit real medication names, schedules, screenshots, backups, or other personal health information. The app is designed to store this information locally on the device and does not include cloud sync.

## Status

Early starter implementation. Android and Windows platform runners, builds, and notification behavior still need to be validated on real devices.
