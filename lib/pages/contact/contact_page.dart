import 'package:flutter/material.dart';

import '../../config/mx_colors.dart';
import '../../config/mx_config.dart';
import '../../config/mx_type.dart';
import '../../router/routes.dart';
import '../../services/url_launcher.dart';
import '../../widgets/editorial.dart';
import '../../widgets/mx_cta.dart';
import '../../widgets/page.dart';
import '../../widgets/shell.dart';

class ContactPage extends StatelessWidget {
  const ContactPage({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final desktop = width >= 1024;

    return MxShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MxPageHero(
            overline: 'Contact',
            title: 'Say hello',
            body:
                'Order questions, bulk supply, or just want to talk mushrooms? '
                'WhatsApp and Instagram are the fastest ways to reach us.',
            image: 'assets/images/packaging.jpg',
          ),
          MxPage(
            padding: const EdgeInsets.symmetric(vertical: 84),
            child: Column(
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 820;
                    final cards = <Widget>[
                      _ContactCard(
                        icon: Icons.chat_bubble_rounded,
                        accent: const Color(0xFF128C4A),
                        title: 'WhatsApp',
                        line: MxConfig.whatsappDisplay,
                        subtitle:
                            'Best for orders and quick questions. Tap to open a chat.',
                        actionLabel: 'Open WhatsApp',
                        onTap: () => UrlLauncher.open(
                          'https://wa.me/${MxConfig.whatsappNumber}',
                        ),
                      ),
                      _ContactCard(
                        icon: Icons.camera_alt_rounded,
                        accent: MxColors.earth,
                        title: 'Instagram',
                        line: '@${MxConfig.instagramHandle}',
                        subtitle:
                            'Farm updates, harvests and behind the scenes. DM us there.',
                        actionLabel: 'Visit Instagram',
                        onTap: () => UrlLauncher.open(MxConfig.instagramUrl),
                      ),
                    ];
                    return wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (var i = 0; i < cards.length; i++) ...[
                                Expanded(child: cards[i]),
                                if (i < cards.length - 1)
                                  const SizedBox(width: 20),
                              ],
                            ],
                          )
                        : Column(
                            children: [
                              for (var i = 0; i < cards.length; i++) ...[
                                cards[i],
                                if (i < cards.length - 1)
                                  const SizedBox(height: 16),
                              ],
                            ],
                          );
                  },
                ),
              ],
            ),
          ),
          // For orders: point to checkout; for supply: invite chat.
          Container(
            color: MxColors.creamDeep.withValues(alpha: 0.5),
            child: MxPage(
              padding: const EdgeInsets.symmetric(vertical: 72),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('PLACE AN ORDER'.toUpperCase(), style: MxType.overline()),
                  const SizedBox(height: 14),
                  Text('Ordering is easy', style: MxType.h1(width)),
                  const SizedBox(height: 20),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 900;
                      final steps = <(IconData, String, String)>[
                        (Icons.storefront_outlined, '1 · Add to cart',
                            'Pick your packs in the shop — fresh, dried or preserved.'),
                        (Icons.place_outlined, '2 · Set delivery location',
                            'Checkout asks for your location pin, name and phone.'),
                        (Icons.chat_bubble_outline_rounded, '3 · Send on WhatsApp',
                            'We prepare your order message — you review and press Send.'),
                      ];

                      Widget stepCard((IconData, String, String) s) {
                        final (icon, title, body) = s;
                        return Container(
                          padding: const EdgeInsets.all(22),
                          decoration: BoxDecoration(
                            color: MxColors.creamSoft,
                            borderRadius: BorderRadius.circular(MxRadius.lg),
                            border: Border.all(color: MxColors.line),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(icon, size: 22, color: MxColors.moss),
                              const SizedBox(height: 12),
                              Text(title,
                                  style: MxType.h4(color: MxColors.charcoal)),
                              const SizedBox(height: 8),
                              Text(body,
                                  style: MxType.bodySm(
                                      color: MxColors.charcoalSoft)),
                            ],
                          ),
                        );
                      }

                      if (wide) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var i = 0; i < steps.length; i++) ...[
                              Expanded(child: stepCard(steps[i])),
                              if (i < steps.length - 1)
                                const SizedBox(width: 18),
                            ],
                          ],
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < steps.length; i++) ...[
                            stepCard(steps[i]),
                            if (i < steps.length - 1)
                              const SizedBox(height: 14),
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 30),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('For retail orders',
                                style: MxType.h4(color: MxColors.charcoal)),
                            const SizedBox(height: 8),
                            Text(
                              'Use the shop and checkout — the whole flow is ready.',
                              style: MxType.bodySm(color: MxColors.charcoalSoft),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      MxCta(
                        label: 'Go to Shop',
                        tone: 'primary',
                        icon: Icons.shopping_bag_outlined,
                        onTap: () =>
                            Navigator.of(context).pushNamed(Routes.shop),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Restaurant & bulk supply.
          MxPage(
            padding: const EdgeInsets.symmetric(vertical: 84),
            child: desktop
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        flex: 6,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('FOR BUSINESS'.toUpperCase(),
                                style: MxType.overline()),
                            const SizedBox(height: 14),
                            Text('Restaurant & bulk supply',
                                style: MxType.h1(width)),
                            const SizedBox(height: 18),
                            Text(
                              'Kitchens, caterers, events and resellers — if '
                              'you need a steady supply of fresh oyster '
                              'mushrooms, talk to us directly on WhatsApp. '
                              'Tell us your volume and schedule, and we will '
                              'figure out the rest.',
                              style: MxType.body(width),
                            ),
                            const SizedBox(height: 24),
                            MxCta(
                              label: 'Message us on WhatsApp',
                              tone: 'ghost',
                              icon: Icons.chat_outlined,
                              onTap: () => UrlLauncher.open(
                                'https://wa.me/${MxConfig.whatsappNumber}',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 56),
                      Expanded(
                        flex: 5,
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: MxColors.forest,
                            borderRadius: BorderRadius.circular(MxRadius.lg),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('BULK SUPPLY'.toUpperCase(),
                                  style: MxType.label(
                                      color: MxColors.mossSoft)),
                              const SizedBox(height: 12),
                              Text(
                                'Fresh oyster mushrooms',
                                style: MxType.h2(width,
                                    color: MxColors.cream),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Harvested to order · packed the same day · '
                                'consistency from a grow room we control.',
                                style: MxType.bodySm(
                                    color:
                                        MxColors.cream.withValues(alpha: 0.78)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('FOR BUSINESS'.toUpperCase(),
                          style: MxType.overline()),
                      const SizedBox(height: 14),
                      Text('Restaurant & bulk supply',
                          style: MxType.h1(width)),
                      const SizedBox(height: 18),
                      Text(
                        'Kitchens, caterers, events and resellers — if you '
                        'need a steady supply of fresh oyster mushrooms, talk '
                        'to us directly on WhatsApp. Tell us your volume and '
                        'schedule, and we will figure out the rest.',
                        style: MxType.body(width),
                      ),
                      const SizedBox(height: 24),
                      MxCta(
                        label: 'Message us on WhatsApp',
                        tone: 'ghost',
                        icon: Icons.chat_outlined,
                        onTap: () => UrlLauncher.open(
                          'https://wa.me/${MxConfig.whatsappNumber}',
                        ),
                      ),
                      const SizedBox(height: 32),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: MxColors.forest,
                          borderRadius: BorderRadius.circular(MxRadius.lg),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('BULK SUPPLY'.toUpperCase(),
                                style:
                                    MxType.label(color: MxColors.mossSoft)),
                            const SizedBox(height: 12),
                            Text('Fresh oyster mushrooms',
                                style:
                                    MxType.h2(width, color: MxColors.cream)),
                            const SizedBox(height: 8),
                            Text(
                              'Harvested to order · packed the same day · '
                              'consistency from a grow room we control.',
                              style: MxType.bodySm(
                                  color:
                                      MxColors.cream.withValues(alpha: 0.78)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({
    required this.icon,
    required this.accent,
    required this.title,
    required this.line,
    required this.subtitle,
    required this.actionLabel,
    required this.onTap,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String line;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: MxColors.creamSoft,
        borderRadius: BorderRadius.circular(MxRadius.lg),
        border: Border.all(color: MxColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 22, color: accent),
          ),
          const SizedBox(height: 18),
          Text(title, style: MxType.h3(color: MxColors.charcoal)),
          const SizedBox(height: 4),
          Text(line, style: MxType.h4(color: MxColors.moss)),
          const SizedBox(height: 10),
          Text(subtitle, style: MxType.bodySm(color: MxColors.charcoalSoft)),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: MxCta(
              label: actionLabel,
              tone: 'ghost',
              icon: Icons.open_in_new_rounded,
              onTap: onTap,
            ),
          ),
        ],
      ),
    );
  }
}
