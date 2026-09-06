import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/mx_colors.dart';
import '../../config/mx_config.dart';
import '../../config/mx_type.dart';
import '../../router/routes.dart';
import '../../services/url_launcher.dart';
import '../../state/products_controller.dart';
import '../../widgets/mx_cta.dart';
import '../../widgets/mx_image.dart';
import '../../widgets/page.dart';
import '../../widgets/product_card.dart';
import '../../widgets/products_scope.dart';
import '../../widgets/shell.dart';

/// The landing page: brand story, featured products, farm and team teasers.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return MxShell(
      child: Column(
        children: const [
          _HeroSection(),
          _FeaturedSection(),
          _StorySection(),
          _VisionSection(),
          _WhySection(),
          _ProcessSection(),
          _ResponsibleSection(),
          _JourneyTeaserSection(),
          _TeamTeaserSection(),
          _SupplySection(),
          _ContactSection(),
          _OrderCtaSection(),
        ],
      ),
    );
  }
}

class _HeroSection extends StatelessWidget {
  const _HeroSection();

  /// Clearance for the floating top bar: a short cream band sits behind the
  /// (transparent-at-rest) bar so the wordmark/nav stay readable, then the
  /// light hero starts below it - same convention as every interior page.
  double _topClearance(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= 1024) return 92.0;
    if (width >= 768) return 88.0;
    return 84.0;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final desktop = width >= 1024;
    final clearance = _topClearance(context);
    final vh = MediaQuery.of(context).size.height;

    // The hero fills the first viewport (clearance + hero body), so the
    // section below it never peeks in at load on desktop or tall tablets.
    // The generous cap only guards against pathological fullscreen heights.
    final minH = desktop
        ? math.min(math.max(600.0, vh - clearance), 1700.0)
        : math.min(math.max(520.0, vh - clearance), 1700.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: clearance,
          child: const ColoredBox(color: MxColors.cream),
        ),
        desktop
            ? _HeroBodyDesktop(minHeight: minH)
            : _HeroBodyCompact(minHeight: minH),
      ],
    );
  }
}

/// The warm-parchment hero art shared by every breakpoint. On desktop the
/// forest-green message sits on the start edge and the real grow-room
/// photograph fills one large rounded card on the other side, both vertically
/// centred against the full first-viewport band.
class _HeroBodyDesktop extends StatelessWidget {
  const _HeroBodyDesktop({required this.minHeight});

  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final hpad = width >= 1440 ? 88.0 : 56.0;
    final avail = width - hpad * 2;
    // The card scales with the hero: as large as the remaining width allows
    // (up to a sane cap), but never so wide it crowds the copy.
    final cardWidth = math.min(math.max(avail * 0.46, 360.0), 720.0);
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [MxColors.cream, MxColors.parchment],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: hpad),
        child: SizedBox(
          height: minHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Expanded(child: _HeroCopy()),
              const SizedBox(width: 56),
              _HeroVisual(width: cardWidth),
            ],
          ),
        ),
      ),
    );
  }
}

