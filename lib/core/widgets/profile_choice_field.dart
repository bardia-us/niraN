import 'package:flutter/material.dart';

import '../localization/app_strings.dart';
import 'glass_dialog.dart';

/// A bounded selector that shares the app's glass dialog and rounded ink.
/// Imported nonstandard values remain selectable, rather than silently reset.
class ProfileChoiceField extends StatelessWidget {
  const ProfileChoiceField({
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
    this.errorText,
    super.key,
  });

  final String label;
  final String value;
  final Iterable<String> values;
  final ValueChanged<String>? onChanged;
  final String? errorText;

  String _display(BuildContext context, String option) =>
      option.isEmpty ? context.s('default') : option;

  Future<void> _choose(BuildContext context) async {
    final selected = await showNirangDialog<String>(
      context: context,
      builder: (dialogContext) => Center(
        child: SizedBox(
          width: 416,
          child: NirangAlertDialog(
            title: Text(label),
            contentPadding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
            content: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final option in values.toSet())
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Material(
                        type: MaterialType.transparency,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => Navigator.pop(dialogContext, option),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 13,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  option == value
                                      ? Icons.check_circle_rounded
                                      : Icons.circle_outlined,
                                  size: 20,
                                  color: option == value
                                      ? Theme.of(context).colorScheme.primary
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(_display(context, option)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (context.mounted && selected != null) onChanged?.call(selected);
  }

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onChanged == null ? null : () => _choose(context),
      child: InputDecorator(
        isEmpty: false,
        decoration: InputDecoration(
          labelText: label,
          errorText: errorText,
          enabled: onChanged != null,
        ),
        child: Row(
          children: [
            Expanded(child: Text(_display(context, value))),
            const Icon(Icons.unfold_more_rounded, size: 20),
          ],
        ),
      ),
    ),
  );
}
