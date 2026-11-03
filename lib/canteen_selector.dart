import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'state_views.dart';
import 'theme.dart';

/// Value used for "All canteens".
const String kAllCanteens = 'all';

class CanteenChoice {
  final String id; // kAllCanteens or a canteen id
  final String name;
  const CanteenChoice(this.id, this.name);

  bool get isAll => id == kAllCanteens;

  @override
  bool operator ==(Object other) =>
      other is CanteenChoice && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

/// The canteens an admin can pick from: every canteen that really exists,
/// "Main Canteen" first when its record exists, then the others sorted by name.
/// Main is NOT added when its record has been deleted (every canteen, including
/// Main, can be deleted). [all] adds the leading "All canteens" choice.
List<CanteenChoice> buildCanteenChoices(
  Iterable<MapEntry<String, Map<String, dynamic>>> canteenDocs, {
  bool all = true,
}) {
  CanteenChoice? main;
  final others = <CanteenChoice>[];
  for (final e in canteenDocs) {
    final name = (e.value['name'] ?? '').toString().trim();
    if (e.key == 'main') {
      main = CanteenChoice('main', name.isEmpty ? 'Main Canteen' : name);
    } else {
      others.add(CanteenChoice(e.key, name.isEmpty ? e.key : name));
    }
  }
  others.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return [
    if (all) const CanteenChoice(kAllCanteens, 'All canteens'),
    if (main != null) main,
    ...others,
  ];
}

/// Dropdown for an admin to choose which canteen a screen is about.
///
/// Loads the canteens itself (admins may read them). For tests, pass
/// [choicesStream] to avoid Firestore.
class CanteenSelector extends StatefulWidget {
  /// Currently selected id (`kAllCanteens` or a canteen id).
  final String value;
  final void Function(CanteenChoice choice) onChanged;
  final bool includeAll;
  final String label;
  final Stream<List<CanteenChoice>>? choicesStream;
  final EdgeInsetsGeometry margin;

  const CanteenSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.includeAll = true,
    this.label = 'Canteen',
    this.choicesStream,
    this.margin = const EdgeInsets.fromLTRB(16, 12, 16, 0),
  });

  @override
  State<CanteenSelector> createState() => _CanteenSelectorState();
}

class _CanteenSelectorState extends State<CanteenSelector> {
  late final Stream<List<CanteenChoice>> _stream = widget.choicesStream ??
      FirebaseFirestore.instance.collection('canteens').snapshots().map(
            (snap) => buildCanteenChoices(
              snap.docs.map((d) => MapEntry(d.id, d.data())),
              all: widget.includeAll,
            ),
          );

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: widget.margin,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: darkInputDecoration(),
      child: StreamBuilder<List<CanteenChoice>>(
        stream: _stream,
        builder: (context, snap) {
          // While loading (or on error) offer "All canteens" and keep the current
          // choice visible, so the control is never empty and nothing is
          // invented. (No canteen is assumed to exist.)
          final choices = snap.data ??
              [
                if (widget.includeAll)
                  const CanteenChoice(kAllCanteens, 'All canteens'),
                if (widget.value != kAllCanteens)
                  CanteenChoice(widget.value, widget.value),
              ];
          final value = choices.any((c) => c.id == widget.value)
              ? widget.value
              : choices.first.id;
          return Semantics(
            label: '${widget.label}: choose a canteen',
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                isExpanded: true,
                dropdownColor: AppColors.bgCard,
                iconEnabledColor: AppColors.textSecondary,
                hint: Text(widget.label),
                style:
                    AppText.style(color: AppColors.textPrimary, fontSize: 14),
                items: [
                  for (final c in choices)
                    DropdownMenuItem(
                      value: c.id,
                      child: Text(c.name,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.style(color: AppColors.textPrimary)),
                    ),
                ],
                onChanged: (id) {
                  if (id == null) return;
                  widget.onChanged(choices.firstWhere((c) => c.id == id));
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Shown instead of a screen's content while "All canteens" is selected and the
/// screen can only work on one canteen at a time.
class ChooseCanteenPrompt extends StatelessWidget {
  final String message;
  const ChooseCanteenPrompt({
    super.key,
    this.message = 'Select a canteen above to continue.',
  });

  @override
  Widget build(BuildContext context) => AppEmptyState(
        icon: Icons.storefront_rounded,
        title: 'Choose a canteen',
        message: message,
      );
}
