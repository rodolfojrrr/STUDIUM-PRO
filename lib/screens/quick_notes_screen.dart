import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_store.dart';
import '../core/app_theme.dart';
import '../core/sync_entity.dart';

/// Fast notes are regular synchronized entities. No database migration is needed.
class QuickNotesScreen extends StatefulWidget {
  const QuickNotesScreen({required this.store, super.key});

  final AppStore store;

  @override
  State<QuickNotesScreen> createState() => _QuickNotesScreenState();
}

class _QuickNotesScreenState extends State<QuickNotesScreen>
    with WidgetsBindingObserver {
  final TextEditingController _search = TextEditingController();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();
  String? _selectedId;
  Timer? _debounce;
  Future<void>? _saveInFlight;
  bool _loading = false;
  bool _busy = false;
  bool _dirty = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _title.addListener(_changed);
    _body.addListener(_changed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    if (_dirty) unawaited(_flush());
    _title.removeListener(_changed);
    _body.removeListener(_changed);
    _search.dispose();
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(_flush());
    }
  }

  void _changed() {
    if (_loading || _selectedId == null) return;
    _dirty = true;
    setState(() => _status = 'Salvando…');
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 650), () {
      unawaited(_flush());
    });
  }

  Future<void> _flush() async {
    _debounce?.cancel();
    if (!_dirty || _selectedId == null) {
      final pending = _saveInFlight;
      if (pending != null) await pending;
      return;
    }
    final id = _selectedId!;
    final title = _title.text.trim();
    final body = _body.text;
    _dirty = false;
    final previous = _saveInFlight;
    final saving = () async {
      if (previous != null) await previous;
      final note = widget.store.byId(id);
      if (note == null) return;
      await widget.store.save(
        EntityTypes.quickNote,
        <String, dynamic>{
          ...note.payload,
          'title': title.isEmpty ? 'Sem título' : title,
          'body': body,
          'editedAt': DateTime.now().toIso8601String(),
        },
        id: id,
      );
    }();
    _saveInFlight = saving.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    try {
      await saving;
      if (mounted && _selectedId == id && !_dirty) {
        setState(() => _status = 'Salvo neste aparelho');
      }
    } catch (_) {
      _dirty = true;
      if (mounted) setState(() => _status = 'Falha ao salvar. Tente novamente.');
    }
  }

  void _load(SyncEntity? note) {
    _loading = true;
    _selectedId = note?.id;
    _title.text = note?.payload['title'] as String? ?? '';
    _body.text = note?.payload['body'] as String? ?? '';
    _loading = false;
    _status = '';
    setState(() {});
  }

  Future<void> _select(SyncEntity note) async {
    if (_busy || note.id == _selectedId) return;
    await _flush();
    if (!mounted || _dirty) return;
    _load(note);
  }

  Future<void> _create() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _flush();
      if (_dirty) return;
      final now = DateTime.now().toIso8601String();
      final note = await widget.store.save(EntityTypes.quickNote, <String, dynamic>{
        'title': 'Nova nota',
        'body': '',
        'pinned': false,
        'createdAt': now,
        'editedAt': now,
      });
      if (mounted) _load(note);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _togglePin() async {
    final id = _selectedId;
    if (id == null || _busy) return;
    setState(() => _busy = true);
    try {
      await _flush();
      if (_dirty) return;
      final note = widget.store.byId(id);
      if (note != null) {
        await widget.store.save(
          EntityTypes.quickNote,
          <String, dynamic>{
            ...note.payload,
            'pinned': note.payload['pinned'] != true,
          },
          id: id,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final id = _selectedId;
    if (id == null || _busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Mover nota para a Lixeira?'),
        content: const Text('Você poderá restaurá-la pela Lixeira do aplicativo.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Mover para a Lixeira'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _flush();
      if (_dirty) return;
      await widget.store.remove(id);
      if (mounted) _load(null);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<SyncEntity> _notes() {
    final query = _search.text.trim().toLowerCase();
    final notes = widget.store.records(EntityTypes.quickNote).where((note) {
      if (query.isEmpty) return true;
      final title = note.payload['title'] as String? ?? '';
      final body = note.payload['body'] as String? ?? '';
      return title.toLowerCase().contains(query) ||
          body.toLowerCase().contains(query);
    }).toList();
    notes.sort((a, b) {
      final pinned = (b.payload['pinned'] == true ? 1 : 0) -
          (a.payload['pinned'] == true ? 1 : 0);
      return pinned != 0 ? pinned : b.updatedAtMs.compareTo(a.updatedAtMs);
    });
    return notes;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) => Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
            child: Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    'Suas notas',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _busy ? null : _create,
                  icon: const Icon(Icons.note_add_outlined),
                  label: const Text('Nova nota'),
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final desktop = constraints.maxWidth >= 740;
                final list = _noteList();
                final editor = _selectedId == null
                    ? _emptyState()
                    : _noteEditor(!desktop);
                return desktop
                    ? Row(children: <Widget>[
                        SizedBox(width: 320, child: list),
                        const VerticalDivider(width: 1),
                        Expanded(child: editor),
                      ])
                    : _selectedId == null ? list : editor;
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _noteList() {
    final notes = _notes();
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            key: const Key('quick-notes-search'),
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Buscar nas notas',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
        if (notes.isEmpty)
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _search.text.isEmpty
                      ? 'Anote ideias, dúvidas e lembretes de estudo em um só lugar.'
                      : 'Nenhuma nota encontrada.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textMuted),
                ),
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              itemCount: notes.length,
              itemBuilder: (context, index) {
                final note = notes[index];
                return ListTile(
                  key: ValueKey<String>('quick-note-${note.id}'),
                  selected: note.id == _selectedId,
                  leading: Icon(
                    note.payload['pinned'] == true
                        ? Icons.push_pin
                        : Icons.sticky_note_2_outlined,
                    color: note.payload['pinned'] == true
                        ? AppColors.primary
                        : AppColors.textMuted,
                  ),
                  title: Text(
                    note.payload['title'] as String? ?? 'Sem título',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    note.payload['body'] as String? ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _select(note),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _emptyState() => Center(
        child: FilledButton.icon(
          onPressed: _busy ? null : _create,
          icon: const Icon(Icons.note_add_outlined),
          label: const Text('Criar primeira nota'),
        ),
      );

  Widget _noteEditor(bool mobile) {
    final note = widget.store.byId(_selectedId!);
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          child: Row(
            children: <Widget>[
              if (mobile)
                IconButton(
                  tooltip: 'Voltar para a lista',
                  onPressed: () async {
                    await _flush();
                    if (mounted && !_dirty) _load(null);
                  },
                  icon: const Icon(Icons.arrow_back),
                ),
              Expanded(
                child: Text(_status.isEmpty ? 'Salvamento automático' : _status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ),
              IconButton(
                tooltip: note?.payload['pinned'] == true
                    ? 'Desafixar nota'
                    : 'Fixar nota',
                onPressed: _busy ? null : _togglePin,
                icon: Icon(note?.payload['pinned'] == true
                    ? Icons.push_pin : Icons.push_pin_outlined),
              ),
              IconButton(
                tooltip: 'Excluir nota',
                onPressed: _busy ? null : _delete,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            constraints: const BoxConstraints(maxWidth: 920),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const <BoxShadow>[
                BoxShadow(color: Color(0x33000000), blurRadius: 22),
              ],
            ),
            child: Padding(
              padding: EdgeInsets.all(mobile ? 20 : 38),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  TextField(
                    key: const Key('quick-note-title'),
                    controller: _title,
                    maxLines: 1,
                    style: const TextStyle(
                      color: Color(0xFF202B3A), fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Título',
                      hintStyle: TextStyle(color: Color(0xFF738094)),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  ),
                  const Divider(color: Color(0xFFD5DDE8)),
                  Expanded(
                    child: TextField(
                      key: const Key('quick-note-body'),
                      controller: _body,
                      expands: true,
                      maxLines: null,
                      minLines: null,
                      textAlignVertical: TextAlignVertical.top,
                      style: const TextStyle(
                        color: Color(0xFF202B3A), fontSize: 16, height: 1.55,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Escreva sua nota…',
                        hintStyle: TextStyle(color: Color(0xFF738094)),
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
