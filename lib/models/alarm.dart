import 'package:json_annotation/json_annotation.dart';

part 'alarm.g.dart';

@JsonSerializable()
class Alarm {
  final String id;
  final String name;
  final int hour; // 0-23
  final int minute; // 0-59
  final bool isEnabled;
  final List<int> repeatDays; // 1=周一, 7=周日, 空数组=仅一次
  final String aiPersonaId;
  final DateTime createdAt;
  final DateTime? nextAlarmTime;

  Alarm({
    required this.id,
    required this.name,
    required this.hour,
    required this.minute,
    this.isEnabled = true,
    this.repeatDays = const [],
    this.aiPersonaId = 'gentle',
    required this.createdAt,
    this.nextAlarmTime,
  });

  factory Alarm.fromJson(Map<String, dynamic> json) => _$AlarmFromJson(json);
  Map<String, dynamic> toJson() => _$AlarmToJson(this);

  Alarm copyWith({
    String? id,
    String? name,
    int? hour,
    int? minute,
    bool? isEnabled,
    List<int>? repeatDays,
    String? aiPersonaId,
    DateTime? createdAt,
    DateTime? nextAlarmTime,
  }) {
    return Alarm(
      id: id ?? this.id,
      name: name ?? this.name,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      isEnabled: isEnabled ?? this.isEnabled,
      repeatDays: repeatDays ?? this.repeatDays,
      aiPersonaId: aiPersonaId ?? this.aiPersonaId,
      createdAt: createdAt ?? this.createdAt,
      nextAlarmTime: nextAlarmTime ?? this.nextAlarmTime,
    );
  }

  String getFormattedTime() {
    final h = hour.toString().padLeft(2, '0');
    final m = minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String getRepeatDescription() {
    if (repeatDays.isEmpty) return '仅一次';
    if (repeatDays.length == 7) return '每天';
    if (repeatDays.length == 5 && 
        repeatDays.contains(1) && 
        repeatDays.contains(2) &&
        repeatDays.contains(3) &&
        repeatDays.contains(4) &&
        repeatDays.contains(5)) {
      return '工作日';
    }
    if (repeatDays.length == 2 && 
        repeatDays.contains(6) && 
        repeatDays.contains(7)) {
      return '周末';
    }
    
    const dayNames = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final days = repeatDays.map((d) => dayNames[d - 1]).join(', ');
    return days;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'hour': hour,
      'minute': minute,
      'isEnabled': isEnabled ? 1 : 0,
      'repeatDays': repeatDays.join(','),
      'aiPersonaId': aiPersonaId,
      'createdAt': createdAt.toIso8601String(),
      'nextAlarmTime': nextAlarmTime?.toIso8601String(),
    };
  }

  factory Alarm.fromMap(Map<String, dynamic> map) {
    return Alarm(
      id: map['id'] as String,
      name: map['name'] as String,
      hour: map['hour'] as int,
      minute: map['minute'] as int,
      isEnabled: map['isEnabled'] == 1,
      repeatDays: map['repeatDays'] != null && (map['repeatDays'] as String).isNotEmpty
          ? (map['repeatDays'] as String).split(',').map((e) => int.parse(e)).toList()
          : [],
      aiPersonaId: map['aiPersonaId'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
      nextAlarmTime: map['nextAlarmTime'] != null
          ? DateTime.parse(map['nextAlarmTime'] as String)
          : null,
    );
  }
}
