import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

const int pillCount = 8;
const String _pillsKey = 'pill_slots_v1';
const String _takenKey = 'taken_by_date_v1';

final FlutterLocalNotificationsPlugin notifications =
    FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initializeNotifications();
  runApp(const GrandmaPillTrackerApp());
}

Future<void> _initializeNotifications() async {
  tzdata.initializeTimeZones();
  try {
    final dynamic zone = await FlutterTimezone.getLocalTimezone();
    final String name = zone is String ? zone : zone.identifier as String;
    tz.setLocalLocation(tz.getLocation(name));
  } catch (_) {
    // If timezone lookup is unavailable, use the plugin's default local zone.
  }

  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  const windows = WindowsInitializationSettings(
    appName: 'Grandma Pill Tracker',
    appUserModelId: 'com.example.grandmapilltracker',
    guid: '5a4a4dc7-86e7-44c8-80ab-dbbaf9c3cbe1',
  );
  const settings = InitializationSettings(android: android, windows: windows);
  await notifications.initialize(settings: settings);

  final androidPlugin = notifications.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.requestNotificationsPermission();
}

class PillSlot {
  PillSlot({
    required this.name,
    required this.enabled,
    required this.hour,
    required this.minute,
  });

  String name;
  bool enabled;
  int hour;
  int minute;

  factory PillSlot.empty() =>
      PillSlot(name: '', enabled: false, hour: 8, minute: 0);

  factory PillSlot.fromJson(Map<String, dynamic> json) => PillSlot(
        name: json['name'] as String? ?? '',
        enabled: json['enabled'] as bool? ?? false,
        hour: (json['hour'] as num?)?.toInt() ?? 8,
        minute: (json['minute'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'enabled': enabled,
        'hour': hour,
        'minute': minute,
      };
}

class GrandmaPillTrackerApp extends StatelessWidget {
  const GrandmaPillTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Grandma Pill Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFB66C91),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFFFF8FB),
        cardTheme: const CardThemeData(
          elevation: 0,
          color: Colors.white,
          margin: EdgeInsets.zero,
        ),
      ),
      home: const TrackerHomePage(),
    );
  }
}

class TrackerHomePage extends StatefulWidget {
  const TrackerHomePage({super.key});

  @override
  State<TrackerHomePage> createState() => _TrackerHomePageState();
}

class _TrackerHomePageState extends State<TrackerHomePage> {
  List<PillSlot> pills = List.generate(pillCount, (_) => PillSlot.empty());
  Set<String> taken = {};
  bool loading = true;
  bool remindersPermissionGranted = true;

  String get todayKey {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  String _takenId(int index) => '$todayKey:$index';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final rawPills = prefs.getString(_pillsKey);
    final rawTaken = prefs.getString(_takenKey);
    if (rawPills != null) {
      try {
        final decoded = jsonDecode(rawPills) as List<dynamic>;
        pills = List.generate(
          pillCount,
          (i) => i < decoded.length
              ? PillSlot.fromJson(
                  Map<String, dynamic>.from(decoded[i] as Map))
              : PillSlot.empty(),
        );
      } catch (_) {
        pills = List.generate(pillCount, (_) => PillSlot.empty());
      }
    }
    if (rawTaken != null) {
      try {
        final decoded = jsonDecode(rawTaken) as Map<String, dynamic>;
        taken = Set<String>.from(
          (decoded[todayKey] as List<dynamic>? ?? []).cast<String>(),
        );
      } catch (_) {
        taken = {};
      }
    }
    if (!mounted) return;
    setState(() => loading = false);
    await _rescheduleAll();
  }

