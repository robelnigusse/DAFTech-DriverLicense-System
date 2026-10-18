/// Values parsed out of the QR payload on the back of a driving licence.
class ParsedLicenseQr {
  final String? fullName;
  final String? licenseId;
  final String? licenseType;

  const ParsedLicenseQr({
    this.fullName,
    this.licenseId,
    this.licenseType,
  });
}

/// Parsing helpers shared by the registration scanner and the
/// verification screen.
class LicenseParser {
  LicenseParser._();

  /// Extracts the driver name and licence number from the raw QR payload.

  static ParsedLicenseQr parseQr(String qrRaw) {
    String? fullName;
    String? licenseId;
    String? licenseType;

    final nameMatch = RegExp(
      r'የአሽከርካሪው\s*ስም\s*[:：-]*(.+?)(?=የመንጃ\s*ፍቃድ\s*ቁጥር|$)',
      dotAll: true,
    ).firstMatch(qrRaw);

    if (nameMatch != null) {
      final name = clean(nameMatch.group(1)!);
      if (name.isNotEmpty) {
        fullName = name;
      }
    }

    final licenseMatch = RegExp(
      r'የመንጃ\s*ፍቃድ\s*ቁጥር\s*[:：-]*(.+)$',
      dotAll: true,
    ).firstMatch(qrRaw);

    if (licenseMatch != null) {
      final parts = licenseMatch
          .group(1)!
          .split('-')
          .map(clean)
          .where((part) => part.isNotEmpty)
          .toList();

      if (parts.length >= 3) {
        licenseType = parts[1];
        licenseId = parts.sublist(2).join('-');
      } else if (parts.length == 2) {
        licenseType = parts[0];
        licenseId = parts[1];
      } else if (parts.length == 1) {
        licenseId = parts.first;
      }
    }

    return ParsedLicenseQr(
      fullName: fullName,
      licenseId: licenseId,
      licenseType: licenseType,
    );
  }

  /// Best-effort licence number for verification.
  ///
  /// Falls back to the raw payload when the QR contains a plain licence
  /// number instead of the labelled format.
  static String? licenseIdFromRaw(String qrRaw) {
    final parsed = parseQr(qrRaw);
    final parsedId = parsed.licenseId;
    if (parsedId != null && parsedId.isNotEmpty) {
      return parsedId;
    }

    final trimmed = qrRaw.trim();
    if (trimmed.isEmpty || trimmed.contains('\n') || trimmed.length > 100) {
      return null;
    }
    return trimmed;
  }

  static String clean(String value) {
    return value
        .replaceAll(RegExp(r'^[\s:./|_~-]+|[\s:./|_~-]+$'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Converts a scanned date to the `yyyy-MM-dd` form expected by the API.
  static String? normalizeDate(String? raw) {
    if (raw == null) return null;

    final value = raw.trim();
    if (value.isEmpty) return null;

    final iso =
        RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})$').firstMatch(value);
    if (iso != null) {
      return _format(
        int.parse(iso.group(1)!),
        int.parse(iso.group(2)!),
        int.parse(iso.group(3)!),
      );
    }

    final short =
        RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})$').firstMatch(value);
    if (short != null) {
      var first = int.parse(short.group(1)!);
      var second = int.parse(short.group(2)!);
      var year = int.parse(short.group(3)!);

      if (year < 100) {
        year += year >= 70 ? 1900 : 2000;
      }

      if (first <= 12 && second > 12) {
        final swap = first;
        first = second;
        second = swap;
      }

      return _format(year, second, first);
    }

    return null;
  }

  static String? _format(int year, int month, int day) {
    if (year < 1900 || year > 2100) return null;
    if (month < 1 || month > 12) return null;
    if (day < 1 || day > 31) return null;

    return '$year-${_two(month)}-${_two(day)}';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}