/// Phone/tablet hero: message and photograph stacked and centred, so the hero
/// opens full-screen on phones and the photograph reads as one clean card.
class _HeroBodyCompact extends StatelessWidget {
  const _HeroBodyCompact({required this.minHeight});

  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final contentW = math.min(width - 40, 620.0);
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [MxColors.cream, MxColors.parchment],
        ),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 30, 20, 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _HeroCopy(center: true),
              const SizedBox(height: 30),
              SizedBox(
                width: contentW,
                child: _HeroVisual(width: contentW),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroCopy extends StatelessWidget {
  const _HeroCopy({this.center = false});

  /// Centres the message (phones/tablets); otherwise it sits on the start edge
  /// (desktop).
  final bool center;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment:
            center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment:
                center ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              Container(width: 34, height: 2, color: MxColors.moss),
              const SizedBox(width: 12),
              Text(
                'FRESH OYSTER MUSHROOMS',
                style: MxType.overline(color: MxColors.earth),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'GROWN\nDIFFERENT.',
            textAlign: center ? TextAlign.center : TextAlign.start,
            style: MxType.display(width, color: MxColors.forest),
          ),
          const SizedBox(height: 16),
          Text(
            'Fresh by Us. Naturally Good.',
            textAlign: center ? TextAlign.center : TextAlign.start,
            style: MxType.h3(color: MxColors.mossDeep),
          ),
          const SizedBox(height: 14),
          Text(
            'Six students growing more than mushrooms - building experience, '
            'learning, and a better future.',
            textAlign: center ? TextAlign.center : TextAlign.start,
            style: MxType.body(width, color: MxColors.charcoalSoft),
          ),
          const SizedBox(height: 28),
          Wrap(
            alignment: center ? WrapAlignment.center : WrapAlignment.start,
            spacing: 12,
            runSpacing: 12,
            children: [
              MxCta(
                label: 'Shop Fresh Mushrooms',
                tone: 'primary',
                icon: Icons.shopping_bag_outlined,
                onTap: () => Navigator.of(context).pushNamed(Routes.shop),
              ),
              MxCta(
                label: 'Our Farm',
                tone: 'ghost',
                onTap: () => Navigator.of(context).pushNamed(Routes.farm),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The real grow-room photograph as one large rounded card. It keeps the
/// photograph at its natural aspect (a gentle 7:5), so the frame is never
/// awkwardly cropped and nothing reads as empty space.
class _HeroVisual extends StatelessWidget {
  const _HeroVisual({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    // The card is bound to [width]; the rounded frame keeps the photograph at
    // its natural aspect below it, so the card never steals the Row and the
    // copy keeps its share.
    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(36),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.95),
            width: 1.6,
          ),
          boxShadow: [
            BoxShadow(
              color: MxColors.forest.withValues(alpha: 0.12),
              blurRadius: 44,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(34),
          child: AspectRatio(
            aspectRatio: 7 / 5,
            child: MxImage(
              asset: 'assets/images/hero.jpg',
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),
    );
  }
}

class _FeaturedSection extends StatelessWidget {
  const _FeaturedSection();

  @override
  Widget build(BuildContext context) {
    return MxPage(
      padding: mxSectionPadding(context, large: 72, small: 48),
      child: Column(
        children: [
          MxSectionHeader(
            overline: 'The Harvest',
            title: 'Featured Mushrooms',
            body: 'Hand-picked at peak freshness, delivered to your door.',
          ),
          const SizedBox(height: 44),
          const _FeaturedGrid(),
        ],
      ),
    );
  }
}

/// Featured packs. Kicks the catalog load after the first frame and rebuilds
/// whenever [ProductsController] changes — so an admin adding or editing a
/// product updates this section live, with no refresh needed.
class _FeaturedGrid extends StatefulWidget {
  const _FeaturedGrid();

  @override
  State<_FeaturedGrid> createState() => _FeaturedGridState();
}

class _FeaturedGridState extends State<_FeaturedGrid> {
  @override
  void initState() {
    super.initState();
    // First paint is the hero; fetch right after so the section is populated
    // by the time the user scrolls to it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.products()?.fetchAll();
    });
  }

  @override
  Widget build(BuildContext context) {
    final products = context.watch<ProductsController>();
    if (!products.loaded) {
      if (products.error != null) {
        return Text('Could not load products', style: MxType.bodySm());
      }
      return const SizedBox(
        height: 220,
        child: Center(
          child: CircularProgressIndicator(
            color: MxColors.moss,
            strokeWidth: 2.5,
          ),
        ),
      );
    }
    final items = products.products.where((p) => p.available).take(4).toList();
    return ProductGrid(products: items);
  }
}

// ---------------------------------------------------------------------------
// Brand story
// ---------------------------------------------------------------------------

class _StorySection extends StatelessWidget {
  const _StorySection();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final desktop = width >= 1024;

    return Container(
      color: MxColors.creamDeep.withValues(alpha: 0.55),
      child: MxPage(
        padding: mxSectionPadding(context),
        child: desktop
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    flex: 5,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(MxRadius.lg),
                      child: const MxImage(
                        asset: 'assets/images/moss_close.jpg',
                        fit: BoxFit.cover,
                        height: 420,
                      ),
                    ),
                  ),
                  const SizedBox(width: 56),
                  Expanded(
                    flex: 6,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [_StoryCopy()],
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(MxRadius.lg),
                    child: const MxImage(
                      asset: 'assets/images/moss_close.jpg',
                      fit: BoxFit.cover,
                      height: 240,
                    ),
                  ),
                  const SizedBox(height: 28),
                  const _StoryCopy(),
                ],
              ),
      ),
    );
  }
}

