import 'package:flutter_test/flutter_test.dart';
import 'package:mycosix/widgets/live_lead.dart';

/// Content-override fallback semantics (shared by the Farm/Journey hero and
/// editorial widgets). A blank or missing field must keep the bundled copy —
/// this is what makes an empty `content` collection (or Firebase being off)
/// render byte-identically to the pre-edit site.
void main() {
  group('contentPick', () {
    test('missing document keeps the bundled value', () {
      expect(contentPick(null, 'title', 'Bundled'), 'Bundled');
      expect(contentPick(const {}, 'title', 'Bundled'), 'Bundled');
    });

    test('blank or whitespace field keeps the bundled value', () {
      expect(
          contentPick({'title': ''}, 'title', 'Bundled'), 'Bundled');
      expect(contentPick({'title': '   '}, 'title', 'Bundled'), 'Bundled');
    });

    test('non-string value keeps the bundled value', () {
      expect(
          contentPick({'title': 42}, 'title', 'Bundled'), 'Bundled');
    });

    test('present value is trimmed and used', () {
      expect(
          contentPick({'title': '  Edited title  '}, 'title', 'Bundled'),
          'Edited title');
    });

    test('only the edited field changes; the rest stay bundled', () {
      const m = <String, dynamic>{'body': 'New body'};
      expect(contentPick(m, 'title', 'Bundled title'), 'Bundled title');
      expect(contentPick(m, 'body', 'Bundled body'), 'New body');
    });
  });

  group('contentPickOpt', () {
    test('missing/blank keeps the optional fallback (may be null)', () {
      expect(contentPickOpt(null, 'bodyExtra', null), isNull);
      expect(
          contentPickOpt(const {'bodyExtra': ''}, 'bodyExtra', 'x'), 'x');
    });

    test('present value is trimmed and used', () {
      expect(
          contentPickOpt({'bodyExtra': '  extra  '}, 'bodyExtra', null),
          'extra');
    });
  });
}
