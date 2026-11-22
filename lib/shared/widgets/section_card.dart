import 'package:material_ui/material_ui.dart';

/// A responsive, consistently padded application section.
class SectionCard extends StatelessWidget {
  /// Creates a section with an optional title and helper copy.
  const SectionCard({
    super.key,
    this.title,
    this.subtitle,
    required this.child,
  });

  /// Optional heading shown above the section body.
  final String? title;

  /// Optional explanatory copy.
  final String? subtitle;

  /// Section contents.
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Text(title!, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
          ],
          if (subtitle != null) ...[
            Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 18),
          ],
          child,
        ],
      ),
    ),
  );
}

/// An honest unavailable-feature notice used until its native service exists.
class DevelopmentNotice extends StatelessWidget {
  /// Explains the next implementation dependency without simulating success.
  const DevelopmentNotice({super.key, required this.message});

  /// Concrete state of the integration.
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFEAF1F5),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.construction_outlined, size: 21),
        const SizedBox(width: 12),
        Expanded(child: Text(message)),
      ],
    ),
  );
}
