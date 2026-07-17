import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/motion.dart';
import '../core/tokens.dart';
import '../core/ui.dart';
import '../models/visitor_event.dart';
import '../services/api_service.dart';
import '../state/providers.dart';
import '../widgets/event_card.dart';

/// Full detail for one visitor event, reached from History via a shared-element
/// hero transition. Shows the door snapshot (if one was saved), the full
/// multi-person breakdown, a read-aloud action, and delete.
class EventDetailScreen extends ConsumerStatefulWidget {
  const EventDetailScreen({super.key, required this.event, this.heroTag});

  final VisitorEvent event;
  final String? heroTag;

  @override
  ConsumerState<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends ConsumerState<EventDetailScreen> {
  bool _deleting = false;

  Future<void> _speak() async {
    final e = widget.event;
    final text = e.announcementText.trim().isNotEmpty
        ? e.announcementText
        : '${e.countLine}. ${e.sceneSummary}';
    await ref.read(audioProvider).speak(text, ref.read(apiProvider));
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this visit?'),
        content: const Text(
            'This removes the event and its saved snapshot. It cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: T.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _deleting = true);
    try {
      await ref.read(apiProvider).deleteEvent(widget.event.eventId);
      ref.invalidate(historyProvider);
      if (mounted) {
        showSnack(context, 'Visit deleted');
        Navigator.of(context).pop();
      }
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    final api = ref.watch(apiProvider);
    final tag = widget.heroTag;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(prettyTime(e.timestamp)),
        actions: [
          IconButton(
            onPressed: _speak,
            icon: const Icon(Icons.volume_up),
            tooltip: 'Read aloud',
          ),
          IconButton(
            onPressed: _deleting ? null : _delete,
            icon: _deleting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.delete_outline),
            tooltip: 'Delete visit',
          ),
        ],
      ),
      body: MeshScaffoldBody(
        child: SafeArea(
          child: ContentWidth(
            child: ListView(
              padding: const EdgeInsets.all(T.s16),
              children: [
                if (e.eventId.isNotEmpty)
                  Entrance(
                    index: 0,
                    child: Container(
                      // Specular hairline frame around the snapshot.
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(T.rLg),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withValues(alpha: 0.22),
                            Colors.white.withValues(alpha: 0.04),
                            T.jarvis2.withValues(alpha: 0.16),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.45),
                            blurRadius: 36,
                            offset: const Offset(0, 14),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(1.2),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(T.rLg - 1.2),
                        child: AspectRatio(
                          aspectRatio: 4 / 3,
                          child: Image.network(
                            api.snapshotUrl(e.eventId),
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            errorBuilder: (_, _, _) => Container(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              child: const Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.image_not_supported_outlined,
                                        size: 40),
                                    SizedBox(height: T.s8),
                                    Text('No snapshot saved for this visit'),
                                  ],
                                ),
                              ),
                            ),
                            loadingBuilder: (context, child, progress) =>
                                progress == null
                                    ? child
                                    : const Center(
                                        child: CircularProgressIndicator()),
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: T.s16),
                Entrance(
                  index: 1,
                  child: EventCard(
                    event: e,
                    heroTag: tag,
                    expanded: true,
                  ),
                ),
                const SizedBox(height: T.s24),
                Entrance(
                  index: 2,
                  child: SizedBox(
                    height: T.minTouch,
                    child: FilledButton.icon(
                      onPressed: _speak,
                      icon: const Icon(Icons.volume_up),
                      label: const Text('Read this visit aloud'),
                    ),
                  ),
                ),
                const SizedBox(height: T.s24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
