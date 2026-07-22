class Schedule {
  final String groupName;
  final String day;
  final String shiftName;
  final String startTime;
  final String endTime;
  final int lateTolerance;
  final String routingType;
  final List<String> stores;
  final double? officeLatitude;
  final double? officeLongitude;

  Schedule({
    required this.groupName,
    required this.day,
    required this.shiftName,
    required this.startTime,
    required this.endTime,
    required this.lateTolerance,
    required this.routingType,
    required this.stores,
    this.officeLatitude,
    this.officeLongitude,
  });

  factory Schedule.fromJson(Map<String, dynamic> json) {
    return Schedule(
      groupName: json['group_name'] ?? '',
      day: json['day'] ?? '',
      shiftName: json['shift_name'] ?? 'Shift Bebas',
      startTime: json['start_time'] ?? '08:00:00',
      endTime: json['end_time'] ?? '17:00:00',
      // Memastikan tipe datanya aman menjadi integer
      lateTolerance: int.tryParse(json['late_tolerance'].toString()) ?? 15,
      routingType: json['routing_type'] ?? 'bebas_visit',
      // Mengubah array JSON menjadi List<String> di Flutter
      stores: List<String>.from(json['stores'] ?? []),
      officeLatitude: json['office_latitude'] != null ? double.tryParse(json['office_latitude'].toString()) : null,
      officeLongitude: json['office_longitude'] != null ? double.tryParse(json['office_longitude'].toString()) : null,
    );
  }
}
