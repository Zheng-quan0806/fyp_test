class CalendarTask {
  final String id;
  final String title;
  final String details;
  final DateTime date;
  final int? minutesSinceMidnight;
  final bool isCompleted;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CalendarTask({
    required this.id,
    required this.title,
    required this.details,
    required this.date,
    required this.minutesSinceMidnight,
    required this.isCompleted,
    required this.createdAt,
    required this.updatedAt,
  });

  CalendarTask copyWith({
    String? title,
    String? details,
    DateTime? date,
    int? minutesSinceMidnight,
    bool clearTime = false,
    bool? isCompleted,
    DateTime? updatedAt,
  }) {
    return CalendarTask(
      id: id,
      title: title ?? this.title,
      details: details ?? this.details,
      date: date ?? this.date,
      minutesSinceMidnight:
          clearTime ? null : minutesSinceMidnight ?? this.minutesSinceMidnight,
      isCompleted: isCompleted ?? this.isCompleted,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'details': details,
        'date': dateKey(date),
        'minutesSinceMidnight': minutesSinceMidnight,
        'isCompleted': isCompleted,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory CalendarTask.fromJson(Map<String, dynamic> json) {
    return CalendarTask(
      id: json['id'] as String,
      title: json['title'] as String,
      details: json['details'] as String? ?? '',
      date: DateTime.parse(json['date'] as String),
      minutesSinceMidnight: (json['minutesSinceMidnight'] as num?)?.toInt(),
      isCompleted: json['isCompleted'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  static String dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
