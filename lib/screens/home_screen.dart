import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/db_helper.dart';
import '../services/sync_service.dart';
import 'history_screen.dart';
import 'leave_request_screen.dart';
import 'extra_hour_screen.dart';
import 'bap_screen.dart';
import 'payslip_screen.dart';
import 'visit_log_screen.dart';
import 'add_store_screen.dart';
import '../models/schedule_model.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
class HomeScreen extends StatefulWidget {
  final String token;
  final String name;
  final String baseUrl;
  final double officeLat;
  final double officeLon;
  final double maxRadius;
  final bool isLocationLocked;
  final String entityName;
  final List<dynamic> principals;

  const HomeScreen({
    super.key,
    required this.token,
    required this.name,
    required this.baseUrl,
    required this.officeLat,
    required this.officeLon,
    required this.maxRadius,
    required this.isLocationLocked,
    required this.entityName,
    required this.principals,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _bottomNavIndex = 0;
  bool _isLoading = false;
  String _statusMessage = 'Geser tombol di bawah untuk melakukan absensi';
  Schedule? _todaySchedule; // Variabel untuk menyimpan data jadwal hari ini
  bool _isLoadingSchedule = true; // Indikator loading khusus jadwal

  late double officeLat;
  late double officeLon;
  late double maxRadius;
  late bool isLocationLocked;

  double? _currentDistance;
  Position? _currentPosition;
  bool _isFetchingLocation = false;
  StreamSubscription<Position>? _positionStreamSubscription;

  // --- STATE ALUR LINEAR ABSENSI ---
  bool _isCheckedIn = false;
  bool _isCheckedOut = false; // Sesi harian selesai
  bool _isVisiting = false; // Sedang berada di lokasi visit
  int? _activeVisitId; // Menyimpan ID visit yang sedang berjalan

  final TextEditingController _locationController = TextEditingController();

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
    officeLat = widget.officeLat;
    officeLon = widget.officeLon;
    maxRadius = widget.maxRadius;
    isLocationLocked = widget.isLocationLocked;
    _fetchSchedule();
    _startLocationStream();
    _syncOfflineData();
  }

  Future<void> _syncOfflineData() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (!connectivityResult.contains(ConnectivityResult.none)) {
      final syncService = SyncService(
        baseUrl: widget.baseUrl,
        token: widget.token,
      );
      await syncService.syncOfflineData();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _positionStreamSubscription?.cancel();
    _locationController.dispose();
    super.dispose();
  }

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

    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 2,
    );

    _positionStreamSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (Position position) {
            if (mounted) {
              setState(() {
                _currentPosition = position;
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

  Future<void> _refreshLocation() async {
    setState(() {
      _isFetchingLocation = true;
      _statusMessage = 'Memperbarui akurasi GPS...';
    });

    Position? position = await _getCurrentLocation();

    if (position != null && mounted) {
      setState(() {
        _currentPosition = position;
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
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _statusMessage = 'Gagal: Mohon aktifkan GPS di HP Anda!');
      return null;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => _statusMessage = 'Gagal: Izin lokasi ditolak.');
        return null;
      }
    }
    if (permission == LocationPermission.deniedForever) return null;

    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.best,
    );

    // Deteksi Fake GPS (Mock Location)
    if (position.isMocked) {
      if (mounted) {
        setState(
          () => _statusMessage =
              'Gagal: Aplikasi Fake GPS terdeteksi. Matikan untuk absen!',
        );
        _showErrorSnackBar('Peringatan: Fake GPS terdeteksi!');
      }
      return null;
    }

    return position;
  }

  // --- API 1: CHECK-IN & CHECK-OUT UTAMA ---
  Future<void> _processAttendance() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Memverifikasi radius lokasi...';
    });

