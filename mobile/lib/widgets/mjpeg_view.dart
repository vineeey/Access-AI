import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

/// A small, self-contained MJPEG viewer.
///
/// Connects to a `multipart/x-mixed-replace` (or plainly concatenated-JPEG)
/// stream — e.g. AccessAI's `GET /video` — and renders each frame. This
/// replaces the unmaintained `flutter_mjpeg` package, whose two-year-old release
/// pinned `http < 1.0` and blocked a modern `google_fonts`. We reuse `dio`
/// (already a dependency) to read the byte stream and pull out frames by
/// scanning for the JPEG start (`FF D8`) and end (`FF D9`) markers, which is
/// robust to boundary-format quirks across camera servers.
///
/// Reconnect by giving the widget a fresh [key]: the old state is disposed, the
/// request is cancelled, and a new connection opens.
class MjpegView extends StatefulWidget {
  const MjpegView({
    super.key,
    required this.stream,
    this.fit = BoxFit.contain,
    this.timeout = const Duration(seconds: 8),
    this.loadingBuilder,
    this.errorBuilder,
  });

  /// Absolute URL of the MJPEG stream.
  final String stream;

  /// How each frame is fitted into the available space.
  final BoxFit fit;

  /// How long to wait for the connection and the first frame before erroring.
  final Duration timeout;

  /// Shown until the first frame arrives.
  final WidgetBuilder? loadingBuilder;

  /// Shown when the stream fails to connect or drops.
  final Widget Function(BuildContext context, Object error)? errorBuilder;

  @override
  State<MjpegView> createState() => _MjpegViewState();
}

class _MjpegViewState extends State<MjpegView> {
  // JPEG framing markers.
  static const int _ff = 0xFF;
  static const int _soi = 0xD8; // start of image
  static const int _eoi = 0xD9; // end of image
  // Guard against a non-JPEG stream growing the buffer without bound.
  static const int _maxBuffer = 8 * 1024 * 1024;

  final Dio _dio = Dio();
  final List<int> _buffer = <int>[];
  CancelToken? _cancel;
  StreamSubscription<Uint8List>? _sub;
  Timer? _timeoutTimer;

  Uint8List? _frame;
  Object? _error;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    _cancel = CancelToken();
    _timeoutTimer = Timer(widget.timeout, () {
      if (_frame == null) _fail('Timed out waiting for the camera');
    });
    try {
      final response = await _dio.get<ResponseBody>(
        widget.stream,
        options: Options(
          responseType: ResponseType.stream,
          connectTimeout: widget.timeout,
          // A live stream never idles to "complete", so no receive timeout.
          receiveTimeout: Duration.zero,
          headers: const {'Accept': 'multipart/x-mixed-replace, image/jpeg'},
        ),
        cancelToken: _cancel,
      );
      final body = response.data;
      if (body == null) {
        _fail('Empty camera response');
        return;
      }
      _sub = body.stream.listen(
        _onBytes,
        onError: _fail,
        onDone: () {
          // Stream closed by the server; only surface if we never rendered.
          if (_frame == null) _fail('Camera stream closed');
        },
        cancelOnError: true,
      );
    } catch (e) {
      _fail(e);
    }
  }

  void _onBytes(List<int> chunk) {
    if (_disposed) return;
    _buffer.addAll(chunk);
    Uint8List? latest;
    // Extract every complete JPEG currently buffered; render only the newest.
    while (true) {
      final start = _indexOf2(_buffer, _ff, _soi, 0);
      if (start < 0) {
        // No frame start yet — don't let junk accumulate forever.
        if (_buffer.length > _maxBuffer) _buffer.clear();
        break;
      }
      final end = _indexOf2(_buffer, _ff, _eoi, start + 2);
      if (end < 0) {
        // Frame still incomplete; drop anything before its start to stay small.
        if (start > 0) _buffer.removeRange(0, start);
        if (_buffer.length > _maxBuffer) _buffer.clear();
        break;
      }
      latest = Uint8List.fromList(_buffer.sublist(start, end + 2));
      _buffer.removeRange(0, end + 2);
    }
    if (latest != null && !_disposed) {
      _timeoutTimer?.cancel();
      setState(() {
        _frame = latest;
        _error = null;
      });
    }
  }

  /// Index of the two-byte sequence [b0, b1] at or after [from], else -1.
  int _indexOf2(List<int> data, int b0, int b1, int from) {
    for (var i = from; i < data.length - 1; i++) {
      if (data[i] == b0 && data[i + 1] == b1) return i;
    }
    return -1;
  }

  void _fail(Object error, [StackTrace? _]) {
    if (_disposed || !mounted) return;
    // A cancellation is our own teardown, not a stream failure.
    if (error is DioException && error.type == DioExceptionType.cancel) return;
    _timeoutTimer?.cancel();
    setState(() => _error = error);
  }

  @override
  void dispose() {
    _disposed = true;
    _timeoutTimer?.cancel();
    _sub?.cancel();
    _cancel?.cancel();
    _dio.close(force: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return widget.errorBuilder?.call(context, _error!) ??
          const Center(
            child: Icon(Icons.videocam_off, color: Colors.white70, size: 48),
          );
    }
    final frame = _frame;
    if (frame == null) {
      return widget.loadingBuilder?.call(context) ??
          const Center(child: CircularProgressIndicator());
    }
    return Image.memory(
      frame,
      fit: widget.fit,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: true,
      // A single corrupt frame shouldn't blank the whole view.
      errorBuilder: (_, _, _) => widget.loadingBuilder?.call(context) ??
          const SizedBox.shrink(),
    );
  }
}
