import 'package:cypher/core/security/biometric_auth.dart';

/// Scripted biometrics: [available] toggles the sensor, and each
/// [authenticate] call returns [nextResult] (default success).
final class FakeBiometrics implements BiometricAuth {
  bool available = true;
  BiometricResult nextResult = BiometricResult.success;
  int prompts = 0;
  final List<String> reasons = [];

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<BiometricResult> authenticate(String reason) async {
    prompts++;
    reasons.add(reason);
    return nextResult;
  }
}