class _StoryCopy extends StatelessWidget {
  const _StoryCopy();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('OUR STORY'.toUpperCase(), style: MxType.overline()),
        const SizedBox(height: 14),
        Text('From a single grow room to your table', style: MxType.h1(width)),
        const SizedBox(height: 20),
        Text(
          'MYCOSIX started with a simple question: could six students grow something '
          'real, something the neighbourhood would genuinely love? We built a '
          'climate-controlled grow room, learned the craft of oyster cultivation, '
          'and now we harvest fresh, clean mushrooms every single week.',
          style: MxType.body(width),
        ),
        const SizedBox(height: 14),
        Text(
          'No shortcuts. Just patience, technique and a deep respect '
          'for the small miracle of growing food.',
          style: MxType.body(width),
        ),
        const SizedBox(height: 24),
        MxCta(
          label: 'Read the Journey',
          tone: 'ghost',
          onTap: () => Navigator.of(context).pushNamed(Routes.journey),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Six students / shared vision
// ---------------------------------------------------------------------------

class _VisionSection extends StatelessWidget {
  const _VisionSection();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final desktop = width >= 1024;

    return MxPage(
      padding: mxSectionPadding(context),
      child: Column(
        children: [
          MxSectionHeader(
            overline: 'The Team',
            title: 'Six students. One shared vision.',
            body:
                'We grow mushrooms the way we wish food was grown — fresh, honest and '
                'close to home. Each of us brings something different to the grow room.',
          ),
          const SizedBox(height: 44),
          GridView.count(
            crossAxisCount: desktop ? 6 : (width >= 640 ? 3 : 2),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 20,
            crossAxisSpacing: 20,
            childAspectRatio: 0.9,
            children: [
              for (final name in const [
                'Chandan',
                'Hruday',
                'Preetham',
                'Jashwanth',
                'Neha',
                'Varshini',
              ])
                _VisionCard(name: name),
            ],
          ),
        ],
      ),
    );
  }
}

class _VisionCard extends StatelessWidget {
  const _VisionCard({required this.name});

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
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: MxColors.mossSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.eco_outlined,
              color: MxColors.moss,
              size: 28,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            name,
            style: MxType.h4(color: MxColors.charcoal),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Why oyster mushrooms
// ---------------------------------------------------------------------------

class _WhySection extends StatelessWidget {
  const _WhySection();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final desktop = width >= 1024;

    final items = [
      (
        'Protein',
        'A complete plant protein, with all nine essential amino acids.',
      ),
      (
        'Low calories',
        'Rich and satisfying, yet naturally low in calories and fat.',
      ),
      (
        'Vitamins',
        'Naturally provides B-vitamins, copper, potassium and selenium.',
      ),
      ('Umami', 'A naturally savoury, meaty texture that elevates any dish.'),
    ];

