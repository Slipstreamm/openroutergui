import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/conversation.dart';
import 'discord_oauth_service.dart';

/// Service for interacting with the unified API
class ApiService extends ChangeNotifier {
  // The URL of the API server
  static const String apiUrl = 'https://slipstreamm.dev/api';

  // Discord OAuth service for authentication
  final DiscordOAuthService _authService;

  // API state
  bool _isLoading = false;
  String? _error;

  // Constructor
  ApiService(this._authService);

  // Getters
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _authService.isLoggedIn;

  // Make a request to the API
  Future<dynamic> _makeRequest(String method, String endpoint, {Map<String, dynamic>? data}) async {
    if (!_authService.isLoggedIn) {
      _error = 'Not logged in to Discord';
      notifyListeners();
      throw Exception('Not logged in to Discord');
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final authHeader = _authService.getAuthHeader();
      if (authHeader == null) {
        _error = 'Authentication error';
        _isLoading = false;
        notifyListeners();
        throw Exception('Authentication error');
      }

      final headers = {'Authorization': authHeader, 'Content-Type': 'application/json'};

      final url = Uri.parse('$apiUrl/$endpoint');
      http.Response response;

      if (method == 'GET') {
        response = await http.get(url, headers: headers);
      } else if (method == 'POST') {
        response = await http.post(url, headers: headers, body: data != null ? jsonEncode(data) : null);
      } else if (method == 'PUT') {
        response = await http.put(url, headers: headers, body: data != null ? jsonEncode(data) : null);
      } else if (method == 'DELETE') {
        response = await http.delete(url, headers: headers);
      } else {
        throw Exception('Unsupported HTTP method: $method');
      }

      _isLoading = false;
      notifyListeners();

      if (response.statusCode != 200 && response.statusCode != 201) {
        _error = 'API request failed: ${response.statusCode} - ${response.body}';
        notifyListeners();
        throw Exception('API request failed: ${response.statusCode} - ${response.body}');
      }

      return jsonDecode(response.body);
    } catch (e) {
      _isLoading = false;
      _error = 'Error: $e';
      notifyListeners();
      rethrow;
    }
  }

  // ============= Conversation Methods =============

  /// Get all conversations for the authenticated user
  Future<List<Map<String, dynamic>>> getConversations() async {
    final response = await _makeRequest('GET', 'conversations');
    return List<Map<String, dynamic>>.from(response['conversations']);
  }

  /// Get a specific conversation
  Future<Map<String, dynamic>> getConversation(String conversationId) async {
    final response = await _makeRequest('GET', 'conversations/$conversationId');
    return Map<String, dynamic>.from(response);
  }

  /// Create a new conversation
  Future<Map<String, dynamic>> createConversation(Conversation conversation) async {
    final response = await _makeRequest('POST', 'conversations', data: {'conversation': _convertConversationToApi(conversation)});
    return Map<String, dynamic>.from(response);
  }

  /// Update an existing conversation
  Future<Map<String, dynamic>> updateConversation(Conversation conversation) async {
    final response = await _makeRequest('PUT', 'conversations/${conversation.id}', data: {'conversation': _convertConversationToApi(conversation)});
    return Map<String, dynamic>.from(response);
  }

  /// Delete a conversation
  Future<bool> deleteConversation(String conversationId) async {
    final response = await _makeRequest('DELETE', 'conversations/$conversationId');
    return response['success'] as bool;
  }

  // ============= Settings Methods =============

  /// Get settings for the authenticated user
  Future<Map<String, dynamic>> getSettings() async {
    final response = await _makeRequest('GET', 'settings');
    return Map<String, dynamic>.from(response['settings']);
  }

  /// Update settings for the authenticated user
  Future<Map<String, dynamic>> updateSettings(Map<String, dynamic> settings) async {
    final response = await _makeRequest('PUT', 'settings', data: {'settings': settings});
    return Map<String, dynamic>.from(response);
  }

  /// Sync settings with the API
  Future<bool> syncSettings() async {
    try {
      // Get settings from SharedPreferences
      final settings = await _getUserSettingsFromPrefs();

      // Update settings in the API
      await updateSettings(settings);

      return true;
    } catch (e) {
      debugPrint('Error syncing settings: $e');
      return false;
    }
  }

  /// Get settings from the API and apply them to SharedPreferences
  Future<bool> fetchAndApplySettings() async {
    try {
      // Get settings from the API
      final settings = await getSettings();

      // Apply settings to SharedPreferences
      await _applySettingsToPrefs(settings);

      return true;
    } catch (e) {
      debugPrint('Error fetching and applying settings: $e');
      return false;
    }
  }

  // ============= Helper Methods =============

