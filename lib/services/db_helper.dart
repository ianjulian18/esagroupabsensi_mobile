import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DBHelper {
  static final DBHelper _instance = DBHelper._internal();
  static Database? _database;

  factory DBHelper() => _instance;

  DBHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'attendance_offline.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE offline_attendance(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT,
        latitude TEXT,
        longitude TEXT,
        photo_path TEXT,
        location_name TEXT,
        visit_id TEXT,
        timestamp TEXT
      )
    ''');
  }

  Future<int> insertOfflineAttendance(Map<String, dynamic> data) async {
    final db = await database;
    return await db.insert('offline_attendance', data);
  }

  Future<List<Map<String, dynamic>>> getOfflineAttendances() async {
    final db = await database;
    return await db.query('offline_attendance', orderBy: 'id ASC');
  }

  Future<int> deleteOfflineAttendance(int id) async {
    final db = await database;
    return await db.delete('offline_attendance', where: 'id = ?', whereArgs: [id]);
  }
}
