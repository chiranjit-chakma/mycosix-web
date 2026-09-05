import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/mx_colors.dart';
import '../../config/mx_type.dart';
import '../../state/location_controller.dart';
import 'location_map.dart';

/// Panel to set a delivery location.
///
/// Flow: drag/tap the map OR use GPS → set an UNCONFIRMED candidate →
/// the user EXPLICITLY confirms → the pin location becomes final.
class LocationSelector extends StatefulWidget {
  const LocationSelector({super.key, this.compact = false});

  final bool compact;

  @override
  State<LocationSelector> createState() => _LocationSelectorState();
}

class _LocationSelectorState extends State<LocationSelector> {
  bool _showError = false;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final loc = context.watch<LocationController>();
    final current = loc.location;
    final hasLocation = current != null;

    return Container(
      padding: EdgeInsets.all(widget.compact ? 16 : 24),
      decoration: BoxDecoration(
        color: MxColors.creamSoft,
        borderRadius: BorderRadius.circular(MxRadius.lg),
        border: Border.all(color: MxColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on_outlined, size: 20, color: MxColors.moss),
              const SizedBox(width: 8),
              Text('Delivery Location', style: MxType.h4(color: MxColors.charcoal)),
              const Spacer(),
              if (hasLocation)
                _StatusChip(confirmed: loc.isConfirmed),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            hasLocation
                ? 'Move the pin to ${loc.isConfirmed ? 'adjust' : 'choose'} your exact delivery point.'
                : 'Set your delivery location — drag the map or use your current location.',
            style: MxType.bodySm(color: MxColors.charcoalSoft),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _ActionBtn(
                  icon: Icons.my_location_rounded,
                  label: loc.locating ? 'Getting location…' : 'Use Current Location',
                  loading: loc.locating,
                  onTap: loc.locating ? null : () => _useGps(),
                ),
                if (hasLocation)
                  _ActionBtn(
                    icon: Icons.refresh_rounded,
                    label: 'Reset',
                    onTap: () => loc.clear(),
                  ),
              ],
            ),
          ),
          if (_showError && loc.lastFailure != null) ...[
            const SizedBox(height: 12),
            _ErrorBanner(message: loc.lastFailure!.userMessage),
          ],
          const SizedBox(height: 18),
          if (hasLocation) ...[
            LocationMap(
              latitude: current.latitude,
              longitude: current.longitude,
              height: widget.compact ? 240 : 300,
              onChanged: (latLng) => loc.setCandidate(latLng.$1, latLng.$2),
            ),
            const SizedBox(height: 16),
            // Confirm step — always explicit.
            if (!loc.isConfirmed)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => loc.confirm(),
                  icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                  label: const Text('Confirm this location'),
                ),
              )
            else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: MxColors.okSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, size: 18, color: MxColors.ok),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Location confirmed',
                        style: MxType.bodySm(color: MxColors.ok, weight: FontWeight.w700),
                      ),
                    ),
                    TextButton(
                      onPressed: () => loc.invalidate(),
                      child: const Text('Change'),
                    ),
                  ],
                ),
              ),
            ],
          ] else
            SizedBox(
              height: width >= 768 ? 260 : 220,
              width: double.infinity,
              child: Container(
                decoration: BoxDecoration(
                  color: MxColors.creamDeep,
                  borderRadius: BorderRadius.circular(MxRadius.md),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.map_outlined, size: 34, color: MxColors.stoneLight),
                      const SizedBox(height: 10),
                      Text(
                        'No location set yet',
                        style: MxType.bodySm(color: MxColors.stone),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Use your current location or the map above.',
                        style: MxType.bodyXs(color: MxColors.stoneLight),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _useGps() async {
    setState(() => _showError = true);
    final loc = context.read<LocationController>();
    await loc.useCurrentLocation();
    if (!mounted) return;
    setState(() {});
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.confirmed});

  final bool confirmed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: confirmed ? MxColors.okSoft : MxColors.warnSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        confirmed ? 'Confirmed' : 'Pending',
        style: MxType.label(
          color: confirmed ? MxColors.ok : MxColors.warn,
          weight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({required this.icon, required this.label, this.onTap, this.loading = false});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: MxColors.mossTint,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: MxColors.moss.withValues(alpha: 0.35)),
        ),
        child: loading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: MxColors.moss),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: MxColors.moss),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: MxType.label(color: MxColors.moss, weight: FontWeight.w700),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MxColors.dangerSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, size: 18, color: MxColors.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: MxType.bodySm(color: MxColors.danger, weight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}
