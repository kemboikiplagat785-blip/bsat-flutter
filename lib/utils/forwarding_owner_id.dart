import 'package:uuid/uuid.dart';

const int kForwardingConfirmationProtocolVersion = 2;

class ForwardingOwnerId {
  static const Uuid _uuid = Uuid();
  static final RegExp _uuidV4 = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  static String generate() => _uuid.v4();

  static bool isValid(String? value) =>
      value != null && _uuidV4.hasMatch(value);
}
