import '../core/parse.dart';

/// One module row inside GET /status. `state` is ok | placeholder | unavailable
/// | off, which the UI colours accordingly.
class ModuleStatus {
  final String name;
  final String state;
  final String detail;

  const ModuleStatus({
    required this.name,
    required this.state,
    required this.detail,
  });

  factory ModuleStatus.fromJson(Map<String, dynamic> j) => ModuleStatus(
        name: asStr(j['name']),
        state: asStr(j['state'], 'off'),
        detail: asStr(j['detail']),
      );
}

/// The overall health snapshot from GET /status.
class AppStatus {
  final String app;
  final String mode;
  final String torchVersion;
  final String ttsEngine;
  final String ttsVoice;
  final bool wakewordRunning;
  final List<ModuleStatus> modules;

  const AppStatus({
    required this.app,
    required this.mode,
    required this.torchVersion,
    required this.ttsEngine,
    required this.ttsVoice,
    required this.wakewordRunning,
    required this.modules,
  });

  factory AppStatus.fromJson(Map<String, dynamic> j) {
    final tts = asMap(j['tts']);
    return AppStatus(
      app: asStr(j['app'], 'AccessAI'),
      mode: asStr(j['mode'], 'both'),
      torchVersion: asStr(j['torch_version']),
      ttsEngine: asStr(tts['engine'], 'none'),
      ttsVoice: asStr(tts['voice'], 'none'),
      wakewordRunning: asBool(j['wakeword_running']),
      modules: asMapList(j['modules']).map(ModuleStatus.fromJson).toList(),
    );
  }
}

/// A selectable voice from GET /voices.
class VoiceOption {
  final String id;
  final String label;
  final bool available;

  const VoiceOption(
      {required this.id, required this.label, required this.available});

  factory VoiceOption.fromJson(Map<String, dynamic> j) {
    // The backend voice entries vary; accept id/name/label + available flags.
    final id = asStr(j['id'], asStr(j['voice']));
    return VoiceOption(
      id: id,
      label: asStr(j['label'], asStr(j['name'], id)),
      available: j.containsKey('available') ? asBool(j['available'], true) : true,
    );
  }
}
