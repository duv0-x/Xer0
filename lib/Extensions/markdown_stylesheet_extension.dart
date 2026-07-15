import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

/// Extension on [BuildContext] to provide consistent markdown styling across the app.
extension MarkdownStyleSheetExtension on BuildContext {
  /// Returns a [MarkdownStyleSheet] that matches the app's theme with bodyLarge text size.
  ///
  /// This ensures markdown content uses the same base size as other readable text
  /// in the app, while respecting user accessibility settings up to 2x scale.
  MarkdownStyleSheet get markdownStyleSheet {
    final colorScheme = Theme.of(this).colorScheme;

    return MarkdownStyleSheet.fromTheme(
      Theme.of(this).copyWith(
        textTheme: Theme.of(this).textTheme.copyWith(
              bodyMedium: Theme.of(this).textTheme.bodyLarge,
            ),
      ),
    ).copyWith(
      textScaler: MediaQuery.textScalerOf(this).clamp(
        minScaleFactor: 0.8,
        maxScaleFactor: 2.0,
      ),
      // The package default uses a fixed light-blue background with the
      // theme's body text color, which reads poorly on dark/colored themes.
      // Use the Material 3 container/on-container pair instead, which is
      // guaranteed to have accessible contrast for any seed color or brightness.
      blockquote: Theme.of(this).textTheme.bodyLarge?.copyWith(
            color: colorScheme.onSecondaryContainer,
          ),
      blockquoteDecoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(4.0),
      ),
    );
  }
}