  /// Convert a Conversation object to API format
  Map<String, dynamic> _convertConversationToApi(Conversation conversation) {
    return {
      'id': conversation.id,
      'title': conversation.title,
      'messages':
          conversation.messages
              .map(
                (msg) => {
                  'content': msg.content,
                  'role': msg.role.toString().split('.').last,
                  'timestamp': msg.timestamp.toIso8601String(),
                  'reasoning': msg.reasoning,
                  'usage_data': msg.usageData,
                },
              )
              .toList(),
      'created_at': conversation.createdAt.toIso8601String(),
      'updated_at': conversation.updatedAt.toIso8601String(),
      'model_id': conversation.modelId,
      'reasoning_enabled': conversation.reasoningEnabled,
      'reasoning_effort': conversation.reasoningEffort,
      'temperature': conversation.temperature,
      'max_tokens': conversation.maxTokens,
      'web_search_enabled': conversation.webSearchEnabled,
      'system_message': conversation.systemMessage,
    };
  }

  // Note: This method is kept for reference but not currently used
  // If needed in the future, uncomment and use it
  /*
  /// Convert API conversation to a Conversation object
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
  */

  // Note: This method is kept for reference but not currently used
  // If needed in the future, uncomment and use it
  /*
  /// Parse message role from string
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
  */

  /// Get user settings from SharedPreferences
  Future<Map<String, dynamic>> _getUserSettingsFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();

    // Get all the settings from SharedPreferences
    final modelId = prefs.getString('selected_model') ?? 'openai/gpt-3.5-turbo';
    final temperature = prefs.getDouble('temperature') ?? 0.7;
    final maxTokens = prefs.getInt('max_tokens') ?? 1000;
    final reasoningEnabled = prefs.getBool('reasoningEnabled') ?? false;
    final reasoningEffort = prefs.getString('reasoningEffort') ?? 'medium';
    final webSearchEnabled = prefs.getBool('webSearchEnabled') ?? false;
    final systemMessage = prefs.getString('system_message');
    final character = prefs.getString('character');
    final characterInfo = prefs.getString('character_info');
    final characterBreakdown = prefs.getBool('character_breakdown') ?? false;
    final customInstructions = prefs.getString('custom_instructions');
    final advancedViewEnabled = prefs.getBool('advancedViewEnabled') ?? false;
    final streamingEnabled = prefs.getBool('streamingEnabled') ?? true;

    // Create and return the settings map
    return {
      'model_id': modelId,
      'temperature': temperature,
      'max_tokens': maxTokens,
      'reasoning_enabled': reasoningEnabled,
      'reasoning_effort': reasoningEffort,
      'web_search_enabled': webSearchEnabled,
      'system_message': systemMessage,
      'character': character,
      'character_info': characterInfo,
      'character_breakdown': characterBreakdown,
      'custom_instructions': customInstructions,
      'advanced_view_enabled': advancedViewEnabled,
      'streaming_enabled': streamingEnabled,
      'last_updated': DateTime.now().toIso8601String(),
    };
  }

  /// Apply settings from API to SharedPreferences
  Future<void> _applySettingsToPrefs(Map<String, dynamic> settings) async {
    final prefs = await SharedPreferences.getInstance();

    // Save all the settings to SharedPreferences
    await prefs.setString('selected_model', settings['model_id']);
    await prefs.setDouble('temperature', settings['temperature']);
    await prefs.setInt('max_tokens', settings['max_tokens']);
    await prefs.setBool('reasoningEnabled', settings['reasoning_enabled']);
    await prefs.setString('reasoningEffort', settings['reasoning_effort']);
    await prefs.setBool('webSearchEnabled', settings['web_search_enabled']);

    if (settings['system_message'] != null) {
      await prefs.setString('system_message', settings['system_message']);
    } else {
      await prefs.remove('system_message');
    }

    if (settings['character'] != null) {
      await prefs.setString('character', settings['character']);
    } else {
      await prefs.remove('character');
    }

    if (settings['character_info'] != null) {
      await prefs.setString('character_info', settings['character_info']);
    } else {
      await prefs.remove('character_info');
    }

    await prefs.setBool('character_breakdown', settings['character_breakdown']);

    if (settings['custom_instructions'] != null) {
      await prefs.setString('custom_instructions', settings['custom_instructions']);
    } else {
      await prefs.remove('custom_instructions');
    }

    await prefs.setBool('advancedViewEnabled', settings['advanced_view_enabled']);
    await prefs.setBool('streamingEnabled', settings['streaming_enabled']);

    // Save the update time
    await prefs.setInt('last_settings_update', DateTime.now().millisecondsSinceEpoch);

    // Notify listeners that settings have changed
    notifyListeners();
  }

  @override
  void dispose() {
    // Clean up
    super.dispose();
  }
}
