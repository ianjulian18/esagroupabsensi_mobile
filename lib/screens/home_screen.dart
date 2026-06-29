import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'history_screen.dart';
// import 'dart:io';
import 'package:image_picker/image_picker.dart';

class HomeScreen extends StatefulWidget {
  final String token;
  final String name;
  final String baseUrl;

  const HomeScreen({
    super.key,
    required this.token,
    required this.name,
    required this.baseUrl,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isLoading = false;
  String _statusMessage = 'Ketuk tombol di bawah untuk melakukan absensi';

  // Fungsi sakti untuk meminta izin GPS dan mengambil koordinat HP Karyawan
  Future<Position?> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Cek apakah GPS HP aktif
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _statusMessage = 'Gagal: Mohon aktifkan GPS di HP Anda!');
      return null;
    }

    // Cek izin akses lokasi aplikasi
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(
          () => _statusMessage = 'Gagal: Izin lokasi ditolak oleh pengguna.',
        );
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(
        () => _statusMessage =
            'Gagal: Izin lokasi ditolak permanen. Ubah di pengaturan HP.',
      );
      return null;
    }

    // Ambil koordinat saat ini jika semua aman
    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  // Fungsi untuk menembak API Absen Laravel
  // Fungsi untuk menembak API Absen Laravel & Foto Selfie
  // Fungsi untuk menembak API Absen Laravel & Foto Selfie (Logika Baru: Cek GPS Dulu)
  Future<void> _processAttendance() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Mengecek lokasi GPS Anda...';
    });

    try {
      // ---------------------------------------------------------
      // TAHAP 1: KUNCI KOORDINAT LOKASI TERLEBIH DAHULU
      // ---------------------------------------------------------
      Position? position = await _getCurrentLocation();

      if (position == null) {
        setState(() => _isLoading = false);
        return; // Berhenti jika GPS mati atau tidak diizinkan
      }

      // ---------------------------------------------------------
      // TAHAP 2: CEK JARAK LOKAL DI HP (GEOFENCING FRONTEND)
      // ---------------------------------------------------------
      // ⚠️ PENTING: Samakan koordinat ini dengan yang ada di Laravel!
      double officeLat = -7.2356163;
      double officeLon = 112.73303;
      double maxRadius = 50.0; // 50 meter

      // Fitur sakti Geolocator untuk menghitung jarak akurat
      double distanceInMeters = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        officeLat,
        officeLon,
      );

      // Jika lebih dari 50 meter, TOLAK DAN JANGAN BUKA KAMERA!
      if (distanceInMeters > maxRadius) {
        setState(() {
          _isLoading = false;
          _statusMessage =
              'Ditolak: Jarak Anda ${distanceInMeters.round()} meter dari kantor.';
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Anda di luar jangkauan kantor! (Jarak: ${distanceInMeters.round()} m)',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
        return; // <--- Eksekusi berhenti total di sini.
      }

      // ---------------------------------------------------------
      // TAHAP 3: JIKA JARAK AMAN, BARU BUKA KAMERA
      // ---------------------------------------------------------
      setState(() => _statusMessage = 'Lokasi valid! Membuka kamera...');

      final ImagePicker picker = ImagePicker();
      final XFile? photo = await picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 50,
      );

      // Jika user membatalkan foto
      if (photo == null) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Batal: Foto selfie wajib dilakukan.';
        });
        return;
      }

      // ---------------------------------------------------------
      // TAHAP 4: KIRIM SEMUANYA KE LARAVEL
      // ---------------------------------------------------------
      setState(() => _statusMessage = 'Mengirim data absen ke server...');

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${widget.baseUrl}/attendance/scan'),
      );

      request.headers.addAll({
        'Authorization': 'Bearer ${widget.token}',
        'Accept': 'application/json',
      });

      request.fields['latitude'] = position.latitude.toString();
      request.fields['longitude'] = position.longitude.toString();

      request.files.add(await http.MultipartFile.fromPath('photo', photo.path));

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);
      final data = jsonDecode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        setState(() {
          _statusMessage = data['message'];
        });
        if (!mounted) return;
        _showSuccessDialog(data['message']);
      } else {
        setState(() {
          _statusMessage = data['message'] ?? 'Gagal melakukan absensi.';
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error: Gagal terhubung ke server atau kamera.';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showSuccessDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Text('Sukses'),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
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
          'ESA GROUP ABSENSI',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
        ),
        backgroundColor: Colors.amber,
        elevation: 0,
        actions: [
          // TOMBOL BARU: UNTUK MELIHAT RIWAYAT
          IconButton(
            icon: const Icon(Icons.history, color: Colors.black),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => HistoryScreen(
                    token: widget.token,
                    baseUrl: widget.baseUrl,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.black),
            onPressed: () {
              Navigator.pushReplacementNamed(context, '/');
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.account_circle, size: 70, color: Colors.grey),
            const SizedBox(height: 8),
            Text(
              'Selamat Datang,',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey[400]),
            ),
            Text(
              widget.name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 40),

            // Kartu status penunjuk info
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[800]!),
              ),
              child: Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
            const SizedBox(height: 40),

            // Tombol Utama Absen (Otomatis mendeteksi Masuk/Pulang dari sistem Laravel)
            GestureDetector(
              onTap: _isLoading ? null : _processAttendance,
              child: Container(
                height: 180,
                width: 180,
                decoration: BoxDecoration(
                  color: _isLoading ? Colors.grey : Colors.amber,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.amber.withValues(alpha: 0.3),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Center(
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.black)
                      : const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.fingerprint,
                              size: 60,
                              color: Colors.black,
                            ),
                            SizedBox(height: 8),
                            Text(
                              'TAP TO ABSEN',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
