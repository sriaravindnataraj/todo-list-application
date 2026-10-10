import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MainApp());
}

class TaskItem {
  TaskItem({
    required this.title,
    required this.notificationId,
    this.isCompleted = false,
    this.dueDate,
    this.reminderAt,
  });

  String title;
  int notificationId;
  bool isCompleted;
  DateTime? dueDate;
  DateTime? reminderAt;

  Map<String, Object?> toJson() => {
    'title': title,
    'notificationId': notificationId,
    'isCompleted': isCompleted,
    'dueDate': dueDate?.toIso8601String(),
    'reminderAt': reminderAt?.toIso8601String(),
  };

  factory TaskItem.fromJson(
    Map<String, dynamic> json, {
    required int fallbackNotificationId,
  }) {
    final title = json['title'];
    final notificationId = json['notificationId'] ?? fallbackNotificationId;
    final isCompleted = json['isCompleted'];
    final dueDate = json['dueDate'];
    final reminderAt = json['reminderAt'];
    if (title is! String ||
        notificationId is! int ||
        notificationId <= 0 ||
        notificationId > 0x7fffffff ||
        isCompleted is! bool ||
        (dueDate != null && dueDate is! String) ||
        (reminderAt != null && reminderAt is! String)) {
      throw const FormatException('Invalid saved task data.');
    }
    return TaskItem(
      title: title,
      notificationId: notificationId,
      isCompleted: isCompleted,
      dueDate: dueDate == null ? null : DateTime.parse(dueDate),
      reminderAt: reminderAt == null ? null : DateTime.parse(reminderAt),
    );
  }
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _StatsItem extends StatelessWidget {
  const _StatsItem({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value.toString(),
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.blue,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
        ),
      ],
    );
  }
}

class _EditTaskDialog extends StatefulWidget {
  const _EditTaskDialog({
    required this.initialTitle,
    this.initialDueDate,
    this.initialReminderAt,
  });

  final String initialTitle;
  final DateTime? initialDueDate;
  final DateTime? initialReminderAt;

  @override
  State<_EditTaskDialog> createState() => _EditTaskDialogState();
}

