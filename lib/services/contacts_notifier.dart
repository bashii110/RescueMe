import 'package:flutter/foundation.dart';

/// A global notifier that fires whenever emergency contacts are
/// added, edited, or deleted. Any widget can listen to this and
/// reload its contact count without relying on navigation callbacks
/// or life cycle hacks.
///
/// Usage — notify (in contacts screen after save/delete):
///   Contacts Notifier.instance.notify();
///
/// Usage — listen (in home screen):
///   ContactsNotifier.instance.addListener(_loadContactCount);
///   // remember to removeListener in dispose()
class ContactsNotifier extends ChangeNotifier {
  ContactsNotifier._();
  static final ContactsNotifier instance = ContactsNotifier._();

  /// Call this whenever contacts list changes.
  void notify() => notifyListeners();
}