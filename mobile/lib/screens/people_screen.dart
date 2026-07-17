import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../core/glass.dart';
import '../core/motion.dart';
import '../core/tokens.dart';
import '../core/ui.dart';
import '../models/known_person.dart';
import '../services/api_service.dart';
import '../state/providers.dart';

/// People — the enrolled faces AccessAI recognises. A responsive grid of
/// thumbnails (`GET /known_photo/<name>`); tap-and-hold or the menu to delete;
/// "Add person" enrols from one or more gallery/camera photos via
/// POST /enroll_upload. Known people are never deleted by clearing history.
class PeopleScreen extends ConsumerWidget {
  const PeopleScreen({super.key});

  Future<void> _delete(
      BuildContext context, WidgetRef ref, KnownPerson p) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${p.name}?'),
        content: const Text('AccessAI will no longer recognise this person.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: T.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(apiProvider).deleteKnown(p.name);
      ref.invalidate(knownProvider);
      if (context.mounted) showSnack(context, 'Removed ${p.name}');
    } on ApiException catch (e) {
      if (context.mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: const _EnrollSheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final known = ref.watch(knownProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('People')),
      // Lifted above the floating glass nav pill.
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 88),
        child: FloatingActionButton.extended(
          onPressed: () => _add(context, ref),
          icon: const Icon(Icons.person_add_alt),
          label: const Text('Add person'),
        ),
      ),
      body: MeshScaffoldBody(
        child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(knownProvider);
              await ref.read(knownProvider.future);
            },
            child: switch (known) {
              AsyncData(:final value) when value.isEmpty => _empty(context),
              AsyncData(:final value) => _grid(context, ref, value),
              AsyncError(:final error) => _error(context, ref, '$error'),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
        ),
      ),
    );
  }

  Widget _grid(BuildContext context, WidgetRef ref, List<KnownPerson> people) {
    final api = ref.watch(apiProvider);
    return GridView.builder(
      // 120 bottom clears the floating glass nav pill + lifted FAB.
      padding: const EdgeInsets.fromLTRB(T.s16, T.s16, T.s16, 120),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        childAspectRatio: 0.82,
        crossAxisSpacing: T.s12,
        mainAxisSpacing: T.s12,
      ),
      itemCount: people.length,
      itemBuilder: (context, i) {
        final p = people[i];
        return Entrance(
          index: i.clamp(0, 8),
          child: _PersonCard(
            person: p,
            imageUrl: api.knownPhotoUrl(p.name),
            onDelete: () => _delete(context, ref, p),
          ),
        );
      },
    );
  }

  Widget _empty(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(T.s32, T.s32, T.s32, 120),
      children: [
        const SizedBox(height: 64),
        Entrance(
          child: GlassCard(
            padding: const EdgeInsets.all(T.s32),
            child: Column(
              children: [
                Container(
                  width: 88,
                  height: 88,
                  padding: const EdgeInsets.all(2.5),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: T.aurora,
                  ),
                  child: Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: T.bg2,
                    ),
                    child: Icon(Icons.groups_outlined,
                        size: 40,
                        color: cs.onSurface.withValues(alpha: 0.75)),
                  ),
                ),
                const SizedBox(height: T.s16),
                Text('No one enrolled yet',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: T.s8),
                Text('Tap "Add person" to teach AccessAI a face.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _error(BuildContext context, WidgetRef ref, String message) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(T.s32, T.s32, T.s32, 120),
      children: [
        const SizedBox(height: 64),
        Entrance(
          child: GlassCard(
            borderTint: T.danger,
            padding: const EdgeInsets.all(T.s32),
            child: Column(
              children: [
                const Icon(Icons.cloud_off, size: 56),
                const SizedBox(height: T.s16),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: T.s16),
                SizedBox(
                  height: T.minTouch,
                  child: FilledButton.icon(
                    onPressed: () => ref.invalidate(knownProvider),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({
    required this.person,
    required this.imageUrl,
    required this.onDelete,
  });

  final KnownPerson person;
  final String imageUrl;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      label: '${person.name}, ${person.photos} '
          '${person.photos == 1 ? 'photo' : 'photos'} enrolled',
      child: Container(
        // Aurora hairline frame around each portrait.
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(T.rMd),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              T.jarvis1.withValues(alpha: 0.45),
              Colors.white.withValues(alpha: 0.10),
              T.jarvis3.withValues(alpha: 0.45),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        padding: const EdgeInsets.all(1.4),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(T.rMd - 1.4),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(color: cs.surfaceContainerHighest),
              if (person.sample != null)
                Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => _placeholder(cs),
                )
              else
                _placeholder(cs),
              // Gradient scrim for legible name text.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black87],
                  ),
                ),
              ),
              Positioned(
                left: T.s12,
                right: T.s12,
                bottom: T.s12,
                child: Text(
                  person.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white, fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Positioned(
                top: 0,
                right: 0,
                child: IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, color: Colors.white),
                  tooltip: 'Remove ${person.name}',
                  style: IconButton.styleFrom(
                      backgroundColor: Colors.black38,
                      minimumSize: const Size(48, 48)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder(ColorScheme cs) => Center(
        child: Icon(Icons.person, size: 56, color: cs.onSurfaceVariant),
      );
}

/// Bottom-sheet flow: name + pick photos + enrol.
class _EnrollSheet extends ConsumerStatefulWidget {
  const _EnrollSheet();

  @override
  ConsumerState<_EnrollSheet> createState() => _EnrollSheetState();
}

class _EnrollSheetState extends ConsumerState<_EnrollSheet> {
  final _name = TextEditingController();
  final List<({String name, Uint8List bytes})> _picked = [];
  bool _busy = false;

  Future<void> _addFile(XFile x, int index) async {
    final bytes = await x.readAsBytes();
    final fname = x.name.isNotEmpty ? x.name : 'photo_$index.jpg';
    if (mounted) setState(() => _picked.add((name: fname, bytes: bytes)));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickGallery() async {
    try {
      final files = await ImagePicker().pickMultiImage();
      for (var i = 0; i < files.length; i++) {
        await _addFile(files[i], _picked.length + i);
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Could not open gallery: $e', error: true);
    }
  }

  Future<void> _pickCamera() async {
    try {
      final f = await ImagePicker().pickImage(source: ImageSource.camera);
      if (f != null) await _addFile(f, _picked.length);
    } catch (e) {
      if (mounted) showSnack(context, 'Could not open camera: $e', error: true);
    }
  }

  Future<void> _enroll() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showSnack(context, 'Enter a name first', error: true);
      return;
    }
    if (_picked.isEmpty) {
      showSnack(context, 'Add at least one photo', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final payload = [
        for (final p in _picked) (filename: p.name, bytes: p.bytes),
      ];
      final res =
          await ref.read(apiProvider).enrollUpload(name, payload);
      ref.invalidate(knownProvider);
      if (mounted) {
        Navigator.of(context).pop();
        final ok = res['ok'] == true || (res['message'] ?? '').toString().isNotEmpty;
        showSnack(
            context,
            ok
                ? 'Enrolled $name from ${_picked.length} '
                    '${_picked.length == 1 ? 'photo' : 'photos'}'
                : 'Enrolment finished');
      }
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(T.s20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Add a person', style: text.titleLarge),
          const SizedBox(height: T.s16),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'e.g. Priya',
            ),
          ),
          const SizedBox(height: T.s16),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _pickGallery,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Gallery'),
                  ),
                ),
              ),
              const SizedBox(width: T.s12),
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _pickCamera,
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Camera'),
                  ),
                ),
              ),
            ],
          ),
          if (_picked.isNotEmpty) ...[
            const SizedBox(height: T.s16),
            Text('${_picked.length} photo${_picked.length == 1 ? '' : 's'} selected',
                style: text.labelLarge),
            const SizedBox(height: T.s8),
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _picked.length,
                separatorBuilder: (_, _) => const SizedBox(width: T.s8),
                itemBuilder: (context, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(T.rSm),
                  child: Image.memory(
                    _picked[i].bytes,
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => Container(
                      width: 72,
                      height: 72,
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.image),
                    ),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: T.s20),
          SizedBox(
            width: double.infinity,
            height: T.minTouch,
            child: FilledButton.icon(
              onPressed: _busy ? null : _enroll,
              icon: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: Text(_busy ? 'Enrolling…' : 'Enroll'),
            ),
          ),
          const SizedBox(height: T.s8),
        ],
      ),
    );
  }
}