class _EditTaskDialogState extends State<_EditTaskDialog> {
  late final TextEditingController _controller;
  DateTime? _dueDate;
  DateTime? _reminderAt;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialTitle);
    _dueDate = widget.initialDueDate;
    _reminderAt = widget.initialReminderAt;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    return AlertDialog(
      title: const Text('Edit Task'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Task name',
            ),
          ),
          const SizedBox(height: 12),
          _DateTimeControls(
            dueDate: _dueDate,
            reminderAt: _reminderAt,
            onDueDateChanged: (date) => setState(() {
              final previousReminder = _reminderAt;
              _dueDate = date;
              _reminderAt = date == null || previousReminder == null
                  ? null
                  : DateTime(
                      date.year,
                      date.month,
                      date.day,
                      previousReminder.hour,
                      previousReminder.minute,
                    );
            }),
            onReminderChanged: (reminder) =>
                setState(() => _reminderAt = reminder),
            formatDate: localizations.formatMediumDate,
            formatTime: (date) =>
                localizations.formatTimeOfDay(TimeOfDay.fromDateTime(date)),
          ),
          if (_errorText != null) ...[
            const SizedBox(height: 8),
            Text(
              _errorText!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            final title = _controller.text.trim();
            if (title.isEmpty) return;
            if (_reminderAt != null && !_reminderAt!.isAfter(DateTime.now())) {
              setState(() => _errorText = 'Choose a future reminder time.');
              return;
            }
            Navigator.of(context).pop(
              _TaskEditResult(
                title: title,
                dueDate: _dueDate,
                reminderAt: _reminderAt,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _TaskEditResult {
  const _TaskEditResult({
    required this.title,
    required this.dueDate,
    required this.reminderAt,
  });

  final String title;
  final DateTime? dueDate;
  final DateTime? reminderAt;
}

class _DateTimeControls extends StatelessWidget {
  const _DateTimeControls({
    required this.dueDate,
    required this.reminderAt,
    required this.onDueDateChanged,
    required this.onReminderChanged,
    required this.formatDate,
    required this.formatTime,
  });

  final DateTime? dueDate;
  final DateTime? reminderAt;
  final ValueChanged<DateTime?> onDueDateChanged;
  final ValueChanged<DateTime?> onReminderChanged;
  final String Function(DateTime) formatDate;
  final String Function(DateTime) formatTime;

  Future<void> _pickDueDate(BuildContext context) async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: dueDate ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (selected == null) return;
    onDueDateChanged(DateTime(selected.year, selected.month, selected.day));
  }

  Future<void> _pickReminderTime(BuildContext context) async {
    if (dueDate == null) return;
    final selected = await showTimePicker(
      context: context,
      initialTime: reminderAt == null
          ? const TimeOfDay(hour: 9, minute: 0)
          : TimeOfDay.fromDateTime(reminderAt!),
    );
    if (selected == null) return;
    onReminderChanged(
      DateTime(
        dueDate!.year,
        dueDate!.month,
        dueDate!.day,
        selected.hour,
        selected.minute,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: () => _pickDueDate(context),
          icon: const Icon(Icons.calendar_today_outlined),
          label: Text(dueDate == null ? 'Set due date' : formatDate(dueDate!)),
        ),
        if (dueDate != null) ...[
          OutlinedButton.icon(
            onPressed: () => _pickReminderTime(context),
            icon: const Icon(Icons.notifications_outlined),
            label: Text(
              reminderAt == null
                  ? 'Set reminder'
                  : 'Reminder: ${formatTime(reminderAt!)}',
            ),
          ),
          if (reminderAt != null)
            TextButton(
              onPressed: () => onReminderChanged(null),
              child: const Text('Remove reminder'),
            ),
          TextButton(
            onPressed: () => onDueDateChanged(null),
            child: const Text('Remove due date'),
          ),
        ],
      ],
    );
  }
}

class _TaskReminder {
  const _TaskReminder({
    required this.notificationId,
    required this.title,
    required this.isCompleted,
    required this.reminderAt,
  });

  final int notificationId;
  final String title;
  final bool isCompleted;
  final DateTime? reminderAt;
}

enum _ReminderSyncResult { success, unsupported, permissionDenied }

class _ReminderNotifications {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  Future<void>? _initialization;

  bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> _initialize() {
    return _initialization ??= _initializePlugin();
  }

  Future<void> _initializePlugin() async {
    tz.initializeTimeZones();
    final timezone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timezone.identifier));

    final initialized = await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    if (initialized != true) {
      throw StateError('Could not initialize local notifications.');
    }
  }

  Future<_ReminderSyncResult> sync(List<_TaskReminder> tasks) async {
    final reminders = tasks
        .where(
          (task) =>
              !task.isCompleted &&
              task.reminderAt != null &&
              task.reminderAt!.isAfter(DateTime.now()),
        )
        .toList();
    if (reminders.isEmpty && _initialization == null) {
      return _ReminderSyncResult.success;
    }
    if (!isSupported) {
      return reminders.isEmpty
          ? _ReminderSyncResult.success
          : _ReminderSyncResult.unsupported;
    }

    await _initialize();
    await _plugin.cancelAll();
    if (reminders.isEmpty) return _ReminderSyncResult.success;

    final hasPermission = switch (defaultTargetPlatform) {
      TargetPlatform.android =>
        await _plugin
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >()
                ?.requestNotificationsPermission() ??
            false,
      TargetPlatform.iOS =>
        await _plugin
                .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin
                >()
                ?.requestPermissions(alert: true, badge: true, sound: true) ??
            false,
      _ => false,
    };
    if (!hasPermission) return _ReminderSyncResult.permissionDenied;

    for (final reminder in reminders) {
      await _plugin.zonedSchedule(
        id: reminder.notificationId,
        title: 'Task reminder',
        body: reminder.title,
        scheduledDate: tz.TZDateTime.from(reminder.reminderAt!, tz.local),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'task_reminders',
            'Task reminders',
            channelDescription: 'Reminders for your to-do tasks',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
    return _ReminderSyncResult.success;
  }
}

class _MainAppState extends State<MainApp> {
  static const _tasksStorageKey = 'tasks';

  final _taskController = TextEditingController();
  final List<TaskItem> _tasks = [];
  final _reminderNotifications = _ReminderNotifications();
  Future<void> _saveQueue = Future<void>.value();
  DateTime? _newTaskDueDate;
  DateTime? _newTaskReminderAt;
  bool _reminderStatusShown = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  @override
  void dispose() {
    _taskController.dispose();
    super.dispose();
  }

  Future<void> _loadTasks() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final savedTasks = preferences.getString(_tasksStorageKey);
      if (savedTasks != null) {
        final decodedTasks = jsonDecode(savedTasks);
        if (decodedTasks is! List) {
          throw const FormatException('Saved tasks must be a list.');
        }
        for (final savedTask in decodedTasks) {
          if (savedTask is! Map<String, dynamic>) {
            throw const FormatException('Invalid saved task data.');
          }
          final task = TaskItem.fromJson(
            savedTask,
            fallbackNotificationId: _createNotificationId(),
          );
          if (_tasks.any(
            (existingTask) =>
                existingTask.notificationId == task.notificationId,
          )) {
            task.notificationId = _createNotificationId();
          }
          _tasks.add(task);
        }
      }
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'todo list',
          context: ErrorDescription('while loading saved tasks'),
        ),
      );
      if (mounted) {
        setState(() => _isLoading = false);
        _showStorageError();
      }
      return;
    }

    if (mounted) {
      setState(() => _isLoading = false);
      await _saveTasks();
    }
  }

  Future<void> _saveTasks() {
    final savedTasks = jsonEncode(_tasks.map((task) => task.toJson()).toList());
    final reminders = _tasks
        .map(
          (task) => _TaskReminder(
            notificationId: task.notificationId,
            title: task.title,
            isCompleted: task.isCompleted,
            reminderAt: task.reminderAt,
          ),
        )
        .toList();
    _saveQueue = _saveQueue.then((_) async {
      try {
        final preferences = await SharedPreferences.getInstance();
        final saved = await preferences.setString(_tasksStorageKey, savedTasks);
        if (!saved) {
          _showStorageError();
        }
      } catch (error, stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'todo list',
            context: ErrorDescription('while saving tasks'),
          ),
        );
        _showStorageError();
      }
      try {
        final result = await _reminderNotifications.sync(reminders);
        if (result != _ReminderSyncResult.success && !_reminderStatusShown) {
          _reminderStatusShown = true;
          _showReminderStatus(result);
        }
      } catch (error, stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'todo list',
            context: ErrorDescription('while scheduling task reminders'),
          ),
        );
        _showReminderStatus(null);
      }
    });
    return _saveQueue;
  }

  int _createNotificationId() {
    var candidate = DateTime.now().microsecondsSinceEpoch & 0x7fffffff;
    if (candidate == 0) candidate = 1;
    while (_tasks.any((task) => task.notificationId == candidate)) {
      candidate = candidate == 0x7fffffff ? 1 : candidate + 1;
    }
    return candidate;
  }

  void _showStorageError() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not save or load your tasks.')),
    );
  }

  void _showReminderStatus(_ReminderSyncResult? result) {
    if (!mounted) return;
    final message = switch (result) {
      _ReminderSyncResult.unsupported =>
        'Task reminders are available on Android and iOS only.',
      _ReminderSyncResult.permissionDenied =>
        'Notification permission was not granted; reminders are not scheduled.',
      _ => 'Could not schedule task reminders.',
    };
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _addTask() {
    final title = _taskController.text.trim();
    if (title.isEmpty) return;
    if (_newTaskReminderAt != null &&
        !_newTaskReminderAt!.isAfter(DateTime.now())) {
      _showMessage('Choose a future reminder time.');
      return;
    }

    setState(() {
      _tasks.add(
        TaskItem(
          title: title,
          notificationId: _createNotificationId(),
          dueDate: _newTaskDueDate,
          reminderAt: _newTaskReminderAt,
        ),
      );
      _taskController.clear();
      _newTaskDueDate = null;
      _newTaskReminderAt = null;
    });
    _saveTasks();
  }

  Future<void> _editTask(int index, BuildContext dialogContext) async {
    final task = _tasks[index];
    final updatedTask = await showDialog<_TaskEditResult>(
      context: dialogContext,
      builder: (_) => _EditTaskDialog(
        initialTitle: task.title,
        initialDueDate: task.dueDate,
        initialReminderAt: task.reminderAt,
      ),
    );

    if (updatedTask == null || !mounted || !_tasks.contains(task)) return;
    setState(() {
      task
        ..title = updatedTask.title
        ..dueDate = updatedTask.dueDate
        ..reminderAt = updatedTask.reminderAt;
    });
    await _saveTasks();
  }

  void _showSavingFlow(BuildContext dialogContext) {
    showDialog<void>(
      context: dialogContext,
      builder: (context) => AlertDialog(
        title: const Text('How tasks are saved'),
        content: const Text(
          'Add, edit, complete, or delete a task\n'
          '↓\n'
          'tasks[]\n'
          '↓\n'
          '_saveTasks()\n'
          '↓\n'
          'JSON conversion\n'
          '↓\n'
          'SharedPreferences on this device',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final completedCount = _tasks.where((task) => task.isCompleted).length;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Builder(
        builder: (context) {
          final localizations = MaterialLocalizations.of(context);
          return Scaffold(
            appBar: AppBar(
              title: const Text('Todo List'),
              actions: [
                Builder(
                  builder: (context) => IconButton(
                    onPressed: () => _showSavingFlow(context),
                    icon: const Icon(Icons.help_outline),
                    tooltip: 'How tasks are saved',
                  ),
                ),
              ],
            ),
            body: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      TextField(
                        controller: _taskController,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _addTask(),
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Enter the task',
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 50,
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _addTask,
                          child: const Text('Add Task'),
                        ),
                      ),
                      _DateTimeControls(
                        dueDate: _newTaskDueDate,
                        reminderAt: _newTaskReminderAt,
                        onDueDateChanged: (date) => setState(() {
                          final previousReminder = _newTaskReminderAt;
                          _newTaskDueDate = date;
                          _newTaskReminderAt =
                              date == null || previousReminder == null
                              ? null
                              : DateTime(
                                  date.year,
                                  date.month,
                                  date.day,
                                  previousReminder.hour,
                                  previousReminder.minute,
                                );
                        }),
                        onReminderChanged: (reminder) =>
                            setState(() => _newTaskReminderAt = reminder),
                        formatDate: localizations.formatMediumDate,
                        formatTime: (date) => localizations.formatTimeOfDay(
                          TimeOfDay.fromDateTime(date),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _StatsItem(label: 'Total', value: _tasks.length),
                            _StatsItem(
                              label: 'Completed',
                              value: completedCount,
                            ),
                            _StatsItem(
                              label: 'Remaining',
                              value: _tasks.length - completedCount,
                            ),
                          ],
                        ),
                      ),
                      if (completedCount > 0)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () {
                              setState(
                                () => _tasks.removeWhere(
                                  (task) => task.isCompleted,
                                ),
                              );
                              _saveTasks();
                            },
                            icon: const Icon(Icons.delete_sweep_outlined),
                            label: const Text('Clear completed'),
                          ),
                        ),
                      const SizedBox(height: 8),
                      if (_tasks.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('📝', style: TextStyle(fontSize: 48)),
                              const SizedBox(height: 12),
                              const Text(
                                'No tasks yet',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Add your first task!',
                                style: TextStyle(color: Colors.grey.shade700),
                              ),
                            ],
                          ),
                        )
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(bottom: 16),
                          itemCount: _tasks.length,
                          itemBuilder: (context, index) {
                            final task = _tasks[index];
                            final isOverdue =
                                task.dueDate != null &&
                                !task.isCompleted &&
                                DateTime(
                                  task.dueDate!.year,
                                  task.dueDate!.month,
                                  task.dueDate!.day,
                                ).isBefore(
                                  DateTime(
                                    DateTime.now().year,
                                    DateTime.now().month,
                                    DateTime.now().day,
                                  ),
                                );
                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.05),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.task_alt_outlined,
                                    color: Colors.blue,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Checkbox(
                                    value: task.isCompleted,
                                    activeColor: Colors.blue,
                                    onChanged: (value) {
                                      setState(
                                        () => task.isCompleted = value ?? false,
                                      );
                                      _saveTasks();
                                    },
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          task.title,
                                          style: TextStyle(
                                            fontSize: 16,
                                            color: task.isCompleted
                                                ? Colors.grey.shade600
                                                : Colors.black87,
                                            decoration: task.isCompleted
                                                ? TextDecoration.lineThrough
                                                : TextDecoration.none,
                                          ),
                                        ),
                                        if (task.dueDate != null)
                                          Text(
                                            'Due: ${localizations.formatMediumDate(task.dueDate!)}'
                                            '${isOverdue ? ' · Overdue' : ''}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: isOverdue
                                                  ? Colors.red.shade700
                                                  : Colors.grey.shade700,
                                            ),
                                          ),
                                        if (task.reminderAt != null)
                                          Text(
                                            'Reminder: ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(task.reminderAt!))}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade700,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => _editTask(index, context),
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      size: 18,
                                    ),
                                    label: const Text('Edit'),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.orange.shade800,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () {
                                      setState(() => _tasks.removeAt(index));
                                      _saveTasks();
                                    },
                                    icon: const Icon(Icons.delete_outline),
                                    color: const Color.fromARGB(
                                      255,
                                      207,
                                      33,
                                      33,
                                    ),
                                    tooltip: 'Delete task',
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                    ],
                  ),
          );
        },
      ),
    );
  }
}
