import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:todolist_app/main.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('task due dates and reminders round-trip through JSON', () {
    final dueDate = DateTime(2026, 10, 12);
    final reminderAt = DateTime(2026, 10, 12, 9, 30);
    final task = TaskItem(
      title: 'Submit report',
      notificationId: 42,
      dueDate: dueDate,
      reminderAt: reminderAt,
    );
    final restored = TaskItem.fromJson(
      jsonDecode(jsonEncode(task.toJson())) as Map<String, dynamic>,
      fallbackNotificationId: 43,
    );

    expect(restored.dueDate, dueDate);
    expect(restored.reminderAt, reminderAt);
    expect(restored.notificationId, 42);
  });

  testWidgets('shows the empty state and adds a task', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MainApp());
    await tester.pumpAndSettle();

    expect(find.text('No tasks yet'), findsOneWidget);
    expect(find.text('Add your first task!'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Buy milk');
    await tester.tap(find.text('Add Task'));
    await tester.pump();

    expect(find.text('Buy milk'), findsOneWidget);
  });

  testWidgets('tasks persist when the app is restarted', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MainApp());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Buy milk');
    await tester.tap(find.text('Add Task'));
    await tester.pump();
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(const MainApp());
    await tester.pumpAndSettle();

    expect(find.text('Buy milk'), findsOneWidget);
    expect(tester.widget<Checkbox>(find.byType(Checkbox).first).value, isTrue);
  });

  testWidgets('edit task updates the task and saves the new title', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MainApp());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Old title');
    await tester.tap(find.text('Add Task'));
    await tester.pump();

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Task'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'Updated title');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Old title'), findsNothing);
    expect(find.text('Updated title'), findsOneWidget);
    final preferences = await SharedPreferences.getInstance();
    final savedTasks =
        jsonDecode(preferences.getString('tasks')!) as List<dynamic>;
    final savedTask = savedTasks.single as Map<String, dynamic>;
    expect(savedTask['title'], 'Updated title');
    expect(savedTask['isCompleted'], isFalse);
    expect(savedTask['notificationId'], isA<int>());
    expect(savedTask['dueDate'], isNull);
    expect(savedTask['reminderAt'], isNull);
  });

  testWidgets('loads and migrates tasks saved before due dates were added', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'tasks': '[{"title":"Legacy task","isCompleted":false}]',
    });

    await tester.pumpWidget(const MainApp());
    await tester.pumpAndSettle();

    expect(find.text('Legacy task'), findsOneWidget);
    final preferences = await SharedPreferences.getInstance();
    final savedTasks =
        jsonDecode(preferences.getString('tasks')!) as List<dynamic>;
    final savedTask = savedTasks.single as Map<String, dynamic>;
    expect(savedTask['notificationId'], isA<int>());
    expect(savedTask['dueDate'], isNull);
    expect(savedTask['reminderAt'], isNull);
  });

  testWidgets('clear completed removes checked tasks', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'tasks':
          '[{"title":"Learn Flutter","isCompleted":true},'
          '{"title":"Practice Python","isCompleted":false}]',
    });
    await tester.pumpWidget(const MainApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Clear completed'));
    await tester.pump();

    expect(find.text('Learn Flutter'), findsNothing);
    expect(find.text('Practice Python'), findsOneWidget);
  });
}
