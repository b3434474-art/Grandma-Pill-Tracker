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
bool notificationPluginReady = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeNotifications();
  runApp(const GrandmaPillTrackerApp());
}

Future<void> initializeNotifications() async {
  tzdata.initializeTimeZones();

  try {
    final dynamic zoneInfo = await FlutterTimezone.getLocalTimezone();
    final String zoneName =
        zoneInfo is String ? zoneInfo : zoneInfo.identifier as String;
    tz.setLocalLocation(tz.getLocation(zoneName));
  } catch (error) {
    debugPrint('Could not read the device time zone: $error');
  }

  const initializationSettings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    windows: WindowsInitializationSettings(
      appName: 'Grandma Pill Tracker',
      appUserModelId: 'com.b3434474.grandmapilltracker',
      guid: '5a4a4dc7-86e7-44c8-80ab-dbbaf9c3cbe1',
    ),
  );

  try {
    await notifications.initialize(settings: initializationSettings);
    notificationPluginReady = true;
  } catch (error) {
    debugPrint('Notification setup could not finish: $error');
  }

  try {
    await notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  } catch (error) {
    debugPrint('Notification permission was not requested: $error');
  }
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
    final colors = ColorScheme.fromSeed(
      seedColor: const Color(0xFF9B5275),
      brightness: Brightness.light,
    );

    return MaterialApp(
      title: 'Grandma Pill Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colors,
        scaffoldBackgroundColor: const Color(0xFFF8F5F7),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF8F5F7),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF7F3F6),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFE9E0E6)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: colors.primary, width: 1.5),
          ),
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

  String get todayKey {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  String takenId(int index) => '$todayKey:$index';

  int get completedCount => List.generate(
        pillCount,
        (index) => taken.contains(takenId(index)),
      ).where((value) => value).length;

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawPills = prefs.getString(_pillsKey);
      final rawTaken = prefs.getString(_takenKey);

      if (rawPills != null) {
        try {
          final decoded = jsonDecode(rawPills) as List<dynamic>;
          pills = List.generate(
            pillCount,
            (index) => index < decoded.length
                ? PillSlot.fromJson(
                    Map<String, dynamic>.from(decoded[index] as Map),
                  )
                : PillSlot.empty(),
          );
        } catch (error) {
          debugPrint('Saved pill settings could not be read: $error');
        }
      }

      if (rawTaken != null) {
        try {
          final decoded = jsonDecode(rawTaken) as Map<String, dynamic>;
          taken = Set<String>.from(
            (decoded[todayKey] as List<dynamic>? ?? <dynamic>[]).cast<String>(),
          );
        } catch (error) {
          debugPrint('Today’s checklist could not be read: $error');
          taken = {};
        }
      }
    } catch (error) {
      debugPrint('Local app data could not be loaded: $error');
    }

    if (!mounted) return;
    setState(() => loading = false);
    await rescheduleAll();
  }

  Future<void> savePills() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _pillsKey,
      jsonEncode(pills.map((pill) => pill.toJson()).toList()),
    );
  }

  Future<void> saveTaken() async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> history = {};
    final raw = prefs.getString(_takenKey);

    if (raw != null) {
      try {
        history = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      } catch (error) {
        debugPrint('Previous checklist history could not be read: $error');
      }
    }

    history[todayKey] = List<String>.from(taken);
    await prefs.setString(_takenKey, jsonEncode(history));
  }

  Future<bool> rescheduleAll() async {
    if (!notificationPluginReady) return false;

    var success = true;
    try {
      await notifications.cancelAll();
    } catch (error) {
      debugPrint('Old reminders could not be cleared: $error');
      success = false;
    }

    for (var index = 0; index < pills.length; index++) {
      final pill = pills[index];
      if (!pill.enabled || pill.name.trim().isEmpty) continue;

      try {
        await schedulePill(index, pill);
      } catch (error) {
        debugPrint('Reminder ${index + 1} could not be scheduled: $error');
        success = false;
      }
    }
    return success;
  }

  Future<void> schedulePill(int index, PillSlot pill) async {
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
      channelDescription: 'Daily reminders configured in this app',
      importance: Importance.high,
      priority: Priority.high,
    );

    await notifications.zonedSchedule(
      id: index + 1,
      title: 'Medication reminder',
      body: 'Time to check: ${pill.name}',
      scheduledDate: scheduled,
      notificationDetails: const NotificationDetails(
        android: androidDetails,
        windows: WindowsNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> editPill(int index) async {
    final original = pills[index];
    final nameController = TextEditingController(text: original.name);
    var enabled = original.enabled;
    var hour = original.hour;
    var minute = original.minute;

    final result = await showDialog<PillSlot>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            original.name.trim().isEmpty
                ? 'Set up pill ${index + 1}'
                : 'Edit pill ${index + 1}',
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pill name',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    maxLength: 40,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      hintText: 'Enter the name from the label',
                      prefixIcon: Icon(Icons.medication_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Daily reminder'),
                    subtitle: const Text('Show a notification at the chosen time'),
                    value: enabled,
                    onChanged: (value) =>
                        setDialogState(() => enabled = value),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.schedule_outlined),
                    label: Text('Reminder time · ${formatTime(hour, minute)}'),
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
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F1F5),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, size: 20),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Use the schedule on the prescription label or confirmed by a pharmacist. This app does not choose doses or tell anyone what to take.',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(
                dialogContext,
                PillSlot(
                  name: nameController.text.trim(),
                  enabled: enabled,
                  hour: hour,
                  minute: minute,
                ),
              ),
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Save changes'),
            ),
          ],
        ),
      ),
    );

    nameController.dispose();
    if (result == null) return;

    setState(() => pills[index] = result);
    await savePills();
    final remindersSaved = await rescheduleAll();

    if (mounted &&
        result.enabled &&
        result.name.trim().isNotEmpty &&
        !remindersSaved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Your changes were saved, but this device could not confirm the reminder. Check notification settings.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> toggleTaken(int index, bool value) async {
    if (pills[index].name.trim().isEmpty) return;

    setState(() {
      if (value) {
        taken.add(takenId(index));
      } else {
        taken.remove(takenId(index));
      }
    });

    try {
      await saveTaken();
    } catch (error) {
      debugPrint('Checklist update could not be saved: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The change could not be saved on this device.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String formatTime(int hour, int minute) {
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    return '$displayHour:${minute.toString().padLeft(2, '0')} '
        '${hour < 12 ? 'AM' : 'PM'}';
  }

  String get todayLabel {
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final now = DateTime.now();
    return '${weekdays[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}';
  }

  @override
  Widget build(BuildContext context) {
    final completed = completedCount;
    final wide = MediaQuery.sizeOf(context).width >= 900;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 82,
        titleSpacing: 20,
        title: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFFF0DDE7),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(
                Icons.favorite_rounded,
                color: Color(0xFF914668),
                size: 25,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Grandma’s Daily Care',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                  ),
                  Text(
                    'Medication checklist',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF786D75),
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: IconButton.filledTonal(
              tooltip: 'Reminder information',
              onPressed: showReminderInfo,
              icon: const Icon(Icons.notifications_active_outlined),
            ),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, _) => Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1260),
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      wide ? 30 : 18,
                      18,
                      wide ? 30 : 18,
                      32,
                    ),
                    children: [
                      if (wide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 320,
                              child: Column(
                                children: [
                                  progressPanel(completed),
                                  const SizedBox(height: 18),
                                  reminderInfoCard(),
                                ],
                              ),
                            ),
                            const SizedBox(width: 24),
                            Expanded(child: checklistPanel(wide: true)),
                          ],
                        )
                      else ...[
                        progressPanel(completed),
                        const SizedBox(height: 26),
                        checklistPanel(wide: false),
                        const SizedBox(height: 18),
                        reminderInfoCard(),
                      ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget progressPanel(int completed) {
    final progress = completed / pillCount;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFF1DDE7),
            Color(0xFFE8E3F3),
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE9D8E3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'YOUR DAY',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: const Color(0xFF76536A),
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                      ),
                ),
              ),
              const Icon(
                Icons.wb_sunny_outlined,
                color: Color(0xFF8F6680),
                size: 22,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'One step at a time.',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF392B35),
                  height: 1.15,
                ),
          ),
          const SizedBox(height: 5),
          Text(
            todayLabel,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF6F606A),
                ),
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$completed of $pillCount',
                      style:
                          Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF4B3342),
                                letterSpacing: -0.8,
                              ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      completed == pillCount
                          ? 'Checklist complete'
                          : '${pillCount - completed} entries remaining',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF695763),
                          ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 76,
                height: 76,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 8,
                        strokeCap: StrokeCap.round,
                        backgroundColor: Colors.white.withValues(alpha: 0.7),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF945476),
                        ),
                      ),
                    ),
                    Text(
                      '${(progress * 100).round()}%',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF56384B),
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              minHeight: 9,
              value: progress,
              backgroundColor: Colors.white.withValues(alpha: 0.78),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF945476),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget checklistPanel({required bool wide}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Today’s checklist',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          color: const Color(0xFF302832),
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Check an entry after it has been taken.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF786D75),
                        ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFEFE8ED),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                '8 entries',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: const Color(0xFF65495A),
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (wide)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: pillCount,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              mainAxisExtent: 156,
            ),
            itemBuilder: (context, index) => pillCard(index),
          )
        else
          for (var index = 0; index < pillCount; index++) ...[
            pillCard(index),
            if (index != pillCount - 1) const SizedBox(height: 12),
          ],
      ],
    );
  }

  Widget pillCard(int index) {
    final pill = pills[index];
    final isTaken = taken.contains(takenId(index));
    final hasName = pill.name.trim().isNotEmpty;
    final accent = isTaken
        ? const Color(0xFF347B68)
        : const Color(0xFF925273);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(21),
        border: Border.all(
          color: isTaken
              ? const Color(0xFFCFE4DC)
              : const Color(0xFFEDE5EA),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x09000000),
            blurRadius: 16,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(15, 14, 13, 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isTaken
                        ? const Color(0xFFE4F1EC)
                        : const Color(0xFFF6EAF0),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    '${index + 1}'.padLeft(2, '0'),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: accent,
                        ),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasName ? pill.name : 'Add a pill name',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: isTaken
                                  ? const Color(0xFF61736C)
                                  : const Color(0xFF342B33),
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isTaken
                            ? 'Checked off today'
                            : hasName
                                ? 'Daily checklist item'
                                : 'Tap Edit to set this up',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF817680),
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Checkbox(
                  value: isTaken,
                  onChanged: hasName
                      ? (value) => toggleTaken(index, value ?? false)
                      : null,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  visualDensity: VisualDensity.standard,
                ),
              ],
            ),
            const Spacer(),
            Divider(height: 1, color: const Color(0xFFF0EAF0)),
            const SizedBox(height: 5),
            Row(
              children: [
                Icon(
                  pill.enabled && hasName
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_none_outlined,
                  size: 17,
                  color: pill.enabled && hasName
                      ? const Color(0xFF8A5774)
                      : const Color(0xFF958B93),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    !hasName
                        ? 'Reminder not set'
                        : pill.enabled
                            ? formatTime(pill.hour, pill.minute)
                            : 'Reminder off',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: const Color(0xFF70646D),
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => editPill(index),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Edit'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 36),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget reminderInfoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(19),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFEDE5EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF0F7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.notifications_active_outlined,
                  color: Color(0xFF536D8B),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'A helpful reminder',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Edit an entry to choose its reminder time. Allow notifications in device settings so alerts can appear.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.45,
                  color: const Color(0xFF716771),
                ),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: showReminderInfo,
            icon: const Icon(Icons.info_outline, size: 18),
            label: const Text('How reminders work'),
          ),
        ],
      ),
    );
  }

  Future<void> showReminderInfo() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('About reminders'),
        content: const SizedBox(
          width: 420,
          child: Text(
            'Each entry can have its own daily reminder time. Notifications depend on device permissions and system settings, and may be delayed or blocked. Windows and Android should both be tested on the actual device before relying on alerts.\n\n'
            'This app is only a checklist and reminder. It does not choose medicines, doses, or schedules, and a checked box cannot confirm that a medicine was swallowed. Follow the prescription label and ask a pharmacist or healthcare professional about any questions.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
