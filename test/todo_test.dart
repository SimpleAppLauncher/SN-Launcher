import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sn_launcher/src/services/settings_store.dart';
import 'package:sn_launcher/src/services/todo_service.dart';
import 'package:sn_launcher/src/theme/ambient_palette.dart';
import 'package:sn_launcher/src/theme/nest_metrics.dart';
import 'package:sn_launcher/src/theme/nest_type.dart';
import 'package:sn_launcher/src/widgets/todo_card.dart';

/// A settings store backed by a real file, so persistence is genuinely
/// exercised rather than mocked away.
SettingsStore _fileStore(String path) => SettingsStore(fallbackPath: path);

void main() {
  // The settings store talks to a MethodChannel. Without a binding, touching
  // one throws a null-check error that the store does not catch, and the
  // file fallback is never reached.
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sn_todo_test');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('TodoService', () {
    test('starts empty', () async {
      final s = TodoService(_fileStore('${tmp.path}/a.json'));
      await s.load();
      expect(s.items, isEmpty);
      expect(s.openCount, 0);
    });

    test('adds, and ignores blank text', () async {
      final s = TodoService(_fileStore('${tmp.path}/b.json'));
      await s.load();
      await s.add('Buy milk');
      expect(s.items.map((i) => i.text), ['Buy milk']);
      expect(s.openCount, 1);

      await s.add('   ');
      await s.add('');
      expect(s.items.length, 1, reason: 'blank items must not be added');
    });

    test('trims what it stores', () async {
      final s = TodoService(_fileStore('${tmp.path}/c.json'));
      await s.load();
      await s.add('  Buy milk  ');
      expect(s.items.single.text, 'Buy milk');
    });

    test('toggles done, and sorts finished items to the bottom', () async {
      final s = TodoService(_fileStore('${tmp.path}/d.json'));
      await s.load();
      await s.add('First');
      await s.add('Second');
      await s.add('Third');

      await s.toggle(s.items.first.id);
      final texts = s.items.map((i) => i.text).toList();
      expect(texts, ['Second', 'Third', 'First'],
          reason: 'outstanding items first, finished last');
      expect(s.openCount, 2);
    });

    test('removes', () async {
      final s = TodoService(_fileStore('${tmp.path}/e.json'));
      await s.load();
      await s.add('Gone');
      await s.remove(s.items.single.id);
      expect(s.items, isEmpty);
    });

    test('toggling and removing an unknown id does nothing', () async {
      final s = TodoService(_fileStore('${tmp.path}/f.json'));
      await s.load();
      await s.add('Keep');
      await s.toggle('nope');
      await s.remove('nope');
      expect(s.items.length, 1);
      expect(s.items.single.done, isFalse);
    });

    test('survives a restart', () async {
      final path = '${tmp.path}/g.json';
      final first = TodoService(_fileStore(path));
      await first.load();
      await first.add('Persisted');
      await first.toggle(first.items.single.id);

      final second = TodoService(_fileStore(path));
      await second.load();
      expect(second.items.single.text, 'Persisted');
      expect(second.items.single.done, isTrue);
    });

    test('a corrupt store fails closed rather than throwing', () async {
      // The stored string can be hand-edited, or written by a build with a
      // different shape. One bad value must cost the list, not the app.
      final path = '${tmp.path}/h.json';
      File(path).writeAsStringSync(jsonEncode({'todo': 'not json at all'}));

      final s = TodoService(_fileStore(path));
      await s.load();
      expect(s.items, isEmpty);
    });

    test('a list containing one bad entry keeps the good ones', () async {
      final path = '${tmp.path}/i.json';
      File(path).writeAsStringSync(jsonEncode({
        'todo': jsonEncode([
          {'id': '1', 'text': 'Good', 'done': false},
          {'nonsense': true},
          {'id': '2', 'text': '', 'done': false},
          {'id': '3', 'text': 'Also good', 'done': true},
        ]),
      }));

      final s = TodoService(_fileStore(path));
      await s.load();
      expect(s.items.map((i) => i.text), ['Good', 'Also good']);
    });

    test('a non-list JSON document fails closed', () async {
      final path = '${tmp.path}/j.json';
      File(path).writeAsStringSync(jsonEncode({'todo': '"just a string"'}));
      final s = TodoService(_fileStore(path));
      await s.load();
      expect(s.items, isEmpty);
    });
  });

  group('the card', () {
    Future<TodoService> pump(WidgetTester tester, String path) async {
      final service = TodoService(_fileStore(path));
      // Real file IO does not complete inside a widget test's fake-async
      // zone, so anything that touches the disk has to go through runAsync.
      await tester.runAsync(() => service.load());
      final m = NestMetrics.forSize(const Size(1280, 800));
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'GoogleSans'),
          home: Material(
            color: const Color(0xFF000000),
            child: Scaffold(
              body: SizedBox(
                width: 400,
                height: 600,
                child: TodoCard(
                  service: service,
                  metrics: m,
                  palette: AmbientPalette.of(NestTheme.day),
                  type: NestType(m),
                ),
              ),
            ),
          ),
        ),
      );
      return service;
    }

    testWidgets('says so when there is nothing on it', (tester) async {
      await pump(tester, '${tmp.path}/k.json');
      expect(find.text('Nothing to do'), findsOneWidget);
      expect(find.text('Add an item'), findsOneWidget);
    });

    testWidgets('adds what you type', (tester) async {
      final service = await pump(tester, '${tmp.path}/l.json');
      await tester.enterText(find.byType(TextField), 'Water the plants');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Water the plants'), findsOneWidget);
      expect(service.items.single.text, 'Water the plants');
      expect(
        find.byKey(const ValueKey('todo-input')),
        findsOneWidget,
      );
    });

    testWidgets('the field clears after adding', (tester) async {
      await pump(tester, '${tmp.path}/m.json');
      await tester.enterText(find.byType(TextField), 'Something');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(const Duration(milliseconds: 50));
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller?.text, isEmpty);
    });

    testWidgets('ticking an item marks it done and strikes it through',
        (tester) async {
      final service = await pump(tester, '${tmp.path}/n.json');
      await tester.enterText(find.byType(TextField), 'Tick me');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(const Duration(milliseconds: 50));
      expect(service.items.single.done, isFalse);

      final id = service.items.single.id;
      await tester.tap(find.byKey(ValueKey('todo-tick-$id')));
      await tester.pump(const Duration(milliseconds: 50));

      expect(service.items.single.done, isTrue);
      expect(find.text('Tick me'), findsOneWidget);
      expect(service.openCount, 0);
    });

    testWidgets('deleting an item removes it', (tester) async {
      final service = await pump(tester, '${tmp.path}/p.json');
      await tester.enterText(find.byType(TextField), 'Delete me');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(const Duration(milliseconds: 50));

      final id = service.items.single.id;
      await tester.tap(find.byKey(ValueKey('todo-delete-$id')));
      await tester.pump(const Duration(milliseconds: 50));

      expect(service.items, isEmpty);
      expect(find.text('Delete me'), findsNothing);
      expect(find.text('Nothing to do'), findsOneWidget);
    });

    testWidgets('the count of outstanding items is shown', (tester) async {
      final service = await pump(tester, '${tmp.path}/o.json');
      await tester.runAsync(() => service.add('One'));
      await tester.runAsync(() => service.add('Two'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('2 left'), findsOneWidget);
    });
  });
}
