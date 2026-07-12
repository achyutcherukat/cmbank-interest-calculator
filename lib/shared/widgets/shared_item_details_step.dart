import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../features/admin/data/item_types_repository.dart';
import '../../features/admin/data/purity_types_repository.dart';
import 'flow_widgets.dart';

// Fallbacks used only until the active lists load from the DB (item_types /
// purity_types tables).
const _kItemTypes = [
  'Necklace', 'Ring', 'Bangle', 'Earring', 'Bracelet',
  'Chain', 'Anklet', 'Coin', 'Bar', 'Pendant',
  'Waist Belt', 'Nose Ring', 'Other',
];

const _kPurityTypes = ['916', '22K', 'Other'];

// ─── Data classes ─────────────────────────────────────────────────────────────

class ItemEntryData {
  const ItemEntryData({
    required this.itemType,
    required this.grossWeight,
    required this.netWeight,
    this.quantity = 1,
    this.notes,
    this.purity,
    this.goldRate,
    this.pledgeRate,
    this.itemValue,
  });

  final String itemType;
  final double grossWeight;
  final double netWeight;
  final int quantity;
  final String? notes;
  final String? purity;

  /// Rate/value snapshot for this item's purity. [getData] always resolves
  /// these to a concrete number (0 when unresolved) — from a live
  /// [SharedItemDetailsStep.purityRates] lookup for a brand-new item, or
  /// preserved from the item's own historical snapshot when editing an
  /// existing pledge (see [SharedItemDetailsStep.initialData]). Nullable here
  /// only so construction sites that don't care about rates can omit them.
  final double? goldRate;
  final double? pledgeRate;
  final double? itemValue;
}

class ItemDetailsData {
  const ItemDetailsData({required this.items, required this.photos});

  final List<ItemEntryData> items;
  final List<File> photos;
}

// ─── Internal data model ──────────────────────────────────────────────────────

class _TypeQtyPair {
  String type;
  int qty;
  _TypeQtyPair({required this.type, this.qty = 1});
}

class _ItemEntry {
  _ItemEntry({this.origin});

  /// The [ItemEntryData] this entry was built from (i.e. an existing item
  /// carried over via [SharedItemDetailsStep.initialData]). Null for a
  /// brand-new entry added via "ADD ANOTHER ITEM LIST" — there's no original
  /// to report as released if this one gets deleted.
  final ItemEntryData? origin;

  final grossCtrl = TextEditingController();
  final netCtrl = TextEditingController();
  final notesCtrl = TextEditingController();
  final purityCtrl = TextEditingController();
  final rateCtrl = TextEditingController();
  final grossFocus = FocusNode();
  final netFocus = FocusNode();
  List<_TypeQtyPair> typeQtyPairs = [];

  // Historical gold-rate snapshot, carried over from an existing pledge_items
  // row (editMode). Pledge rate has no separate snapshot field any more —
  // rateCtrl (visible and user-editable) is always the source of truth for
  // it, seeded from the historical value or a live lookup once at entry
  // creation. Gold rate stays pinned to its snapshot only while
  // [snapshotPurity] still matches the currently-selected purity; changing
  // the purity invalidates it and falls back to a live lookup.
  String? snapshotPurity;
  double? snapshotGoldRate;

  double get grossWeight => double.tryParse(grossCtrl.text) ?? 0;
  double get netWeight => double.tryParse(netCtrl.text) ?? 0;

  int get totalQuantity {
    final s = typeQtyPairs.fold(0, (acc, p) => acc + p.qty);
    return s < 1 ? 1 : s;
  }

  /// Auto-generated comma-separated description, e.g. "Chain - 2, Bangle - 2".
  String get itemType {
    if (typeQtyPairs.isEmpty) return 'Other';
    return typeQtyPairs.map((p) => '${p.type} - ${p.qty}').join(', ');
  }

  void dispose() {
    grossCtrl.dispose();
    netCtrl.dispose();
    notesCtrl.dispose();
    purityCtrl.dispose();
    rateCtrl.dispose();
    grossFocus.dispose();
    netFocus.dispose();
  }
}

// ─── Widget ───────────────────────────────────────────────────────────────────

