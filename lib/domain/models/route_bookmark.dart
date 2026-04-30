class RouteBookmark {
  const RouteBookmark({
    required this.id,
    required this.userId,
    required this.routeId,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String routeId;
  final DateTime createdAt;

  factory RouteBookmark.fromJson(Map<String, dynamic> json) {
    return RouteBookmark(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      routeId: json['route_id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'route_id': routeId,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
