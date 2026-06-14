import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../shared/widgets/flow_widgets.dart';
import '../../../shared/widgets/shared_customer_details_step.dart';
import '../data/customer_repository.dart';

class AddEditCustomerScreen extends StatefulWidget {
  const AddEditCustomerScreen({super.key, this.customerId});

  final int? customerId;

  bool get isEdit => customerId != null;

  @override
  State<AddEditCustomerScreen> createState() =>
      _AddEditCustomerScreenState();
}

class _AddEditCustomerScreenState extends State<AddEditCustomerScreen> {
  final _customerKey = GlobalKey<SharedCustomerDetailsStepState>();
  CustomerDetailsData? _initialData;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    if (!widget.isEdit) {
      setState(() => _loading = false);
      return;
    }

    final row = await CustomerRepository.instance
        .getCustomerById(widget.customerId!);
    if (!mounted) return;

    if (row == null) {
      setState(() => _loading = false);
      return;
    }

    List<File> existingPhotos = [];
    final pathsJson = row['id_proof_photo_paths'] as String?;
    if (pathsJson != null && pathsJson.isNotEmpty) {
      try {
        final paths = (jsonDecode(pathsJson) as List).cast<String>();
        existingPhotos = paths
            .map((p) => File(p))
            .where((f) => f.existsSync())
            .toList();
      } catch (_) {}
    }

    setState(() {
      _initialData = CustomerDetailsData(
        phone: row['phone'] as String? ?? '',
        name: row['name'] as String? ?? '',
        address: row['address'] as String? ?? '',
        idProofType: row['id_proof_type'] as String? ?? 'None',
        idNumber: row['id_proof_number'] as String? ?? '',
        idProofPhotos: existingPhotos,
        existingCustomerId: row['id'] as int?,
      );
      _loading = false;
    });
  }

  Future<void> _save() async {
    final data = _customerKey.currentState?.getData();
    if (data == null) return;

    if (data.name.trim().isEmpty) {
      _showError('Customer name is required');
      return;
    }

    if (data.phone.trim().isEmpty) {
      _showError('Phone number is required');
      return;
    }

    final addressError = _customerKey.currentState?.validate();
    if (addressError != null) {
      _showError(addressError);
      return;
    }

    final phoneExists = await CustomerRepository.instance.phoneExistsForOther(
      data.phone,
      excludeId: widget.customerId,
    );
    if (!mounted) return;

    if (phoneExists) {
      _showError('Customer with this phone number already exists');
      return;
    }

    setState(() => _saving = true);
    try {
      if (widget.isEdit) {
        await CustomerRepository.instance
            .updateCustomer(widget.customerId!, data);
      } else {
        await CustomerRepository.instance.createCustomer(data);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.isEdit
              ? 'Customer updated successfully'
              : 'Customer added successfully'),
          backgroundColor: FlowColors.green,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) _showError('Error saving customer: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: Text(
          widget.isEdit ? 'Edit Customer' : 'Add New Customer',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              child: SharedCustomerDetailsStep(
                key: _customerKey,
                initialData: _initialData,
                pledgeNumber: 'customer',
              ),
            ),
      bottomNavigationBar: _loading
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: FlowColors.primary,
                      foregroundColor: FlowColors.textOnNavyLarge,
                      disabledBackgroundColor:
                          FlowColors.primary.withAlpha(150),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                color: FlowColors.textOnNavyLarge, strokeWidth: 2.5),
                          )
                        : const Icon(Icons.save, size: 22),
                    label: Text(
                      _saving ? 'Saving...' : 'SAVE',
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
