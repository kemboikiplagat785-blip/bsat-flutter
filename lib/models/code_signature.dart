import 'dart:convert';

/// importantSteps: List of maps
/// each map has:
/// - "stepPosition": int (0-based index of the step in the conversation)
/// - "options": String (the response received at that step)
/// - "input": String (the input sent at that step, if any)
///
///
///
/// acceptedProcedure: List of maps
/// each map has:
/// - "option": int (step in the conversation)
/// - "choice": String (the response received at that step)

class CodeSignature {
  final int? id;
  final int? ussdCodeId;
  final String usdCode;
  List<Map<String, dynamic>>? acceptedProcedure;
  List<Map<String, dynamic>>? lastProcedure;
  final List<Map<String, String>> importantSteps;
  bool? mightBeCompromised;
  bool? autoSwitch;

  CodeSignature({
    this.id,
    this.ussdCodeId,
    required this.usdCode,
    this.acceptedProcedure,
    this.lastProcedure,
    List<Map<String, String>>? importantSteps,
    bool? mightBeCompromised = false,
    this.autoSwitch = false,
  }) : importantSteps = importantSteps ?? [];

  /// Create a CodeSignature from a DB row (Map<String, dynamic>)
  factory CodeSignature.fromMap(Map<String, dynamic> map) {
    return CodeSignature(
      id: map['id'] is int
          ? map['id'] as int
          : (map['id'] != null ? int.tryParse(map['id'].toString()) : null),
      ussdCodeId: map['ussdCodeId'] is int
          ? map['ussdCodeId'] as int
          : (map['ussdCodeId'] != null
              ? int.tryParse(map['ussdCodeId'].toString())
              : null),
      usdCode: map['usdCode']?.toString() ?? '',
      acceptedProcedure: decodeAcceptedProcedure(map['acceptedProcedure']),
      lastProcedure: decodeAcceptedProcedure(map['lastProcedure']),
      importantSteps: _decodeImportantSteps(map['importantSteps']),
      mightBeCompromised: _parseBoolFromDynamic(map['mightBeCompromised']),
      autoSwitch: _parseBoolFromDynamic(map['autoSwitch']),
    );
  }

  /// Convert to a map suitable for inserting/updating the DB
  Map<String, dynamic> toMap() {
    final m = <String, dynamic>{
      'ussdCodeId': ussdCodeId,
      'usdCode': usdCode,
      'acceptedProcedure': acceptedProcedure,
      'lastProcedure': lastProcedure,
      'importantSteps': _encodeImportantSteps(importantSteps),
      'mightBeCompromised':
          mightBeCompromised == true ? 1 : 0, // Store as int in DB
      'autoSwitch': autoSwitch == true ? 1 : 0,
    };
    if (id != null) m['id'] = id;
    return m;
  }

  /// Encode the importantSteps as a JSON string for storage
  static String _encodeImportantSteps(List<Map<String, String>> steps) {
    return jsonEncode(steps);
  }

  /// Decode the JSON string stored in the DB to a List<Map<String,String>>
  static List<Map<String, String>> _decodeImportantSteps(dynamic data) {
    if (data == null) return [];
    try {
      final decoded = jsonDecode(data);
      if (decoded is List) {
        return decoded.map<Map<String, String>>((item) {
          if (item is Map) {
            return item
                .map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
          }
          return <String, String>{};
        }).toList();
      }
    } catch (e) {
      // ignore and return empty
    }
    return [];
  }

  static String encodeAcceptedProcedure(
      List<Map<String, String>>? acceptedProcedure) {
    if (acceptedProcedure == null) return '';
    return jsonEncode(acceptedProcedure);
  }

  static List<Map<String, String>>? decodeAcceptedProcedure(dynamic data) {
    if (data == null) return null;
    try {
      final decoded = jsonDecode(data);
      if (decoded is List) {
        return decoded.map<Map<String, String>>((item) {
          if (item is Map) {
            return item
                .map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
          }
          return <String, String>{};
        }).toList();
      }
    } catch (e) {
      // ignore and return null
    }
    return null;
  }

  static List<Map<String, String>> simpleProcedure(
      List<Map<String, dynamic>>? acceptedProcedure) {
    if (acceptedProcedure == null) return [];

    return acceptedProcedure.map((step) {
      // We create a temporary map to satisfy extractChosenOption's key requirements
      String extracted = extractChosenOption(
          {'options': step['options'] ?? '', 'choice': step['choice'] ?? ''});

      return {
        "option": extracted,
        "choice": step["choice"]?.toString() ?? '',
      };
    }).toList(); // Convert Iterable to List
  }

  static bool _parseBoolFromDynamic(dynamic v) {
    if (v == null) return false;
    if (v is bool) return v;
    if (v is int) return v != 0;
    final s = v.toString().toLowerCase();
    return s == '1' || s == 'true' || s == 'yes';
  }

