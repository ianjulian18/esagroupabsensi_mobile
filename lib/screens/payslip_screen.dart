import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class PayslipScreen extends StatefulWidget {
  final String token;
  final String baseUrl;

  const PayslipScreen({super.key, required this.token, required this.baseUrl});

  @override
  State<PayslipScreen> createState() => _PayslipScreenState();
}

class _PayslipScreenState extends State<PayslipScreen> {
  List<dynamic> _payslips = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchPayslips();
  }

  Future<void> _fetchPayslips() async {
    try {
      final response = await http.get(
        Uri.parse('${widget.baseUrl}/payslips'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _payslips = data['data'];
          _isLoading = false;
        });
      } else {
        _showError('Gagal mengambil data slip gaji');
      }
    } catch (e) {
      _showError('Gagal terhubung ke server');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() => _isLoading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  // Helper Format Rupiah
  String _formatRupiah(dynamic number) {
    final currencyFormatter = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    return currencyFormatter.format(int.parse(number.toString()));
  }

  // Helper Format Bulan & Tahun
  String _formatMonthYear(String dateString) {
    DateTime date = DateTime.parse(dateString);
    List<String> months = [
      'Januari',
      'Februari',
      'Maret',
      'April',
      'Mei',
      'Juni',
      'Juli',
      'Agustus',
      'September',
      'Oktober',
      'November',
      'Desember',
    ];
    return "${months[date.month - 1]} ${date.year}";
  }

  // Pop-up Detail Slip Gaji (Sudah diperbaiki anti-overflow)
  void _showPayslipDetail(dynamic slip) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height:
            MediaQuery.of(context).size.height *
            0.75, // Tinggi pop-up 75% layar
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 50,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: Text(
                'SLIP GAJI - ${_formatMonthYear(slip['period']).toUpperCase()}',
                style: const TextStyle(
                  color: const Color(0xFF2E3190),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Center(
              child: Text(
                'ESA GROUP',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ),
            const Divider(color: Colors.white24, height: 30, thickness: 1),

            // --- BAGIAN INI DIBUAT BISA DI-SCROLL AGAR TIDAK OVERFLOW ---
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'PENDAPATAN',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildDetailRow(
                      'Gaji Pokok',
                      slip['basic_salary'],
                      Colors.white70,
                    ),
                    _buildDetailRow(
                      'Tunjangan',
                      slip['allowances'],
                      Colors.white70,
                    ),
                    _buildDetailRow(
                      'Uang Lembur',
                      slip['overtime_pay'],
                      Colors.white70,
                    ),

                    const SizedBox(height: 24),

                    const Text(
                      'POTONGAN',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildDetailRow(
                      'Total Potongan',
                      slip['deductions'],
                      Colors.redAccent,
                    ),

                    const Divider(
                      color: Colors.white24,
                      height: 30,
                      thickness: 1,
                    ),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'GAJI BERSIH',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          _formatRupiah(slip['net_salary']),
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20), // Spasi tambahan di bawah
                  ],
                ),
              ),
            ),
            // -------------------------------------------------------------

            // Tombol Tutup (Akan selalu menempel di paling bawah)
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[800],
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                    label: const Text(
                      'TUTUP',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E3190),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      _downloadPdf(slip);
                    },
                    icon: const Icon(Icons.download, color: Colors.black),
                    label: const Text(
                      'UNDUH PDF',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadPdf(dynamic slip) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text('ESA GROUP', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
              ),
              pw.Center(
                child: pw.Text('SLIP GAJI', style: pw.TextStyle(fontSize: 18)),
              ),
              pw.SizedBox(height: 30),
              pw.Text('Periode: ${_formatMonthYear(slip['period']).toUpperCase()}', style: pw.TextStyle(fontSize: 14)),
              pw.SizedBox(height: 20),
              
              pw.Text('PENDAPATAN', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.Divider(),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Gaji Pokok'), pw.Text(_formatRupiah(slip['basic_salary']))]),
              pw.SizedBox(height: 8),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Tunjangan'), pw.Text(_formatRupiah(slip['allowances']))]),
              pw.SizedBox(height: 8),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Uang Lembur'), pw.Text(_formatRupiah(slip['overtime_pay']))]),
              pw.SizedBox(height: 20),
              
              pw.Text('POTONGAN', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.Divider(),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Total Potongan'), pw.Text(_formatRupiah(slip['deductions']))]),
              pw.SizedBox(height: 20),
              
              pw.Divider(thickness: 2),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text('GAJI BERSIH', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)), 
                pw.Text(_formatRupiah(slip['net_salary']), style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold))
              ]),
            ],
          );
        },
      ),
    );

    await Printing.sharePdf(bytes: await pdf.save(), filename: 'Slip_Gaji_${slip['period']}.pdf');
  }

  Widget _buildDetailRow(String label, dynamic value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(
            _formatRupiah(value),
            style: TextStyle(color: valueColor, fontWeight: FontWeight.w500),
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
          'SLIP GAJI',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
        ),
        backgroundColor: const Color(0xFF2E3190),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: const Color(0xFF2E3190)))
          : _payslips.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.receipt_long, color: Colors.grey, size: 60),
                  SizedBox(height: 16),
                  Text(
                    'Belum ada slip gaji yang diterbitkan.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _payslips.length,
              itemBuilder: (context, index) {
                final slip = _payslips[index];
                return Card(
                  color: Colors.white,
                  margin: const EdgeInsets.only(bottom: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey[800]!),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: const CircleAvatar(
                      backgroundColor: const Color(0xFF2E3190),
                      child: Icon(Icons.request_quote, color: Colors.black),
                    ),
                    title: Text(
                      'Periode ${_formatMonthYear(slip['period'])}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        'Gaji Bersih: ${_formatRupiah(slip['net_salary'])}',
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: Colors.grey,
                    ),
                    onTap: () => _showPayslipDetail(slip),
                  ),
                );
              },
            ),
    );
  }
}
