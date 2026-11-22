import 'package:material_ui/material_ui.dart';

import '../models/demo_credential.dart';

/// Accessible, wrapping preview row shared by lists and the dashboard.
class CredentialTile extends StatelessWidget {
  /// Opens the read-only preview when tapped.
  const CredentialTile({super.key, required this.record, required this.onTap});

  /// Fictional record displayed by the tile.
  final DemoCredential record;

  /// Detail navigation callback.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: record.color.withValues(alpha: 0.09),
              foregroundColor: record.color,
              child: Icon(record.icon),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.type,
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${record.holder} · ${record.isBusiness ? '사업장' : '직원'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${record.status} · ${record.countdown}',
                    style: TextStyle(
                      color: record.color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20),
          ],
        ),
      ),
    ),
  );
}
