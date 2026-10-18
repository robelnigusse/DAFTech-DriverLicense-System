/// A driver licence record returned by `GET /api/drivers`.
class Driver {
  final String driverId;
  final String licenseId;
  final String fullName;
  final String? dateOfBirth;
  final String? licenseType;
  final String? expiryDate;
  final String? qrRawData;
  final String? ocrRawText;
  final DateTime? createdDate;
  final String? registeredBy;

  const Driver({
    required this.driverId,
    required this.licenseId,
    required this.fullName,
    this.dateOfBirth,
    this.licenseType,
    this.expiryDate,
    this.qrRawData,
    this.ocrRawText,
    this.createdDate,
    this.registeredBy,
  });

  factory Driver.fromJson(Map<String, dynamic> json) {
    return Driver(
      driverId: (json['driverId'] ?? '').toString(),
      licenseId: (json['licenseId'] ?? '').toString(),
      fullName: (json['fullName'] ?? '').toString(),
      dateOfBirth: json['dateOfBirth'] as String?,
      licenseType: json['licenseType'] as String?,
      expiryDate: json['expiryDate'] as String?,
      qrRawData: json['qrRawData'] as String?,
      ocrRawText: json['ocrRawText'] as String?,
      createdDate: DateTime.tryParse((json['createdDate'] ?? '').toString()),
      registeredBy: json['registeredBy']?.toString(),
    );
  }

  /// `Active`, `Expired`, or `Unknown` — mirrors the backend's rule.
  String get status {
    final expiry = expiryDate == null ? null : DateTime.tryParse(expiryDate!);
    if (expiry == null) return 'Unknown';

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final expiryDay = DateTime(expiry.year, expiry.month, expiry.day);

    return expiryDay.isBefore(today) ? 'Expired' : 'Active';
  }
}
