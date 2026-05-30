
import 'package:flutter/material.dart';
import 'package:pro_tocol/view/theme/AppColors.dart';

class TypingIndicatorBubble extends StatelessWidget {
  const TypingIndicatorBubble({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        decoration: const BoxDecoration(
          color: AppColors.surfaceHighlight,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('Escribiendo...',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            SizedBox(height: 6),
            SizedBox(
              width: 120,
              child: LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: AppColors.surface,
                valueColor: AlwaysStoppedAnimation(AppColors.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}