  Future<void> _savePills() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _pillsKey,
      jsonEncode(pills.map((pill) => pill.toJson()).toList()),
    );
  }

  Future<void> _saveTaken() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_takenKey);
    Map<String, dynamic> history = {};
    if (raw != null) {
      try {
        history = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      } catch (_) {}
    }
    history[todayKey] = taken.toList();
    await prefs.setString(_takenKey, jsonEncode(history));
  }

  Future<void> _rescheduleAll() async {
    await notifications.cancelAll();
    for (var i = 0; i < pills.length; i++) {
      final pill = pills[i];
      if (!pill.enabled || pill.name.trim().isEmpty) continue;
      await _schedulePill(i, pill);
    }
  }

  Future<void> _schedulePill(int index, PillSlot pill) async {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      pill.hour,
      pill.minute,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    const androidDetails = AndroidNotificationDetails(
      'pill_reminders',
      'Pill reminders',
      channelDescription: 'Reminders configured in Grandma Pill Tracker',
      importance: Importance.high,
      priority: Priority.high,
    );
    const windowsDetails = WindowsNotificationDetails();
    await notifications.zonedSchedule(
      id: index + 1,
      title: 'Medication reminder',
      body: 'Time for: ${pill.name}',
      scheduledDate: scheduled,
      notificationDetails: const NotificationDetails(
        android: androidDetails,
        windows: windowsDetails,
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> _editPill(int index) async {
    final original = pills[index];
    final nameController = TextEditingController(text: original.name);
    var enabled = original.enabled;
    var hour = original.hour;
    var minute = original.minute;

    final result = await showDialog<PillSlot>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Pill ${index + 1}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Pill name',
                    hintText: 'Enter the name from the label',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Enable reminder'),
                  value: enabled,
                  onChanged: (value) =>
                      setDialogState(() => enabled = value),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.schedule),
                  label: Text(_formatTime(hour, minute)),
                  onPressed: () async {
                    final selected = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay(hour: hour, minute: minute),
                    );
                    if (selected != null) {
                      setDialogState(() {
                        hour = selected.hour;
                        minute = selected.minute;
                      });
                    }
                  },
                ),
                const SizedBox(height: 6),
                Text(
                  'Use the schedule confirmed by Grandma’s pharmacist or '
                  'prescription label.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                PillSlot(
                  name: nameController.text.trim(),
                  enabled: enabled,
                  hour: hour,
                  minute: minute,
                ),
              ),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    nameController.dispose();
    if (result == null) return;
    setState(() => pills[index] = result);
    await _savePills();
    await _rescheduleAll();
  }

  Future<void> _toggleTaken(int index, bool value) async {
    setState(() {
      if (value) {
        taken.add(_takenId(index));
      } else {
        taken.remove(_takenId(index));
      }
    });
    await _saveTaken();
  }

  String _formatTime(int hour, int minute) {
    final h = hour % 12 == 0 ? 12 : hour % 12;
    final m = minute.toString().padLeft(2, '0');
    return '$h:$m ${hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    final completed = List.generate(pillCount, (i) => taken.contains(_takenId(i)))
        .where((value) => value)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Grandma’s Pill Tracker'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Reminder settings',
            onPressed: _showReminderInfo,
            icon: const Icon(Icons.notifications_active_outlined),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _ProgressCard(completed: completed),
                    const SizedBox(height: 16),
                    Text(
                      'Today’s pills',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    for (var i = 0; i < pillCount; i++)
                      _pillCard(i),
                    const SizedBox(height: 16),
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'This app is a reminder and checklist only. '
                                'It cannot confirm that a medicine was swallowed '
                                'or determine what should be taken. Follow the '
                                'prescription label and healthcare professional’s '
                                'instructions.',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _pillCard(int index) {
    final pill = pills[index];
    final isTaken = taken.contains(_takenId(index));
    return Card(
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: Checkbox(
          value: isTaken,
          onChanged: (value) => _toggleTaken(index, value ?? false),
        ),
        title: Text(
          pill.name.isEmpty ? 'Set up pill ${index + 1}' : pill.name,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            decoration: isTaken ? TextDecoration.lineThrough : null,
            color: isTaken ? Colors.grey : null,
          ),
        ),
        subtitle: Text(
          pill.name.isEmpty
              ? 'Tap Edit to enter the pill name'
              : pill.enabled
                  ? 'Reminder: ${_formatTime(pill.hour, pill.minute)}'
                  : 'Reminder off',
        ),
        trailing: TextButton(
          onPressed: () => _editPill(index),
          child: const Text('Edit'),
        ),
      ),
    );
  }

  Future<void> _showReminderInfo() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reminders'),
        content: const Text(
          'Edit any pill and turn on its reminder. Choose the time with the '
          'time picker. Notifications must be allowed in device settings. '
          'Android and Windows handle background notifications differently, '
          'so test each reminder on the device before relying on it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.completed});

  final int completed;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFF9EAF1),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Daily progress',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$completed of $pillCount',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(width: 8),
                const Padding(
                  padding: EdgeInsets.only(bottom: 5),
                  child: Text('checked off today'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: completed / pillCount),
          ],
        ),
      ),
    );
  }
}
