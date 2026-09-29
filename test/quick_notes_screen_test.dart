import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_routine_active/core/app_store.dart';
import 'package:my_routine_active/core/app_theme.dart';
import 'package:my_routine_active/core/backup_service.dart';
import 'package:my_routine_active/core/local_database.dart';
import 'package:my_routine_active/core/sync_entity.dart';
import 'package:my_routine_active/screens/quick_notes_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('bloco de notas salva e recupera uma nota pela Lixeira',
      (tester) async {
    tester.view.physicalSize = const Size(1024, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = _NotesStore();

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: QuickNotesScreen(store: store)),
    ));
    await tester.tap(find.text('Nova nota'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('quick-note-title')), 'Redes');
    await tester.enterText(find.byKey(const Key('quick-note-body')),
        'Revisar máscaras de sub-rede.');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();

    final note = store.records(EntityTypes.quickNote).single;
    expect(note.payload['title'], 'Redes');
    expect(note.payload['body'], 'Revisar máscaras de sub-rede.');
    final backup = BackupService.decodeBundle(await store.exportBundle());
    expect(backup.entities.single.id, note.id);
    expect(backup.entities.single.payload['body'], note.payload['body']);

    await tester.tap(find.byTooltip('Excluir nota'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mover para a Lixeira'));
    await tester.pumpAndSettle();
    expect(store.records(EntityTypes.quickNote), isEmpty);
    expect(store.deletedRecords().single.id, note.id);
    await store.restore(note.id);
    expect(store.records(EntityTypes.quickNote).single.payload['body'],
        'Revisar máscaras de sub-rede.');

    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });

  test('nota é persistida no banco existente e incluída no backup .mra',
      () async {
    final database = await LocalDatabase.createInMemoryForTesting();
    final store = AppStore(database: database);
    await store.initialize();
    final note = await store.save(EntityTypes.quickNote, <String, dynamic>{
      'title': 'Redes',
      'body': 'Revisar máscaras de sub-rede.',
      'pinned': false,
    });
    final backup = BackupService.decodeBundle(await store.exportBundle());
    expect(backup.entities.single.id, note.id);
    expect(backup.entities.single.payload['body'], note.payload['body']);
    await store.remove(note.id);
    expect(store.deletedRecords().single.id, note.id);
    await store.restore(note.id);
    expect(store.records(EntityTypes.quickNote).single.payload['body'],
        'Revisar máscaras de sub-rede.');
    store.dispose();
    await database.close();
  });
}

class _NotesStore extends AppStore {
  final List<SyncEntity> _items = <SyncEntity>[];

  @override
  List<SyncEntity> records(String type) => _items
      .where((item) => item.type == type && !item.isDeleted)
      .toList(growable: false);

  @override
  SyncEntity? byId(String id) {
    for (final item in _items) {
      if (item.id == id && !item.isDeleted) return item;
    }
    return null;
  }

  @override
  List<SyncEntity> deletedRecords() => _items
      .where((item) => item.isDeleted)
      .toList(growable: false);

  @override
  Future<SyncEntity> save(
    String type,
    Map<String, dynamic> payload, {
    String? id,
  }) async {
    final previous = id == null ? null : byId(id);
    final note = SyncEntity(
      id: id ?? 'note-1',
      type: type,
      payload: Map<String, dynamic>.from(payload),
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      deviceId: 'test',
      revision: (previous?.revision ?? 0) + 1,
    );
    _items.removeWhere((item) => item.id == note.id);
    _items.add(note);
    notifyListeners();
    return note;
  }

  @override
  Future<void> remove(String id) async {
    final previous = byId(id);
    if (previous == null) return;
    _items.remove(previous);
    _items.add(SyncEntity(
      id: previous.id,
      type: previous.type,
      payload: previous.payload,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      deletedAtMs: DateTime.now().millisecondsSinceEpoch,
      deviceId: 'test',
      revision: previous.revision + 1,
    ));
    notifyListeners();
  }

  @override
  Future<void> restore(String id) async {
    final previous = deletedRecords().singleWhere((item) => item.id == id);
    await save(previous.type, previous.payload, id: id);
  }

  @override
  Future<List<int>> exportBundle() async => BackupService.createBundle(
        entities: _items,
        deviceId: 'test',
      );
}
