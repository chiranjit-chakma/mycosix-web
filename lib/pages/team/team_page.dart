import 'package:flutter/material.dart';

import '../../config/mx_colors.dart';
import '../../config/mx_config.dart';
import '../../config/mx_type.dart';
import '../../router/routes.dart';
import '../../widgets/editorial.dart';
import '../../widgets/mx_cta.dart';
import '../../widgets/mx_image.dart';
import '../../widgets/page.dart';
import '../../widgets/shell.dart';

class TeamPage extends StatelessWidget {
  const TeamPage({super.key});

  static const _names = <String>[
    'Chandan',
    'Hruday',
    'Preetham',
    'Jashwanth',
    'Neha',
    'Varshini',
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    return MxShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MxPageHero(
            overline: 'The Team',
            title: 'Six students. One grow room.',
            body:
                'We are Chandan, Hruday, Preetham, Jashwanth, Neha and '
                'Varshini — six students who started MYCOSIX together and '
                'grow every harvest as a team.',
            image: 'assets/images/harvest_hands.jpg',
          ),
          MxPage(
            padding: const EdgeInsets.symmetric(vertical: 84),
            child: Column(
              children: [
                MxSectionHeader(
                  overline: 'Who We Are',
                  title: 'The founding six',
                  body:
                      'Each of us brings a different strength — biology, '
                      'business, design, code, care — but we all show up for '
                      'the same reason: to grow something real.',
                ),
                const SizedBox(height: 44),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final cols = constraints.maxWidth >= 1100
                        ? 6
                        : (constraints.maxWidth >= 700
                              ? 3
                              : (constraints.maxWidth >= 420 ? 2 : 1));
                    return GridView.count(
                      crossAxisCount: cols,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 18,
                      crossAxisSpacing: 18,
                      childAspectRatio: cols >= 3 ? 0.86 : 1.1,
                      children: [
                        for (final name in _names) _MemberCard(name: name),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          // Shared principles — honest, no invented credentials.
          Container(
            color: MxColors.forest,
            child: MxPage(
              padding: const EdgeInsets.symmetric(vertical: 72),
              child: Column(
                children: [
                  MxSectionHeader(
                    overline: 'What We Share',
                    title: 'The same three rules',
                    body:
                        'They sound simple. Keeping them, every single day, is '
                        'the actual work.',
                    tone: 'dark',
                  ),
                  const SizedBox(height: 40),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final cols = constraints.maxWidth >= 900 ? 3 : 1;
                      final items = <(IconData, String, String)>[
                        (
                          Icons.spa_outlined,
                          'Fresh first',
                          'Nothing sits around. We harvest, pack and deliver '
                              'as fast as the mushrooms allow.',
                        ),
                        (
                          Icons.eco_outlined,
                          'Clean by default',
                          'A clean room and careful hands — the simple version '
                              'of what we do every single day.',
                        ),
                        (
                          Icons.school_outlined,
                          'Still learning',
                          'We are students. We try, fail, fix and share — '
                              'and we will keep getting better.',
                        ),
                      ];
                      return GridView.count(
                        crossAxisCount: cols,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 18,
                        crossAxisSpacing: 18,
                        childAspectRatio: cols >= 3 ? 1.9 : 2.4,
                        children: [
                          for (final (icon, title, body) in items)
                            Container(
                              padding: const EdgeInsets.all(22),
                              decoration: BoxDecoration(
                                color: MxColors.forest.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(
                                  MxRadius.lg,
                                ),
                                border: Border.all(
                                  color: MxColors.lineDark.withValues(
                                    alpha: 0.5,
                                  ),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    icon,
                                    size: 22,
                                    color: MxColors.mossSoft,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    title,
                                    style: MxType.h4(color: MxColors.cream),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    body,
                                    style: MxType.bodySm(
                                      color: MxColors.cream.withValues(
                                        alpha: 0.78,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          // Farm / journey CTAs + photo strip.
          MxPage(
            padding: const EdgeInsets.symmetric(vertical: 84),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 900;
                    final imgs = <Widget>[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(MxRadius.lg),
                        child: const MxImage(
                          asset: 'assets/images/shelf.jpg',
                          fit: BoxFit.cover,
                          height: 240,
                        ),
                      ),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(MxRadius.lg),
                        child: const MxImage(
                          asset: 'assets/images/moss_close.jpg',
                          fit: BoxFit.cover,
                          height: 240,
                        ),
                      ),
                    ];
                    return wide
                        ? Row(
                            children: [
                              Expanded(child: imgs[0]),
                              const SizedBox(width: 16),
                              Expanded(child: imgs[1]),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              imgs[0],
                              const SizedBox(height: 14),
                              imgs[1],
                            ],
                          );
                  },
                ),
                const SizedBox(height: 40),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SEE THE FARM'.toUpperCase(),
                            style: MxType.overline(),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Where we spend our days',
                            style: MxType.h2(width),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    MxCta(
                      label: 'Visit the Farm',
                      tone: 'ghost',
                      icon: Icons.arrow_forward_rounded,
                      onTap: () => Navigator.of(context).pushNamed(Routes.farm),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Contact CTA band.
          MxPage(
            padding: const EdgeInsets.only(bottom: 84),
            child: Container(
              padding: EdgeInsets.all(width >= 768 ? 48 : 28),
              decoration: BoxDecoration(
                color: MxColors.moss,
                borderRadius: BorderRadius.circular(MxRadius.xl),
              ),
              child: Column(
                children: [
                  Text(
                    'Questions for the team?',
                    textAlign: TextAlign.center,
                    style: MxType.h1(width, color: Colors.white),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Message us on WhatsApp or Instagram — a real person, '
                    'usually covered in mushroom spores, will reply.',
                    textAlign: TextAlign.center,
                    style: MxType.body(
                      width,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(height: 26),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: [
                      MxCta(
                        label: 'WhatsApp ${MxConfig.whatsappDisplay}',
                        tone: 'light',
                        icon: Icons.chat_outlined,
                        onTap: () =>
                            Navigator.of(context).pushNamed(Routes.contact),
                      ),
                      MxCta(
                        label: 'Instagram @${MxConfig.instagramHandle}',
                        tone: 'light',
                        icon: Icons.camera_alt_outlined,
                        onTap: () =>
                            Navigator.of(context).pushNamed(Routes.contact),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MxColors.creamSoft,
        borderRadius: BorderRadius.circular(MxRadius.lg),
        border: Border.all(color: MxColors.line),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 62,
            height: 62,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: MxColors.mossSoft,
              shape: BoxShape.circle,
            ),
            child: Text(
              name.substring(0, 1).toUpperCase(),
              style: const TextStyle(
                fontFamily: 'Fraunces',
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: MxColors.moss,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            name,
            textAlign: TextAlign.center,
            style: MxType.h4(color: MxColors.charcoal),
          ),
          const SizedBox(height: 4),
          Text(
            'MYCOSIX',
            textAlign: TextAlign.center,
            style: MxType.label(color: MxColors.earth),
          ),
        ],
      ),
    );
  }
}
