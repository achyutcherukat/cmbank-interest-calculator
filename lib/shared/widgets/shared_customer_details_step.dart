import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/database/app_database.dart';
import 'flow_widgets.dart';

const _kIdProofTypes = [
  'None',
  'Aadhaar Card',
  'PAN Card',
  'Passport',
  'Voter ID',
  'Driving License',
  'Ration Card',
  'Other',
];

// ─── Data class ───────────────────────────────────────────────────────────────

class CustomerDetailsData {
  const CustomerDetailsData({
    required this.phone,
    required this.name,
    required this.address,
    required this.idProofType,
    required this.idNumber,
    required this.idProofPhotos,
    this.existingCustomerId,
    this.pinCode,
    this.district,
    this.state,
  });

  final String phone;
  final String name;
  final String address;
  final String idProofType;
  final String idNumber;
  final List<File> idProofPhotos;
  final int? existingCustomerId;
  final String? pinCode;
  final String? district;
  final String? state;

  bool get isEmpty => name.isEmpty && phone.isEmpty;
}

// ─── Widget ───────────────────────────────────────────────────────────────────

class SharedCustomerDetailsStep extends StatefulWidget {
  const SharedCustomerDetailsStep({
    super.key,
    this.initialData,
    this.pledgeNumber = '',
  });

  final CustomerDetailsData? initialData;
  final String pledgeNumber;

  @override
  State<SharedCustomerDetailsStep> createState() =>
      SharedCustomerDetailsStepState();
}