class SharedItemDetailsStep extends StatefulWidget {
  const SharedItemDetailsStep({
    super.key,
    required this.grossWeight,
    required this.netWeight,
    this.initialData,
    this.pledgeNumber = '',
    this.prefillOtherItem = false,
    this.purityRates = const {},
    this.showPhotoSection = true,
  });

  final double grossWeight;
  final double netWeight;
  final ItemDetailsData? initialData;
  final String pledgeNumber;
  final bool prefillOtherItem;

  /// Whether to show the "Item Photos" camera/gallery section. Defaults to
  /// true (new-pledge / edit-pledge item entry). Callers that only reuse this
  /// step for editing an existing pledge's items without capturing new
  /// photos (e.g. Part Release "item release") pass false.
  final bool showPhotoSection;

  /// Current gold/pledge rate per purity name (from `gold_rates`, per
  /// purity_type). When non-empty, each item shows a live "Item Value"
  /// (net weight × that purity's pledge rate) and a running total, and
  /// [getData] resolves goldRate/pledgeRate/itemValue on every item. Left
  /// empty (default) for callers that don't use per-purity rates — the value
  /// UI stays hidden and resolved rates come back as 0, exactly as before
  /// this parameter existed.
  final Map<String, ({double? goldRate, double pledgeRate})> purityRates;

  @override
  State<SharedItemDetailsStep> createState() => SharedItemDetailsStepState();
}