    bool isLate = _checkIfLate();
    if (isLate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '⚠️ Anda Check-In di luar jam toleransi! Status: TERLAMBAT.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    }

    try {
      Position? position = await _getCurrentLocation();
      if (position == null) {
        setState(() => _isLoading = false);
        return;
      }

      double distanceInMeters = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        officeLat,
        officeLon,
      );
      setState(() => _currentDistance = distanceInMeters);

      // Bypass radius jika check-out dari luar kantor (opsional, tergantung kebijakan HR)
      if (isLocationLocked && distanceInMeters > maxRadius && !_isCheckedIn) {
        setState(() {
          _isLoading = false;
          _statusMessage =
              'Ditolak: Jarak Anda ${distanceInMeters.round()} m dari kantor.';
        });
        _showErrorSnackBar('Anda di luar radius ${maxRadius.round()}m!');
        return;
      }

      bool confirm = await _showMapConfirmationDialog();
      if (!confirm) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Dibatalkan.';
        });
        return;
      }

      setState(() => _statusMessage = 'Membuka kamera...');
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

      setState(() => _statusMessage = 'Mendeteksi wajah...');
      bool hasFace = await _detectFace(photo.path);
      if (!hasFace) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Ditolak: Wajah tidak terdeteksi pada foto!';
        });
        _showErrorSnackBar('Gagal: Wajah tidak terdeteksi!');
        return;
      }

      setState(() => _statusMessage = 'Memeriksa koneksi & mengirim data...');

      final connectivityResult = await Connectivity().checkConnectivity();
      final hasInternet = !connectivityResult.contains(ConnectivityResult.none);

      if (!hasInternet) {
        // Mode Offline: Simpan ke SQLite
        final dbHelper = DBHelper();
        await dbHelper.insertOfflineAttendance({
          'type': 'attendance',
          'latitude': position.latitude.toString(),
          'longitude': position.longitude.toString(),
          'photo_path': photo.path,
          'timestamp': DateTime.now().toIso8601String(),
        });
        setState(() {
          _statusMessage = 'Offline: Data disimpan lokal.';
          if (_isCheckedIn) {
            _isCheckedOut = true;
            _timer?.cancel();
          } else {
            _isCheckedIn = true;
            _checkInTime = DateTime.now();
            _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
              setState(
                () => _workDuration = DateTime.now().difference(_checkInTime!),
              );
            });
          }
        });
        _showSuccessDialog(
          'Mode Offline: Absen berhasil disimpan secara lokal dan akan disinkronisasi saat online.',
        );
        return;
      }

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
            _isCheckedOut = true;
            _timer?.cancel();
          } else {
            _isCheckedIn = true;
            _checkInTime = DateTime.now();
            _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
              setState(
                () => _workDuration = DateTime.now().difference(_checkInTime!),
              );
            });
          }
        });
        _showSuccessDialog(data['message']);
      } else {
        setState(() => _statusMessage = data['message'] ?? 'Gagal absensi.');
      }
    } catch (e) {
      setState(() => _statusMessage = 'Error: Gagal terhubung ke server.');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // --- API 2: VISIT IN ---
  Future<void> _processVisitIn() async {
    if (_locationController.text.isEmpty) {
      _showErrorSnackBar('Nama Toko/Lokasi tidak boleh kosong!');
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Membuka kamera untuk Visit...';
    });

    try {
      Position? position = await _getCurrentLocation();
      if (position == null) {
        setState(() => _isLoading = false);
        return;
      }

      bool confirm = await _showMapConfirmationDialog();
      if (!confirm) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Dibatalkan.';
        });
        return;
      }

      final ImagePicker picker = ImagePicker();
      final XFile? photo = await picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 50,
      );

      if (photo == null) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Batal: Foto wajib.';
        });
        return;
      }

      setState(() => _statusMessage = 'Mendeteksi wajah...');
      bool hasFace = await _detectFace(photo.path);
      if (!hasFace) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Ditolak: Wajah tidak terdeteksi pada foto!';
        });
        _showErrorSnackBar('Gagal: Wajah tidak terdeteksi!');
        return;
      }

      setState(() => _statusMessage = 'Memeriksa koneksi & mengirim data...');

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${widget.baseUrl}/visit/in'),
      );
      request.headers.addAll({
        'Authorization': 'Bearer ${widget.token}',
        'Accept': 'application/json',
      });
      request.fields['latitude'] = position.latitude.toString();
      request.fields['longitude'] = position.longitude.toString();
      request.fields['location_name'] = _locationController.text;
      request.files.add(await http.MultipartFile.fromPath('photo', photo.path));

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);
      final data = jsonDecode(response.body);

      if (response.statusCode == 201) {
        setState(() {
          _isVisiting = true;
          _activeVisitId = data['data']['id'];
          _statusMessage = data['message'];
        });
        _showSuccessDialog(data['message']);
      } else {
        setState(() => _statusMessage = data['message'] ?? 'Gagal Visit In.');
        _showErrorSnackBar(data['message'] ?? 'Terjadi kesalahan.');
      }
    } catch (e) {
      setState(() => _statusMessage = 'Error server/jaringan.');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // --- API 3: VISIT OUT ---
  Future<void> _processVisitOut() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Menutup sesi visit...';
    });

    try {
      Position? position = await _getCurrentLocation();
      if (position == null) {
        setState(() => _isLoading = false);
        return;
      }

      bool confirm = await _showMapConfirmationDialog();
      if (!confirm) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Dibatalkan.';
        });
        return;
      }

      final ImagePicker picker = ImagePicker();
      final XFile? photo = await picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 50,
      );

      if (photo == null) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Batal: Foto wajib.';
        });
        return;
      }

      setState(() => _statusMessage = 'Mendeteksi wajah...');
      bool hasFace = await _detectFace(photo.path);
      if (!hasFace) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Ditolak: Wajah tidak terdeteksi pada foto!';
        });
        _showErrorSnackBar('Gagal: Wajah tidak terdeteksi!');
        return;
      }

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${widget.baseUrl}/visit/out'),
      );
      request.headers.addAll({
        'Authorization': 'Bearer ${widget.token}',
        'Accept': 'application/json',
      });
      request.fields['latitude'] = position.latitude.toString();
      request.fields['longitude'] = position.longitude.toString();
      request.fields['visit_id'] = _activeVisitId.toString();
      request.files.add(await http.MultipartFile.fromPath('photo', photo.path));

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);
      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        setState(() {
          _isVisiting = false;
          _activeVisitId = null;
          _locationController.clear();
          _statusMessage = data['message'];
        });
        _showSuccessDialog(data['message']);
      } else {
        setState(() => _statusMessage = data['message'] ?? 'Gagal Visit Out.');
      }
    } catch (e) {
      setState(() => _statusMessage = 'Error server/jaringan.');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchSchedule() async {
    setState(() => _isLoadingSchedule = true);
    try {
      final response = await http.get(
        Uri.parse('${widget.baseUrl}/my-schedule'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success' && data['data'] != null) {
          setState(() {
            _todaySchedule = Schedule.fromJson(data['data']);

            // Override office coordinates if API provides them (e.g., First Visit Lock)
            if (_todaySchedule!.officeLatitude != null &&
                _todaySchedule!.officeLongitude != null) {
              officeLat = _todaySchedule!.officeLatitude!;
              officeLon = _todaySchedule!.officeLongitude!;
            }
          });

          // Recalculate distance against the new coordinates
          _refreshLocation();
        }
      }
    } catch (e) {
      print('Error: $e');
    } finally {
      setState(() => _isLoadingSchedule = false);
    }
  }

  bool _checkIfLate() {
    if (_todaySchedule == null) return false;
    final now = DateTime.now();
    final parts = _todaySchedule!.startTime.split(':');
    final shiftStart = DateTime(
      now.year,
      now.month,
      now.day,
      int.parse(parts[0]),
      int.parse(parts[1]),
    );
    final limitTime = shiftStart.add(
      Duration(minutes: _todaySchedule!.lateTolerance),
    );
    return now.isAfter(limitTime);
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showSuccessDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
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
            child: const Text('OK', style: TextStyle(color: const Color(0xFF2E3190))),
          ),
        ],
      ),
    );
  }

  // Komponen Slider Kustom
  Widget _buildSlider({
    required String label,
    required Color color,
    required Future<void> Function() onAction,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        double trackWidth = constraints.maxWidth;
        double knobSize = 56.0;
        double maxDragDistance = trackWidth - knobSize - 8.0;

        return Container(
          height: 64,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Center(
                child: Text(
                  _isLoading ? 'MEMPROSES...' : label,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    letterSpacing: 1.0,
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
                            if (_sliderPosition < 0) _sliderPosition = 0;
                            if (_sliderPosition > maxDragDistance) {
                              _sliderPosition = maxDragDistance;
                            }
                          });
                        },
                  onHorizontalDragEnd: _isLoading
                      ? null
                      : (details) async {
                          if (_sliderPosition >= maxDragDistance * 0.85) {
                            setState(() => _sliderPosition = maxDragDistance);
                            await onAction();
                          }
                          setState(() => _sliderPosition = 0.0);
                        },
                  child: Container(
                    width: knobSize,
                    height: knobSize,
                    decoration: BoxDecoration(
                      color: _isLoading ? Colors.grey : color,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Center(
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Icon(
                              Icons.arrow_forward_outlined,
                              color: Colors.white,
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
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isInRadius =
        !isLocationLocked ||
        (_currentDistance != null && _currentDistance! <= maxRadius);

    final List<Widget> pages = [
      _buildDashboard(isInRadius),
      PayslipScreen(token: widget.token, baseUrl: widget.baseUrl),
      HistoryScreen(token: widget.token, baseUrl: widget.baseUrl),
      Scaffold(
        appBar: AppBar(
          title: const Text('Account', style: TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFF2E3190),
        ),
        body: Center(
          child: ElevatedButton(
            onPressed: () => Navigator.pushReplacementNamed(context, '/'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E3190), foregroundColor: Colors.white),
            child: const Text('Logout'),
          ),
        ),
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: IndexedStack(
        index: _bottomNavIndex,
        children: pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _bottomNavIndex,
        onTap: (index) {
          setState(() {
            _bottomNavIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF2E3190),
        unselectedItemColor: Colors.grey,
        backgroundColor: Colors.white,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.receipt), label: 'Payslip'),
          BottomNavigationBarItem(icon: Icon(Icons.show_chart), label: 'Activity'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Account'),
        ],
      ),
    );
  }

  Widget _buildDashboard(bool isInRadius) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          children: [
            // Header Merah
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24).copyWith(bottom: 60),
              decoration: const BoxDecoration(
                color: Color(0xFF2E3190),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.person, size: 40, color: Colors.grey),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          widget.entityName,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.notifications, color: Colors.white),
                ],
              ),
            ),
            
            // Grid Menu
            Transform.translate(
              offset: const Offset(0, -40),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: Colors.grey.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 5)),
                  ],
                ),
                child: Wrap(
                  spacing: 20,
                  runSpacing: 20,
                  alignment: WrapAlignment.spaceEvenly,
                  children: [
                    _buildMenuIcon(Icons.history, 'Riwayat Absen', () => Navigator.push(context, MaterialPageRoute(builder: (_) => HistoryScreen(token: widget.token, baseUrl: widget.baseUrl)))),
                    _buildMenuIcon(Icons.directions_run, 'Visit Log', () => Navigator.push(context, MaterialPageRoute(builder: (_) => VisitLogScreen(token: widget.token, baseUrl: widget.baseUrl, storeName: '')))),
                    _buildMenuIcon(Icons.edit_calendar, 'Cuti / Izin', () => Navigator.push(context, MaterialPageRoute(builder: (_) => LeaveRequestScreen(token: widget.token, baseUrl: widget.baseUrl)))),
                    _buildMenuIcon(Icons.add_location_alt, 'Tambah Lokasi', () => Navigator.push(context, MaterialPageRoute(builder: (_) => AddStoreScreen(token: widget.token, baseUrl: widget.baseUrl)))),
                    _buildMenuIcon(Icons.more_time, 'Lembur', () => Navigator.push(context, MaterialPageRoute(builder: (_) => ExtraHourScreen(token: widget.token, baseUrl: widget.baseUrl)))),
                    _buildMenuIcon(Icons.post_add, 'Pengajuan BAP', () => Navigator.push(context, MaterialPageRoute(builder: (_) => BapScreen(token: widget.token, baseUrl: widget.baseUrl)))),
                  ],
                ),
              ),
            ),
            
            // Konten Bawah Grid
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Informasi', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                  const SizedBox(height: 12),
                  
                  // Kotak Absen
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(color: Colors.grey.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 5)),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Detail Lokasi (Mocked like image)
                        Row(
                          children: [
                            const Icon(Icons.store, color: Color(0xFF2E3190)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _todaySchedule?.shiftName ?? 'Area Absensi / Kantor',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
                                  ),
                                  Text(
                                    _currentDistance != null ? '${_currentDistance!.toStringAsFixed(1)} Meter - $_statusMessage' : 'Mencari sinyal...',
                                    style: TextStyle(fontSize: 12, color: isInRadius ? Colors.green : Colors.red),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        // Detail Durasi
                        if (_isCheckedIn && !_isCheckedOut)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.access_time, size: 16, color: Colors.green),
                                  const SizedBox(width: 4),
                                  Text('CHECK IN: ${_checkInTime?.hour.toString().padLeft(2,'0')}:${_checkInTime?.minute.toString().padLeft(2,'0')} WIB', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                                ],
                              ),
                              Text('Duration : ${_formattedDuration}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
                            ],
                          ),
                        if (_isCheckedIn && !_isCheckedOut) const SizedBox(height: 16),
                        
                        // Slider / Action area
                        if (_isCheckedOut)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Text('Sesi Kerja Hari Ini Selesai', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                            ),
                          )
                        else if (!_isCheckedIn)
                          _buildSlider(label: 'GESER UNTUK CHECK IN', color: const Color(0xFF2E3190), onAction: _processAttendance)
                        else if (_isCheckedIn && !_isVisiting)
                          Column(
                            children: [
                              _buildSlider(label: 'Checkout >>', color: const Color(0xFF2E3190), onAction: _processAttendance),
                              const SizedBox(height: 16),
                              // Visit Mode
                              if (_todaySchedule != null && _todaySchedule!.stores.isNotEmpty)
                                DropdownButtonFormField<String>(
                                  value: _todaySchedule!.stores.contains(_locationController.text)
                                      ? _locationController.text
                                      : null,
                                  items: _todaySchedule!.stores.map((String store) {
                                    return DropdownMenuItem<String>(
                                      value: store,
                                      child: Text(store, overflow: TextOverflow.ellipsis),
                                    );
                                  }).toList(),
                                  onChanged: (String? newValue) {
                                    if (newValue != null) {
                                      setState(() {
                                        _locationController.text = newValue;
                                      });
                                    }
                                  },
                                  decoration: InputDecoration(
                                    labelText: 'Pilih Toko / Lokasi Visit',
                                    labelStyle: const TextStyle(color: Colors.grey),
                                    prefixIcon: const Icon(Icons.store, color: Colors.grey),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                                  ),
                                )
                              else
                                TextField(
                                  controller: _locationController,
                                  decoration: InputDecoration(
                                    labelText: 'Nama Toko / Lokasi Visit',
                                    labelStyle: const TextStyle(color: Colors.grey),
                                    prefixIcon: const Icon(Icons.store, color: Colors.grey),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                                  ),
                                ),
                              const SizedBox(height: 12),
                              _buildSlider(label: 'VISIT IN >>', color: const Color(0xFF3F51B5), onAction: _processVisitIn),
                            ],
                          )
                        else if (_isVisiting)
                          Column(
                            children: [
                              Text('Sedang Visit di: ${_locationController.text}', style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 16),
                              OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => VisitLogScreen(
                                        token: widget.token,
                                        baseUrl: widget.baseUrl,
                                        storeName: _locationController.text,
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.edit_document, color: Color(0xFF2E3190)),
                                label: const Text('Isi Laporan Visit (Visit Log)', style: TextStyle(color: Color(0xFF2E3190), fontWeight: FontWeight.bold)),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Color(0xFF2E3190)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                ),
                              ),
                              const SizedBox(height: 16),
                              _buildSlider(label: 'VISIT OUT >>', color: Colors.orangeAccent, onAction: _processVisitOut),
                            ],
                          ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  // Riwayat Geofence
                  const Text('Riwayat Geofence (Hari Ini)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(color: Colors.grey.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 5)),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                             _isCheckedIn && _checkInTime != null
                                ? '${_checkInTime!.day} ${_checkInTime!.month} ${_checkInTime!.hour.toString().padLeft(2,'0')}:${_checkInTime!.minute.toString().padLeft(2,'0')} — Masuk area kantor'
                                : 'Belum ada riwayat check-in hari ini',
                             style: const TextStyle(color: Colors.green, fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuIcon(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFFE2E8F0), // Soft grey background
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.grey, size: 28),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87)),
        ],
      ),
    );
  }

  Widget _buildMap() {
    if (_currentPosition == null) {
      return const SizedBox(
        height: 150,
        child: Center(child: Text('Menunggu lokasi...')),
      );
    }
    return Container(
      height: 150,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: FlutterMap(
          options: MapOptions(
            initialCenter: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
            initialZoom: 16.0,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.esagroup_absensi_app',
            ),
            CircleLayer(
              circles: [
                CircleMarker(
                  point: LatLng(widget.officeLat, widget.officeLon),
                  color: Colors.blue.withValues(alpha: 0.3),
                  borderColor: Colors.blue,
                  borderStrokeWidth: 2,
                  useRadiusInMeter: true,
                  radius: widget.maxRadius,
                ),
              ],
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                  width: 40,
                  height: 40,
                  child: const Icon(Icons.location_on, color: Colors.red, size: 40),
                ),
                Marker(
                  point: LatLng(widget.officeLat, widget.officeLon),
                  width: 40,
                  height: 40,
                  child: const Icon(Icons.business, color: Color(0xFF2E3190), size: 40),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _showMapConfirmationDialog() async {
    if (_currentPosition == null) return true; // If no pos yet, just bypass or handle error. Usually not null here.
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Konfirmasi Lokasi', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: Column(
              children: [
                Expanded(child: _buildMap()),
                const SizedBox(height: 12),
                const Text(
                  'Pastikan lokasi Anda (merah) sudah benar dan akurat.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E3190),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Lanjut Buka Kamera', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    ) ?? false;
  }

  Future<bool> _detectFace(String imagePath) async {
    final options = FaceDetectorOptions();
    final faceDetector = FaceDetector(options: options);
    final inputImage = InputImage.fromFilePath(imagePath);

    try {
      final List<Face> faces = await faceDetector.processImage(inputImage);
      return faces.isNotEmpty;
    } catch (e) {
      return false;
    } finally {
      faceDetector.close();
    }
  }
}
