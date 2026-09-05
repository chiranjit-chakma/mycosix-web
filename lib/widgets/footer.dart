import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/mx_colors.dart';
import '../config/mx_config.dart';
import '../config/mx_type.dart';
import '../router/routes.dart';
import '../services/url_launcher.dart';
import '../state/cart_controller.dart';
import 'mx_image.dart';

class MxFooter extends StatelessWidget {
  const MxFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final gutter = width >= 1024 ? 56.0 : 20.0;
    final cart = context.watch<CartController>();

    return Container(
      width: double.infinity,
      color: MxColors.forest,
      padding: EdgeInsets.fromLTRB(gutter, 64, gutter, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The real MYCOSIX brand seal, on a cream tile.
              ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: const MxImage(
                  asset: 'assets/brand/mycosix-tile.webp',
                  width: 132,
                  height: 132,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'MYCOSIX MUSHROOMS',
                        style: TextStyle(
                          fontFamily: 'Fraunces',
                          fontSize: 21,
                          height: 1.1,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.08,
                          color: MxColors.cream,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        MxConfig.tagline,
                        style: MxType.bodySm(
                          color: MxColors.cream.withValues(alpha: 0.72),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (width >= 768)
                _FooterLink(
                  label: 'Instagram',
                  onTap: () => UrlLauncher.open(MxConfig.instagramUrl),
                )
              else
                const SizedBox.shrink(),
            ],
          ),
          const SizedBox(height: 36),
          LayoutBuilder(
            builder: (context, constraints) {
              final cols = constraints.maxWidth >= 900
                  ? 4
                  : (constraints.maxWidth >= 560 ? 3 : 2);
              final rows = <Widget>[
                _FooterColumn(
                  title: 'Shop',
                  links: const [
                    ('Fresh Oyster', Routes.shop),
                    ('Dried & Powder', Routes.shop),
                    ('Gift Packs', Routes.shop),
                  ],
                ),
                _FooterColumn(
                  title: 'Explore',
                  links: const [
                    ('Our Farm', Routes.farm),
                    ('Our Journey', Routes.journey),
                    ('The Team', Routes.team),
                  ],
                ),
                _FooterColumn(
                  title: 'Company',
                  links: const [
                    ('Contact', Routes.contact),
                    ('Privacy', Routes.privacy),
                    ('Terms', Routes.terms),
                  ],
                ),
                _FooterColumn(
                  title: 'Order',
                  links: const [
                    ('Cart', Routes.cart),
                    ('Checkout', Routes.checkout),
                    ('WhatsApp', Routes.contact),
                  ],
                ),
              ];
              // A column (title + up to three links) is ~122 px tall. Using a
              // fixed row height instead of an aspect ratio guarantees it fits
              // at every breakpoint - an aspect-ratio cell was shorter than
              // the text on phones, tablets and small laptops and overflowed.
              return GridView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  crossAxisSpacing: 24,
                  mainAxisSpacing: 8,
                  mainAxisExtent: 140,
                ),
                children: rows,
              );
            },
          ),
          const SizedBox(height: 48),
          const Divider(color: MxColors.lineDark),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  'Fresh by Us. Naturally Good.\nSix students growing more than mushrooms.',
                  style: MxType.bodySm(
                    color: MxColors.cream.withValues(alpha: 0.7),
                  ),
                ),
              ),
              if (width >= 560)
                Text(
                  '© ${DateTime.now().year} MYCOSIX MUSHROOMS',
                  style: MxType.bodyXs(
                    color: MxColors.cream.withValues(alpha: 0.55),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${MxConfig.serviceArea} · ${MxConfig.whatsappDisplay}',
                  style: MxType.bodyXs(
                    color: MxColors.cream.withValues(alpha: 0.55),
                  ),
                ),
              ),
              if (cart.totalQuantity > 0)
                Text(
                  '${cart.totalQuantity} item${cart.totalQuantity == 1 ? '' : 's'} in cart',
                  style: MxType.bodyXs(
                    color: MxColors.cream.withValues(alpha: 0.55),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FooterColumn extends StatelessWidget {
  const _FooterColumn({required this.title, required this.links});

  final String title;
  final List<(String, String)> links;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: MxType.label(color: MxColors.mossSoft.withValues(alpha: 0.9)),
        ),
        const SizedBox(height: 12),
        for (final (label, route) in links)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: () => Navigator.of(context).pushNamed(route),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  label,
                  style: MxType.bodySm(
                    color: MxColors.cream.withValues(alpha: 0.78),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _FooterLink extends StatelessWidget {
  const _FooterLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        child: Text(label, style: MxType.label(color: MxColors.mossSoft)),
      ),
    );
  }
}
