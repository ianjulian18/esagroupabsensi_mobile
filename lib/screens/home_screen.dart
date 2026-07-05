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
  final double officeLat;
  final double officeLon;
  final double maxRadius;
  final bool isLocationLocked;

  const HomeScreen({
    super.key,
    required this.token,
    required this.name,
    required this.baseUrl,
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

  late double officeLat;
  late double officeLon;
  late double maxRadius;
  late bool isLocationLocked;

  double? _currentDistance;
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
    _startLocationStream();
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
          permission == LocationPermission.deniedForever)
        return;
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
      if (mounted)
        setState(() {
          _isFetchingLocation = false;
          _statusMessage = 'Gagal mengunci sinyal GPS.';
        });
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

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.best,
    );
  }

  // --- API 1: CHECK-IN & CHECK-OUT UTAMA ---
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

      setState(() => _statusMessage = 'Mengirim data absen...');

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
            // Jika sebelumnya sudah Check-In, berarti ini adalah Check-Out harian
            _isCheckedOut = true;
            _timer?.cancel();
          } else {
            // Ini adalah Check-In Pagi
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

      setState(() => _statusMessage = 'Menyimpan Visit In...');

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

  // Komponen Slider Kustom
  Widget _buildSlider({
    required String label,
    required Color color,
    required Future<void> Function() onAction,
  }) {
    return LayoutBuilder(
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
                  _isLoading ? 'MEMPROSES...' : label,
                  style: TextStyle(
                    color: color.withOpacity(0.8),
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
                            if (_sliderPosition < 0) _sliderPosition = 0;
                            if (_sliderPosition > maxDragDistance)
                              _sliderPosition = maxDragDistance;
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
                          color: color.withOpacity(0.4),
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
                          : const Icon(
                              Icons.arrow_forward_ios,
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
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    HistoryScreen(token: widget.token, baseUrl: widget.baseUrl),
              ),
            ),
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

              // KARTU LOKASI
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
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // PESAN STATUS
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
              const SizedBox(height: 30),

              // DURASI KERJA
              if (_isCheckedIn && !_isCheckedOut) ...[
                Center(
                  child: Text(
                    'WAKTU BEKERJA',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      color: Colors.green,
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
                const SizedBox(height: 30),
              ],

              // -------------------------------------------------------------
              // LOGIKA STATE MACHINE UNTUK ALUR ABSENSI
              // -------------------------------------------------------------
              if (_isCheckedOut)
                // FASE 4: SELESAI
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.green),
                  ),
                  child: const Column(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        color: Colors.green,
                        size: 48,
                      ),
                      SizedBox(height: 10),
                      Text(
                        'Sesi Kerja Hari Ini Selesai',
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Terima kasih atas kerja keras Anda!',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    ],
                  ),
                )
              else if (!_isCheckedIn)
                // FASE 1: BELUM CHECK-IN PAGI
                _buildSlider(
                  label: 'GESER UNTUK CHECK IN',
                  color: Colors.amber,
                  onAction: _processAttendance,
                )
              else if (_isCheckedIn && !_isVisiting)
                // FASE 2: SUDAH CHECK IN, STANDBY UNTUK VISIT ATAU PULANG
                Column(
                  children: [
                    TextField(
                      controller: _locationController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Nama Toko / Lokasi Visit',
                        labelStyle: const TextStyle(color: Colors.grey),
                        prefixIcon: const Icon(
                          Icons.store,
                          color: Colors.amber,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey[800]!),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.amber),
                        ),
                        filled: true,
                        fillColor: const Color(0xFF1E1E1E),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildSlider(
                      label: 'GESER UNTUK VISIT IN',
                      color: Colors.blueAccent,
                      onAction: _processVisitIn,
                    ),
                    const SizedBox(height: 20),
                    const Divider(color: Colors.grey),
                    const SizedBox(height: 20),
                    _buildSlider(
                      label: 'AKHIRI SESI & CHECK OUT',
                      color: Colors.redAccent,
                      onAction: _processAttendance,
                    ),
                  ],
                )
              else if (_isVisiting)
                // FASE 3: SEDANG VISIT DI TOKO
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blueAccent),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.storefront,
                            color: Colors.blueAccent,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Sedang Visit di:',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  _locationController.text,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                    _buildSlider(
                      label: 'GESER UNTUK VISIT OUT',
                      color: Colors.orangeAccent,
                      onAction: _processVisitOut,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
