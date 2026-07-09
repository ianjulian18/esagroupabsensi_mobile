import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ExtraHourScreen extends StatefulWidget {
  final String token;
  final String baseUrl;

  const ExtraHourScreen({
    super.key,
    required this.token,
    required this.baseUrl,
  });

  @override
  State<ExtraHourScreen> createState() => _ExtraHourScreenState();
}

class _ExtraHourScreenState extends State<ExtraHourScreen> {
  final TextEditingController _reasonController = TextEditingController();

  DateTime? _date;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  bool _isLoading = false;

  // Format Helper
  String _formatDate(DateTime? date) {
    if (date == null) return 'Pilih Tanggal';
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }

  String _formatTime(TimeOfDay? time) {
    if (time == null) return '--:--';
    return "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}";
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now().subtract(
        const Duration(days: 7),
      ), // Maksimal klaim lembur mundur 7 hari
      lastDate: DateTime.now().add(const Duration(days: 7)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.amber,
              onPrimary: Colors.black,
              surface: Color(0xFF1E1E1E),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _date = picked);
    }
  }

  Future<void> _selectTime(BuildContext context, bool isStart) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.amber,
              onPrimary: Colors.black,
              surface: Color(0xFF1E1E1E),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  Future<void> _submitRequest() async {
    if (_date == null ||
        _startTime == null ||
        _endTime == null ||
        _reasonController.text.isEmpty) {
      _showSnackBar(
        'Mohon lengkapi tanggal, jam, dan alasan lembur!',
        Colors.redAccent,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await http.post(
        Uri.parse('${widget.baseUrl}/extra-hour/request'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'date': _formatDate(_date),
          'start_time': _formatTime(_startTime),
          'end_time': _formatTime(_endTime),
          'reason': _reasonController.text,
        }),
      );

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
        backgroundColor: const Color(0xFF1E1E1E),
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
              Navigator.pop(context); // Kembali ke Home
            },
            child: const Text('OK', style: TextStyle(color: Colors.amber)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text(
          'KLAIM LEMBUR',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
        ),
        backgroundColor: Colors.amber,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Tanggal Lembur
              const Text(
                'Tanggal Pelaksanaan',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () => _selectDate(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[800]!),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calendar_today,
                        color: Colors.amber,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _formatDate(_date),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // 2. Jam Mulai & Selesai
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Jam Mulai',
                          style: TextStyle(color: Colors.grey, fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () => _selectTime(context, true),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 16,
                              horizontal: 12,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E1E1E),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey[800]!),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.access_time,
                                  color: Colors.amber,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _formatTime(_startTime),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                    ),
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
                          'Jam Selesai',
                          style: TextStyle(color: Colors.grey, fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () => _selectTime(context, false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 16,
                              horizontal: 12,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E1E1E),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey[800]!),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.access_time,
                                  color: Colors.amber,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _formatTime(_endTime),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                    ),
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

              // 3. Alasan / Pekerjaan
              const Text(
                'Rincian Pekerjaan',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _reasonController,
                style: const TextStyle(color: Colors.white),
                maxLines: 4,
                decoration: InputDecoration(
                  hintText:
                      'Tuliskan detail pekerjaan yang Anda lakukan saat lembur...',
                  hintStyle: const TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: const Color(0xFF1E1E1E),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[800]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.amber),
                  ),
                ),
              ),
              const SizedBox(height: 40),

              // 4. Tombol Submit
              SizedBox(
                height: 55,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _isLoading ? null : _submitRequest,
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.black)
                      : const Text(
                          'KIRIM KLAIM LEMBUR',
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