class SharedItemDetailsStepState extends State<SharedItemDetailsStep>
    with AutomaticKeepAliveClientMixin {
  final _imagePicker = ImagePicker();
  late List<_ItemEntry> _items;
  List<File> _itemPhotos = [];
  List<String> _itemTypes = _kItemTypes;
  List<String> _purityTypes = _kPurityTypes;
  final List<ItemEntryData> _removedOrigins = [];

  // This step is embedded inside plain scrolling ListViews (Part Release's
  // "item release" step in particular sits well above the Proceed button, with
  // several cards in between). Without keep-alive, Flutter's sliver list
  // disposes this State once it scrolls far enough outside the viewport +
  // cache extent, silently discarding every edit/deletion the moment the user
  // scrolls down to reach a button further below.
  @override
  bool get wantKeepAlive => true;

  Future<void> _loadLookups() async {
    try {
      final items = await ItemTypesRepository.instance.getActiveItemTypes();
      final purities =
          await PurityTypesRepository.instance.getActivePurityTypes();
      if (mounted) {
        setState(() {
          if (items.isNotEmpty) _itemTypes = items;
          if (purities.isNotEmpty) _purityTypes = purities;
        });
      }
    } catch (_) {
      // Keep fallbacks on error.
    }
  }

  /// Parses an existing item_type string back into type+qty pairs.
  /// Handles both the new format ("Chain - 2, Bangle - 2") and old single-type
  /// format ("Necklace") from records created before this rework.
  static List<_TypeQtyPair> _parseItemType(String itemType, int fallbackQty) {
    if (itemType.isEmpty || itemType == 'Other') return [];
    final parts = itemType
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final result = <_TypeQtyPair>[];
    for (final part in parts) {
      final dashIdx = part.lastIndexOf(' - ');
      if (dashIdx > 0) {
        final typePart = part.substring(0, dashIdx).trim();
        final qtyStr = part.substring(dashIdx + 3).trim();
        final qty = int.tryParse(qtyStr);
        if (qty != null && qty > 0 && typePart.isNotEmpty) {
          result.add(_TypeQtyPair(type: typePart, qty: qty));
          continue;
        }
      }
      // Old format or unparseable: treat whole string as single type name.
      final effectiveQty =
          parts.length == 1 ? (fallbackQty < 1 ? 1 : fallbackQty) : 1;
      result.add(_TypeQtyPair(type: part, qty: effectiveQty));
    }
    return result;
  }

  @override
  void initState() {
    super.initState();
    _loadLookups();
    final d = widget.initialData;
    if (d != null && d.items.isNotEmpty) {
      _items = d.items.map((e) {
        final entry = _ItemEntry(origin: e);
        entry.grossCtrl.text =
            e.grossWeight > 0 ? e.grossWeight.toString() : '';
        entry.netCtrl.text = e.netWeight > 0 ? e.netWeight.toString() : '';
        entry.notesCtrl.text = e.notes ?? '';
        entry.purityCtrl.text = e.purity ?? '';
        entry.typeQtyPairs = _parseItemType(e.itemType, e.quantity);
        // 0 means "no historical rate on file" (pre-dates this feature or a
        // brand-new item carried over from an in-progress session) — treat
        // it as no snapshot so build() falls back to a live rate lookup.
        entry.snapshotPurity = e.purity;
        entry.snapshotGoldRate = (e.goldRate ?? 0) > 0 ? e.goldRate : null;
        final snapshotPledgeRate = (e.pledgeRate ?? 0) > 0 ? e.pledgeRate : null;
        _seedRate(entry, fallbackRate: snapshotPledgeRate);
        return entry;
      }).toList();
      _itemPhotos = List.from(d.photos);
    } else {
      _items = [_newItemEntry()];
      // Pre-fill first item with totals from Step 1.
      if (widget.grossWeight > 0) {
        _items[0].grossCtrl.text = widget.grossWeight.toString();
      }
      if (widget.netWeight > 0) {
        _items[0].netCtrl.text = widget.netWeight.toString();
      }
      if (widget.prefillOtherItem) {
        _items[0].typeQtyPairs = [_TypeQtyPair(type: 'Other', qty: 1)];
      }
    }
  }

  @override
  void didUpdateWidget(covariant SharedItemDetailsStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The parent loads purityRates asynchronously, often after this widget
    // (and its default item) has already been created. Catch up any rate box
    // still blank so the default purity's rate doesn't get stuck at "not set"
    // once the rates finish loading. Never overwrites a value the user has
    // already typed or that already resolved from a prior update.
    if (widget.purityRates.isEmpty ||
        identical(widget.purityRates, oldWidget.purityRates)) {
      return;
    }
    for (final entry in _items) {
      if (entry.rateCtrl.text.trim().isNotEmpty) continue;
      _seedRate(entry);
    }
  }

  @override
  void dispose() {
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  /// Creates a blank item entry defaulted to '916' purity (or the first
  /// active purity if '916' isn't configured), with its Pledge Rate box
  /// pre-populated from the live rate for that purity.
  _ItemEntry _newItemEntry({bool autofocusGross = false}) {
    final entry = _ItemEntry();
    if (_purityTypes.contains('916')) {
      entry.purityCtrl.text = '916';
    } else if (_purityTypes.isNotEmpty) {
      entry.purityCtrl.text = _purityTypes.first;
    }
    _seedRate(entry);
    if (autofocusGross) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) entry.grossFocus.requestFocus();
      });
    }
    return entry;
  }

  /// Populates [entry]'s Pledge Rate box: [fallbackRate] (a historical
  /// snapshot) if given, otherwise a live lookup for the entry's current
  /// purity. Leaves the box blank if neither is available.
  void _seedRate(_ItemEntry entry, {double? fallbackRate}) {
    final purity = entry.purityCtrl.text.trim();
    final live = purity.isEmpty ? null : widget.purityRates[purity]?.pledgeRate;
    final rate = fallbackRate ?? live;
    entry.rateCtrl.text =
        (rate != null && rate > 0) ? formatIndian(rate.round().toString()) : '';
  }

  /// Returns a validation error message, or null if all Item Lists are valid.
  String? validate() {
    for (int i = 0; i < _items.length; i++) {
      final e = _items[i];
      if (e.typeQtyPairs.isEmpty) {
        return 'Item List ${i + 1}: Add at least one item type before proceeding.';
      }
      if (e.grossWeight <= 0) {
        return 'Item List ${i + 1}: Enter a valid gross weight.';
      }
      if (e.netWeight <= 0) {
        return 'Item List ${i + 1}: Enter a valid net weight.';
      }
      if (e.netWeight > e.grossWeight) {
        return 'Item List ${i + 1}: Net weight cannot exceed gross weight.';
      }
    }
    return null;
  }

  /// The original (pre-edit) data of every Item List the staff has deleted
  /// via the trash icon, in deletion order. Entries added via "ADD ANOTHER
  /// ITEM LIST" (no [ItemEntryData] origin) are never included here even if
  /// later deleted, since there's nothing "released" about them.
  List<ItemEntryData> getRemovedItems() => List.unmodifiable(_removedOrigins);

  ItemDetailsData getData() {
    return ItemDetailsData(
      items: _items
          .where((e) => e.grossWeight > 0 || e.netWeight > 0)
          .map((e) {
            final resolved = _resolvedRates(e);
            return ItemEntryData(
              itemType: e.itemType,
              grossWeight: e.grossWeight,
              netWeight: e.netWeight,
              quantity: e.typeQtyPairs.isEmpty ? 1 : e.totalQuantity,
              notes: e.notesCtrl.text.trim().isEmpty
                  ? null
                  : e.notesCtrl.text.trim(),
              purity: e.purityCtrl.text.trim().isEmpty
                  ? null
                  : e.purityCtrl.text.trim(),
              goldRate: resolved.goldRate,
              pledgeRate: resolved.pledgeRate,
              itemValue: resolved.itemValue,
            );
          })
          .toList(),
      photos: List.unmodifiable(_itemPhotos),
    );
  }

  /// Resolves this item's gold rate and value. Pledge rate is read directly
  /// from [_ItemEntry.rateCtrl] — the visible, user-editable box is always
  /// the source of truth for it (seeded once from a historical snapshot or a
  /// live lookup; see [_seedRate]). Gold rate has no visible box, so it stays
  /// pinned to its historical snapshot while the purity is unchanged,
  /// otherwise falls back to a live lookup against
  /// [SharedItemDetailsStep.purityRates].
  ({double goldRate, double pledgeRate, double itemValue}) _resolvedRates(
      _ItemEntry entry) {
    final currentPurity = entry.purityCtrl.text.trim();
    double goldRate;
    if (entry.snapshotGoldRate != null &&
        entry.snapshotPurity == currentPurity) {
      goldRate = entry.snapshotGoldRate!;
    } else {
      final live =
          currentPurity.isEmpty ? null : widget.purityRates[currentPurity];
      goldRate = live?.goldRate ?? 0;
    }
    final pledgeRate =
        double.tryParse(entry.rateCtrl.text.replaceAll(',', '')) ?? 0;
    return (
      goldRate: goldRate,
      pledgeRate: pledgeRate,
      itemValue: entry.netWeight * pledgeRate,
    );
  }

  Future<void> _showAddItemTypeDialog(int itemIndex) async {
    String selectedType = 'Other';
    int selectedQty = 1;

    final result = await showDialog<_TypeQtyPair?>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text('Add Item Type',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InputDecorator(
                decoration: const InputDecoration(
                    labelText: 'Item Type', isDense: true),
                child: DropdownButton<String>(
                  value: selectedType,
                  isExpanded: true,
                  underline: const SizedBox(),
                  items: _itemTypes
                      .map((t) => DropdownMenuItem(
                          value: t,
                          child: Text(t,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 16))))
                      .toList(),
                  onChanged: (v) =>
                      setStateDialog(() => selectedType = v ?? selectedType),
                ),
              ),
              const SizedBox(height: 14),
              InputDecorator(
                decoration: const InputDecoration(
                    labelText: 'Quantity', isDense: true),
                child: DropdownButton<int>(
                  value: selectedQty,
                  isExpanded: true,
                  underline: const SizedBox(),
                  items: List.generate(9, (i) => i + 1)
                      .map((n) => DropdownMenuItem(
                          value: n,
                          child: Text('$n',
                              style: const TextStyle(fontSize: 16))))
                      .toList(),
                  onChanged: (v) =>
                      setStateDialog(() => selectedQty = v ?? selectedQty),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('CANCEL',
                  style: TextStyle(
                      color: Colors.black54, fontWeight: FontWeight.w600)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx)
                  .pop(_TypeQtyPair(type: selectedType, qty: selectedQty)),
              style: ElevatedButton.styleFrom(
                backgroundColor: FlowColors.primary,
                foregroundColor: FlowColors.textOnNavyLarge,
              ),
              child: const Text('ADD'),
            ),
          ],
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() => _items[itemIndex].typeQtyPairs.add(result));
    }
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 75,
        maxWidth: 1400,
      );
      if (picked == null || !mounted) return;

      final cropped = await ImageCropper().cropImage(
        sourcePath: picked.path,
        compressQuality: 85,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Photo',
            toolbarColor: FlowColors.primary,
            toolbarWidgetColor: FlowColors.goldRich,
            lockAspectRatio: false,
            hideBottomControls: true,
          ),
          IOSUiSettings(title: 'Crop Photo'),
        ],
      );
      if (cropped == null || !mounted) return;

      final docsDir = await getApplicationDocumentsDirectory();
      final destDir = Directory('${docsDir.path}/pledge_photos');
      await destDir.create(recursive: true);

      final ts = DateTime.now().millisecondsSinceEpoch;
      final prefix =
          widget.pledgeNumber.isNotEmpty ? widget.pledgeNumber : 'pledge';
      final dest = File('${destDir.path}/${prefix}_item_$ts.jpg');
      await File(cropped.path).copy(dest.path);

      if (mounted) setState(() => _itemPhotos = [..._itemPhotos, dest]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Could not pick photo: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin
    final totalGross = _items.fold(0.0, (s, i) => s + i.grossWeight);
    final totalNet = _items.fold(0.0, (s, i) => s + i.netWeight);
    final remGross = widget.grossWeight - totalGross;
    final remNet = widget.netWeight - totalNet;
    final grossOk = widget.grossWeight == 0 || remGross.abs() < 0.001;
    final netOk = widget.netWeight == 0 || remNet.abs() < 0.001;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Reference totals from Step 1
        if (widget.grossWeight > 0 || widget.netWeight > 0)
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: FlowColors.accent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: FlowColors.primaryLight),
            ),
            child: Row(
              children: [
                Expanded(child: _weightStat('Total Gross', widget.grossWeight)),
                Container(
                    width: 1, height: 36, color: FlowColors.primaryLight),
                Expanded(child: _weightStat('Total Net', widget.netWeight)),
              ],
            ),
          ),

        const _ItemSecHeader('Item Lists'),
        ...List.generate(_items.length, _buildItemRow),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: TextButton.icon(
            onPressed: () => setState(
                () => _items.add(_newItemEntry(autofocusGross: true))),
            icon: const Icon(Icons.add_circle,
                color: FlowColors.primary, size: 20),
            label: const Text('ADD ANOTHER ITEM LIST',
                style: TextStyle(
                    fontSize: 15,
                    color: FlowColors.primary,
                    fontWeight: FontWeight.bold)),
          ),
        ),

        // Running total max pledge value (only when a caller supplies
        // per-purity rates — hidden entirely for callers that don't use
        // them). Full-width card matching the style used for this figure on
        // the Pledge Basics step.
        if (widget.purityRates.isNotEmpty) _totalMaxPledgeValueCard(),

        // Running totals (only show if reference weights are provided)
        if (widget.grossWeight > 0 || widget.netWeight > 0)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: (grossOk && netOk)
                  ? FlowColors.greenLight
                  : FlowColors.orangeLight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: (grossOk && netOk)
                      ? FlowColors.green
                      : FlowColors.orange),
            ),
            child: Column(
              children: [
                _weightRow('Gross entered', totalGross, widget.grossWeight, grossOk),
                const SizedBox(height: 4),
                _weightRow('Net entered', totalNet, widget.netWeight, netOk),
              ],
            ),
          ),

        if (widget.showPhotoSection) ...[
          const _ItemSecHeader('Item Photos'),
          _photoBlock(),
        ],
      ],
    );
  }

  Widget _buildItemRow(int index) {
    final entry = _items[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: FlowColors.primaryLight, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card header
          Row(
            children: [
              Text('Item List ${index + 1}',
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: FlowColors.primary)),
              const Spacer(),
              if (_items.length > 1)
                GestureDetector(
                  onTap: () => setState(() {
                    final removed = _items.removeAt(index);
                    if (removed.origin != null) {
                      _removedOrigins.add(removed.origin!);
                    }
                    removed.dispose();
                  }),
                  child: const Icon(Icons.delete_outline,
                      color: Colors.red, size: 22),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Item type + quantity chips sub-section
          const Text('ITEM TYPES',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: FlowColors.medText,
                  letterSpacing: 0.6)),
          const SizedBox(height: 8),

          if (entry.typeQtyPairs.isNotEmpty) ...[
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: List.generate(entry.typeQtyPairs.length, (ci) {
                final pair = entry.typeQtyPairs[ci];
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: FlowColors.accent,
                    borderRadius: BorderRadius.circular(24),
                    border:
                        Border.all(color: FlowColors.primaryLight, width: 1.2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${pair.qty} × ${pair.type}',
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: FlowColors.primary)),
                      const SizedBox(width: 8),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () =>
                            setState(() => entry.typeQtyPairs.removeAt(ci)),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.close,
                              size: 20, color: FlowColors.primary),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
            const SizedBox(height: 8),
          ],

          TextButton.icon(
            onPressed: () => _showAddItemTypeDialog(index),
            icon: const Icon(Icons.add, color: FlowColors.primary, size: 18),
            label: const Text('ADD ITEM TYPE',
                style: TextStyle(
                    fontSize: 14,
                    color: FlowColors.primary,
                    fontWeight: FontWeight.w600)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),

          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFEEEEEE)),
          const SizedBox(height: 12),

          // Purity + Pledge Rate for this Item List — purity first, rate
          // beside it (auto-populated from purity, live-editable).
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<String>(
                  initialValue: _purityValue(entry.purityCtrl.text),
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Gold Purity (optional)', isDense: true),
                  items: _purityItems(entry.purityCtrl.text)
                      .map((t) => DropdownMenuItem(
                          value: t,
                          child: Text(t, style: const TextStyle(fontSize: 16))))
                      .toList(),
                  onChanged: (v) => setState(() {
                    entry.purityCtrl.text = v ?? '';
                    _seedRate(entry);
                  }),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: _rateField(entry)),
            ],
          ),

          // Shared weight fields for this Item List — gross then net, with
          // Enter/Done moving focus gross → net → dismiss keyboard.
          Row(
            children: [
              Expanded(
                child: _decimalField('Gross (g)', entry.grossCtrl,
                    focusNode: entry.grossFocus,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => entry.netFocus.requestFocus()),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _decimalField('Net (g)', entry.netCtrl,
                    focusNode: entry.netFocus,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) =>
                        FocusScope.of(context).unfocus()),
              ),
            ],
          ),
          const SizedBox(height: 6),

          TextField(
            controller: entry.notesCtrl,
            style: const TextStyle(fontSize: 16),
            decoration: const InputDecoration(
                labelText: 'Notes (optional)', isDense: true),
          ),
          const SizedBox(height: 8),

          // Live summary line
          if (_buildItemSummary(entry).isNotEmpty)
            Text(
              _buildItemSummary(entry),
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: FlowColors.medText),
            ),

          // Live item value (only when a caller supplies per-purity rates)
          if (widget.purityRates.isNotEmpty) ...[
            const SizedBox(height: 8),
            _itemValueLine(entry),
          ],
        ],
      ),
    );
  }

  Widget _itemValueLine(_ItemEntry entry) {
    final purity = entry.purityCtrl.text.trim();
    if (purity.isEmpty) {
      return const Text(
        'Select a gold purity to calculate this item\'s value.',
        style: TextStyle(
            fontSize: 13,
            color: FlowColors.orange,
            fontWeight: FontWeight.w600),
      );
    }
    final resolved = _resolvedRates(entry);
    if (resolved.pledgeRate <= 0) {
      return const Text(
        'Enter a pledge rate above to calculate this item\'s value.',
        style: TextStyle(
            fontSize: 13,
            color: FlowColors.orange,
            fontWeight: FontWeight.w600),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: FlowColors.accent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Max Pledge Amount (${money(resolved.pledgeRate)}/g)',
              style: const TextStyle(
                  fontSize: 13,
                  color: FlowColors.medText,
                  fontWeight: FontWeight.w600)),
          Text(money(resolved.itemValue),
              style: const TextStyle(
                  fontSize: 15,
                  color: FlowColors.primary,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  /// Pledge Rate box shown beside the purity dropdown. Auto-populated from
  /// the purity's current rate (see [_seedRate]) but freely editable — typing
  /// here overrides the rate used for this item's value; changing purity
  /// resets it back to that purity's live rate.
  Widget _rateField(_ItemEntry entry) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: entry.rateCtrl,
        keyboardType: TextInputType.number,
        inputFormatters: [IndianNumberFormatter()],
        style: const TextStyle(fontSize: 16),
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          labelText: 'Pledge Rate (₹/g)',
          prefixText: '₹ ',
          isDense: true,
        ),
      ),
    );
  }

  /// Full-width card matching the style used for this figure on the Pledge
  /// Basics step (FlowCard + the same label/amount typography).
  Widget _totalMaxPledgeValueCard() {
    final total =
        _items.fold(0.0, (s, e) => s + _resolvedRates(e).itemValue);
    return FlowCard(
      backgroundColor: FlowColors.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('TOTAL MAX PLEDGE VALUE',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: FlowColors.medText,
                  letterSpacing: 0.5)),
          const SizedBox(height: 4),
          Text(money(total),
              style: const TextStyle(
                  color: FlowColors.primary,
                  fontSize: 30,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  String _buildItemSummary(_ItemEntry entry) {
    final parts = <String>[];
    if (entry.typeQtyPairs.isNotEmpty) {
      final total = entry.totalQuantity;
      parts.add('$total item${total == 1 ? '' : 's'} total');
    }
    if (entry.netWeight > 0) {
      parts.add('Net: ${entry.netWeight.toStringAsFixed(2)} g');
    }
    if (entry.purityCtrl.text.trim().isNotEmpty) {
      parts.add(entry.purityCtrl.text.trim());
    }
    return parts.join('   •   ');
  }

  String? _purityValue(String current) =>
      current.isNotEmpty && _purityTypes.contains(current) ? current : null;

  List<String> _purityItems(String current) {
    if (current.isEmpty || _purityTypes.contains(current)) return _purityTypes;
    return [current, ..._purityTypes];
  }

  Widget _decimalField(
    String label,
    TextEditingController ctrl, {
    FocusNode? focusNode,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctrl,
        focusNode: focusNode,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: textInputAction,
        onSubmitted: onSubmitted,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))
        ],
        style: const TextStyle(fontSize: 16),
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(labelText: label, isDense: true),
      ),
    );
  }

  Widget _photoBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pickPhoto(ImageSource.camera),
                icon: const Icon(Icons.camera_alt, size: 18),
                label: const Text('Camera'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pickPhoto(ImageSource.gallery),
                icon: const Icon(Icons.photo_library, size: 18),
                label: const Text('Gallery'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _itemPhotos.isNotEmpty
            ? SizedBox(
                height: 90,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _itemPhotos.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (ctx, i) => Stack(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  _PhotoView(file: _itemPhotos[i])),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(_itemPhotos[i],
                              height: 90, width: 90, fit: BoxFit.cover),
                        ),
                      ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: GestureDetector(
                          onTap: () => setState(() {
                            _itemPhotos = List.from(_itemPhotos)..removeAt(i);
                          }),
                          child: Container(
                            decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle),
                            child: const Icon(Icons.close,
                                color: Colors.white, size: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : Container(
                height: 50,
                width: double.infinity,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFEEEEEE),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('No photos yet',
                    style: TextStyle(color: Colors.black54)),
              ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _weightStat(String label, double value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  color: Colors.black54,
                  fontWeight: FontWeight.w600)),
          Text('${value.toStringAsFixed(2)} g',
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: FlowColors.primary)),
        ],
      ),
    );
  }

  Widget _weightRow(
      String label, double entered, double total, bool ok) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600)),
        Row(
          children: [
            Text(
                '${entered.toStringAsFixed(2)} / ${total.toStringAsFixed(2)} g',
                style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Icon(ok ? Icons.check_circle : Icons.warning_amber,
                color: ok ? FlowColors.green : FlowColors.orange,
                size: 16),
          ],
        ),
      ],
    );
  }
}

// ─── Private helpers ──────────────────────────────────────────────────────────

class _ItemSecHeader extends StatelessWidget {
  const _ItemSecHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      child: Text(title,
          style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: FlowColors.primary)),
    );
  }
}

class _PhotoView extends StatelessWidget {
  const _PhotoView({required this.file});
  final File file;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Photo'),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5.0,
          child: Image.file(file),
        ),
      ),
    );
  }
}
