typedef PopStateCallback = void Function();

/// Web dışındaki platformlarda tarayıcı geçmişi köprüsü boş (no-op) çalışır.
class PlatformWebHistory {
  void initialize(PopStateCallback onPopState) {}

  String get currentHash => '';

  void ensureBaseHash(String hash) {}

  void pushHash(String hash) {}

  void back() {}

  void dispose() {}
}
