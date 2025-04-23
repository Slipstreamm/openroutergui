import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../services/api_service.dart';

// Simple response class for simulating AI responses
class AIResponse {
  final String content;
  final String? reasoning;
  final Map<String, dynamic>? usageData;

  AIResponse({required this.content, this.reasoning, this.usageData});
}

class ChatModel extends ChangeNotifier {
  // Services
  final ApiService _apiService;

  // State
  List<Conversation> _conversations = [];
  String? _activeConversationId;
  bool _isLoading = false;
  bool _isStreaming = false;
  String _currentStreamingContent = '';
  String? _error;

  // Settings
  bool _reasoningEnabled = false;
  String _reasoningEffort = 'medium';
  bool _webSearchEnabled = false;
  bool _streamingEnabled = true;

  // Getters
  List<Conversation> get conversations => _conversations;
  Conversation? get activeConversation =>
      _activeConversationId != null
          ? _conversations.firstWhere(
            (c) => c.id == _activeConversationId,
            orElse:
                () => Conversation(
                  id: '',
                  title: '',
                  messages: [],
                  createdAt: DateTime.now(),
                  updatedAt: DateTime.now(),
                  modelId: 'openai/gpt-3.5-turbo',
                  reasoningEnabled: false,
                  reasoningEffort: 'medium',
                  temperature: 0.7,
                  maxTokens: 1000,
                  webSearchEnabled: false,
                ),
          )
          : null;
  bool get isLoading => _isLoading;
  bool get isStreaming => _isStreaming;
  String? get error => _error;
  bool get reasoningEnabled => _reasoningEnabled;
  String get reasoningEffort => _reasoningEffort;
  bool get webSearchEnabled => _webSearchEnabled;
  bool get streamingEnabled => _streamingEnabled;

  // Constructor
  ChatModel(this._apiService) {
    _loadConversations();
    _loadSettings();
  }

  // Load conversations from API if logged in, otherwise from local storage
  Future<void> _loadConversations() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      if (_apiService.isAuthenticated) {
        // Load conversations from API
        final apiConversations = await _apiService.getConversations();
        _conversations = apiConversations.map((conv) => _convertApiToConversation(conv)).toList();
        debugPrint('Loaded ${_conversations.length} conversations from API');
      } else {
        // Load conversations from local storage
        final prefs = await SharedPreferences.getInstance();
        final conversationsJson = prefs.getString('conversations');

        if (conversationsJson != null) {
          final List<dynamic> decoded = jsonDecode(conversationsJson);
          _conversations = decoded.map((json) => Conversation.fromJson(json)).toList();
          debugPrint('Loaded ${_conversations.length} conversations from local storage');
        }
      }

