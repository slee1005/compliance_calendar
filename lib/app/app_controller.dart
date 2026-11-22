import 'package:flutter/foundation.dart';

import '../shared/models/demo_credential.dart';
import 'router.dart';

/// Ephemeral navigation and preview state, with no disk or network access.
class AppController extends ChangeNotifier {
  bool _started = false;
  bool _example = false;
  AppDestination _destination = AppDestination.dashboard;
  DemoCredential? _selectedCredential;
  String? _selectedStaff;

  /// Whether onboarding has been left during this process.
  bool get started => _started;

  /// Whether fictional data was explicitly requested.
  bool get example => _example;

  /// Current primary screen.
  AppDestination get destination => _destination;

  /// Display-only detail selection.
  DemoCredential? get selectedCredential => _selectedCredential;

  /// Display-only staff selection.
  String? get selectedStaff => _selectedStaff;

  /// Empty by default; no sample data is merged into a real data source.
  List<DemoCredential> get records => _example ? demoCredentials : const [];

  /// Enters the shell without persisting onboarding choices.
  void start({bool example = false}) {
    _started = true;
    _example = example;
    notifyListeners();
  }

  /// Enables or clears all fictional preview state.
  void setExample(bool enabled) {
    _example = enabled;
    _selectedCredential = null;
    _selectedStaff = null;
    notifyListeners();
  }

  /// Navigates to a top-level screen and closes detail views.
  void navigate(AppDestination destination) {
    _destination = destination;
    _selectedCredential = null;
    _selectedStaff = null;
    notifyListeners();
  }

  /// Opens a fictional credential's read-only detail view.
  void showCredential(DemoCredential credential) {
    _destination = AppDestination.licenses;
    _selectedCredential = credential;
    _selectedStaff = null;
    notifyListeners();
  }

  /// Opens a fictional person's read-only credential list.
  void showStaff(String alias) {
    _destination = AppDestination.staff;
    _selectedStaff = alias;
    _selectedCredential = null;
    notifyListeners();
  }

  /// Returns to the welcome screen and clears the preview.
  void restart() {
    _started = false;
    _example = false;
    _destination = AppDestination.dashboard;
    _selectedCredential = null;
    _selectedStaff = null;
    notifyListeners();
  }
}
