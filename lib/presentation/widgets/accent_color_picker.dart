import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

Future<void> showAccentColorPicker(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF1C1F26),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
          child: Consumer<AppAccentProvider>(
            builder: (context, accentProvider, _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Akzentfarbe',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Ändert Knöpfe, Reiter, Symbole und aktive Elemente der App.',
                    style: TextStyle(color: Color(0xFFA0AEC0), fontSize: 13),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final option in AppAccentOption.values)
                        _AccentColorOption(
                          option: option,
                          selected: accentProvider.option == option,
                          onTap: () async {
                            await context.read<AppAccentProvider>().setOption(
                              option,
                            );
                            if (sheetContext.mounted) {
                              Navigator.pop(sheetContext);
                            }
                          },
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      );
    },
  );
}

class _AccentColorOption extends StatelessWidget {
  final AppAccentOption option;
  final bool selected;
  final VoidCallback onTap;

  const _AccentColorOption({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        width: 104,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected
              ? option.color.withValues(alpha: 0.16)
              : const Color(0xFF11151D),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? option.color
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: option.color,
                    shape: BoxShape.circle,
                  ),
                ),
                if (selected)
                  const Icon(Icons.check, color: Colors.white, size: 22),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              option.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFFA0AEC0),
                fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