      // Load active conversation ID
      await _loadActiveConversationId();

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _error = 'Error loading conversations: $e';
      debugPrint(_error);
      notifyListeners();
    }
  }

  // Load active conversation ID from SharedPreferences
  Future<void> _loadActiveConversationId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _activeConversationId = prefs.getString('activeConversationId');

      // Ensure the active conversation exists
      if (_activeConversationId != null) {
        final exists = _conversations.any((c) => c.id == _activeConversationId);
        if (!exists) {
          _activeConversationId = null;
        }
      }

      // If no active conversation, set the first one as active
      if (_activeConversationId == null && _conversations.isNotEmpty) {
        _activeConversationId = _conversations.first.id;
      }
    } catch (e) {
      debugPrint('Error loading active conversation ID: $e');
    }
  }

  // Load settings from SharedPreferences
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Load reasoning settings
      final reasoningEnabled = prefs.getBool('reasoningEnabled');
      final reasoningEffort = prefs.getString('reasoningEffort');

      if (reasoningEnabled != null) {
        _reasoningEnabled = reasoningEnabled;
      }

      if (reasoningEffort != null && ['low', 'medium', 'high'].contains(reasoningEffort)) {
        _reasoningEffort = reasoningEffort;
      }

      // Load web search setting
      final webSearchEnabled = prefs.getBool('webSearchEnabled');
      if (webSearchEnabled != null) {
        _webSearchEnabled = webSearchEnabled;
      }

      // Load streaming setting
      final streamingEnabled = prefs.getBool('streamingEnabled');
      if (streamingEnabled != null) {
        _streamingEnabled = streamingEnabled;
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Error loading settings: $e');
    }
  }

  // Save conversations to API if logged in, otherwise to local storage
  Future<void> _saveConversations() async {
    try {
      if (_apiService.isAuthenticated) {
        // Save active conversation to API if it exists
        if (activeConversation != null) {
          await _apiService.updateConversation(activeConversation!);
          debugPrint('Saved active conversation to API');
        }
      } else {
        // Save to local storage
        final prefs = await SharedPreferences.getInstance();
        final conversationsJson = jsonEncode(_conversations.map((c) => c.toJson()).toList());
        await prefs.setString('conversations', conversationsJson);
        debugPrint('Saved conversations to local storage');
      }
    } catch (e) {
      debugPrint('Error saving conversations: $e');
    }
  }

  // Public method to force saving conversations
  Future<void> forceSaveConversations() async {
    debugPrint('Force saving conversations');
    await _saveConversations();
  }

  // Create a new conversation
  Future<Conversation> createConversation({String? title}) async {
    final newConversation = Conversation(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title ?? 'New Conversation',
      messages: [],
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      modelId: 'openai/gpt-3.5-turbo',
      reasoningEnabled: _reasoningEnabled,
      reasoningEffort: _reasoningEffort,
      temperature: 0.7,
      maxTokens: 1000,
      webSearchEnabled: _webSearchEnabled,
    );

    _conversations.add(newConversation);
    _activeConversationId = newConversation.id;

    // Save to API if authenticated
    if (_apiService.isAuthenticated) {
      try {
        final apiConversation = await _apiService.createConversation(newConversation);
        // Update the local conversation with the API version
        final index = _conversations.indexWhere((c) => c.id == newConversation.id);
        if (index >= 0) {
          _conversations[index] = _convertApiToConversation(apiConversation);
        }
      } catch (e) {
        debugPrint('Error creating conversation in API: $e');
      }
    }

    await _saveConversations();
    await _saveActiveConversationId();
    notifyListeners();

    return newConversation;
  }

  // Delete a conversation
  Future<void> deleteConversation(String conversationId) async {
    // Delete from API if authenticated
    if (_apiService.isAuthenticated) {
      try {
        await _apiService.deleteConversation(conversationId);
        debugPrint('Deleted conversation from API');
      } catch (e) {
        debugPrint('Error deleting conversation from API: $e');
      }
    }

    _conversations.removeWhere((c) => c.id == conversationId);

    // If the active conversation was deleted, set a new active conversation
    if (_activeConversationId == conversationId) {
      _activeConversationId = _conversations.isNotEmpty ? _conversations.first.id : null;
      await _saveActiveConversationId();
    }

    await _saveConversations();
    notifyListeners();
  }

  // Set the active conversation
  Future<void> setActiveConversation(String conversationId) async {
    _activeConversationId = conversationId;
    await _saveActiveConversationId();
    notifyListeners();
  }

  // Save active conversation ID
  Future<void> _saveActiveConversationId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_activeConversationId != null) {
        await prefs.setString('activeConversationId', _activeConversationId!);
      } else {
        await prefs.remove('activeConversationId');
      }
    } catch (e) {
      debugPrint('Error saving active conversation ID: $e');
    }
  }

  // Send a message to the AI
  Future<void> sendMessage(String content) async {
    if (activeConversation == null) {
      await createConversation();
    }

    // Add user message to conversation
    final userMessage = Message(content: content, role: MessageRole.user, timestamp: DateTime.now());

    activeConversation!.messages.add(userMessage);
    activeConversation!.updatedAt = DateTime.now();
    notifyListeners();

    // Save the conversation
    await _saveConversations();

    // Get AI response
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Prepare the conversation for the AI
      final messages = activeConversation!.messages.map((msg) => {'content': msg.content, 'role': msg.role.toString().split('.').last}).toList();

      // Add system message if available
      if (activeConversation!.systemMessage != null) {
        messages.insert(0, {'content': activeConversation!.systemMessage!, 'role': 'system'});
      }

      // Get response from OpenRouter
      if (_streamingEnabled) {
        // Use streaming
        _isStreaming = true;
        _currentStreamingContent = '';
        notifyListeners();

        // Note: This is a placeholder for the streaming implementation
        // In a real implementation, you would use the OpenRouterService's streaming method
        // For now, we'll simulate a stream with a single chunk
        final stream = Stream.fromIterable(['This is a simulated response from the AI.']);

        // Add assistant message with empty content
        final assistantMessage = Message(content: '', role: MessageRole.assistant, timestamp: DateTime.now());

        activeConversation!.messages.add(assistantMessage);
        notifyListeners();

        // Process the stream
        await for (final chunk in stream) {
          // Update the message content
          _currentStreamingContent += chunk;
          final lastIndex = activeConversation!.messages.length - 1;
          activeConversation!.messages[lastIndex] = Message(
            content: _currentStreamingContent,
            role: MessageRole.assistant,
            timestamp: activeConversation!.messages[lastIndex].timestamp,
          );
          notifyListeners();
        }

        // Finalize the message
        final lastIndex = activeConversation!.messages.length - 1;
        final content = activeConversation!.messages[lastIndex].content;

        // Clean up any malformed markdown that might have been added during streaming
        try {
          // Fix any markdown issues in the final content
          final cleanedContent = _cleanupMarkdownContent(content);

          if (cleanedContent != content) {
            activeConversation!.messages[lastIndex] = Message(
              content: cleanedContent,
              role: MessageRole.assistant,
              timestamp: activeConversation!.messages[lastIndex].timestamp,
            );
          }
        } catch (e) {
          debugPrint('Error cleaning up markdown content: $e');
        }

        _isStreaming = false;
        _currentStreamingContent = '';
      } else {
        // Use non-streaming
        // Note: This is a placeholder for the non-streaming implementation
        // In a real implementation, you would use the OpenRouterService's completion method
        // For now, we'll create a simulated response
        final response = AIResponse(
          content: 'This is a simulated response from the AI.',
          reasoning: _reasoningEnabled ? 'This is simulated reasoning.' : null,
          usageData: {'prompt_tokens': 10, 'completion_tokens': 20, 'total_tokens': 30},
        );

        // Add assistant message
        final assistantMessage = Message(
          content: response.content,
          role: MessageRole.assistant,
          timestamp: DateTime.now(),
          reasoning: response.reasoning,
          usageData: response.usageData,
        );

        activeConversation!.messages.add(assistantMessage);
      }

      // Update conversation
      activeConversation!.updatedAt = DateTime.now();

      _isLoading = false;
      notifyListeners();

      // Save the conversation
      await _saveConversations();
    } catch (e) {
      _isLoading = false;
      _isStreaming = false;
      _error = 'Error getting AI response: $e';
      debugPrint(_error);
      notifyListeners();
    }
  }

  // Clean up markdown content
  String _cleanupMarkdownContent(String content) {
    // Fix common markdown issues
    var cleaned = content;

    // Fix unclosed code blocks
    final codeBlockCount = '```'.allMatches(cleaned).length;
    if (codeBlockCount % 2 != 0) {
      cleaned += '\n```';
    }

    return cleaned;
  }

  // Set reasoning enabled
  void setReasoningEnabled(bool enabled) async {
    _reasoningEnabled = enabled;

    // Update active conversation if it exists
    if (activeConversation != null) {
      activeConversation!.reasoningEnabled = enabled;
      await _saveConversations();
    }

    // Save to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('reasoningEnabled', enabled);

    notifyListeners();
  }

  // Set reasoning effort
  void setReasoningEffort(String effort) async {
    if (!['low', 'medium', 'high'].contains(effort)) {
      return;
    }

    _reasoningEffort = effort;

    // Update active conversation if it exists
    if (activeConversation != null) {
      activeConversation!.reasoningEffort = effort;
      await _saveConversations();
    }

    // Save to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('reasoningEffort', effort);

    notifyListeners();
  }

  // Set web search enabled
  void setWebSearchEnabled(bool enabled) async {
    _webSearchEnabled = enabled;

    // Update active conversation if it exists
    if (activeConversation != null) {
      activeConversation!.webSearchEnabled = enabled;
      await _saveConversations();
    }

    // Save to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('webSearchEnabled', enabled);

    notifyListeners();
  }

  // Set streaming enabled
  void setStreamingEnabled(bool enabled) async {
    _streamingEnabled = enabled;

    // Save to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('streamingEnabled', enabled);

    notifyListeners();
  }

  // Set system message
  Future<void> setSystemMessage(String message) async {
    // Update active conversation if it exists
    if (activeConversation != null) {
      activeConversation!.systemMessage = message.isNotEmpty ? message : null;
      await _saveConversations();
    }

    notifyListeners();
  }

  // Set global character settings
  Future<void> setGlobalCharacterSettings(String? character, String? characterInfo, bool characterBreakdown, String? customInstructions) async {
    // Save to SharedPreferences
    final prefs = await SharedPreferences.getInstance();

    if (character != null) {
      await prefs.setString('character', character);
    } else {
      await prefs.remove('character');
    }

    if (characterInfo != null) {
      await prefs.setString('character_info', characterInfo);
    } else {
      await prefs.remove('character_info');
    }

    await prefs.setBool('character_breakdown', characterBreakdown);

    if (customInstructions != null) {
      await prefs.setString('custom_instructions', customInstructions);
    } else {
      await prefs.remove('custom_instructions');
    }

    // Sync with API if authenticated
    if (_apiService.isAuthenticated) {
      await _apiService.syncSettings();
    }

    notifyListeners();
  }

  // Update conversation character settings
  Future<void> updateConversationCharacterSettings(
    String conversationId,
    String character,
    String characterInfo,
    bool characterBreakdown,
    String customInstructions,
  ) async {
    final conversation = _conversations.firstWhere(
      (c) => c.id == conversationId,
      orElse:
          () => Conversation(
            id: '',
            title: '',
            messages: [],
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            modelId: 'openai/gpt-3.5-turbo',
            reasoningEnabled: false,
            reasoningEffort: 'medium',
            temperature: 0.7,
            maxTokens: 1000,
            webSearchEnabled: false,
          ),
    );

    if (conversation.id.isNotEmpty) {
      // Build system message from character settings
      String systemMessage = '';

      if (character.isNotEmpty) {
        systemMessage += 'You are $character. ';

        if (characterInfo.isNotEmpty) {
          if (characterBreakdown) {
            // Add character info with breakdown
            systemMessage += 'Here is information about your character:\n\n$characterInfo\n\n';
          } else {
            // Add character info without breakdown
            systemMessage += '$characterInfo ';
          }
        }
      }

      if (customInstructions.isNotEmpty) {
        systemMessage += customInstructions;
      }

      // Update the conversation
      conversation.systemMessage = systemMessage.isNotEmpty ? systemMessage : null;
      conversation.updatedAt = DateTime.now();

      await _saveConversations();
      notifyListeners();
    }
  }

  // Reload and apply global settings to all conversations
  Future<void> reloadAndApplyGlobalSettings() async {
    await _loadSettings();

    // Apply settings to all conversations
    for (final conversation in _conversations) {
      conversation.reasoningEnabled = _reasoningEnabled;
      conversation.reasoningEffort = _reasoningEffort;
      conversation.webSearchEnabled = _webSearchEnabled;
    }

    await _saveConversations();
    notifyListeners();
  }

  // Convert API conversation to a Conversation object
  Conversation _convertApiToConversation(Map<String, dynamic> apiConversation) {
    return Conversation(
      id: apiConversation['id'],
      title: apiConversation['title'],
      messages:
          (apiConversation['messages'] as List).map((msgData) {
            final role = _parseMessageRole(msgData['role']);
            return Message(
              content: msgData['content'],
              role: role,
              timestamp: DateTime.parse(msgData['timestamp']),
              reasoning: msgData['reasoning'],
              usageData: msgData['usage_data'] != null ? Map<String, dynamic>.from(msgData['usage_data']) : null,
            );
          }).toList(),
      createdAt: DateTime.parse(apiConversation['created_at']),
      updatedAt: DateTime.parse(apiConversation['updated_at']),
      modelId: apiConversation['model_id'],
      reasoningEnabled: apiConversation['reasoning_enabled'],
      reasoningEffort: apiConversation['reasoning_effort'],
      temperature: apiConversation['temperature'].toDouble(),
      maxTokens: apiConversation['max_tokens'],
      webSearchEnabled: apiConversation['web_search_enabled'],
      systemMessage: apiConversation['system_message'],
    );
  }

  // Parse message role from string
  MessageRole _parseMessageRole(String roleStr) {
    switch (roleStr.toLowerCase()) {
      case 'user':
        return MessageRole.user;
      case 'assistant':
        return MessageRole.assistant;
      case 'system':
        return MessageRole.system;
      default:
        return MessageRole.user;
    }
  }
}
