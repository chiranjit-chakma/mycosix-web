import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/mx_colors.dart';
import '../config/mx_type.dart';
import '../services/url_launcher.dart';
import '../state/site_config_controller.dart';

/// Customer-facing "deliveries are paused" banner.
///
/// Shown only while the admin has switched "Delivery enabled" off in admin
/// Settings. It reads the live [SiteConfigController], so the moment an admin
/// pauses delivery every customer page showing this notice reacts immediately —
/// and the WhatsApp link lets a would-be customer still reach the farm.
/// Renders nothing when delivery is enabled (or before a live update has been
/// seen), so the shop looks exactly as before until an admin actually pauses.
class DeliveryPausedNotice extends StatelessWidget {
  const DeliveryPausedNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final config = context.watch<SiteConfigController>();
    if (config.deliveryEnabled) return const SizedBox.shrink();
    final digits = config.settings.whatsappNumber.replaceAll(RegExp(r'\D'), '');
    final waUrl = digits.isEmpty
        ? null
        : Uri.parse('https://wa.me/$digits')
            .replace(queryParameters: {
              'text': 'Hello MYCOSIX, are you taking orders today?',
            })
            .toString();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MxColors.warn.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(MxRadius.md),
        border: Border.all(color: MxColors.warn.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(
              Icons.pause_circle_outline_rounded,
              size: 22,
              color: MxColors.warn,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Deliveries are paused',
                  style: MxType.bodySm(
                    color: MxColors.charcoal,
                    weight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'MYCOSIX is not taking new orders right now. Check back '
                  'soon, or message us on WhatsApp to ask when delivery '
                  'resumes.',
                  style: MxType.bodyXs(color: MxColors.charcoalSoft),
                ),
                if (waUrl != null) ...[
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: () => UrlLauncher.open(waUrl),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(
                      Icons.chat_outlined,
                      size: 15,
                      color: MxColors.mossDeep,
                    ),
                    label: Text(
                      'Message us on WhatsApp',
                      style: MxType.bodyXs(
                        color: MxColors.mossDeep,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
