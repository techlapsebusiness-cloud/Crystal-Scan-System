import 'package:flutter/material.dart';

import 'package:microscopeapp/features/capture/domain/frame_counts.dart';

class FrameCountSelector extends StatelessWidget {
  const FrameCountSelector({
    super.key,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final int selected;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Frames', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        SegmentedButton<int>(
          segments: [
            for (final count in allowedFrameCounts)
              ButtonSegment<int>(
                value: count,
                label: Text('$count'),
              ),
          ],
          selected: {selected},
          emptySelectionAllowed: false,
          showSelectedIcon: false,
          onSelectionChanged: enabled
              ? (selection) => onChanged(selection.first)
              : null,
          style: SegmentedButton.styleFrom(
            minimumSize: const Size(48, 48),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
