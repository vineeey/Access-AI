import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/glass.dart';
import '../core/motion.dart';
import '../core/tokens.dart';
import '../services/api_service.dart';
import '../services/prefs_service.dart';
import '../state/providers.dart';
import '../widgets/doorbell_hero.dart';

/// First-run connection screen. The one thing the app can't guess is where the
/// AccessAI server lives, so we ask for it up front, test it, and only then
/// enter the app. The user can also continue without a successful test (e.g. to
/// configure it later) — nothing here gates functionality permanently.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  late final TextEditingController _url;
  bool _connecting = false;
  String? _error;
  bool _testedButFailed = false;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: PrefsService.defaultBaseUrl);
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final url = PrefsService.normalizeUrl(_url.text.trim());
    if (url.isEmpty) {
      setState(() => _error = 'Enter the server address');
      return;
    }
    setState(() {
      _connecting = true;
      _error = null;
    });
    final probe = ApiService(url);
    try {
      final status = await probe.status();
      // Success — persist (flips isConfigured) so the root swaps to the app.
      await ref.read(baseUrlProvider.notifier).set(url);
      ref.read(modeProvider.notifier).adopt(status.mode);
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _testedButFailed = true;
      });
    } finally {
      probe.close();
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _continueAnyway() async {
    final url = PrefsService.normalizeUrl(_url.text.trim());
    await ref.read(baseUrlProvider.notifier).set(url);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: GradientMesh(animate: !context.reduceMotion)),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(T.s24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Entrance(
                        index: 0,
                        child: Center(
                          child: AuroraRing(
                            size: 200,
                            thickness: 4,
                            active: true,
                            child: const DoorbellHero(size: 150),
                          ),
                        ),
                      ),
                      const SizedBox(height: T.s20),
                      Entrance(
                        index: 1,
                        child: Text('AccessAI',
                            textAlign: TextAlign.center,
                            style: text.displaySmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1.0)),
                      ),
                      const SizedBox(height: T.s8),
                      Entrance(
                        index: 2,
                        child: Text(
                          'Your accessible eyes and ears at the door.',
                          textAlign: TextAlign.center,
                          style: text.titleMedium?.copyWith(color: T.muted),
                        ),
                      ),
                      const SizedBox(height: T.s32),
                      Entrance(
                        index: 3,
                        child: GlassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Connect to your server',
                                style: text.titleMedium),
                            const SizedBox(height: T.s8),
                            Text(
                              'Enter the address shown when you start the '
                              'AccessAI server (its LAN IP and port). Your phone '
                              'and computer must be on the same Wi‑Fi.',
                              style: text.bodySmall,
                            ),
                            const SizedBox(height: T.s16),
                            TextField(
                              controller: _url,
                              keyboardType: TextInputType.url,
                              autocorrect: false,
                              onSubmitted: (_) => _connect(),
                              decoration: const InputDecoration(
                                labelText: 'Server address',
                                prefixIcon: Icon(Icons.dns_outlined),
                              ),
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: T.s12),
                              Row(
                                children: [
                                  const Icon(Icons.error_outline,
                                      color: T.danger, size: 20),
                                  const SizedBox(width: T.s8),
                                  Expanded(
                                      child: Text(_error!,
                                          style: text.bodySmall?.copyWith(
                                              color: T.danger))),
                                ],
                              ),
                            ],
                            const SizedBox(height: T.s16),
                            SizedBox(
                              height: T.minTouch,
                              child: FilledButton.icon(
                                onPressed: _connecting ? null : _connect,
                                icon: _connecting
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2))
                                    : const Icon(Icons.wifi_tethering),
                                label: Text(
                                    _connecting ? 'Connecting…' : 'Connect'),
                              ),
                            ),
                            if (_testedButFailed) ...[
                              const SizedBox(height: T.s8),
                              TextButton(
                                onPressed: _continueAnyway,
                                child: const Text('Continue anyway'),
                              ),
                            ],
                          ],
                        ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
