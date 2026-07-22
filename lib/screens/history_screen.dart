import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class HistoryScreen extends StatefulWidget {
  final String token;
  final String baseUrl;

  const HistoryScreen({super.key, required this.token, required this.baseUrl});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<dynamic> _historyData = [];
  List<dynamic> _scheduleData = [];
  bool _isLoading = true;
  bool _isLoadingSchedule = true;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
    _fetchSchedule();
  }

  Future<void> _fetchHistory() async {
    try {
      final response = await http.get(
        Uri.parse('${widget.baseUrl}/attendance/history'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _historyData = data['data'];
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
        _showErrorSnackBar('Gagal mengambil data riwayat.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showErrorSnackBar('Error: Gagal terhubung ke server riwayat.');
    }
  }

  Future<void> _fetchSchedule() async {
    try {
      final response = await http.get(
        Uri.parse('${widget.baseUrl}/my-schedule/future'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _scheduleData = data['data'];
          _isLoadingSchedule = false;
        });
      } else {
        setState(() => _isLoadingSchedule = false);
        _showErrorSnackBar('Gagal mengambil jadwal roster.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingSchedule = false);
      _showErrorSnackBar('Error: Gagal terhubung ke server jadwal.');
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Widget _buildTimeRow(String label, String? time, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Text(
          '$label: ${time ?? '--:--'}',
          style: const TextStyle(color: Colors.black87, fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildHistoryTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF2E3190)));
    }
    if (_historyData.isEmpty) {
      return const Center(
        child: Text(
          'Belum ada riwayat absensi.',
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _historyData.length,
      itemBuilder: (context, index) {
        final item = _historyData[index];
        final List<dynamic> visits = item['visits'] ?? [];

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: Colors.grey.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 5)),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      item['date'] ?? 'Tanggal Tidak Valid',
                      style: const TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Builder(
                      builder: (context) {
                        String statusStr = (item['status'] ?? '-').toLowerCase();
                        Color statusColor;
                        if (statusStr == 'hadir') {
                          statusColor = const Color(0xFF4CAF50); // Hijau
                        } else if (statusStr == 'terlambat') {
                          statusColor = const Color(0xFFFF9800); // Oranye
                        } else if (statusStr == 'off' || statusStr == 'libur') {
                          statusColor = const Color(0xFF9E9E9E); // Abu-abu
                        } else {
                          statusColor = const Color(0xFFF44336); // Merah (Alpha/Tidak Hadir)
                        }

                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            statusStr.toUpperCase(),
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.corporate_fare, color: Colors.grey, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      item['user']?['location']?['name'] ?? 'Kantor Pusat / Default',
                      style: const TextStyle(color: Colors.black54, fontSize: 13),
                    ),
                  ],
                ),
                const Divider(color: Colors.grey, height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildTimeRow('Masuk', item['clock_in'], Icons.login, Colors.green),
                    _buildTimeRow('Pulang', item['clock_out'], Icons.logout, Colors.redAccent),
                  ],
                ),
                if (visits.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Daftar Visit:',
                    style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ...visits.map((visit) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.store, color: Colors.blueAccent, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  visit['location_name'] ?? 'Lokasi Tidak Diketahui',
                                  style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                              ),
                              if (visit['status'] == 'completed')
                                const Icon(Icons.check_circle, color: Colors.green, size: 16)
                              else
                                const Icon(Icons.pending, color: Colors.orange, size: 16),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.subdirectory_arrow_right, color: Colors.grey, size: 14),
                              const SizedBox(width: 4),
                              RichText(
                                text: TextSpan(
                                  children: [
                                    TextSpan(text: 'In: ${visit['visit_in'] ?? '--:--'}', style: const TextStyle(color: Colors.blue, fontSize: 12, fontWeight: FontWeight.bold)),
                                    const TextSpan(text: ' | ', style: TextStyle(color: Colors.grey, fontSize: 12)),
                                    TextSpan(text: 'Out: ${visit['visit_out'] ?? '--:--'}', style: const TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildScheduleTab() {
    if (_isLoadingSchedule) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF2E3190)));
    }
    if (_scheduleData.isEmpty) {
      return const Center(
        child: Text(
          'Tidak ada data jadwal.',
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _scheduleData.length,
      itemBuilder: (context, index) {
        final item = _scheduleData[index];
        final List<dynamic> stores = item['stores'] ?? [];

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(color: Colors.grey.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 5)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${item['day']}, ${item['date']}',
                    style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E3190).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      item['shift_name'],
                      style: const TextStyle(color: Color(0xFF2E3190), fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  )
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.access_time, color: Colors.grey, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    '${item['start_time']} - ${item['end_time']}',
                    style: const TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.route, color: Colors.grey, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    'Tipe Routing: ${(item['routing_type'] == 'routing_aktif') ? "Aktif (Sesuai Urutan)" : "Bebas Visit"}',
                    style: const TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ],
              ),
              if (stores.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Toko Kunjungan:', style: TextStyle(color: Colors.black54, fontSize: 12)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: stores.map((s) => Chip(
                    label: Text(s.toString(), style: const TextStyle(fontSize: 12)),
                    backgroundColor: Colors.blueAccent.withValues(alpha: 0.2),
                    labelStyle: const TextStyle(color: Colors.blueAccent),
                    padding: EdgeInsets.zero,
                  )).toList(),
                )
              ]
            ],
          ),
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FB),
        appBar: AppBar(
          title: const Text(
            'ATTENDANCE',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
          ),
          backgroundColor: const Color(0xFF2E3190),
          iconTheme: const IconThemeData(color: Colors.white),
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            tabs: [
              Tab(text: 'Riwayat Absen', icon: Icon(Icons.history)),
              Tab(text: 'Jadwal 30 Hari', icon: Icon(Icons.calendar_month)),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildHistoryTab(),
            _buildScheduleTab(),
          ],
        ),
      ),
    );
  }
}

