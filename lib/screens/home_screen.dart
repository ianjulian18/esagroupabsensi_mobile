import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'history_screen.dart';

class HomeScreen extends StatefulWidget {
  final String token;
  final String name;
  final String baseUrl;
  // --- VARIABEL BARU UNTUK LOKASI DINAMIS ---
  final double officeLat;
  final double officeLon;
  final double maxRadius;
  final bool isLocationLocked;

  const HomeScreen({
    super.key,
    required this.token,
    required this.name,
    required this.baseUrl,
    // --- WAJIB DIKIRIM DARI LOGIN ---
    required this.officeLat,
    required this.officeLon,
    required this.maxRadius,
    required this.isLocationLocked,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isLoading = false;
  String _statusMessage = 'Geser tombol di bawah untuk melakukan absensi';

  // ---------------------------------------------------------
  // KONFIGURASI LOKASI KANTOR & GEOFENCING
  // ---------------------------------------------------------
  // final double officeLat = -7.2356163;
  // final double officeLon = 112.73303;
  // final double maxRadius = 50.0;
  late double officeLat;
  late double officeLon;
  late double maxRadius;
  late bool isLocationLocked;

  // State untuk Real-time GPS
  double? _currentDistance;
  bool _isFetchingLocation = false;
  StreamSubscription<Position>? _positionStreamSubscription;

  // State untuk Live Counter & Absensi
  bool _isCheckedIn = false;
  DateTime? _checkInTime;
  Timer? _timer;
  Duration _workDuration = const Duration();
  double _sliderPosition = 0.0;

  String get _formattedDuration {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(_workDuration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(_workDuration.inSeconds.remainder(60));
    return "${twoDigits(_workDuration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  void initState() {
    super.initState();

    // Tarik data dinamis dari konstruktor
    officeLat = widget.officeLat;
    officeLon = widget.officeLon;
    maxRadius = widget.maxRadius;
    isLocationLocked = widget.isLocationLocked;

    _startLocationStream(); // Mulai melacak jarak secara realtime saat layar dibuka
  }

  @override
  void dispose() {
    _timer?.cancel();
    _positionStreamSubscription
        ?.cancel(); // Matikan pelacak GPS saat keluar aplikasi
    super.dispose();
  }

  // ---------------------------------------------------------
  // FUNGSI 1: MELACAK JARAK SECARA REAL-TIME
  // ---------------------------------------------------------
  void _startLocationStream() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
    }

    // Melacak posisi pengguna, update setiap pergerakan minimal 2 meter
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 2,
    );

    _positionStreamSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (Position position) {
            if (mounted) {
              setState(() {
                _currentDistance = Geolocator.distanceBetween(
                  position.latitude,
                  position.longitude,
                  officeLat,
                  officeLon,
                );
              });
            }
          },
        );
  }

  // ---------------------------------------------------------
  // FUNGSI 2: TOMBOL REFRESH MANUAL (AKURASI TINGGI)
  // ---------------------------------------------------------
  Future<void> _refreshLocation() async {
    setState(() {
      _isFetchingLocation = true;
      _statusMessage = 'Memperbarui akurasi GPS...';
    });

    Position? position = await _getCurrentLocation();

    if (position != null && mounted) {
      setState(() {
        _currentDistance = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          officeLat,
          officeLon,
        );
        _statusMessage = 'Sinyal GPS diperbarui!';
        _isFetchingLocation = false;
      });
    } else {
      if (mounted) {
        setState(() {
          _isFetchingLocation = false;
          _statusMessage = 'Gagal mengunci sinyal GPS.';
        });
      }
    }
  }

  Future<Position?> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _statusMessage = 'Gagal: Mohon aktifkan GPS di HP Anda!');
      return null;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => _statusMessage = 'Gagal: Izin lokasi ditolak.');
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() => _statusMessage = 'Gagal: Izin lokasi ditolak permanen.');
      return null;
    }

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.best,
    );
  }

  // ---------------------------------------------------------
  // FUNGSI 3: PROSES UTAMA ABSENSI (SUDAH DINAMIS)
  // ---------------------------------------------------------
  Future<void> _processAttendance() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Memverifikasi radius lokasi...';
    });

    try {
      Position? position = await _getCurrentLocation();
      if (position == null) {
        setState(() => _isLoading = false);
        return;
      }

      // 1. Hitung Jarak menggunakan variabel dinamis (officeLat & officeLon dari Laravel)
      double distanceInMeters = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        officeLat,
        officeLon,
      );

      // Pastikan jarak UI juga terupdate dengan hasil tembakan terakhir
      setState(() => _currentDistance = distanceInMeters);

      // 2. Validasi Jarak & Saklar Bypass
      // Jika lokasi DIKUNCI (true) DAN jarak LEBIH DARI batas radius, maka tolak!
      if (isLocationLocked && distanceInMeters > maxRadius) {
        setState(() {
          _isLoading = false;
          _statusMessage =
              'Ditolak: Jarak Anda ${distanceInMeters.round()} m dari kantor.';
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Anda di luar radius ${maxRadius.round()}m! (Jarak: ${distanceInMeters.round()} m)',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }

      // 3. Lanjut Buka Kamera jika lolos validasi
      setState(() => _statusMessage = 'Lokasi valid! Membuka kamera...');

      final ImagePicker picker = ImagePicker();
      final XFile? photo = await picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 50,
      );

      if (photo == null) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Batal: Foto selfie wajib dilakukan.';
        });
        return;
      }

      setState(() => _statusMessage = 'Mengirim data ke server...');

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
          if (_isCheckedIn) {
            _isCheckedIn = false;
            _timer?.cancel();
          } else {
            _isCheckedIn = true;
            _checkInTime = DateTime.now();
            _workDuration = const Duration();
            _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
              setState(
                () => _workDuration = DateTime.now().difference(_checkInTime!),
              );
            });
          }
        });

        if (!mounted) return;
        _showSuccessDialog(data['message']);
      } else {
        setState(
          () => _statusMessage = data['message'] ?? 'Gagal melakukan absensi.',
        );
      }
    } catch (e) {
      setState(
        () => _statusMessage = 'Error: Gagal terhubung ke server atau kamera.',
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSuccessDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Text('Sukses', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
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
    // Penentuan Warna Status Radius
    // Ubah menjadi seperti ini:
    bool isInRadius =
        !isLocationLocked ||
        (_currentDistance != null && _currentDistance! <= maxRadius);

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
            onPressed: () => Navigator.pushReplacementNamed(context, '/'),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),

              const Icon(Icons.account_circle, size: 80, color: Colors.grey),
              const SizedBox(height: 12),
              Text(
                'Selamat Datang,',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey[400]),
              ),
              Text(
                widget.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 30),

              // -------------------------------------------------------------
              // KARTU BARU: INFO JARAK REAL-TIME & TOMBOL REFRESH
              // -------------------------------------------------------------
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 20,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isInRadius
                        ? Colors.green.withOpacity(0.5)
                        : Colors.redAccent.withOpacity(0.5),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isInRadius
                          ? Colors.green.withOpacity(0.1)
                          : Colors.redAccent.withOpacity(0.1),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isInRadius ? Icons.location_on : Icons.location_off,
                          color: isInRadius ? Colors.green : Colors.redAccent,
                          size: 30,
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Jarak ke Kantor',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _currentDistance != null
                                  ? '${_currentDistance!.toStringAsFixed(1)} Meter'
                                  : 'Mencari sinyal...',
                              style: TextStyle(
                                color: isInRadius
                                    ? Colors.green
                                    : Colors.redAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    IconButton(
                      icon: _isFetchingLocation
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.amber,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.my_location, color: Colors.amber),
                      onPressed: _isFetchingLocation ? null : _refreshLocation,
                      tooltip: 'Refresh Lokasi',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

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
                  style: const TextStyle(color: Colors.amber, fontSize: 14),
                ),
              ),
              const SizedBox(height: 40),

              Center(
                child: Text(
                  _isCheckedIn ? "SEDANG BEKERJA" : "WAKTU BEKERJA",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                    color: _isCheckedIn ? Colors.green : Colors.grey,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: Text(
                  _formattedDuration,
                  style: const TextStyle(
                    fontSize: 56,
                    fontWeight: FontWeight.w300,
                    letterSpacing: 2.0,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 50),

              LayoutBuilder(
                builder: (context, constraints) {
                  double trackWidth = constraints.maxWidth;
                  double knobSize = 64.0;
                  double maxDragDistance = trackWidth - knobSize - 8.0;

                  return Container(
                    height: 72,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(36),
                      border: Border.all(color: Colors.grey[800]!),
                    ),
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        Center(
                          child: Text(
                            _isLoading
                                ? 'MEMPROSES...'
                                : (_isCheckedIn
                                      ? 'GESER UNTUK CHECK OUT'
                                      : 'GESER UNTUK ABSEN MASUK'),
                            style: TextStyle(
                              color: _isCheckedIn
                                  ? Colors.redAccent.withOpacity(0.8)
                                  : Colors.amber.withOpacity(0.8),
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),

                        Positioned(
                          left: _sliderPosition + 4,
                          child: GestureDetector(
                            onHorizontalDragUpdate: _isLoading
                                ? null
                                : (details) {
                                    setState(() {
                                      _sliderPosition += details.delta.dx;
                                      if (_sliderPosition < 0)
                                        _sliderPosition = 0;
                                      if (_sliderPosition > maxDragDistance)
                                        _sliderPosition = maxDragDistance;
                                    });
                                  },
                            onHorizontalDragEnd: _isLoading
                                ? null
                                : (details) async {
                                    if (_sliderPosition >=
                                        maxDragDistance * 0.85) {
                                      setState(
                                        () => _sliderPosition = maxDragDistance,
                                      );
                                      await _processAttendance();
                                    }
                                    setState(() => _sliderPosition = 0.0);
                                  },
                            child: Container(
                              width: knobSize,
                              height: knobSize,
                              decoration: BoxDecoration(
                                color: _isLoading
                                    ? Colors.grey
                                    : (_isCheckedIn
                                          ? Colors.redAccent
                                          : Colors.amber),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        (_isCheckedIn
                                                ? Colors.redAccent
                                                : Colors.amber)
                                            .withOpacity(0.4),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: _isLoading
                                    ? const SizedBox(
                                        width: 26,
                                        height: 26,
                                        child: CircularProgressIndicator(
                                          color: Colors.black,
                                          strokeWidth: 2.5,
                                        ),
                                      )
                                    : Icon(
                                        _isCheckedIn
                                            ? Icons.exit_to_app
                                            : Icons.arrow_forward_ios,
                                        color: _isCheckedIn
                                            ? Colors.white
                                            : Colors.black,
                                        size: 24,
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 40),

              const Divider(color: Colors.grey),
              ListTile(
                leading: const Icon(Icons.info_outline, color: Colors.grey),
                title: const Text(
                  'Pastikan berada dalam radius 50m dari kantor untuk melakukan absensi.',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
