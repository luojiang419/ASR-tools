import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all loc keys used in lib exist in zh and en localization maps', () {
    final root = Directory.current;
    final localizationFile = File(
      '${root.path}/lib/l10n/app_localizations.dart',
    );
    final localizationContent = localizationFile.readAsStringSync();

    final zhKeys = _extractMapKeys(localizationContent, '_zh');
    final enKeys = _extractMapKeys(localizationContent, '_en');
    final usedKeys = _extractUsedLocalizationKeys(root);

    final missingZh = usedKeys.where((key) => !zhKeys.contains(key)).toList()
      ..sort();
    final missingEn = usedKeys.where((key) => !enKeys.contains(key)).toList()
      ..sort();

    expect(missingZh, isEmpty, reason: 'Missing zh keys: $missingZh');
    expect(missingEn, isEmpty, reason: 'Missing en keys: $missingEn');
  });
}

Set<String> _extractMapKeys(String content, String mapName) {
  final match = RegExp(
    "static const Map<String, String> $mapName = \\{([\\s\\S]*?)\\n  \\};",
  ).firstMatch(content);
  if (match == null) {
    throw StateError('Could not find localization map $mapName');
  }

  return RegExp(
    r"'([^']+)'\s*:",
  ).allMatches(match.group(1)!).map((match) => match.group(1)!).toSet();
}

Set<String> _extractUsedLocalizationKeys(Directory root) {
  final keys = <String>{};
  final tPatternSingle = RegExp(r"loc\.t\('([^']+)'\)");
  final tPatternDouble = RegExp(r'loc\.t\("([^"]+)"\)');
  final pPatternSingle = RegExp(r"locp\('([^']+)'");
  final pPatternDouble = RegExp(r'locp\("([^"]+)"');

  for (final entity in Directory(
    '${root.path}/lib',
  ).listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final content = entity.readAsStringSync();
    keys.addAll(tPatternSingle.allMatches(content).map((m) => m.group(1)!));
    keys.addAll(tPatternDouble.allMatches(content).map((m) => m.group(1)!));
    keys.addAll(pPatternSingle.allMatches(content).map((m) => m.group(1)!));
    keys.addAll(pPatternDouble.allMatches(content).map((m) => m.group(1)!));
  }

  return keys;
}
