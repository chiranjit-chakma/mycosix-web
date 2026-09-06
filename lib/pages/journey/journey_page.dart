import 'package:flutter/material.dart';

import '../../config/mx_colors.dart';
import '../../config/mx_type.dart';
import '../../router/routes.dart';
import '../../widgets/editorial.dart';
import '../../widgets/mx_cta.dart';
import '../../widgets/mx_image.dart';
import '../../widgets/page.dart';
import '../../widgets/shell.dart';

class JourneyPage extends StatelessWidget {
  const JourneyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final desktop = width >= 1024;

    return MxShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MxPageHero(
            overline: 'Our Journey',
            title: 'Six students, one grow room',
            body:
                'How a college idea about mushrooms became a real harvest, a '
                'real business and a reason to show up early every morning.',
            image: 'assets/images/journey_new.jpg',
          ),
          MxPage(
            padding: const EdgeInsets.symmetric(vertical: 84),
            child: Column(
              children: [
                MxSectionHeader(
                  overline: 'The Story So Far',
                  title: 'From classroom question to weekly harvest',
                  body:
                      'We keep this page honest — the journey is still being '
                      'written, one flush at a time.',
                ),
                const SizedBox(height: 52),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final horizontal = constraints.maxWidth >= 900;
                    final milestones = <_Milestone>[
                      _Milestone(
                        step: '01',
                        title: 'The question',
                        body:
                            'It started as a college project: could a few '
                            'students grow real food, in the city, without a '
                            'farm? Oyster mushrooms kept coming up — fast '
                            'growing, low resource use, genuinely wanted.',
                      ),
                      _Milestone(
                        step: '02',
                        title: 'Learning the craft',
                        body:
                            'We read, watched and experimented. Spawn, '
                            'substrate, humidity, airflow — every variable was '
                            'a lesson, and most lessons started with a failed '
                            'batch.',
                      ),
                      _Milestone(
                        step: '03',
                        title: 'Building the room',
                        body:
                            'Shelves, misting, a little climate control — we '
                            'turned a small space into a grow room and learned '
                            'to keep it clean and consistent.',
                      ),
                      _Milestone(
                        step: '04',
                        title: 'First real harvest',
                        body:
                            'The first clusters that looked like the ones in '
                            'the books felt like a small miracle. We have been '
                            'growing weekly since.',
                      ),
                      _Milestone(
                        step: '05',
                        title: 'Today',
                        body:
                            'MYCOSIX is six of us — Chandan, Hruday, Preetham, '
                            'Jashwanth, Neha and Varshini — growing, packing '
                            'and delivering fresh oyster mushrooms, and '
                            'learning what it takes to run something real.',
                      ),
                    ];

                    if (horizontal) {
                      return SizedBox(
                        height: 380,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var i = 0; i < milestones.length; i++) ...[
                              Expanded(child: milestones[i]),
                              if (i < milestones.length - 1)
                                Padding(
                                  padding: const EdgeInsets.only(top: 34),
                                  child: Container(
                                    width: 22,
                                    height: 1.5,
                                    color: MxColors.line,
                                  ),
                                ),
                            ],
                          ],
                        ),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < milestones.length; i++) ...[
                          milestones[i],
                          if (i < milestones.length - 1)
                            const Center(
                              child: SizedBox(
                                height: 24,
                                child: VerticalDivider(
                                  width: 1,
                                  thickness: 1.5,
                                  color: MxColors.line,
                                ),
                              ),
                            ),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          // Image + short feature
          MxPage(
            padding: const EdgeInsets.only(bottom: 84),
            child: desktop
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        flex: 6,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'WHAT DRIVES US'.toUpperCase(),
                              style: MxType.overline(),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'More than mushrooms',
                              style: MxType.h1(width),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              'We are students first. MYCOSIX is where we put '
                              'what we learn into practice — biology, business, '
                              'design, patience. Every harvest teaches us '
                              'something the classroom cannot.',
                              style: MxType.body(width),
                            ),
                            const SizedBox(height: 24),
                            MxCta(
                              label: 'Meet the Team',
                              tone: 'ghost',
                              onTap: () =>
                                  Navigator.of(context).pushNamed(Routes.team),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 56),
                      Expanded(
                        flex: 5,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(MxRadius.lg),
                          child: const MxImage(
                            asset: 'assets/images/dark_portrait.jpg',
                            fit: BoxFit.cover,
                            height: 360,
                          ),
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(MxRadius.lg),
                          child: const MxImage(
                            asset: 'assets/images/dark_portrait.jpg',
                            fit: BoxFit.cover,
                            height: 240,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'WHAT DRIVES US'.toUpperCase(),
                        style: MxType.overline(),
                      ),
                      const SizedBox(height: 14),
                      Text('More than mushrooms', style: MxType.h1(width)),
                      const SizedBox(height: 18),
                      Text(
                        'We are students first. MYCOSIX is where we put what we '
                        'learn into practice — biology, business, design, '
                        'patience. Every harvest teaches us something the '
                        'classroom cannot.',
                        style: MxType.body(width),
                      ),
                      const SizedBox(height: 24),
                      MxCta(
                        label: 'Meet the Team',
                        tone: 'ghost',
                        onTap: () =>
                            Navigator.of(context).pushNamed(Routes.team),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _Milestone extends StatelessWidget {
  const _Milestone({
    required this.step,
    required this.title,
    required this.body,
  });

  final String step;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(step, style: MxType.displayAlt(width, color: MxColors.earth)),
        const SizedBox(height: 12),
        Text(title, style: MxType.h4(color: MxColors.charcoal)),
        const SizedBox(height: 8),
        Text(body, style: MxType.bodySm(color: MxColors.charcoalSoft)),
      ],
    );
    // In a vertical layout milestones stretch full width; in the horizontal
    // rail they share the row equally via the outer Expanded.
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: MxColors.creamSoft,
            borderRadius: BorderRadius.circular(MxRadius.lg),
            border: Border.all(color: MxColors.line),
          ),
          child: text,
        );
      },
    );
  }
}