class SharedCustomerDetailsStepState
    extends State<SharedCustomerDetailsStep> {
  final _imagePicker = ImagePicker();

  late final TextEditingController _phoneCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _districtCtrl;
  late final TextEditingController _stateCtrl;
  late final TextEditingController _pinCodeCtrl;
  late final TextEditingController _idNumberCtrl;
  final _pinCodeFocus = FocusNode();

  String _idProofType = 'None';
  List<File> _idProofPhotos = [];
  int? _existingCustomerId;

  // Address auto-fill tracking
  String _lastAddress = '';
  bool _districtIsAutofilled = false;
  bool _stateIsAutofilled = false;
  bool _showPinCodeError = false;
  bool _showDistrictError = false;
  bool _showStateError = false;

  @override
  void initState() {
    super.initState();
    final d = widget.initialData;
    _phoneCtrl = TextEditingController(text: d?.phone ?? '');
    _nameCtrl = TextEditingController(text: d?.name ?? '');
    _addressCtrl = TextEditingController(text: d?.address ?? '');
    _districtCtrl = TextEditingController(text: d?.district ?? '');
    _stateCtrl = TextEditingController(text: d?.state ?? '');
    _pinCodeCtrl = TextEditingController(text: d?.pinCode ?? '');
    _idNumberCtrl = TextEditingController(text: d?.idNumber ?? '');
    _lastAddress = d?.address ?? '';
    if (d != null) {
      _idProofType = d.idProofType;
      _idProofPhotos = List.from(d.idProofPhotos);
      _existingCustomerId = d.existingCustomerId;
    }
    _pinCodeFocus.addListener(_onPinCodeFocusChange);
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _districtCtrl.dispose();
    _stateCtrl.dispose();
    _pinCodeCtrl.dispose();
    _idNumberCtrl.dispose();
    _pinCodeFocus.removeListener(_onPinCodeFocusChange);
    _pinCodeFocus.dispose();
    super.dispose();
  }

  void _onPinCodeFocusChange() {
    if (!_pinCodeFocus.hasFocus) {
      setState(() {
        _showPinCodeError = _addressCtrl.text.trim().isNotEmpty &&
            _pinCodeCtrl.text.trim().isEmpty;
      });
    }
  }

  CustomerDetailsData getData() {
    return CustomerDetailsData(
      phone: _phoneCtrl.text.trim(),
      name: _nameCtrl.text.trim(),
      address: _addressCtrl.text.trim(),
      idProofType: _idProofType,
      idNumber: _idNumberCtrl.text.trim(),
      idProofPhotos: List.unmodifiable(_idProofPhotos),
      existingCustomerId: _existingCustomerId,
      pinCode:
          _pinCodeCtrl.text.trim().isEmpty ? null : _pinCodeCtrl.text.trim(),
      district:
          _districtCtrl.text.trim().isEmpty ? null : _districtCtrl.text.trim(),
      state: _stateCtrl.text.trim().isEmpty ? null : _stateCtrl.text.trim(),
    );
  }

  /// Returns an error message if validation fails, null if valid.
  String? validate() {
    final hasAddress = _addressCtrl.text.trim().isNotEmpty;
    final districtMissing = hasAddress && _districtCtrl.text.trim().isEmpty;
    final stateMissing = hasAddress && _stateCtrl.text.trim().isEmpty;
    final pinMissing = hasAddress && _pinCodeCtrl.text.trim().isEmpty;

    setState(() {
      _showDistrictError = districtMissing;
      _showStateError = stateMissing;
      _showPinCodeError = pinMissing;
    });

    if (districtMissing || stateMissing || pinMissing) {
      return 'District, State and PIN Code are required when address is provided';
    }
    return null;
  }

  void _onAddressChanged(String value) {
    final wasEmpty = _lastAddress.trim().isEmpty;
    final isNowEmpty = value.trim().isEmpty;
    _lastAddress = value;

    if (wasEmpty && !isNowEmpty) {
      // Address went from empty → has content: auto-populate district/state
      setState(() {
        if (_districtCtrl.text.isEmpty) {
          _districtCtrl.text = 'Kozhikode';
          _districtIsAutofilled = true;
        }
        if (_stateCtrl.text.isEmpty) {
          _stateCtrl.text = 'Kerala';
          _stateIsAutofilled = true;
        }
      });
    } else if (!wasEmpty && isNowEmpty) {
      // Address cleared: revert auto-filled defaults if user hasn't edited them
      setState(() {
        if (_districtIsAutofilled) {
          _districtCtrl.text = '';
          _districtIsAutofilled = false;
        }
        if (_stateIsAutofilled) {
          _stateCtrl.text = '';
          _stateIsAutofilled = false;
        }
        _showPinCodeError = false;
        _showDistrictError = false;
        _showStateError = false;
      });
    }
  }

  Future<void> _searchCustomer() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.length < 10) return;

    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'customers',
      where: 'phone = ?',
      whereArgs: [phone],
      limit: 1,
    );
    if (rows.isEmpty || !mounted) return;

    final c = rows.first;
    final name = c['name'] as String? ?? '';
    final address = c['address'] as String? ?? '';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Customer Found',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: FlowColors.primary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            if (address.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(address,
                    style: const TextStyle(
                        fontSize: 15, color: Colors.black54)),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Different Customer',
                style: TextStyle(fontSize: 16, color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: FlowColors.primary),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Use This',
                style: TextStyle(
                    fontSize: 16, color: FlowColors.textOnNavySmall)),
          ),
        ],
      ),
    );

    // Keep keyboard dismissed — dialog restore can re-focus the phone field
    if (mounted) FocusScope.of(context).unfocus();

    if (confirmed == true && mounted) {
      List<File> existingPhotos = [];
      final pathsJson = c['id_proof_photo_paths'] as String?;
      if (pathsJson != null && pathsJson.isNotEmpty) {
        try {
          final paths = (jsonDecode(pathsJson) as List).cast<String>();
          existingPhotos =
              paths.map((p) => File(p)).where((f) => f.existsSync()).toList();
        } catch (_) {}
      }
      setState(() {
        _existingCustomerId = c['id'] as int?;
        _nameCtrl.text = name;
        _addressCtrl.text = address;
        _idProofType = (c['id_proof_type'] as String?) ?? 'Aadhaar Card';
        _idNumberCtrl.text = (c['id_proof_number'] as String?) ?? '';
        _idProofPhotos = existingPhotos;
        _districtCtrl.text = (c['district'] as String?) ?? '';
        _stateCtrl.text = (c['state'] as String?) ?? '';
        _pinCodeCtrl.text = (c['pin_code'] as String?) ?? '';
        // Values from DB are not auto-filled; don't auto-clear on address edit
        _districtIsAutofilled = false;
        _stateIsAutofilled = false;
        _lastAddress = address;
        _showPinCodeError = false;
      });
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
      final dest = File('${destDir.path}/${prefix}_id_$ts.jpg');
      await File(cropped.path).copy(dest.path);

      if (mounted) {
        setState(() => _idProofPhotos = [..._idProofPhotos, dest]);
      }
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SecHeader('Phone Lookup'),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                style: const TextStyle(fontSize: 18),
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  prefixIcon: Icon(Icons.phone),
                  hintText: '10-digit mobile',
                ),
                onChanged: (v) {
                  setState(() {});
                  if (v.length == 10) {
                    FocusScope.of(context).unfocus();
                    _searchCustomer();
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: _searchCustomer,
              icon: const Icon(Icons.person_search,
                  color: FlowColors.primary, size: 28),
              tooltip: 'Search',
            ),
          ],
        ),
        const SizedBox(height: 20),
        const _SecHeader('Customer Details'),
        _textField('Full Name', _nameCtrl, icon: Icons.person),
        _textField(
          'Address',
          _addressCtrl,
          icon: Icons.location_on,
          maxLines: 2,
          onChanged: _onAddressChanged,
        ),
        _textField(
          'District',
          _districtCtrl,
          icon: Icons.map_outlined,
          errorText:
              _showDistrictError ? 'Required when address is provided' : null,
          onChanged: (v) {
            if (_districtIsAutofilled) _districtIsAutofilled = false;
            if (_showDistrictError && v.trim().isNotEmpty) {
              setState(() => _showDistrictError = false);
            }
          },
        ),
        _textField(
          'State',
          _stateCtrl,
          icon: Icons.flag_outlined,
          errorText:
              _showStateError ? 'Required when address is provided' : null,
          onChanged: (v) {
            if (_stateIsAutofilled) _stateIsAutofilled = false;
            if (_showStateError && v.trim().isNotEmpty) {
              setState(() => _showStateError = false);
            }
          },
        ),
        _pinCodeField(),
        const SizedBox(height: 4),
        const _CardLbl('ID PROOF'),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: _idProofType,
          decoration: const InputDecoration(
            labelText: 'ID Proof Type',
            prefixIcon: Icon(Icons.badge),
          ),
          items: _kIdProofTypes
              .map((t) => DropdownMenuItem(
                  value: t,
                  child: Text(t, style: const TextStyle(fontSize: 17))))
              .toList(),
          onChanged: (v) => setState(() => _idProofType = v ?? 'None'),
        ),
        const SizedBox(height: 14),
        _textField('ID Proof Number', _idNumberCtrl, icon: Icons.numbers),
        const SizedBox(height: 8),
        _photoBlock(),
      ],
    );
  }

  Widget _pinCodeField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: _pinCodeCtrl,
        focusNode: _pinCodeFocus,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(6),
        ],
        style: const TextStyle(fontSize: 18),
        decoration: InputDecoration(
          labelText: 'PIN Code',
          prefixIcon: const Icon(Icons.pin_drop_outlined),
          errorText: _showPinCodeError
              ? 'PIN Code is required when address is provided'
              : null,
        ),
        onChanged: (v) {
          if (_showPinCodeError && v.isNotEmpty) {
            setState(() => _showPinCodeError = false);
          }
        },
      ),
    );
  }

  Widget _photoBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('ID Proof Photos',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: FlowColors.primary)),
        const SizedBox(height: 8),
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
        _idProofPhotos.isNotEmpty
            ? SizedBox(
                height: 90,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _idProofPhotos.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (ctx, i) => Stack(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  _PhotoView(file: _idProofPhotos[i])),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(_idProofPhotos[i],
                              height: 90, width: 90, fit: BoxFit.cover),
                        ),
                      ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: GestureDetector(
                          onTap: () => setState(() {
                            _idProofPhotos = List.from(_idProofPhotos)
                              ..removeAt(i);
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

  Widget _textField(
    String label,
    TextEditingController ctrl, {
    IconData? icon,
    int maxLines = 1,
    void Function(String)? onChanged,
    String? errorText,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: ctrl,
        maxLines: maxLines,
        style: const TextStyle(fontSize: 18),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: icon != null ? Icon(icon) : null,
          errorText: errorText,
        ),
        onChanged: onChanged,
      ),
    );
  }
}

// ─── Private helpers ──────────────────────────────────────────────────────────

class _SecHeader extends StatelessWidget {
  const _SecHeader(this.title);
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

class _CardLbl extends StatelessWidget {
  const _CardLbl(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text,
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: FlowColors.medText,
              letterSpacing: 0.5)),
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
