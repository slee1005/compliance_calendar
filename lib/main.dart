import 'package:material_ui/material_ui.dart';

import 'app/security_bootstrap.dart';

/// Starts the four-platform compliance application.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SecurityBootstrap());
}
