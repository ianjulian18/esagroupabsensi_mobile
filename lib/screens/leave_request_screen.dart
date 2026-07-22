import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class LeaveRequestScreen extends StatefulWidget {
  final String token;
  final String baseUrl;

  const LeaveRequestScreen({
    super.key,
    required this.token,
    required this.baseUrl,
  });

  @override
  State<LeaveRequestScreen> createState() => _LeaveRequestScreenState();
}

class _LeaveRequestScreenState extends State<LeaveRequestScreen> {
  final TextEditingController _reasonController = TextEditingController();

  String _selectedType = 'cuti';
  DateTime? _startDate;
  DateTime? _endDate;
  XFile? _document;
  bool _isLoading = false;

  // Formatting tanggal manual agar tidak perlu install package tambahan
  String _formatDate(DateTime? date) {
    if (date == null) return 'Pilih Tanggal';
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }

  Future<void> _selectDate(BuildContext context, bool isStart) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now().subtract(
        const Duration(days: 30),
      ), // Bisa cuti mundur (misal sakit)
      lastDate: DateTime.now().add(const Duration(days: 90)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: const Color(0xFF2E3190), // warna header kalender
              onPrimary: Colors.black, // warna teks di header
              surface: Colors.white, // background kalender
              onSurface: Colors.white, // warna angka
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          // Jika end date belum dipilih atau lebih kecil dari start date, samakan
          if (_endDate == null || _endDate!.isBefore(_startDate!)) {
            _endDate = picked;
          }
        } else {
          _endDate = picked;
        }
      });
    }
  }

  Future<void> _pickDocument() async {
    final ImagePicker picker = ImagePicker();
    // Boleh dari kamera atau galeri untuk surat dokter
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 50,
    );

    if (image != null) {
      setState(() {
        _document = image;
      });
    }
  }

  Future<void> _submitRequest() async {
    if (_startDate == null ||
        _endDate == null ||
        _reasonController.text.isEmpty) {
      _showSnackBar('Mohon lengkapi tanggal dan alasan!', Colors.redAccent);
      return;
    }

    if (_selectedType == 'sakit' && _document == null) {
      _showSnackBar(
        'Surat Dokter (Bukti) wajib dilampirkan jika sakit!',
        Colors.redAccent,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${widget.baseUrl}/leave/request'),
      );
      request.headers.addAll({
        'Authorization': 'Bearer ${widget.token}',
        'Accept': 'application/json',
      });

      request.fields['type'] = _selectedType;
      request.fields['start_date'] = _formatDate(_startDate);
      request.fields['end_date'] = _formatDate(_endDate);
      request.fields['reason'] = _reasonController.text;

      if (_document != null) {
        request.files.add(
          await http.MultipartFile.fromPath('document', _document!.path),
        );
      }

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);
      final data = jsonDecode(response.body);

      if (response.statusCode == 201) {
        _showSuccessDialog(data['message']);
      } else {
        _showSnackBar(
          data['message'] ?? 'Gagal mengirim pengajuan',
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
              Navigator.pop(context); // Kembali ke halaman sebelumnya
            },
            child: const Text('OK', style: TextStyle(color: const Color(0xFF2E3190))),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text(
          'PENGAJUAN CUTI / IZIN',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
        ),
        backgroundColor: const Color(0xFF2E3190),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Tipe Pengajuan
              const Text(
                'Tipe Pengajuan',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[800]!),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedType,
                    dropdownColor: Colors.white,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    icon: const Icon(
                      Icons.arrow_drop_down,
                      color: const Color(0xFF2E3190),
                    ),
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(
                        value: 'cuti',
                        child: Text('Annual Leave', style: TextStyle(color: Colors.black87)),
                      ),
                      DropdownMenuItem(
                        value: 'izin',
                        child: Text('Permission', style: TextStyle(color: Colors.black87)),
                      ),
                      DropdownMenuItem(
                        value: 'sakit', 
                        child: Text('Medical Leave', style: TextStyle(color: Colors.black87))
                      ),
                      DropdownMenuItem(
                        value: 'shift_swap', 
                        child: Text('Shift Swap', style: TextStyle(color: Colors.black87))
                      ),
                      DropdownMenuItem(
                        value: 'extra_off', 
                        child: Text('Extra Off', style: TextStyle(color: Colors.black87))
                      ),
                      DropdownMenuItem(
                        value: 'store_closed', 
                        child: Text('Store Closed', style: TextStyle(color: Colors.black87))
                      ),
                    ],
                    onChanged: (value) {
                      setState(() => _selectedType = value!);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // 2. Tanggal Pilihan
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Dari Tanggal',
                          style: TextStyle(color: Colors.grey, fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () => _selectDate(context, true),
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
                                  color: const Color(0xFF2E3190),
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _formatDate(_startDate),
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Sampai Tanggal',
                          style: TextStyle(color: Colors.grey, fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () => _selectDate(context, false),
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
                                  color: const Color(0xFF2E3190),
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _formatDate(_endDate),
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // 3. Alasan
              const Text(
                'Alasan / Keterangan',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _reasonController,
                style: const TextStyle(color: Colors.white),
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Tuliskan alasan pengajuan Anda di sini...',
                  hintStyle: const TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: Colors.white,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[800]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: const Color(0xFF2E3190)),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // 4. Lampiran Bukti
              const Text(
                'Lampiran Bukti (Opsional / Wajib jika Sakit)',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: _pickDocument,
                child: Container(
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _document != null
                          ? Colors.green
                          : Colors.grey[800]!,
                      style: BorderStyle.solid,
                    ),
                  ),
                  child: _document != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            File(_document!.path),
                            fit: BoxFit.cover,
                            width: double.infinity,
                          ),
                        )
                      : const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.upload_file,
                              color: const Color(0xFF2E3190),
                              size: 40,
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Klik untuk unggah foto (Galeri/Kamera)',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 40),

              // 5. Tombol Submit
              SizedBox(
                height: 55,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E3190),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _isLoading ? null : _submitRequest,
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.black)
                      : const Text(
                          'KIRIM PENGAJUAN',
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
