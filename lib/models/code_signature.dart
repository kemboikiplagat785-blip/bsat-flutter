import 'dart:convert';

/// importantSteps: List of maps
/// each map has:
/// - "stepPosition": int (0-based index of the step in the conversation)
/// - "options": String (the response received at that step)
/// - "input": String (the input sent at that step, if any)
///
///
///
/// acceptedProcedure: List of maps, one per step after the dial, in order
/// each map has:
/// - "options": String (the USSD screen shown at that step)
/// - "choice": String (the input sent on it; "n" for the customer number)
///
/// A signature belongs to one exact USSD code ([usdCode]), so another code of
/// the same offer, or its alternative code, is never checked against it. Offers
/// for different amounts that dial the same code share its signature.

class CodeSignature {
  final int? id;
  final int? ussdCodeId;
  final String usdCode;
  List<Map<String, dynamic>>? acceptedProcedure;
  List<Map<String, dynamic>>? lastProcedure;
  final List<Map<String, String>> importantSteps;
  bool? mightBeCompromised;
  bool? autoSwitch;
  bool? isActive;

  CodeSignature({
    this.id,
    this.ussdCodeId,
    required this.usdCode,
    this.acceptedProcedure,
    this.lastProcedure,
    List<Map<String, String>>? importantSteps,
    this.mightBeCompromised = false,
    this.autoSwitch = false,
    this.isActive = true,
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
      isActive: _parseBoolFromDynamic(map['isActive']),
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
      'isActive': isActive == true ? 1 : 0,
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
      // DB rows hold JSON text; toMap() and toJson() hold the list itself.
      final decoded = data is String ? jsonDecode(data) : data;
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

  /// A finished recording as stored: the probe number is not kept as a choice.
  static List<Map<String, String>> procedureFromRecording(
    List<Map<String, dynamic>> conversation,
    String probeNumber,
  ) {
    return conversation.map((step) {
      final choice = step['choice']?.toString() ?? '';
      return {
        'options': step['options']?.toString() ?? '',
        'choice': choice.replaceAll(' ', '') == probeNumber ? 'n' : choice,
      };
    }).toList();
  }

  /// What the native matcher needs from [acceptedProcedure].
  static List<Map<String, String>> wireProcedure(
      List<Map<String, dynamic>>? acceptedProcedure) {
    return (acceptedProcedure ?? [])
        .map((step) => {
              'options': step['options']?.toString() ?? '',
              'choice': step['choice']?.toString() ?? '',
            })
        .toList();
  }

  static List<String> codeSteps(String code) {
    var sequence = code.trim();
    if (sequence.endsWith('#')) {
      sequence = sequence.substring(0, sequence.length - 1);
    }
    return sequence.split('*').where((step) => step.isNotEmpty).toList();
  }

  /// Whether [code] (a saved code, or one with `n` filled in) is this
  /// signature's code.
  bool matchesCode(String code) {
    final mine = codeSteps(usdCode);
    final other = codeSteps(code);
    if (mine.isEmpty || mine.length != other.length) return false;
    final customerNumber = RegExp(r'^(n|[0-9]{9,12})$');
    for (var i = 0; i < mine.length; i++) {
      final sameStep = mine[i] == other[i] ||
          (mine[i] == 'n' && customerNumber.hasMatch(other[i]));
      if (!sameStep) return false;
    }
    return true;
  }

  bool get isRecorded => acceptedProcedure?.isNotEmpty ?? false;

  /// This signature as offer [offerId]'s copy, stored in row [rowId] if it has
  /// one: offers for different amounts can share one code, and so its menu.
  CodeSignature forOffer(int offerId, {int? rowId}) => CodeSignature(
        id: rowId,
        ussdCodeId: offerId,
        usdCode: usdCode,
        acceptedProcedure: acceptedProcedure,
        lastProcedure: lastProcedure,
        importantSteps: importantSteps,
        mightBeCompromised: mightBeCompromised,
        autoSwitch: autoSwitch,
        isActive: isActive,
      );

  /// A signature only protects [code] if it was fully recorded from that code.
  bool isUsableFor(String code) =>
      matchesCode(code) &&
      acceptedProcedure?.length == codeSteps(code).length - 1;

  static bool _parseBoolFromDynamic(dynamic v) {
    if (v == null) return false;
    if (v is bool) return v;
    if (v is int) return v != 0;
    final s = v.toString().toLowerCase();
    return s == '1' || s == 'true' || s == 'yes';
  }

  /// The text of the option chosen at [step], or null for free input such as
  /// the customer number.
  static String? chosenLabel(Map<String, dynamic> step) {
    final screen = step['options']?.toString() ?? '';
    final choice = RegExp.escape(step['choice']?.toString() ?? '');
    final line = RegExp(
        '^$choice' r'\s*(?:[:)\-]\s*|\.(?!\d)\s*|\s+)(\S.*)$');
    final optionStart = RegExp(r'(?<=\s)(?=(?:\d{1,3}|[*#])(?::|\)|\.(?!\d)))');
    final lines = screen.split('\n').expand((text) => text.split(optionStart));
    for (final candidate in lines) {
      final match = line.firstMatch(candidate.trim());
      if (match != null) return match.group(1)!.trim();
    }
    return null;
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
        'isActive': isActive,
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
    bool? autoSwitch, 
    bool? isActive,
    }) {    return CodeSignature(
      id: id ?? this.id,
      ussdCodeId: ussdCodeId ?? this.ussdCodeId,
      usdCode: usdCode ?? this.usdCode,
      acceptedProcedure: acceptedProcedure ?? this.acceptedProcedure,
      lastProcedure: lastProcedure ?? this.lastProcedure,
      importantSteps: importantSteps ?? this.importantSteps,
      mightBeCompromised: mightBeCompromised ?? this.mightBeCompromised,
      autoSwitch: autoSwitch ?? this.autoSwitch,
      isActive: isActive ?? this.isActive,
    );
  }

  @override
  String toString() {
    return 'CodeSignature(id: $id, ussdCodeId: $ussdCodeId, usdCode: $usdCode, acceptedProcedure: $acceptedProcedure, lastProcedure: $lastProcedure, importantSteps: $importantSteps, mightBeCompromised: $mightBeCompromised, autoSwitch: $autoSwitch, isActive: $isActive)';
  }

  Map<String, dynamic> sqlSavableForm() {
    // print("data: ${toMap()}");
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
      'isActive': (isActive == true) ? 1 : 0,
    };
  }
}
