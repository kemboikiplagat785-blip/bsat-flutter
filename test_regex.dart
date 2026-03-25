void main() {
  // A dynamic list of incoming SMS messages (can be in any order, with any IDs)
  final incomingMessages =[
    // "Your request for M-PESA Transaction ID UCP9WAJ6TS has been approved. Here are the details 254702015937 - Mark Njoroge Wanjiru",
    "UCP9WAJ6TS Confirmed.You have received Ksh3.00 from Mark  Wanjiru 0702***937 on 25/3/26 at 1:54 PM  New M-PESA balance is Ksh8,796.00.",
    // "XYZ123ABCD Confirmed.You have received Ksh500.50 from Jane Doe 0711***222 on 25/3/26 at 2:00 PM  New M-PESA balance is Ksh9,296.50.",
    "Your request for M-PESA Transaction ID XYZ123ABCD has been approved. Here are the details 254711000222 - Jane Mary Doe"
  ];

  final extractor = MpesaExtractor();

  // 1. Process all messages dynamically
  for (String sms in incomingMessages) {
    extractor.processMessage(sms);
  }

  // 2. Get all extracted and merged transactions dynamically
  final allTransactions = extractor.getAllTransactions();

  // 3. Print the results to prove it handled everything dynamically
  for (var transaction in allTransactions) {
    print(transaction);
  }
}

class MpesaRecord {
  String transactionId;
  double? amount;
  String? name;
  String? phoneNumber;

  MpesaRecord({
    required this.transactionId,
    this.amount,
    this.name,
    this.phoneNumber,
  });

  // Smartly merges new data into the existing record
  void merge(MpesaRecord other) {
    amount ??= other.amount;

    // Prefer the unmasked full phone number (no asterisks)
    if (other.phoneNumber != null) {
      if (phoneNumber == null || !other.phoneNumber!.contains('*')) {
        phoneNumber = other.phoneNumber;
      }
    }

    // Prefer the longer, more complete name 
    if (other.name != null) {
      if (name == null || other.name!.length > name!.length) {
        name = other.name;
      }
    }
  }

  @override
  String toString() {
    return '''
-------------------------
Transaction ID : $transactionId
Amount         : Ksh ${amount ?? 'Pending...'}
Phone Number   : ${phoneNumber ?? 'Pending...'}
Full Name      : ${name ?? 'Pending...'}''';
  }
}

class MpesaExtractor {
  // Regex 1: Dynamically catches ID, Amount, Name, and Masked Phone from standard receipt
  // Looks for:[10-char ID] Confirmed ... Ksh[Amount] from [Name] [Phone] on
  static final RegExp _receiptRegex = RegExp(
    r'^([A-Z0-9]{10})\s*Confirmed.*?received\s*Ksh([\d,.]+)\s*from\s*(.*?)\s*([\d*+]+)\s*on',
    caseSensitive: false,
  );

  // Regex 2: Dynamically catches ID, Full Phone, and Full Name from the details SMS
  // Looks for: Transaction ID [10-char ID] ... details [Phone] - [Name]
  static final RegExp _detailsRegex = RegExp(
    r'Transaction ID\s+([A-Z0-9]{10}).*?details\s+([\d+]+)\s*-\s*(.*)',
    caseSensitive: false,
  );

  // Stores transactions dynamically using the extracted ID as the map key
  final Map<String, MpesaRecord> _transactions = {};

  void processMessage(String sms) {
    // Try to parse the SMS with both Regex patterns
    MpesaRecord? record = _parseReceipt(sms) ?? _parseDetails(sms);

    if (record != null) {
      // If we already have this dynamic ID in our map, update/merge it
      if (_transactions.containsKey(record.transactionId)) {
        _transactions[record.transactionId]!.merge(record);
      } else {
        // Otherwise, create a new entry for this newly discovered ID
        _transactions[record.transactionId] = record;
      }
    }
  }

  // Returns all processed transactions as a list
  List<MpesaRecord> getAllTransactions() {
    return _transactions.values.toList();
  }

  // --- Private Parsing Helpers ---

  MpesaRecord? _parseReceipt(String sms) {
    final match = _receiptRegex.firstMatch(sms);
    if (match != null) {
      return MpesaRecord(
        transactionId: match.group(1)!.toUpperCase(), // Dynamic ID (Group 1)
        amount: double.tryParse(match.group(2)!.replaceAll(',', '')), // Dynamic Amount (Group 2)
        name: _cleanName(match.group(3)!), // Dynamic Partial Name (Group 3)
        phoneNumber: match.group(4)!, // Dynamic Masked Phone (Group 4)
      );
    }
    return null;
  }

  MpesaRecord? _parseDetails(String sms) {
    final match = _detailsRegex.firstMatch(sms);
    if (match != null) {
      return MpesaRecord(
        transactionId: match.group(1)!.toUpperCase(), // Dynamic ID (Group 1)
        phoneNumber: match.group(2)!, // Dynamic Unmasked Phone (Group 2)
        name: _cleanName(match.group(3)!), // Dynamic Full Name (Group 3)
      );
    }
    return null;
  }

  // Cleans up double spaces (e.g. "Mark  Wanjiru" -> "Mark Wanjiru")
  String _cleanName(String rawName) {
    return rawName.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
