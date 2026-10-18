/// Result returned by `POST /api/verification/verify`.
class VerificationResult {
  final String licenseId;
  final String? fullName;

  /// `Real` or `Fake`.
  final String status;

  /// `Active`, `Expired`, `Unknown`, or `NeedsReview`.
  final String expiryStatus;

  final String? checkedBy;
  final DateTime? checkedDate;

  const VerificationResult({
    required this.licenseId,
    required this.status,
    required this.expiryStatus,
    this.fullName,
    this.checkedBy,
    this.checkedDate,
  });

  factory VerificationResult.fromJson(Map<String, dynamic> json) {
    return VerificationResult(
      licenseId: (json['licenseId'] ?? '').toString(),
      fullName: json['fullName'] as String?,
      status: (json['status'] ?? 'Unknown').toString(),
      expiryStatus: (json['expiryStatus'] ?? 'Unknown').toString(),
      checkedBy: json['checkedBy']?.toString(),
      checkedDate: DateTime.tryParse((json['checkedDate'] ?? '').toString()),
    );
  }

  bool get isReal => status.toLowerCase() == 'real';

  bool get isActive => expiryStatus.toLowerCase() == 'active';
}
