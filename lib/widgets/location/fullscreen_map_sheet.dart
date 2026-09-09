import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/mx_colors.dart';
import '../../config/mx_config.dart';
import '../../config/mx_type.dart';
import '../../state/location_controller.dart';
import 'location_map.dart';

/// Opens the delivery map as a near-full-screen sheet.
///
/// This is the BIG map customers actually move the pin on: it fills most of
/// the screen, zooms from whole countries (level 3) down to a building
/// (level 20), and lets the pin be dragged anywhere in the world — the
/// checkout's inline panel stays small and points here. Dragging the map or
/// the pin sets an unconfirmed candidate (live, so the checkout can show the
/// delivery fee for the current spot as it moves); the Confirm button below
/// the map is the explicit confirm step the order flow requires.
Future<void> showDeliveryMapSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    showDragHandle: true,
    builder: (_) => const _DeliveryMapSheet(),
  );
}

class _DeliveryMapSheet extends StatelessWidget {
  const _DeliveryMapSheet();

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocationController>();
    final current = loc.location;
    final screenHeight = MediaQuery.sizeOf(context).height;

    return Container(
      height: screenHeight * 0.94,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
      decoration: BoxDecoration(
        color: MxColors.creamSoft,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        border: Border.all(color: MxColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: title + close. The map itself is the rest of the sheet.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
            child: Row(
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  size: 20,
                  color: MxColors.moss,
                ),
                const SizedBox(width: 8),
                Text(
                  'Delivery location',
                  style: MxType.h3(color: MxColors.charcoal),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close_rounded, size: 22),
                  color: MxColors.charcoalSoft,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Drag the map to move around, tap to drop the pin, drag the pin '
              'to fine-tune, and pinch or use + / − to zoom from whole '
              'countries down to your building. The pin can go anywhere — '
              'if a spot is too far to deliver to, we will say so here.',
              style: MxType.bodySm(color: MxColors.charcoalSoft),
            ),
          ),
          const SizedBox(height: 12),
          // The big map: everything between the header and the footer.
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(MxRadius.lg),
                child: LayoutBuilder(
                  builder: (context, constraints) => LocationMap(
                    latitude:
                        current?.latitude ?? MxConfig.defaultLatitude,
                    longitude:
                        current?.longitude ?? MxConfig.defaultLongitude,
                    height: constraints.maxHeight,
                    onChanged: (latLng) =>
                        loc.setCandidate(latLng.$1, latLng.$2),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Footer: live pin readout + the explicit Confirm step.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (current != null) ...[
                        Text(
                          '${current.latitude.toStringAsFixed(5)}, '
                          '${current.longitude.toStringAsFixed(5)}',
                          style: MxType.bodyXs(
                            color: MxColors.charcoal,
                            weight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          current.confirmed
                              ? 'This spot is confirmed.'
                              : 'This spot is not confirmed yet.',
                          style: MxType.bodyXs(color: MxColors.stone),
                        ),
                      ] else
                        Text(
                          'No pin yet — drag the map to drop yours.',
                          style: MxType.bodySm(color: MxColors.stone),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: current == null
                      ? null
                      : () {
                          loc.confirm();
                          Navigator.of(context).pop();
                        },
                  icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                  label: Text(
                    current == null
                        ? 'Set the pin on the map'
                        : 'Confirm this location',
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
