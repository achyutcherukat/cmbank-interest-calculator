import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'flow_widgets.dart';

const _kItemTypes = [
  'Necklace', 'Ring', 'Bangle', 'Earring', 'Bracelet',
  'Chain', 'Anklet', 'Coin', 'Bar', 'Pendant',
  'Waist Belt', 'Nose Ring', 'Other',
];

// ─── Data classes ─────────────────────────────────────────────────────────────

class ItemEntryData {
  const ItemEntryData({
    required this.itemType,
    required this.grossWeight,
    required this.netWeight,
    this.notes,
    this.purity,
  });

  final String itemType;
  final double grossWeight;
  final double netWeight;
  final String? notes;
  final String? purity;
}

class ItemDetailsData {
  const ItemDetailsData({required this.items, required this.photos});

  final List<ItemEntryData> items;
  final List<File> photos;
}

// ─── Mutable entry (internal) ─────────────────────────────────────────────────

class _ItemEntry {
  final grossCtrl = TextEditingController();
  final netCtrl = TextEditingController();
  final notesCtrl = TextEditingController();
  final purityCtrl = TextEditingController();
  String itemType = 'Other';

  double get grossWeight => double.tryParse(grossCtrl.text) ?? 0;
  double get netWeight => double.tryParse(netCtrl.text) ?? 0;

  void dispose() {
    grossCtrl.dispose();
    netCtrl.dispose();
    notesCtrl.dispose();
    purityCtrl.dispose();
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
  });

  final double grossWeight;
  final double netWeight;
  final ItemDetailsData? initialData;
  final String pledgeNumber;

  @override
  State<SharedItemDetailsStep> createState() => SharedItemDetailsStepState();
}

class SharedItemDetailsStepState extends State<SharedItemDetailsStep> {
  final _imagePicker = ImagePicker();
  late List<_ItemEntry> _items;
  List<File> _itemPhotos = [];

  @override
  void initState() {
    super.initState();
    final d = widget.initialData;
    if (d != null && d.items.isNotEmpty) {
      _items = d.items.map((e) {
        final entry = _ItemEntry();
        entry.grossCtrl.text =
            e.grossWeight > 0 ? e.grossWeight.toString() : '';
        entry.netCtrl.text = e.netWeight > 0 ? e.netWeight.toString() : '';
        entry.notesCtrl.text = e.notes ?? '';
        entry.purityCtrl.text = e.purity ?? '';
        entry.itemType = e.itemType;
        return entry;
      }).toList();
      _itemPhotos = List.from(d.photos);
    } else {
      _items = [_ItemEntry()];
      // Pre-fill first item with totals from Step 1
      if (widget.grossWeight > 0) {
        _items[0].grossCtrl.text = widget.grossWeight.toString();
      }
      if (widget.netWeight > 0) {
        _items[0].netCtrl.text = widget.netWeight.toString();
      }
    }
  }

  @override
  void dispose() {
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  ItemDetailsData getData() {
    return ItemDetailsData(
      items: _items
          .where((e) => e.grossWeight > 0 || e.netWeight > 0)
          .map((e) => ItemEntryData(
                itemType: e.itemType,
                grossWeight: e.grossWeight,
                netWeight: e.netWeight,
                notes: e.notesCtrl.text.trim().isEmpty
                    ? null
                    : e.notesCtrl.text.trim(),
                purity: e.purityCtrl.text.trim().isEmpty
                    ? null
                    : e.purityCtrl.text.trim(),
              ))
          .toList(),
      photos: List.unmodifiable(_itemPhotos),
    );
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

        const _ItemSecHeader('Items'),
        ...List.generate(_items.length, _buildItemRow),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: TextButton.icon(
            onPressed: () => setState(() => _items.add(_ItemEntry())),
            icon: const Icon(Icons.add_circle,
                color: FlowColors.primary, size: 20),
            label: const Text('ADD ANOTHER ITEM',
                style: TextStyle(
                    fontSize: 15,
                    color: FlowColors.primary,
                    fontWeight: FontWeight.bold)),
          ),
        ),

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

        const _ItemSecHeader('Item Photos'),
        _photoBlock(),
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
          Row(
            children: [
              Text('Item ${index + 1}',
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: FlowColors.primary)),
              const Spacer(),
              if (index > 0)
                GestureDetector(
                  onTap: () => setState(() {
                    _items[index].dispose();
                    _items.removeAt(index);
                  }),
                  child: const Icon(Icons.delete_outline,
                      color: Colors.red, size: 22),
                ),
            ],
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: entry.itemType,
            decoration: const InputDecoration(
                labelText: 'Item Type', isDense: true),
            items: _kItemTypes
                .map((t) => DropdownMenuItem(
                    value: t,
                    child: Text(t, style: const TextStyle(fontSize: 16))))
                .toList(),
            onChanged: (v) =>
                setState(() => entry.itemType = v ?? 'Other'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _decimalField('Gross (g)', entry.grossCtrl)),
              const SizedBox(width: 10),
              Expanded(child: _decimalField('Net (g)', entry.netCtrl)),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: entry.purityCtrl,
            style: const TextStyle(fontSize: 16),
            decoration: const InputDecoration(
                labelText: 'Gold Purity (optional, e.g. 22K, 18K)',
                isDense: true),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: entry.notesCtrl,
            style: const TextStyle(fontSize: 16),
            decoration: const InputDecoration(
                labelText: 'Notes (optional)', isDense: true),
          ),
        ],
      ),
    );
  }

  Widget _decimalField(String label, TextEditingController ctrl) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
