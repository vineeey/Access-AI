import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/glass.dart';
import '../core/tokens.dart';
import '../models/visitor_event.dart';
import 'person_tile.dart';

/// A rich card summarising one visitor event. Leads with the count line
/// ("3 people — 1 known, 2 unknown"), then per-person tiles, scene summary,
/// any speech, and hazards. Used on Home (latest) and History (list rows). The
/// full people list shows on [expanded]; the compact form caps to the first two.
class EventCard extends StatelessWidget {
  const EventCard({
    super.key,
    required this.event,
    this.onTap,
    this.heroTag,
    this.expanded = false,
  });

  final VisitorEvent event;
  final VoidCallback? onTap;
  final String? heroTag;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final people = event.people;
    final shown = expanded ? people : people.take(2).toList();
    final hiddenCount = people.length - shown.length;

    // State-coloured edge: spoof warnings outrank known-person green.
    final Color? borderTint = event.anySpoof
        ? T.danger
        : event.knownCount > 0
            ? T.seed
            : null;

    Widget card = GlassCard(
      onTap: onTap,
      borderTint: borderTint,
      padding: const EdgeInsets.all(T.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: count + time.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  event.countLine,
                  style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: T.s8),
              if (event.timestamp.isNotEmpty)
                Text(prettyTime(event.timestamp),
                    style: text.labelMedium
                        ?.copyWith(color: cs.onSurface.withValues(alpha: 0.6))),
            ],
          ),
          if (event.anySpoof)
            Padding(
              padding: const EdgeInsets.only(top: T.s8),
              child: _Banner(
                icon: Icons.warning_amber,
                color: T.danger,
                text: 'A face here may be a photo, not a live person.',
              ),
            ),
          const SizedBox(height: T.s12),

          if (people.isEmpty)
            Text(
              event.sceneSummary.isNotEmpty
                  ? event.sceneSummary
                  : 'Motion detected at the door.',
              style: text.bodyMedium,
            )
          else
            for (int i = 0; i < shown.length; i++) ...[
              if (i > 0) Divider(color: cs.onSurface.withValues(alpha: 0.08)),
              PersonTile(person: shown[i], reidSeen: event.reidSeenCount),
            ],

          if (hiddenCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: T.s8),
              child: Text('+ $hiddenCount more',
                  style: text.labelLarge?.copyWith(color: cs.primary)),
            ),

          if (event.hasSpeech) ...[
            const SizedBox(height: T.s12),
            _SpeechBlock(event: event),
          ],

          if (expanded && event.sceneSummary.isNotEmpty && people.isNotEmpty) ...[
            const SizedBox(height: T.s12),
            Text(event.sceneSummary,
                style: text.bodyMedium
                    ?.copyWith(color: cs.onSurface.withValues(alpha: 0.8))),
          ],

          if (event.carriedObjects.isNotEmpty) ...[
            const SizedBox(height: T.s12),
            Wrap(
              spacing: T.s8,
              runSpacing: T.s8,
              children: [
                for (final o in event.carriedObjects)
                  _Tag(o, Icons.shopping_bag_outlined, cs.primary),
              ],
            ),
          ],

          if (event.hazards.isNotEmpty && event.hazards != 'none') ...[
            const SizedBox(height: T.s12),
            _Banner(
                icon: Icons.report_problem,
                color: T.accent,
                text: 'Note: ${event.hazards}'),
          ],
        ],
      ),
    );

    if (heroTag != null) {
      card = Hero(tag: heroTag!, child: Material(type: MaterialType.transparency, child: card));
    }
    return card;
  }
}

class _SpeechBlock extends StatelessWidget {
  const _SpeechBlock({required this.event});
  final VisitorEvent event;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final original = event.speechTranscript.trim();
    final translated = event.translatedTranscript.trim();
    final showTranslated = translated.isNotEmpty && translated != original;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(T.s12),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(T.rSm),
        border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.record_voice_over, size: 16, color: cs.primary),
              const SizedBox(width: T.s8),
              Text('They said',
                  style: text.labelMedium?.copyWith(
                      color: cs.primary, fontWeight: FontWeight.w700)),
              if (event.languageDetected.isNotEmpty &&
                  event.languageDetected != 'en') ...[
                const SizedBox(width: T.s8),
                Text('(${event.languageDetected})',
                    style: text.labelSmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.6))),
              ],
            ],
          ),
          const SizedBox(height: T.s4),
          Text(showTranslated ? translated : original,
              style: text.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
          if (showTranslated && original.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('Original: $original',
                  style: text.bodySmall
                      ?.copyWith(color: cs.onSurface.withValues(alpha: 0.55))),
            ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: T.s12, vertical: T.s8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(T.rSm),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: T.s8),
          Expanded(
              child: Text(text,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: T.s12, vertical: T.s8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: T.s4),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}
