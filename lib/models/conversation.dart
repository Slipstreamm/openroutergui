import 'message.dart';

class Conversation {
  String id;
  String title;
  List<Message> messages;
  DateTime createdAt;
  DateTime updatedAt;
  String modelId;

  // Conversation-specific settings
  bool reasoningEnabled;
  String reasoningEffort; // 'low', 'medium', 'high'
  double temperature;
  int maxTokens;
  bool webSearchEnabled;
  String? systemMessage;

  // Character-related settings
  String? character;
  String? characterInfo;
  bool characterBreakdown;
  String? customInstructions;

  Conversation({
    required this.id,
    required this.title,
    required this.messages,
    required this.createdAt,
    required this.updatedAt,
    required this.modelId,
    this.reasoningEnabled = false,
    this.reasoningEffort = 'medium',
    this.temperature = 0.7,
    this.maxTokens = 1000,
    this.webSearchEnabled = false,
    this.systemMessage,
    this.character,
    this.characterInfo,
    this.characterBreakdown = false,
    this.customInstructions,
  });

  // Create a new empty conversation
  factory Conversation.create({
    required String id,
    required String title,
    required String modelId,
    bool reasoningEnabled = false,
    String reasoningEffort = 'medium',
    double temperature = 0.7,
    int maxTokens = 1000,
    bool webSearchEnabled = false,
    String? systemMessage,
    String? character,
    String? characterInfo,
    bool characterBreakdown = false,
    String? customInstructions,
  }) {
    final now = DateTime.now();
    return Conversation(
      id: id,
      title: title,
      messages: [],
      createdAt: now,
      updatedAt: now,
      modelId: modelId,
      reasoningEnabled: reasoningEnabled,
      reasoningEffort: reasoningEffort,
      temperature: temperature,
      maxTokens: maxTokens,
      webSearchEnabled: webSearchEnabled,
      systemMessage: systemMessage,
      character: character,
      characterInfo: characterInfo,
      characterBreakdown: characterBreakdown,
      customInstructions: customInstructions,
    );
  }

  // Update the title
  void updateTitle(String newTitle) {
    title = newTitle;
    updatedAt = DateTime.now();
  }

  // Add a message
  void addMessage(Message message) {
    messages.add(message);
    updatedAt = DateTime.now();
  }

  // Edit a message
  void editMessage(int index, String newContent) {
    if (index >= 0 && index < messages.length) {
      final message = messages[index];
      messages[index] = Message(content: newContent, role: message.role, timestamp: message.timestamp);
      updatedAt = DateTime.now();
    }
  }

  // Delete a message
  void deleteMessage(int index) {
    if (index >= 0 && index < messages.length) {
      messages.removeAt(index);
      updatedAt = DateTime.now();
    }
  }

  // Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'messages': messages.map((m) => m.toMap()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'modelId': modelId,
      'reasoningEnabled': reasoningEnabled,
      'reasoningEffort': reasoningEffort,
      'temperature': temperature,
      'maxTokens': maxTokens,
      'webSearchEnabled': webSearchEnabled,
      if (systemMessage != null) 'systemMessage': systemMessage,
      if (character != null) 'character': character,
      if (characterInfo != null) 'characterInfo': characterInfo,
      'characterBreakdown': characterBreakdown,
      if (customInstructions != null) 'customInstructions': customInstructions,
    };
  }

  // Create from JSON
  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'] as String,
      title: json['title'] as String,
      messages: (json['messages'] as List).map((m) => Message.fromMap(m as Map<String, dynamic>)).toList(),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      modelId: json['modelId'] as String,
      reasoningEnabled: json['reasoningEnabled'] as bool? ?? false,
      reasoningEffort: json['reasoningEffort'] as String? ?? 'medium',
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.7,
      maxTokens: json['maxTokens'] as int? ?? 1000,
      webSearchEnabled: json['webSearchEnabled'] as bool? ?? false,
      systemMessage: json['systemMessage'] as String?,
      character: json['character'] as String?,
      characterInfo: json['characterInfo'] as String?,
      characterBreakdown: json['characterBreakdown'] as bool? ?? false,
      customInstructions: json['customInstructions'] as String?,
    );
  }

  // Get a preview of the conversation (first few characters)
  String get preview {
    if (messages.isEmpty) {
      return 'Empty conversation';
    }

    // Find the first non-system message
    final firstMessage = messages.firstWhere((m) => m.role != MessageRole.system, orElse: () => messages.first);

    final content = firstMessage.content;
    if (content.length <= 50) {
      return content;
    }
    return '${content.substring(0, 47)}...';
  }

  // Update conversation settings
  void updateSettings({
    bool? reasoningEnabled,
    String? reasoningEffort,
    double? temperature,
    int? maxTokens,
    bool? webSearchEnabled,
    String? systemMessage,
    String? character,
    String? characterInfo,
    bool? characterBreakdown,
    String? customInstructions,
  }) {
    if (reasoningEnabled != null) this.reasoningEnabled = reasoningEnabled;
    if (reasoningEffort != null) this.reasoningEffort = reasoningEffort;
    if (temperature != null) this.temperature = temperature;
    if (maxTokens != null) this.maxTokens = maxTokens;
    if (webSearchEnabled != null) this.webSearchEnabled = webSearchEnabled;
    if (systemMessage != null) this.systemMessage = systemMessage;
    if (character != null) this.character = character;
    if (characterInfo != null) this.characterInfo = characterInfo;
    if (characterBreakdown != null) this.characterBreakdown = characterBreakdown;
    if (customInstructions != null) this.customInstructions = customInstructions;

    updatedAt = DateTime.now();
  }
}