  static String extractChosenOption(Map<String, dynamic> data) {
    String options = data['options'] ?? '';
    String choice = data['choice'].toString();

    // 1. Split the string into individual lines
    // USSD responses usually use \n for new lines
    List<String> lines = options.split('\n');

    // 2. Define the prefix we are looking for (e.g., "6:")
    String searchPrefix = "$choice:";

    for (String line in lines) {
      String trimmedLine = line.trim();

      // 3. Check if the line starts with our choice number + colon
      if (trimmedLine.startsWith(searchPrefix)) {
        // 4. Remove the "6:" part and return the remaining text
        return trimmedLine.substring(searchPrefix.length).trim();
      }
    }

    return "Option not found";
  }

  static List<Map<String, String>> decodeImportantSteps(dynamic data) {
    if (data == null) return [];
    try {
      final decoded = jsonDecode(data);
      if (decoded is List) {
        return decoded.map<Map<String, String>>((item) {
          if (item is Map) {
            return item
                .map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
          }
          return <String, String>{};
        }).toList();
      }
    } catch (e) {
      // ignore and return empty
    }
    return [];
  }

  /// Helper: create an instance from raw DB query result that may be null-safe
  static CodeSignature? fromNullableMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    return CodeSignature.fromMap(map);
  }

  /// Utility: list of CodeSignature from query result
  static List<CodeSignature> listFromRows(List<Map<String, dynamic>> rows) {
    return rows.map((r) => CodeSignature.fromMap(r)).toList();
  }

  /// Convert to JSON (not the DB representation) - useful for API or debug
  Map<String, dynamic> toJson() => {
        'id': id,
        'ussdCodeId': ussdCodeId,
        'usdCode': usdCode,
        'acceptedProcedure': acceptedProcedure,
        'lastProcedure': lastProcedure,
        'importantSteps': importantSteps,
        'mightBeCompromised': mightBeCompromised,
        'autoSwitch': autoSwitch,
      };

  /// Create from JSON (inverse of toJson)
  factory CodeSignature.fromJson(Map<String, dynamic> json) {
    final imp = <Map<String, String>>[];
    if (json['importantSteps'] is List) {
      for (final item in json['importantSteps']) {
        if (item is Map) {
          imp.add(
              item.map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')));
        }
      }
    }
    return CodeSignature(
      id: json['id'] is int
          ? json['id'] as int
          : (json['id'] != null ? int.tryParse(json['id'].toString()) : null),
      ussdCodeId: json['ussdCodeId'] is int
          ? json['ussdCodeId'] as int
          : (json['ussdCodeId'] != null
              ? int.tryParse(json['ussdCodeId'].toString())
              : null),
      usdCode: json['usdCode']?.toString() ?? '',
      acceptedProcedure: decodeAcceptedProcedure(json['acceptedProcedure']),
      lastProcedure: decodeAcceptedProcedure(json['lastProcedure']),
      importantSteps: imp,
      mightBeCompromised: _parseBoolFromDynamic(json['mightBeCompromised']),
      autoSwitch: _parseBoolFromDynamic(json['autoSwitch']),
    );
  }

  /// Copy with
  CodeSignature copyWith({
    int? id,
    int? ussdCodeId,
    String? usdCode,
    List<Map<String, dynamic>>? acceptedProcedure,
    List<Map<String, dynamic>>? lastProcedure,
    List<Map<String, String>>? importantSteps,
    bool? mightBeCompromised,
    bool? autoSwitch,}) {    return CodeSignature(
      id: id ?? this.id,
      ussdCodeId: ussdCodeId ?? this.ussdCodeId,
      usdCode: usdCode ?? this.usdCode,
      acceptedProcedure: acceptedProcedure ?? this.acceptedProcedure,
      lastProcedure: lastProcedure ?? this.lastProcedure,
      importantSteps: importantSteps ?? this.importantSteps,
      mightBeCompromised: mightBeCompromised ?? this.mightBeCompromised,
      autoSwitch: autoSwitch ?? this.autoSwitch,
    );
  }

  @override
  String toString() {
    return 'CodeSignature(id: $id, ussdCodeId: $ussdCodeId, usdCode: $usdCode, acceptedProcedure: $acceptedProcedure, lastProcedure: $lastProcedure, importantSteps: $importantSteps, mightBeCompromised: $mightBeCompromised), autoSwitch: $autoSwitch)';
  }

  Map<String, dynamic> sqlSavableForm() {
    print("data: ${toMap()}");
    return {
      if (id != null) 'id': id,
      'ussdCodeId': ussdCodeId,
      'usdCode': usdCode,

      // Convert Lists/Maps to JSON Strings because SQL doesn't support List types
      'acceptedProcedure':
          acceptedProcedure != null ? jsonEncode(acceptedProcedure) : null,

      'lastProcedure': lastProcedure != null ? jsonEncode(lastProcedure) : null,

      'importantSteps': jsonEncode(importantSteps),

      // SQL uses 1 for true and 0 for false
      'mightBeCompromised': (mightBeCompromised == true) ? 1 : 0,
      'autoSwitch': (autoSwitch == true) ? 1 : 0,
    };
  }
}
