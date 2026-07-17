import '../core/parse.dart';

/// An enrolled known person, from GET /known. `sample` is a relative path like
/// `/known_photo/<name>` (may be null when there is no photo yet).
class KnownPerson {
  final String name;
  final int photos;
  final String? sample;

  const KnownPerson({required this.name, required this.photos, this.sample});

  factory KnownPerson.fromJson(Map<String, dynamic> j) => KnownPerson(
        name: asStr(j['name']),
        photos: asInt(j['photos'], asInt(j['count'])),
        sample: j['sample'] == null ? null : asStr(j['sample']),
      );
}
