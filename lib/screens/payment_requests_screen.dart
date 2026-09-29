import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_pagination_service.dart';
import '../utils/lot_formatters.dart';

class PaymentRequestsScreen extends StatefulWidget {
  const PaymentRequestsScreen({super.key, this.admin = false});
  final bool admin;
  @override
  State<PaymentRequestsScreen> createState() => _PaymentRequestsScreenState();
}

class _PaymentRequestsScreenState extends State<PaymentRequestsScreen> {
  final _client = Supabase.instance.client;
  bool _loading = true, _saving = false;
  String? _error;
  List<Map<String, dynamic>> _requests = [], _ownerships = [];
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final requests = await SupabasePaginationService.selectAll(
        supabase: _client,
        table: 'payment_requests',
        columns: '*',
        orderColumn: 'request_id',
      );
      final ownerships = widget.admin
          ? await SupabasePaginationService.selectAll(
              supabase: _client,
              table: 'lot_ownership',
              columns:
                  'ownership_id,lot_id,total_months,months_paid,status,cemetery_lot(lot_number,lot_label,block_number)',
              orderColumn: 'ownership_id',
            )
          : List<Map<String, dynamic>>.from(
              await _client
                  .from('lot_ownership')
                  .select(
                    'ownership_id,lot_id,total_months,months_paid,status,cemetery_lot(lot_number,lot_label,block_number)',
                  )
                  .eq('user_id', _client.auth.currentUser!.id),
            );
      if (!mounted) return;
      setState(() {
        _requests = requests.reversed.toList();
        _ownerships = ownerships;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load payments: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic>? _ownership(Object? id) {
    for (final o in _ownerships) {
      if (o['ownership_id'] == id) return o;
    }
    return null;
  }

  String _label(Map<String, dynamic> o) =>
      lotReference(Map<String, dynamic>.from(o['cemetery_lot'] as Map? ?? {}));
  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _submit() async {
    final amount = TextEditingController(), notes = TextEditingController();
    var date = DateTime.now();
    int? ownershipId = _ownerships.isEmpty
        ? null
        : _ownerships.first['ownership_id'] as int;
    PlatformFile? proof;
    String? error;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, change) => AlertDialog(
          title: const Text('Submit payment proof'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: ownershipId,
                    decoration: const InputDecoration(labelText: 'Owned lot'),
                    items: _ownerships
                        .map(
                          (o) => DropdownMenuItem(
                            value: o['ownership_id'] as int,
                            child: Text(_label(o)),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => change(() => ownershipId = v),
                  ),
                  TextField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Amount paid (PHP)',
                    ),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.calendar_today),
                    label: Text(DateFormat.yMMMd().format(date)),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: date,
                        firstDate: DateTime(1900),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null && context.mounted) {
                        change(() => date = picked);
                      }
                    },
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.upload_file),
                    label: Text(
                      proof?.name ?? 'Choose receipt image (max 5 MB)',
                    ),
                    onPressed: () async {
                      final result = await FilePicker.platform.pickFiles(
                        type: FileType.custom,
                        allowedExtensions: ['jpg', 'jpeg', 'png'],
                        withData: true,
                      );
                      if (result == null || !context.mounted) return;
                      final file = result.files.single;
                      if (file.size > 5 * 1024 * 1024 || file.bytes == null) {
                        change(
                          () => error =
                              'Choose a JPG or PNG no larger than 5 MB.',
                        );
                        return;
                      }
                      change(() {
                        proof = file;
                        error = null;
                      });
                    },
                  ),
                  TextField(
                    controller: notes,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Notes / reference number',
                    ),
                  ),
                  const Text(
                    'Your payment remains pending until an administrator verifies the receipt.',
                  ),
                  if (error != null)
                    Text(error!, style: const TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value = double.tryParse(amount.text.trim());
                if (ownershipId == null ||
                    value == null ||
                    !value.isFinite ||
                    value <= 0 ||
                    proof == null) {
                  change(
                    () => error =
                        'Choose a lot, enter a positive amount, and attach a receipt.',
                  );
                  return;
                }
                Navigator.pop(context, true);
              },
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
    final amountValue = double.tryParse(amount.text.trim());
    final notesValue = notes.text.trim();
    amount.dispose();
    notes.dispose();
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    try {
      final ext = proof!.extension!.toLowerCase();
      final path =
          '${_client.auth.currentUser!.id}/${DateTime.now().microsecondsSinceEpoch}.$ext';
      await _client.storage
          .from('payment-proofs')
          .uploadBinary(
            path,
            proof!.bytes!,
            fileOptions: FileOptions(
              contentType: ext == 'png' ? 'image/png' : 'image/jpeg',
            ),
          );
      await _client.rpc(
        'submit_payment_request',
        params: {
          'p_ownership_id': ownershipId,
          'p_amount': amountValue,
          'p_payment_date': DateFormat('yyyy-MM-dd').format(date),
          'p_receipt_path': path,
          'p_notes': notesValue,
        },
      );
      _message('Payment submitted for review.');
      await _load();
    } catch (e) {
      _message('Payment was not submitted: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _proof(Map<String, dynamic> request) async {
    try {
      final path = request['receipt_url']?.toString() ?? '';
      if (path.isEmpty || path.startsWith('http')) {
        _message('No private receipt image is available for this record.');
        return;
      }
      final Uint8List bytes = await _client.storage
          .from('payment-proofs')
          .download(path);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Proof of payment'),
          content: SizedBox(
            width: 650,
            height: 500,
            child: InteractiveViewer(
              child: Image.memory(
                bytes,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) =>
                    const Text('This receipt is not a readable image.'),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      _message('Could not open proof: $e');
    }
  }

  Future<void> _review(Map<String, dynamic> request, bool approve) async {
    final notes = TextEditingController(),
        months = TextEditingController(text: '0');
    final ownership = _ownership(request['ownership_id']);
    final remaining =
        (ownership?['total_months'] as int? ?? 0) -
        (ownership?['months_paid'] as int? ?? 0);
    String? error;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, change) => AlertDialog(
          title: Text(approve ? 'Approve payment' : 'Reject payment'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('PHP ${request['amount']} · ${request['payment_date']}'),
                if (approve)
                  TextField(
                    controller: months,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Installment months to credit (0–$remaining)',
                      helperText:
                          'Use 0 for partial payments that do not complete a month.',
                    ),
                  ),
                TextField(
                  controller: notes,
                  decoration: InputDecoration(
                    labelText: approve
                        ? 'Review notes'
                        : 'Reason for rejection (required)',
                  ),
                ),
                if (error != null)
                  Text(error!, style: const TextStyle(color: Colors.red)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final credit = int.tryParse(months.text);
                if ((approve &&
                        (credit == null || credit < 0 || credit > remaining)) ||
                    (!approve && notes.text.trim().isEmpty)) {
                  change(
                    () => error = 'Check the credited months and review notes.',
                  );
                  return;
                }
                Navigator.pop(context, true);
              },
              child: Text(approve ? 'Approve' : 'Reject'),
            ),
          ],
        ),
      ),
    );
    final noteValue = notes.text.trim(),
        credit = int.tryParse(months.text) ?? 0;
    notes.dispose();
    months.dispose();
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await _client.rpc(
        'review_payment_request',
        params: {
          'p_request_id': request['request_id'],
          'p_approve': approve,
          'p_admin_notes': noteValue,
          'p_months_credit': approve ? credit : 0,
        },
      );
      _message(
        approve ? 'Payment approved and recorded.' : 'Payment rejected.',
      );
      await _load();
    } catch (e) {
      _message('Review failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.admin ? 'Payment review' : 'My payment requests'),
      actions: [
        IconButton(
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh',
        ),
      ],
    ),
    floatingActionButton: widget.admin
        ? null
        : FloatingActionButton.extended(
            onPressed: _loading || _saving || _ownerships.isEmpty
                ? null
                : _submit,
            icon: const Icon(Icons.upload_file),
            label: const Text('Submit payment'),
          ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
            children: [
              if (_saving) const LinearProgressIndicator(),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.red)),
              if (!widget.admin && _ownerships.isEmpty && _error == null)
                const Text('No lots are linked to your account yet.'),
              if (!widget.admin)
                ..._ownerships.map(
                  (o) => ListTile(
                    title: Text('Lot ${_label(o)}'),
                    subtitle: Text(
                      '${o['status']} · ${o['months_paid'] ?? 0}/${o['total_months']} installment months paid',
                    ),
                  ),
                ),
              if (_requests.isEmpty && _error == null)
                const Text('No payment requests yet.'),
              ..._requests.map((r) {
                final o = _ownership(r['ownership_id']);
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Lot ${o == null ? r['ownership_id'] : _label(o)} · PHP ${r['amount']}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text('${r['status']} · ${r['payment_date']}'),
                        if (r['notes'] != null)
                          Text('Owner notes: ${r['notes']}'),
                        if (r['admin_notes'] != null)
                          Text('Review: ${r['admin_notes']}'),
                        Wrap(
                          spacing: 12,
                          children: [
                            TextButton.icon(
                              onPressed: () => _proof(r),
                              icon: const Icon(Icons.receipt),
                              label: const Text('View receipt'),
                            ),
                            if (widget.admin &&
                                r['status'].toString().toLowerCase() ==
                                    'pending') ...[
                              FilledButton(
                                onPressed: _saving
                                    ? null
                                    : () => _review(r, true),
                                child: const Text('Approve'),
                              ),
                              OutlinedButton(
                                onPressed: _saving
                                    ? null
                                    : () => _review(r, false),
                                child: const Text('Reject'),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
  );
}
