import 'dart:convert';
import 'package:uuid/uuid.dart';

class Message {
  final String id;
  final String content;
  final bool isUser;
  final DateTime timestamp;

  Message({
    String? id,
    required this.content,
    required this.isUser,
    required this.timestamp,
  }) : id = id ?? const Uuid().v4();

  Message copyWith({
    String? id,
    String? content,
    bool? isUser,
    DateTime? timestamp,
  }) => Message(
    id: id ?? this.id,
    content: content ?? this.content,
    isUser: isUser ?? this.isUser,
    timestamp: timestamp ?? this.timestamp,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'isUser': isUser,
    'timestamp': timestamp.toIso8601String(),
  };

  factory Message.fromJson(Map<String, dynamic> json) => Message(
    id: json['id'] as String? ?? const Uuid().v4(),
    content: json['content'] as String,
    isUser: json['isUser'] as bool,
    timestamp: DateTime.parse(json['timestamp'] as String),
  );

  String toJsonString() => jsonEncode(toJson());
  factory Message.fromJsonString(String jsonString) => Message.fromJson(jsonDecode(jsonString));
}

class Chat {
  final String id;
  final String title;
  final List<Message> messages;
  final DateTime createdAt;

  Chat({
    required this.id,
    required this.title,
    required this.messages,
    required this.createdAt,
  });

  Chat copyWith({
    String? id,
    String? title,
    List<Message>? messages,
    DateTime? createdAt,
  }) => Chat(
    id: id ?? this.id,
    title: title ?? this.title,
    messages: messages ?? this.messages,
    createdAt: createdAt ?? this.createdAt,
  );

  String toJsonString() => jsonEncode({
    'id': id,
    'title': title,
    'messages': messages.map((m) => m.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
  });

  factory Chat.fromJsonString(String jsonString) {
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    return Chat(
      id: json['id'] as String,
      title: json['title'] as String,
      messages: (json['messages'] as List)
          .map((m) => Message.fromJson(m as Map<String, dynamic>))
          .toList(),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
} 