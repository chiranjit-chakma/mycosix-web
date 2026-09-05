import 'package:flutter/material.dart';

import '../../config/mx_config.dart';
import '../../widgets/legal_page.dart';

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  static const _sections = <(String, List<String>)>[
    (
      'What this policy covers',
      [
        'This page explains what information the MYCOSIX website handles when '
            'you browse, shop and check out. MYCOSIX is a student-run oyster '
            'mushroom farm; if you have questions about this policy, reach us on '
            'WhatsApp or Instagram — the links are on our contact page.',
      ],
    ),
    (
      'Information you enter',
      [
        'When you place an order through the checkout you are asked for your '
            'name and phone number. Email, building/house, apartment/unit, '
            'landmark and delivery instructions are optional. Your delivery '
            'location is collected as a map pin (latitude and longitude).',
        'We ask for this so we can prepare and deliver your order. The '
            'checkout never asks for a password, and no customer account is '
            'created.',
      ],
    ),
    (
      'What stays on your device',
      [
        'Your cart and your delivery location are saved in your browser\'s '
            'local storage so they survive a refresh. They live on your device, '
            'not on a MYCOSIX server. You can clear them by emptying your cart '
            'and resetting the location.',
      ],
    ),
    (
      'Browser location',
      [
        'The "Use Current Location" button in the checkout asks your browser '
            'for your device location. This only happens when you press the '
            'button, and only with your permission. If you grant it, the '
            'coordinates are used to centre the delivery map pin, which you can '
            'then adjust by dragging the map. Denying permission does not '
            'stop you from ordering.',
      ],
    ),
    (
      'Google Maps and site fonts',
      [
        'The checkout embeds a Google Maps view so you can place your '
            'delivery pin. Google Maps is provided by Google and may set its own '
            'cookies or collect its own usage data under Google\'s privacy '
            'policy.',
        'This site ships the Fraunces and Manrope fonts in its own files, '
            'so no font is fetched from Google Fonts or any third-party server.',
      ],
    ),
    (
      'Sharing your information',
      [
        'Your order — including your name, phone number, delivery pin and any '
            'details you add — is composed into a message that is sent to '
            'MYCOSIX\'s WhatsApp number (\$whatsapp) when you press Send in '
            'WhatsApp. The website itself does not send this message for you.',
        'We do not sell your information. This website does not run '
            'advertising or analytics trackers.',
      ],
    ),
    (
      'Your choices',
      [
        'You decide what to share. Every field except name and phone is '
            'optional, and you can review your full order message in WhatsApp '
            'before you send it. To ask us to delete an order conversation you '
            'sent, message us on WhatsApp and we will do what we reasonably can.',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final whatsapp = MxConfig.whatsappDisplay;
    return MxLegalPage(
      overline: 'Legal',
      title: 'Privacy Policy',
      updated: 'September 2026',
      sections: [
        for (final (heading, paras) in _sections)
          (
            heading,
            [for (final p in paras) p.replaceAll('\$whatsapp', whatsapp)],
          ),
      ],
    );
  }
}
