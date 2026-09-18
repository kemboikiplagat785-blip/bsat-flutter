class UssdCode {
  final int? id;
  final String code;
  final int amount;
  final int fromSim;
  final int dialSim;
  final bool canRetry;
  final bool isAdvanced;
  final bool enabled;
  final bool usesBongaPoints;
  final String? fallbackCode;
  final String? balanceCheckCode;
  final int bongaPointsPerTransaction;

  UssdCode({
    this.id,
    required this.code,
    required this.amount,
    this.fromSim = -1,
    this.dialSim = -1,
    this.canRetry = false,
    this.isAdvanced = false,
    this.enabled = true,
    this.usesBongaPoints = false,
    this.fallbackCode,
    this.balanceCheckCode,
    this.bongaPointsPerTransaction = 0,
  });

  factory UssdCode.fromMap(Map<String, dynamic> m) {
    int parseInt(dynamic v, [int def = 0]) {
      if (v == null) return def;
      if (v is int) return v;
      return int.tryParse(v.toString()) ?? def;
    }

    bool parseBool(dynamic v) {
      if (v == null) return false;
      if (v is bool) return v;
      if (v is int) return v != 0;
      final s = v.toString().toLowerCase();
      return s == '1' || s == 'true' || s == 'yes';
    }

    return UssdCode(
      id: parseInt(m['id'], 0) == 0 ? null : parseInt(m['id'], 0),
      code: m['code']?.toString() ?? '',
      amount: parseInt(m['amount'], 0),
      fromSim: parseInt(m['fromSim'], -1),
      dialSim: parseInt(m['dialSim'], -1),
      canRetry: parseBool(m['canRetry']),
      isAdvanced: parseBool(m['isAdvanced']),
      enabled: m['enabled'] == null ? true : parseBool(m['enabled']),
      usesBongaPoints: parseBool(m['usesBongaPoints']),
      fallbackCode: m['fallbackCode']?.toString(),
      balanceCheckCode: m['balanceCheckCode']?.toString(),
      bongaPointsPerTransaction: parseInt(m['bongaPointsPerTransaction'], 0),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'code': code,
      'amount': amount,
      'fromSim': fromSim,
      'dialSim': dialSim,
      'canRetry': canRetry ? 1 : 0,
      'isAdvanced': isAdvanced ? 1 : 0,
      'enabled': enabled ? 1 : 0,
      'usesBongaPoints': usesBongaPoints ? 1 : 0,
      'fallbackCode': fallbackCode,
      'balanceCheckCode': balanceCheckCode,
      'bongaPointsPerTransaction': bongaPointsPerTransaction,
    };
  }
}
