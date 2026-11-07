enum BiometricResult {
  success,

  /// The user cancelled, or the prompt was dismissed by the system.
  cancelled,

  /// No biometric hardware, or nothing enrolled.
  unavailable,

  /// Too many failed attempts; the platform has locked biometrics.
  lockedOut,

  /// Any other failure, including a non-matching fingerprint or face.
  failed,
}

/// Fingerprint / face authentication. Biometric-only: the fallback is
/// CypherAuth's own PIN, never the device's screen-lock credential.
abstract interface class BiometricAuth {
  /// Whether biometrics can be used right now (hardware present, enrolled).
  Future<bool> isAvailable();

  Future<BiometricResult> authenticate(String reason);
}
