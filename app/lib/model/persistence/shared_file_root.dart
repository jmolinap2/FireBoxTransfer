enum SharedFileRootType {
  localPath,
  androidSaf,
}

/// A local directory explicitly exposed to trusted FireBoxTransfer devices.
///
/// [locator] is private implementation data: an absolute path on desktop or
/// an opaque SAF tree URI on Android. It must never be returned by the remote
/// API; peers address entries by the public [id] and relative paths only.
class SharedFileRoot {
  final String id;
  final String name;
  final SharedFileRootType type;
  final String locator;
  final bool readOnly;

  const SharedFileRoot({
    required this.id,
    required this.name,
    required this.type,
    required this.locator,
    required this.readOnly,
  });

  factory SharedFileRoot.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final typeName = json['type'];
    final locator = json['locator'];
    final readOnly = json['readOnly'];

    if (id is! String || !_isSafeText(id, maxLength: 256)) {
      throw const FormatException('Invalid shared root id');
    }
    if (name is! String || !_isSafeText(name, maxLength: 1024)) {
      throw const FormatException('Invalid shared root name');
    }
    if (locator is! String || !_isSafeText(locator, maxLength: 32768)) {
      throw const FormatException('Invalid shared root locator');
    }
    if (typeName is! String || readOnly != null && readOnly is! bool) {
      throw const FormatException('Invalid shared root fields');
    }

    final SharedFileRootType type;
    try {
      type = SharedFileRootType.values.byName(typeName);
    } on ArgumentError {
      throw const FormatException('Invalid shared root type');
    }

    return SharedFileRoot(
      id: id,
      name: name,
      type: type,
      locator: locator,
      readOnly: readOnly as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'locator': locator,
    'readOnly': readOnly,
  };

  SharedFileRoot copyWith({
    String? name,
    bool? readOnly,
  }) {
    return SharedFileRoot(
      id: id,
      name: name ?? this.name,
      type: type,
      locator: locator,
      readOnly: readOnly ?? this.readOnly,
    );
  }
}

bool _isSafeText(String value, {required int maxLength}) {
  return value.isNotEmpty &&
      value.length <= maxLength &&
      !value.runes.any(
        (rune) => rune <= 0x1f || rune == 0x7f,
      );
}
