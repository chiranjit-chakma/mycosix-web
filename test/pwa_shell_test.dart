import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Locks the installable web shell: the manifest carries everything a browser
/// needs (name, standalone display, 192 + 512 icons with maskable variants,
/// theme), and index.html links it plus the iOS add-to-home-screen meta. These
/// read the files the site is actually served from.
void main() {
  test('manifest.json is installable-shaped', () {
    final raw = File('web/manifest.json').readAsStringSync();
    final m = jsonDecode(raw) as Map<String, dynamic>;

    expect(m['name'], 'MYCOSIX MUSHROOMS');
    expect(m['short_name'], 'MYCOSIX');
    expect(m['start_url'], '.');
    expect(m['display'], 'standalone');
    expect(m['background_color'], isNotEmpty);
    expect(m['theme_color'], '#4A5D44');
    expect(m['description'], isNotEmpty);

    final icons = (m['icons'] as List).cast<Map<String, dynamic>>();
    final sizes = icons.map((i) => i['sizes']).toSet();
    expect(sizes, containsAll(<String>['192x192', '512x512']));
    expect(
      icons.any((i) => i['purpose'] == 'maskable' && i['sizes'] == '512x512'),
      isTrue,
      reason: 'Chrome install surfaces require a maskable 512 icon',
    );
    // Every icon points at a file that actually ships.
    for (final i in icons) {
      final f = File('web/${i['src']}');
      expect(f.existsSync() && f.lengthSync() > 0,
          isTrue,
          reason: 'missing icon asset ${i['src']}');
    }
  });

  test('index.html links the manifest and iOS app chrome', () {
    final html = File('web/index.html').readAsStringSync();
    expect(html, contains('<link rel="manifest" href="manifest.json">'));
    expect(html, contains('<link rel="apple-touch-icon"'));
    expect(html, contains('apple-mobile-web-app-title'));
    expect(html, contains('name="theme-color" content="#4A5D44"'));
    expect(html, contains('content="width=device-width'));
  });
}
