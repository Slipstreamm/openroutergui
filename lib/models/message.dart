enum MessageRole { user, assistant, system }

class Message {
  final String content;
  final MessageRole role;
  final DateTime timestamp;
  final String? reasoning; // Reasoning tokens from the model
  final Map<String, dynamic>? usageData; // Usage accounting data from OpenRouter

  Message({required this.content, required this.role, this.reasoning, this.usageData, DateTime? timestamp}) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {'role': role.toString().split('.').last, 'content': content};
  }

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      content: json['content'] as String,
      role: _roleFromString(json['role'] as String),
      reasoning: json['reasoning'] as String?,
      usageData: json['usageData'] != null ? Map<String, dynamic>.from(json['usageData']) : null,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  static MessageRole _roleFromString(String roleStr) {
    switch (roleStr) {
      case 'user':
        return MessageRole.user;
      case 'assistant':
        return MessageRole.assistant;
      case 'system':
        return MessageRole.system;
      default:
        throw ArgumentError('Invalid role: $roleStr');
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'content': content,
      'role': role.toString().split('.').last,
      'timestamp': timestamp.toIso8601String(),
      if (reasoning != null) 'reasoning': reasoning,
      if (usageData != null) 'usageData': usageData,
    };
  }

  factory Message.fromMap(Map<String, dynamic> map) {
    return Message(
      content: map['content'] as String,
      role: _roleFromString(map['role'] as String),
      reasoning: map['reasoning'] as String?,
      usageData: map['usageData'] != null ? Map<String, dynamic>.from(map['usageData']) : null,
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }
}
