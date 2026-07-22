import 'package:http/http.dart' as http;
import 'db_helper.dart';

class SyncService {
  final String baseUrl;
  final String token;

  SyncService({required this.baseUrl, required this.token});

  Future<void> syncOfflineData() async {
    final dbHelper = DBHelper();
    final offlineData = await dbHelper.getOfflineAttendances();

    if (offlineData.isEmpty) return;

    for (var data in offlineData) {
      bool success = false;
      try {
        if (data['type'] == 'attendance') {
          success = await _syncAttendance(data);
        } else if (data['type'] == 'visit_in') {
          success = await _syncVisitIn(data);
        } else if (data['type'] == 'visit_out') {
          success = await _syncVisitOut(data);
        }

        if (success) {
          await dbHelper.deleteOfflineAttendance(data['id']);
        }
      } catch (e) {
        print('Sync error for record ${data['id']}: $e');
      }
    }
  }

  Future<bool> _syncAttendance(Map<String, dynamic> data) async {
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/attendance/scan'),
    );
    request.headers.addAll({
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
    });
    request.fields['latitude'] = data['latitude'];
    request.fields['longitude'] = data['longitude'];
    request.fields['timestamp'] =
        data['timestamp']; // Backend perlu menangani timestamp manual ini jika perlu

    if (data['photo_path'] != null && data['photo_path'].isNotEmpty) {
      request.files.add(
        await http.MultipartFile.fromPath('photo', data['photo_path']),
      );
    }

    var streamedResponse = await request.send();
    return streamedResponse.statusCode == 200 ||
        streamedResponse.statusCode == 201;
  }

  Future<bool> _syncVisitIn(Map<String, dynamic> data) async {
    var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/visit/in'));
    request.headers.addAll({
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
    });
    request.fields['latitude'] = data['latitude'];
    request.fields['longitude'] = data['longitude'];
    request.fields['location_name'] = data['location_name'];
    request.fields['timestamp'] = data['timestamp'];

    if (data['photo_path'] != null && data['photo_path'].isNotEmpty) {
      request.files.add(
        await http.MultipartFile.fromPath('photo', data['photo_path']),
      );
    }

    var streamedResponse = await request.send();
    return streamedResponse.statusCode == 200 ||
        streamedResponse.statusCode == 201;
  }

  Future<bool> _syncVisitOut(Map<String, dynamic> data) async {
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/visit/out'),
    );
    request.headers.addAll({
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
    });
    request.fields['latitude'] = data['latitude'];
    request.fields['longitude'] = data['longitude'];
    request.fields['visit_id'] = data['visit_id'];
    request.fields['timestamp'] = data['timestamp'];

    if (data['photo_path'] != null && data['photo_path'].isNotEmpty) {
      request.files.add(
        await http.MultipartFile.fromPath('photo', data['photo_path']),
      );
    }

    var streamedResponse = await request.send();
    return streamedResponse.statusCode == 200 ||
        streamedResponse.statusCode == 201;
  }
}
