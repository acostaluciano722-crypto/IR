class FaceVerificationStatus {
  const FaceVerificationStatus({
    required this.enrolled,
    required this.available,
    required this.required,
    required this.verificationDue,
    required this.state,
    required this.consentVersion,
    this.enrolledAt,
    this.lastVerifiedAt,
    this.verificationDueAt,
    this.photoUrl,
    this.limitations = '',
  });

  factory FaceVerificationStatus.fromJson(Map<String, dynamic> json) =>
      FaceVerificationStatus(
        enrolled: json['enrolled'] == true,
        available: json['available'] == true,
        required: json['required'] == true,
        verificationDue: json['verification_due'] == true,
        state: json['state']?.toString() ?? 'not_enrolled',
        consentVersion: json['consent_version']?.toString() ?? '',
        enrolledAt: DateTime.tryParse(json['enrolled_at']?.toString() ?? ''),
        lastVerifiedAt:
            DateTime.tryParse(json['last_verified_at']?.toString() ?? ''),
        verificationDueAt:
            DateTime.tryParse(json['verification_due_at']?.toString() ?? ''),
        photoUrl: json['photo_url']?.toString(),
        limitations: json['limitations']?.toString() ?? '',
      );

  final bool enrolled;
  final bool available;
  final bool required;
  final bool verificationDue;
  final String state;
  final String consentVersion;
  final DateTime? enrolledAt;
  final DateTime? lastVerifiedAt;
  final DateTime? verificationDueAt;
  final String? photoUrl;
  final String limitations;

  bool get needsVerification => required && verificationDue;
  bool get hasCurrentVerification => enrolled && !verificationDue;
}

class FaceVerificationResult {
  const FaceVerificationResult({
    required this.status,
    required this.verified,
    this.message,
  });

  factory FaceVerificationResult.fromJson(Map<String, dynamic> json) =>
      FaceVerificationResult(
        status: FaceVerificationStatus.fromJson(json),
        verified: json['verified'] == true,
        message: json['detail']?.toString(),
      );

  final FaceVerificationStatus status;
  final bool verified;
  final String? message;
}
