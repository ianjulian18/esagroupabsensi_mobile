import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class VisitLogScreen extends StatefulWidget {
  final String token;
  final String baseUrl;
  final String storeName; // Menerima nama toko agar otomatis terisi

  const VisitLogScreen({
    super.key,
    required this.token,
    required this.baseUrl,
    required this.storeName,
  });

  @override
  State<VisitLogScreen> createState() => _VisitLogScreenState();
}

class _VisitLogScreenState extends State<VisitLogScreen> {
  final TextEditingController _issueController = TextEditingController();
  final TextEditingController _actionController = TextEditingController();
  final TextEditingController _targetController = TextEditingController();
  final TextEditingController _actualController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  DateTime? _deadline;
  bool _isLoading = false;

  String _formatDate(DateTime? date) {
    if (date == null) return 'Pilih Tanggal Deadline';
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFFD32F2F),
              onPrimary: Colors.black,
              surface: Colors.white,
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _deadline = picked);
    }
  }

  Future<void> _submitLog() async {
    if (_issueController.text.isEmpty ||
        _actionController.text.isEmpty ||
        _targetController.text.isEmpty ||
        _actualController.text.isEmpty ||
        _deadline == null) {
      _showSnackBar(
        'Mohon lengkapi semua data wajib (kecuali Notes)!',
        Colors.redAccent,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await http.post(
        Uri.parse('${widget.baseUrl}/visit-log/submit'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'store_name': widget.storeName,
          'issue': _issueController.text,
          'action': _actionController.text,
          'target': _targetController.text,
          'actual': _actualController.text,
          'deadline': _formatDate(_deadline),
          'notes': _notesController.text,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 201) {
        _showSuccessDialog(data['message']);
      } else {
        _showSnackBar(
          data['message'] ?? 'Gagal mengirim laporan',
          Colors.redAccent,
        );
      }
    } catch (e) {
      _showSnackBar('Error: Gagal terhubung ke server', Colors.redAccent);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  void _showSuccessDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Text('Berhasil', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Tutup dialog
              Navigator.pop(context); // Kembali ke halaman utama (Home)
            },
            child: const Text('OK', style: TextStyle(color: Color(0xFFD32F2F))),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: TextField(
        controller: controller,
        style: const TextStyle(color: Colors.white),
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.grey),
          filled: true,
          fillColor: Colors.white,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey[800]!),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFD32F2F)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text(
          'VISIT LOG',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
        ),
        backgroundColor: const Color(0xFFD32F2F),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blueAccent),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Lokasi Kunjungan:',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    Text(
                      widget.storeName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              _buildTextField(
                'Issue (Masalah yang ditemukan)',
                _issueController,
                maxLines: 2,
              ),
              _buildTextField(
                'Action (Tindakan yang diambil)',
                _actionController,
                maxLines: 2,
              ),
              _buildTextField(
                'Target (Target penyelesaian)',
                _targetController,
              ),
              _buildTextField('Actual (Hasil saat ini)', _actualController),

              const Text(
                'Deadline Penyelesaian',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () => _selectDate(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[800]!),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calendar_today,
                        color: Color(0xFFD32F2F),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _formatDate(_deadline),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              _buildTextField(
                'Notes (Catatan Tambahan - Opsional)',
                _notesController,
                maxLines: 2,
              ),

              const SizedBox(height: 24),
              SizedBox(
                height: 55,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD32F2F),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _isLoading ? null : _submitLog,
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.black)
                      : const Text(
                          'KIRIM LAPORAN VISIT',
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            letterSpacing: 1.2,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
