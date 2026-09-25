import 'dart:io';
import 'package:two_level_qr/two_level_qr.dart';

/// ANSI terminal formatting and rendering utilities.
class TerminalUtils {
  TerminalUtils._();

  static const bool useColors = true;

  // ANSI escape codes
  static const String reset = '\x1B[0m';
  static const String bold = '\x1B[1m';
  static const String dim = '\x1B[2m';
  static const String italic = '\x1B[3m';
  static const String underline = '\x1B[4m';

  static const String black = '\x1B[30m';
  static const String red = '\x1B[31m';
  static const String green = '\x1B[32m';
  static const String yellow = '\x1B[33m';
  static const String blue = '\x1B[34m';
  static const String magenta = '\x1B[35m';
  static const String cyan = '\x1B[36m';
  static const String white = '\x1B[37m';
  static const String gray = '\x1B[90m';

  static const String bgBlack = '\x1B[40m';
  static const String bgWhite = '\x1B[47m';
  static const String bgGreen = '\x1B[42m';
  static const String bgRed = '\x1B[41m';
  static const String bgYellow = '\x1B[43m';
  static const String bgBlue = '\x1B[44m';
  static const String bgCyan = '\x1B[46m';

  static String color(String text, String ansiCode) =>
      useColors ? '$ansiCode$text$reset' : text;

  static String success(String text) => color(text, green);
  static String error(String text) => color(text, red);
  static String warning(String text) => color(text, yellow);
  static String info(String text) => color(text, cyan);
  static String title(String text) => color(text, bold + magenta);
  static String muted(String text) => color(text, gray);

  /// Prints a stylized header banner.
  static void printHeader(String titleText, {String? subtitle}) {
    final line = '═' * 60;
    stdout.writeln(color('╔$line╗', cyan));
    stdout.writeln(color('║  ${titleText.padRight(56)}  ║', bold + cyan));
    if (subtitle != null) {
      stdout.writeln(color('║  ${subtitle.padRight(56)}  ║', gray));
    }
    stdout.writeln(color('╚$line╝', cyan));
  }

  /// Prints a formatted section title.
  static void printSection(String sectionTitle) {
    stdout.writeln();
    stdout.writeln(color('─── $sectionTitle ─────────────────────────────────────────', bold + yellow));
  }

  /// Renders a [QrMatrix] directly into terminal using Unicode half-block characters
  /// (`▀`, `▄`, `█`, ` `) for crisp, compact rendering.
  static void printQrMatrix(QrMatrix matrix, {int quietZone = 2}) {
    final size = matrix.size;
    final totalSize = size + 2 * quietZone;

    stdout.writeln();
    // Use high-density 2-rows-per-character Unicode block rendering
    for (var y = 0; y < totalSize; y += 2) {
      final sb = StringBuffer();
      for (var x = 0; x < totalSize; x++) {
        final mx = x - quietZone;
        final myTop = y - quietZone;
        final myBottom = y + 1 - quietZone;

        final topDark = (mx >= 0 && mx < size && myTop >= 0 && myTop < size)
            ? matrix.isDark(mx, myTop)
            : false;

        final bottomDark = (mx >= 0 && mx < size && myBottom >= 0 && myBottom < size)
            ? matrix.isDark(mx, myBottom)
            : false;

        // In terminals, foreground colored '▀' with white background:
        if (topDark && bottomDark) {
          sb.write('█'); // both dark
        } else if (topDark && !bottomDark) {
          sb.write('▀'); // top dark, bottom light
        } else if (!topDark && bottomDark) {
          sb.write('▄'); // top light, bottom dark
        } else {
          sb.write(' '); // both light
        }
      }
      stdout.writeln(color(sb.toString(), black + bgWhite));
    }
    stdout.writeln();
  }

  /// Prints a key-value metric row.
  static void printMetric(String label, Object value, {String? unit}) {
    final u = unit != null ? ' $unit' : '';
    stdout.writeln('  ${color(label.padRight(24), gray)} : ${color('$value$u', bold + white)}');
  }

  /// Prints test result row with status icon.
  static void printTestResult(String testName, bool passed, {String? extra}) {
    final status = passed ? color('[ PASS ]', bold + green) : color('[ FAIL ]', bold + red);
    final ext = extra != null ? color(' ($extra)', gray) : '';
    stdout.writeln('  $status ${testName.padRight(50)}$ext');
  }
}
