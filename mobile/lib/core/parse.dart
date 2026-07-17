/// Tolerant JSON coercion helpers. The backend is trusted but fields may be
/// missing, null, or a different numeric type than expected across phases — the
/// app must NEVER crash on a parse. Everything degrades to a sane default.
library;

String asStr(dynamic v, [String fallback = '']) {
  if (v == null) return fallback;
  if (v is String) return v;
  return v.toString();
}

int asInt(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is double) return v.round();
  if (v is bool) return v ? 1 : 0;
  if (v is String) return int.tryParse(v) ?? double.tryParse(v)?.round() ?? fallback;
  return fallback;
}

int? asIntOrNull(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) return v.round();
  if (v is String) return int.tryParse(v) ?? double.tryParse(v)?.round();
  return null;
}

double asDouble(dynamic v, [double fallback = 0]) {
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

bool asBool(dynamic v, [bool fallback = false]) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.toLowerCase().trim();
    return s == 'true' || s == '1' || s == 'yes';
  }
  return fallback;
}

List<Map<String, dynamic>> asMapList(dynamic v) {
  if (v is List) {
    return v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }
  return const [];
}

List<String> asStrList(dynamic v) {
  if (v is List) return v.map((e) => asStr(e)).where((s) => s.isNotEmpty).toList();
  return const [];
}

Map<String, dynamic> asMap(dynamic v) {
  if (v is Map) return v.cast<String, dynamic>();
  return <String, dynamic>{};
}
