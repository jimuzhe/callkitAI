import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/alarm.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('call_clock.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    const idType = 'TEXT PRIMARY KEY';
    const textType = 'TEXT NOT NULL';
    const integerType = 'INTEGER NOT NULL';

    await db.execute('''
      CREATE TABLE alarms (
        id $idType,
        name $textType,
        hour $integerType,
        minute $integerType,
        isEnabled $integerType,
        repeatDays $textType,
        aiPersonaId $textType,
        createdAt $textType,
        nextAlarmTime TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp TEXT NOT NULL,
        level TEXT NOT NULL,
        message TEXT NOT NULL
      )
    ''');
  }

  Future<Alarm?> getAlarmById(String id) async {
    final db = await database;
    final maps = await db.query(
      'alarms',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isNotEmpty) {
      return Alarm.fromJson(maps.first);
    }
    return null;
  }

  Future<Alarm> createAlarm(Alarm alarm) async {
    final db = await database;
    await db.insert('alarms', alarm.toMap());
    return alarm;
  }

  Future<Alarm?> getAlarm(String id) async {
    final db = await database;
    final maps = await db.query('alarms', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Alarm.fromMap(maps.first);
  }

  Future<List<Alarm>> getAllAlarms() async {
    final db = await database;
    const orderBy = 'hour ASC, minute ASC';
    final result = await db.query('alarms', orderBy: orderBy);
    return result.map((json) => Alarm.fromMap(json)).toList();
  }

  Future<List<Alarm>> getEnabledAlarms() async {
    final db = await database;
    final result = await db.query(
      'alarms',
      where: 'isEnabled = ?',
      whereArgs: [1],
      orderBy: 'hour ASC, minute ASC',
    );
    return result.map((json) => Alarm.fromMap(json)).toList();
  }

  Future<int> updateAlarm(Alarm alarm) async {
    final db = await database;
    return db.update('alarms', alarm.toMap(),
        where: 'id = ?', whereArgs: [alarm.id]);
  }

  Future<int> deleteAlarm(String id) async {
    final db = await database;
    return await db.delete('alarms', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> log(String level, String message) async {
    final db = await database;
    await db.insert('logs', {
      'timestamp': DateTime.now().toIso8601String(),
      'level': level,
      'message': message,
    });
  }

  Future<List<Map<String, dynamic>>> getLogs({int limit = 100}) async {
    final db = await database;
    return await db.query('logs', orderBy: 'timestamp DESC', limit: limit);
  }

  Future<void> clearOldLogs({int daysToKeep = 7}) async {
    final db = await database;
    final cutoffDate = DateTime.now().subtract(Duration(days: daysToKeep));
    await db.delete('logs',
        where: 'timestamp < ?', whereArgs: [cutoffDate.toIso8601String()]);
  }

  Future<void> close() async {
    final db = await database;
    db.close();
  }
}
