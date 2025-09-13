class Client {
  final int? id;
  final String firstName;
  final String lastName;
  final String phoneNumber;
  final DateTime createdAt;
  final DateTime? lastBought;
  final int noOfPurchases;

  Client({
    this.id,
    required this.firstName,
    required this.lastName,
    required this.phoneNumber,
    required this.createdAt,
    this.lastBought,
    this.noOfPurchases = 0,
  });

  // Convert Client to Map (for database operations)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'firstName': firstName,
      'lastName': lastName,
      'phoneNumber': phoneNumber,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'lastBought': lastBought?.millisecondsSinceEpoch,
      'noOfPurchases': noOfPurchases,
    };
  }

  // Create Client from Map (for database queries)
  factory Client.fromMap(Map<String, dynamic> map) {
    return Client(
      id: map['id']?.toInt(),
      firstName: map['firstName'] ?? '',
      lastName: map['lastName'] ?? '',
      phoneNumber: map['phoneNumber'] ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt']),
      lastBought: map['lastBought'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(map['lastBought'])
          : null,
      noOfPurchases: map['noOfPurchases'] ?? 0,
    );
  }

  // Get full name
  String get fullName => '$firstName $lastName'.trim();

  // Get formatted phone number
  String get formattedPhone {
    String cleaned = phoneNumber.replaceAll(RegExp(r'[^\d]'), '');
    if (cleaned.startsWith('254')) {
      return '+$cleaned';
    } else if (cleaned.startsWith('0')) {
      return '+254${cleaned.substring(1)}';
    } else if (cleaned.length == 9) {
      return '+254$cleaned';
    }
    return phoneNumber;
  }

  // Get days since last purchase
  int? get daysSinceLastPurchase {
    if (lastBought == null) return null;
    return DateTime.now().difference(lastBought!).inDays;
  }

  // Check if client is active (purchased within last 30 days)
  bool get isActive {
    if (lastBought == null) return false;
    return daysSinceLastPurchase! <= 30;
  }

  // Copy with method for updates
  Client copyWith({
    int? id,
    String? firstName,
    String? lastName,
    String? phoneNumber,
    DateTime? createdAt,
    DateTime? lastBought,
    int? noOfPurchases,
  }) {
    return Client(
      id: id ?? this.id,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      createdAt: createdAt ?? this.createdAt,
      lastBought: lastBought ?? this.lastBought,
      noOfPurchases: noOfPurchases ?? this.noOfPurchases,
    );
  }

  @override
  String toString() {
    return 'Client{id: $id, fullName: $fullName, phoneNumber: $phoneNumber, purchases: $noOfPurchases}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Client &&
        other.id == id &&
        other.phoneNumber == phoneNumber;
  }

  @override
  int get hashCode => id.hashCode ^ phoneNumber.hashCode;
}