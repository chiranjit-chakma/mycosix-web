import 'package:flutter/material.dart';

import '../../config/mx_config.dart';
import '../../widgets/legal_page.dart';

class TermsPage extends StatelessWidget {
  const TermsPage({super.key});

  static const _sections = <(String, List<String>)>[
    (
      'Using this website',
      [
        'This website lets you browse MYCOSIX mushrooms and prepare an order '
        'that is sent to us on WhatsApp. By using the site you agree to these '
        'terms. MYCOSIX is run by six students, and we keep things simple and '
        'honest.',
      ],
    ),
    (
      'Placing an order',
      [
        'Adding items to your cart does not place an order. An order is placed '
        'when you send us your completed order message on WhatsApp and we '
        'confirm it there. Until we confirm availability, nothing is reserved.',
      ],
    ),
    (
      'Prices, weights and availability',
      [
        'Prices are shown in Indian rupees on the product pages and at '
        'checkout, and include the pack weight listed for each product. Fresh '
        'mushrooms are a harvest crop: availability changes with each '
        'harvest, and an item shown as unavailable cannot be ordered. We may '
        'need to confirm the exact weight or quantity of a fresh pack with '
        'you on WhatsApp before delivery.',
      ],
    ),
    (
      'Delivery',
      [
        'The delivery fee shown at checkout is added to your total. Delivery '
        'timing and the exact delivery area are arranged on WhatsApp after '
        'you send your order. We will always confirm the total with you '
        'before you accept delivery.',
      ],
    ),
    (
      'Payment',
      [
        'Payment is arranged between you and MYCOSIX on WhatsApp. This '
        'website does not collect payments or store card details.',
      ],
    ),
    (
      'Food safety',
      [
        'Fresh mushrooms are perishable. We harvest and pack them as fresh as '
        'we can, but you should store them chilled after delivery and use '
        'them within the guidance we share with your order. Always wash and '
        'cook fresh mushrooms before eating.',
      ],
    ),
    (
      'Our content',
      [
        'The MYCOSIX name, logo and the text and imagery on this site belong '
        'to MYCOSIX. Please ask before reusing them.',
      ],
    ),
    (
      'Changes and contact',
      [
        'We may update these terms as the site grows. The latest version is '
        'always this page. Questions? Message us on WhatsApp (\$whatsapp) or '
        'on Instagram — @\$handle.',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final whatsapp = MxConfig.whatsappDisplay;
    final handle = MxConfig.instagramHandle;
    return MxLegalPage(
      overline: 'Legal',
      title: 'Terms & Conditions',
      updated: 'September 2026',
      sections: [
        for (final (heading, paras) in _sections)
          (
            heading,
            [
              for (final p in paras)
                p
                    .replaceAll(r'$whatsapp', whatsapp)
                    .replaceAll(r'$handle', handle),
            ],
          ),
      ],
    );
  }
}
