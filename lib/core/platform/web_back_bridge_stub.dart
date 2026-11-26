typedef PopStateCallback = void Function();

/// Web dışındaki platformlarda tarayıcı geçmişi köprüsü boş (no-op) çalışır.
class PlatformWebHistory {
  void initialize(PopStateCallback onPopState) {}

  void pushState() {}

  void back() {}

  void dispose() {}
}
