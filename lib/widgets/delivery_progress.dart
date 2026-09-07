import 'package:flutter/material.dart';

import '../config/mx_colors.dart';
import '../config/mx_type.dart';
import '../models/order_status.dart';

/// A Zomato/Swiggy-style "line filling" tracker for a customer's order — not a
/// map, just the four delivery stages with the connecting line filling up as
/// the order moves forward.
///
/// The admin's latest status is streamed live into My Orders, so this widget
/// simply renders the [OrderStatus] it is given: pending orders sit at
/// "Placed", confirmed ones fill the first segment, "Out for delivery" fills
/// up to "On the way", and a delivered order is fully filled. Cancelled orders
/// show a clear cancelled state instead of any progress.
class DeliveryProgress extends StatelessWidget {
  const DeliveryProgress({super.key, required this.status});

  final OrderStatus status;

  static const List<String> _steps = ['Placed', 'Confirmed', 'On the way', 'Delivered'];

  @override
  Widget build(BuildContext context) {
    if (status == OrderStatus.cancelled) {
      return Container(
        key: const Key('delivery-progress-cancelled'),
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: MxColors.dangerSoft,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.cancel_outlined, size: 20, color: MxColors.danger),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Order cancelled',
                    style: MxType.bodySm(
                      color: MxColors.danger,
                      weight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'No delivery will be made — message us if this looks wrong.',
                    style: MxType.bodyXs(color: MxColors.stone),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final progress = status.deliveryProgress.clamp(1, 4);

    return Container(
      key: const Key('delivery-progress'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MxColors.mossTint,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_headlineIcon, size: 18, color: MxColors.moss),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _headline,
                  style: MxType.bodySm(
                    color: MxColors.forest,
                    weight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final trackLeft = 20.0;
              final trackWidth = constraints.maxWidth - (trackLeft * 2);
              final fill = trackWidth * ((progress - 1) / 3);
              return SizedBox(
                height: 62,
                child: Stack(
                  alignment: Alignment.topCenter,
                  children: [
                    // Track (remaining journey), then the filled line on top.
                    Positioned(
                      top: 10,
                      left: trackLeft,
                      width: trackWidth,
                      height: 3,
                      child: _Line(color: MxColors.line),
                    ),
                    if (fill > 0)
                      Positioned(
                        top: 10,
                        left: trackLeft,
                        width: fill,
                        height: 3,
                        child: _Line(color: MxColors.moss),
                      ),
                    // The four stages: a dot above each label.
                    Row(
                      children: [
                        for (var i = 0; i < _steps.length; i++)
                          Expanded(
                            child: _Step(
                              label: _steps[i],
                              done: i < progress,
                              current: i == progress - 1,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  String get _headline => switch (status) {
        OrderStatus.newOrder || OrderStatus.contacted =>
          'We have received your order',
        OrderStatus.confirmed => 'Your order is confirmed',
        OrderStatus.preparing => 'Your order is being prepared',
        OrderStatus.outForDelivery => 'Your order is out for delivery',
        OrderStatus.delivered => 'Your order has been delivered',
        OrderStatus.cancelled => 'Order cancelled',
      };

  IconData get _headlineIcon => switch (status) {
        OrderStatus.newOrder || OrderStatus.contacted =>
          Icons.receipt_long_outlined,
        OrderStatus.confirmed => Icons.check_circle_outline_rounded,
        OrderStatus.preparing => Icons.restaurant_outlined,
        OrderStatus.outForDelivery => Icons.local_shipping_outlined,
        OrderStatus.delivered => Icons.check_circle_rounded,
        OrderStatus.cancelled => Icons.cancel_outlined,
      };
}

class _Step extends StatelessWidget {
  const _Step({
    required this.label,
    required this.done,
    required this.current,
  });

  final String label;
  final bool done;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final color = current
        ? MxColors.forest
        : done
            ? MxColors.moss
            : MxColors.stoneLight;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The dot. The current stage is a touch bigger with a white ring so it
        // reads as "this is where your order is right now".
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          width: current ? 24 : 20,
          height: current ? 24 : 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? color : MxColors.cream,
            border: Border.all(
              color: current ? MxColors.forest : MxColors.line,
              width: current ? 2 : 1.5,
            ),
          ),
          child: done && !current
              ? const Icon(Icons.check_rounded, size: 13, color: Colors.white)
              : null,
        ),
        const SizedBox(height: 7),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: MxType.bodyXs(
            color: current || done ? MxColors.forest : MxColors.stone,
            weight: current ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
