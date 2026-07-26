class CommunityChatMessage {
  const CommunityChatMessage({
    required this.id,
    required this.communityId,
    required this.userId,
    required this.body,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
    this.replyToMessageId,
    this.routeAttachment,
    this.pinnedAt,
    this.pinnedBy,
    this.profile,
    this.reactions = const [],
  });

  final String id;
  final String communityId;
  final String userId;
  final String body;
  final String? createdAt;
  final String? updatedAt;
  final String? deletedAt;
  final String? replyToMessageId;
  final Map<String, dynamic>? routeAttachment;
  final String? pinnedAt;
  final String? pinnedBy;
  final Map<String, dynamic>? profile;
  // 2026-07-22 (vucko Emoji-Reaktionen): rohe {emoji, user_id}-Maps aus dem
  // community_message_reactions-Embed — bewusst ungetypt wie beim Gruppen-Chat-
  // Vorbild, damit toggleReaction() dieselbe Liste direkt mutieren kann.
  final List<Map<String, dynamic>> reactions;

  factory CommunityChatMessage.fromJson(Map<String, dynamic> json) {
    return CommunityChatMessage(
      id: json['id']?.toString() ?? '',
      communityId: json['community_id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      createdAt: json['created_at']?.toString(),
      updatedAt: json['updated_at']?.toString(),
      deletedAt: json['deleted_at']?.toString(),
      replyToMessageId: json['reply_to_message_id']?.toString(),
      routeAttachment: _readMap(json['route_attachment']),
      pinnedAt: json['pinned_at']?.toString(),
      pinnedBy: json['pinned_by']?.toString(),
      profile: _readMap(json['profiles']),
      reactions: _readReactions(json['community_message_reactions']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'community_id': communityId,
    'user_id': userId,
    'body': body,
    'created_at': createdAt,
    'updated_at': updatedAt,
    'deleted_at': deletedAt,
    'reply_to_message_id': replyToMessageId,
    'route_attachment': routeAttachment,
    'pinned_at': pinnedAt,
    'pinned_by': pinnedBy,
    'profiles': profile,
    'community_message_reactions': reactions,
  };

  static List<Map<String, dynamic>> _readReactions(Object? value) {
    if (value is! List) return const [];
    return [
      for (final r in value)
        if (r is Map) Map<String, dynamic>.from(r),
    ];
  }

  static Map<String, dynamic>? _readMap(Object? value) {
    if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }
}