    return Container(
      color: MxColors.forest,
      child: MxPage(
        padding: mxSectionPadding(context),
        child: Column(
          children: [
            MxSectionHeader(
              overline: 'Why Oysters',
              title: 'Good for you. Good for the planet.',
              body:
                  'Oyster mushrooms are a low-impact food — grown on agricultural '
                  'waste with a fraction of the water and land of most crops.',
              tone: 'dark',
            ),
            const SizedBox(height: 44),
            // Fixed row height so a card never clips: at ~170px-wide desktop
            // cells the body wraps to three lines, which needs more than the
            // aspect-ratio cell (1.5) allowed at 1024px.
            GridView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: desktop ? 4 : (width >= 640 ? 2 : 1),
                mainAxisSpacing: 20,
                crossAxisSpacing: 20,
                mainAxisExtent: 172,
              ),
              children: [
                for (final (title, body) in items)
                  _WhyCard(title: title, body: body),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WhyCard extends StatelessWidget {
  const _WhyCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: MxColors.forest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(MxRadius.lg),
        border: Border.all(color: MxColors.lineDark.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.health_and_safety_outlined,
            color: MxColors.mossSoft,
            size: 22,
          ),
          const SizedBox(height: 12),
          Text(title, style: MxType.h4(color: MxColors.cream)),
          const SizedBox(height: 8),
          Text(
            body,
            style: MxType.bodySm(color: MxColors.cream.withValues(alpha: 0.78)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Spore-to-harvest process
// ---------------------------------------------------------------------------

class _ProcessSection extends StatelessWidget {
  const _ProcessSection();

  @override
  Widget build(BuildContext context) {
    final steps = [
      (
        '01',
        'Spawn & substrate',
        'We prepare sterilised straw and sawdust, then seed it with high-quality oyster spawn.',
      ),
      (
        '02',
        'Climate control',
        'Humidity, airflow and temperature are tuned for each growth stage — the room does the work.',
      ),
      (
        '03',
        'Pinning',
        'Tiny mushroom pins appear within days. This is when the magic happens.',
      ),
      (
        '04',
        'Harvest',
        'Clusters are picked by hand at peak freshness, packed the same day.',
      ),
    ];

    return MxPage(
      padding: mxSectionPadding(context),
      child: Column(
        children: [
          MxSectionHeader(
            overline: 'The Process',
            title: 'Spore to harvest',
            body:
                'A quiet, patient craft — from sterile substrate to a tray of fresh '
                'oysters in about three weeks.',
          ),
          const SizedBox(height: 44),
          LayoutBuilder(
            builder: (context, constraints) {
              final horizontal = constraints.maxWidth >= 900;
              final cards = <Widget>[
                for (final s in steps)
                  _StepCard(number: s.$1, title: s.$2, body: s.$3),
              ];
              if (horizontal) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < cards.length; i++) ...[
                      Expanded(child: cards[i]),
                      if (i < cards.length - 1)
                        const Padding(
                          padding: EdgeInsets.only(top: 40),
                          child: SizedBox(
                            width: 20,
                            child: Divider(color: MxColors.line, height: 1),
                          ),
                        ),
                    ],
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < cards.length; i++) ...[
                    cards[i],
                    if (i < cards.length - 1)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Center(
                          child: SizedBox(
                            width: 1.5,
                            height: 24,
                            child: ColoredBox(color: MxColors.line),
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
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.number,
    required this.title,
    required this.body,
  });

  final String number;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MxColors.creamSoft,
        borderRadius: BorderRadius.circular(MxRadius.lg),
        border: Border.all(color: MxColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(number, style: MxType.displayAlt(width, color: MxColors.earth)),
          const SizedBox(height: 12),
          Text(title, style: MxType.h4(color: MxColors.charcoal)),
          const SizedBox(height: 8),
          Text(body, style: MxType.bodySm(color: MxColors.charcoalSoft)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Responsible cultivation
// ---------------------------------------------------------------------------

class _ResponsibleSection extends StatelessWidget {
  const _ResponsibleSection();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final desktop = width >= 1024;

    return Container(
      color: MxColors.mossTint,
      child: MxPage(
        padding: mxSectionPadding(context),
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
                          'RESPONSIBLE CULTIVATION'.toUpperCase(),
                          style: MxType.overline(),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Grown clean. Grown kind.',
                          style: MxType.h1(width),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Our grow room runs on agricultural waste — straw and sawdust '
                          'that would otherwise be burned. After every harvest we compost '
                          'the spent substrate and start the next batch clean.',
                          style: MxType.body(width),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Growing mushrooms is mostly control — the right humidity, '
                          'steady airflow and careful attention at every stage of the crop.',
                          style: MxType.body(width),
                        ),
                        const SizedBox(height: 24),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: const [
                            _Pill(label: 'Compost, not waste'),
                            _Pill(label: 'Low water use'),
                            _Pill(label: 'Climate controlled'),
                          ],
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
                        asset: 'assets/images/shelf.jpg',
                        fit: BoxFit.cover,
                        height: 380,
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(MxRadius.lg),
                    child: const MxImage(
                      asset: 'assets/images/shelf.jpg',
                      fit: BoxFit.cover,
                      height: 220,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'RESPONSIBLE CULTIVATION'.toUpperCase(),
                    style: MxType.overline(),
                  ),
                  const SizedBox(height: 14),
                  Text('Grown clean. Grown kind.', style: MxType.h1(width)),
                  const SizedBox(height: 20),
                  Text(
                    'Our grow room runs on agricultural waste — straw and sawdust '
                    'that would otherwise be burned. After every harvest we compost '
                    'the spent substrate and start the next batch clean.',
                    style: MxType.body(width),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Growing mushrooms is mostly control — the right humidity, '
                    'steady airflow and careful attention at every stage of the crop.',
                    style: MxType.body(width),
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: const [
                      _Pill(label: 'Compost, not waste'),
                      _Pill(label: 'Low water use'),
                      _Pill(label: 'Climate controlled'),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: MxColors.moss.withValues(alpha: 0.3)),
      ),
      child: Text(label, style: MxType.label(color: MxColors.moss)),
    );
  }
}

// ---------------------------------------------------------------------------
// Journey teaser
// ---------------------------------------------------------------------------

class _JourneyTeaserSection extends StatelessWidget {
  const _JourneyTeaserSection();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    return MxPage(
      padding: mxSectionPadding(context),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= 900;
          final copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('THE JOURNEY'.toUpperCase(), style: MxType.overline()),
              const SizedBox(height: 14),
              Text(
                'From classroom idea to a growing farm',
                style: MxType.h1(width),
              ),
              const SizedBox(height: 20),
              Text(
                'It began as a college project. It became something bigger than '
                'we expected — a real business, a real harvest, and a real reason '
                'to show up every morning.',
                style: MxType.body(width),
              ),
              const SizedBox(height: 24),
              MxCta(
                label: 'Follow the Journey',
                tone: 'ghost',
                onTap: () => Navigator.of(context).pushNamed(Routes.journey),
              ),
            ],
          );
          final img = ClipRRect(
            borderRadius: BorderRadius.circular(MxRadius.lg),
            child: const MxImage(
              asset: 'assets/images/harvest_hands.jpg',
              fit: BoxFit.cover,
              height: 240,
            ),
          );
          if (desktop) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: copy),
                const SizedBox(width: 40),
                SizedBox(width: 300, child: img),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [img, const SizedBox(height: 26), copy],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Team teaser
// ---------------------------------------------------------------------------

class _TeamTeaserSection extends StatelessWidget {
  const _TeamTeaserSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: MxColors.creamDeep.withValues(alpha: 0.45),
      child: MxPage(
        padding: mxSectionPadding(context),
        child: Column(
          children: [
            MxSectionHeader(
              overline: 'The Team',
              title: 'Meet the growers',
              body:
                  'Chandan, Hruday, Preetham, Jashwanth, Neha and Varshini — '
                  'six students, one grow room.',
            ),
            const SizedBox(height: 36),
            // A wrap so all six faces render on phones too (a fixed Row only
            // fitted three on small screens).
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              runSpacing: 12,
              children: const [
                _Avatar(name: 'Chandan'),
                _Avatar(name: 'Hruday'),
                _Avatar(name: 'Preetham'),
                _Avatar(name: 'Jashwanth'),
                _Avatar(name: 'Neha'),
                _Avatar(name: 'Varshini'),
              ],
            ),
            const SizedBox(height: 28),
            MxCta(
              label: 'About the Team',
              tone: 'ghost',
              onTap: () => Navigator.of(context).pushNamed(Routes.team),
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: const BoxDecoration(
              color: MxColors.mossSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.person_outline,
              color: MxColors.moss,
              size: 30,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            name,
            style: MxType.bodySm(
              color: MxColors.charcoal,
              weight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Retail / restaurant / bulk supply
// ---------------------------------------------------------------------------

class _SupplySection extends StatelessWidget {
  const _SupplySection();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final desktop = width >= 1024;

    final items = [
      (
        'Retail',
        'Order fresh oysters in 250 g, 500 g or 1 kg packs for home delivery.',
      ),
      (
        'Restaurants',
        'Consistent weekly supply for kitchens that care about fresh, local produce.',
      ),
      (
        'Bulk supply',
        'Volume orders for events, caterers and resellers — harvest to order.',
      ),
    ];

    return MxPage(
      padding: mxSectionPadding(context),
      child: Column(
        children: [
          MxSectionHeader(
            overline: 'Supply',
            title: 'From our farm to your kitchen',
            body: 'Home delivery, restaurant supply and bulk orders — we work with all of them.',
          ),
          const SizedBox(height: 44),
          GridView.count(
            crossAxisCount: desktop ? 3 : 1,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 20,
            crossAxisSpacing: 20,
            childAspectRatio: desktop ? 2.0 : 2.2,
            children: [
              for (final (title, body) in items)
                Container(
                  padding: const EdgeInsets.all(26),
                  decoration: BoxDecoration(
                    color: MxColors.creamSoft,
                    borderRadius: BorderRadius.circular(MxRadius.lg),
                    border: Border.all(color: MxColors.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(title, style: MxType.h3(color: MxColors.forest)),
                      const SizedBox(height: 10),
                      Text(
                        body,
                        style: MxType.bodySm(color: MxColors.charcoalSoft),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 28),
          MxCta(
            label: 'Talk to us about supply',
            tone: 'ghost',
            onTap: () => Navigator.of(context).pushNamed(Routes.contact),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Contact
// ---------------------------------------------------------------------------

class _ContactSection extends StatelessWidget {
  const _ContactSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: MxColors.forest,
      child: MxPage(
        padding: mxSectionPadding(context),
        child: Column(
          children: [
            MxSectionHeader(
              overline: 'Contact',
              title: 'Say hello',
              body: 'Questions about an order, the farm, or bulk supply? We are happy to help.',
              tone: 'dark',
            ),
            const SizedBox(height: 36),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                _ContactPill(
                  icon: Icons.chat_outlined,
                  label: 'WhatsApp · ${MxConfig.whatsappDisplay}',
                  onTap: () => UrlLauncher.open(
                    'https://wa.me/${MxConfig.whatsappNumber}',
                  ),
                ),
                _ContactPill(
                  icon: Icons.camera_alt_outlined,
                  label: 'Instagram · @${MxConfig.instagramHandle}',
                  onTap: () => UrlLauncher.open(MxConfig.instagramUrl),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactPill extends StatelessWidget {
  const _ContactPill({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: MxColors.forest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: MxColors.lineDark.withValues(alpha: 0.6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: MxColors.mossSoft),
            const SizedBox(width: 8),
            Text(
              label,
              style: MxType.bodySm(
                color: MxColors.cream.withValues(alpha: 0.9),
                weight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Final order CTA
// ---------------------------------------------------------------------------

class _OrderCtaSection extends StatelessWidget {
  const _OrderCtaSection();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    return MxPage(
      padding: mxSectionPadding(context),
      child: Container(
        padding: EdgeInsets.all(width >= 768 ? 56 : 32),
        decoration: BoxDecoration(
          color: MxColors.moss,
          borderRadius: BorderRadius.circular(MxRadius.xl),
        ),
        child: Column(
          children: [
            Text(
              'Ready to taste the difference?',
              textAlign: TextAlign.center,
              style: MxType.h1(width, color: Colors.white),
            ),
            const SizedBox(height: 16),
            Text(
              'Order fresh oyster mushrooms today — harvested this week, delivered to your door.',
              textAlign: TextAlign.center,
              style: MxType.body(
                width,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(height: 28),
            MxCta(
              label: 'Order Fresh Mushrooms',
              tone: 'light',
              icon: Icons.shopping_bag_outlined,
              onTap: () => Navigator.of(context).pushNamed(Routes.shop),
            ),
          ],
        ),
      ),
    );
  }
}
