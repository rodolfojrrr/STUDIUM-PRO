import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_routine_active/core/app_store.dart';
import 'package:my_routine_active/core/app_theme.dart';
import 'package:my_routine_active/core/backup_service.dart';
import 'package:my_routine_active/core/local_database.dart';
import 'package:my_routine_active/screens/quick_notes_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('nota salva, entra no backup e pode voltar da Lixeira',
      (tester) async {
    tester.view.physicalSize = const Size(1024, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final database = await LocalDatabase.createInMemoryForTesting();
    final store = AppStore(database: database);
    await store.initialize();

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
    await database.close();
  });
}
