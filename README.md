# Grandma Pill Tracker

A local-first daily checklist for eight medication entries, with editable names and an individual reminder time for each entry.

## Features

- Exactly eight editable entries.
- Grandma can enter or change each entry name.
- Check off an entry for the current day and undo the check if needed.
- Optional daily reminder for each named entry.
- Large, clear controls and a responsive layout for Android phones and Windows desktops.
- Saves names, reminder settings, and checklist history on the device.
- No account, cloud sync, or subscription.

## Build

The GitHub Actions workflow generates the Android and Windows runner projects, then builds both releases.

For a local Flutter setup:

\`\`\`sh
flutter pub get
flutter run -d windows
flutter run -d <your-android-device-id>

flutter build windows --release
flutter build apk --release
\`\`\`

## Important reminder notes

Notifications depend on Android or Windows notification permissions and system settings. Operating-system battery and background restrictions can delay or prevent notifications. Test alerts on the actual device before relying on them, and do not make this app the only reminder.

Enter reminder times only from the prescription label or a schedule confirmed by a pharmacist or healthcare professional. The app does not recommend medicines or doses, and a checked box cannot confirm that a medicine was swallowed.

## Privacy

This repository is public. Do not commit real medication names, reminder schedules, screenshots, backups, or other personal health information. The app is designed to keep its data on the device and does not include cloud sync.
