import 'package:flutter/material.dart';

import '../config/mx_colors.dart';
import '../config/mx_type.dart';
import 'page.dart';
import 'shell.dart';

/// Shared layout for legal documents (privacy, terms).
class MxLegalPage extends StatelessWidget {
  const MxLegalPage({
    super.key,
    required this.overline,
    required this.title,
    required this.updated,
    required this.sections,
  });

  final String overline;
  final String title;
  final String updated;

  /// Each section: heading + list of paragraphs.
  final List<(String, List<String>)> sections;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    return MxShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 120),
          MxPage(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 30, height: 1.5, color: MxColors.earth),
                    const SizedBox(width: 12),
                    Text(overline.toUpperCase(), style: MxType.overline()),
                  ],
                ),
                const SizedBox(height: 16),
                Text(title, style: MxType.h1(width)),
                const SizedBox(height: 12),
                Text(
                  'Last updated: $updated',
                  style: MxType.bodySm(color: MxColors.stone),
                ),
              ],
            ),
          ),
          const SizedBox(height: 36),
          MxPage(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var s = 0; s < sections.length; s++) ...[
                  if (s > 0) const SizedBox(height: 44),
                  _LegalSection(heading: sections[s].$1, paragraphs: sections[s].$2),
                ],
              ],
            ),
          ),
          const SizedBox(height: 72),
        ],
      ),
    );
  }
}

class _LegalSection extends StatelessWidget {
  const _LegalSection({required this.heading, required this.paragraphs});

  final String heading;
  final List<String> paragraphs;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(heading, style: MxType.h3(color: MxColors.charcoal)),
        const SizedBox(height: 14),
        for (final p in paragraphs) ...[
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Text(p, style: MxType.body(width)),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}
