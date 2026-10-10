import 'package:flutter/material.dart';

import 'package:microscopeapp/core/theme/crystal_theme.dart';

class StabilityNotice extends StatelessWidget {
  const StabilityNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x332DD4BF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: crystalTeal.withValues(alpha: 0.45)),
      ),
      child: const Padding(
        padding: EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: crystalWarning, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Keep the object stationary and the lighting consistent. A tripod is recommended. Focus and exposure are set once at the start and then locked when the camera allows it.',
                style: TextStyle(height: 1.35),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
