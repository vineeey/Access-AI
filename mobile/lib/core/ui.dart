import 'package:flutter/material.dart';

import 'glass.dart';

/// Show a floating snackbar. Errors are tinted with the theme error colour and
/// carry a longer timeout so they can be read. Safe to call after awaits — it
/// no-ops if the messenger is gone.
void showSnack(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final cs = Theme.of(context).colorScheme;
  messenger
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? cs.errorContainer : null,
      duration: Duration(seconds: error ? 5 : 3),
      showCloseIcon: true,
    ));
}

/// A consistent screen background: the ambient aurora mesh sits behind
/// everything. Defaults to the animated [GradientMesh]; pass [mesh] to
/// override (e.g. `SizedBox.shrink()` for a plain screen).
class MeshScaffoldBody extends StatelessWidget {
  const MeshScaffoldBody({super.key, required this.child, this.mesh});

  final Widget child;
  final Widget? mesh;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: mesh ?? const GradientMesh()),
        Positioned.fill(child: child),
      ],
    );
  }
}

const kMaxContentWidth = 640.0;

/// Centres content and caps its width on large screens (tablets/landscape).
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
        child: child,
      ),
    );
  }
}
