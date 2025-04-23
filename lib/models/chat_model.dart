import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:collection/collection.dart'; // Import collection package
import '../services/openrouter_service.dart';
import '../services/sync_service.dart';
import 'message.dart';
import 'conversation.dart';

class ChatModel extends ChangeNotifier {
  // List of all conversations
  final List<Conversation> _conversations = [];

  // Currently active conversation ID
  String? _activeConversationId;

  // UI state
  bool _isLoading = false;
  String _selectedModel = 'openai/gpt-3.5-turbo';
  String _error = '';
  bool _streamingEnabled = true;
  String _currentStreamingContent = '';
  bool _advancedViewEnabled = false;

  // Credits information
  Map<String, dynamic> _credits = {};
  bool _isLoadingCredits = false;

  // Reasoning tokens settings
  bool _reasoningEnabled = false;
  String _reasoningEffort = 'medium'; // 'low', 'medium', 'high'

  // Service for API calls
  final OpenRouterService _openRouterService = OpenRouterService();
  bool _isStreaming = false;

  // Expose OpenRouterService methods
  Stream<Map<String, dynamic>> sendStreamingChatRequest({
    required List<Message> messages,
    required String model,
    double? temperature,
    int? maxTokens,
    bool? reasoningEnabled,
    String? reasoningEffort,
    bool? webSearchEnabled,
    String? character,
    String? characterInfo,
    bool? characterBreakdown,
    String? customInstructions,
    String? systemMessage,
  }) {
    // Get the active conversation
    final conversation = activeConversation;
    if (conversation == null) {
      throw Exception('No active conversation');
    }

    // Refresh credits after streaming is complete
    Future.delayed(const Duration(seconds: 2), () {
      loadCredits();
    });

    return _openRouterService.sendStreamingChatRequest(
      messages: messages,
      model: model,
      temperature: temperature ?? conversation.temperature,
      maxTokens: maxTokens ?? conversation.maxTokens,
      reasoningEnabled: reasoningEnabled ?? conversation.reasoningEnabled,
      reasoningEffort: reasoningEffort ?? conversation.reasoningEffort,
      webSearchEnabled: webSearchEnabled ?? conversation.webSearchEnabled,
      character: character ?? conversation.character,
      characterInfo: characterInfo ?? conversation.characterInfo,
      characterBreakdown: characterBreakdown ?? conversation.characterBreakdown,
      customInstructions: customInstructions ?? conversation.customInstructions,
      systemMessage: systemMessage ?? conversation.systemMessage,
    );
  }

  Future<Map<String, dynamic>> sendChatRequest({
    required List<Message> messages,
    required String model,
    double? temperature,
    int? maxTokens,
    bool? reasoningEnabled,
    String? reasoningEffort,
    bool? webSearchEnabled,
    String? character,
    String? characterInfo,
    bool? characterBreakdown,
    String? customInstructions,
    String? systemMessage,
  }) async {
    // Get the active conversation
    final conversation = activeConversation;
    if (conversation == null) {
      throw Exception('No active conversation');
    }

    final response = await _openRouterService.sendChatRequest(
      messages: messages,
      model: model,
      temperature: temperature ?? conversation.temperature,
      maxTokens: maxTokens ?? conversation.maxTokens,
      reasoningEnabled: reasoningEnabled ?? conversation.reasoningEnabled,
      reasoningEffort: reasoningEffort ?? conversation.reasoningEffort,
      webSearchEnabled: webSearchEnabled ?? conversation.webSearchEnabled,
      character: character ?? conversation.character,
      characterInfo: characterInfo ?? conversation.characterInfo,
      characterBreakdown: characterBreakdown ?? conversation.characterBreakdown,
      customInstructions: customInstructions ?? conversation.customInstructions,
      systemMessage: systemMessage ?? conversation.systemMessage,
    );
    // Refresh credits after request
    loadCredits();
    return response;
  }

  // Get API key
  Future<String?> getApiKey() {
    return _openRouterService.getApiKey();
  }

  // Getters
  List<Conversation> get conversations => List.unmodifiable(_conversations);
  Conversation? get activeConversation =>
      _activeConversationId != null
          ? _conversations.firstWhereOrNull((c) => c.id == _activeConversationId) // Use firstWhereOrNull
          : null;
  List<Message> get messages => activeConversation?.messages ?? [];
  bool get isLoading => _isLoading;
  String get selectedModel => _selectedModel;
  String get error => _error;
  bool get streamingEnabled => _streamingEnabled;
  String get currentStreamingContent => _currentStreamingContent;
  String? get activeConversationId => _activeConversationId;
  bool get isStreaming => _isStreaming;
  Map<String, dynamic> get credits => _credits;
  bool get isLoadingCredits => _isLoadingCredits;
  bool get reasoningEnabled => _reasoningEnabled;
  String get reasoningEffort => _reasoningEffort;
  bool get advancedViewEnabled => _advancedViewEnabled;

  // Get formatted credits string for display
  String get formattedCredits {
    if (_credits.isEmpty) return 'Credits: -';
    if (_credits.containsKey('error')) return 'Credits: Error';

    final available = ((_credits['data']['total_credits'] ?? 0.0) - (_credits['data']['total_usage'] ?? 0.0)).toStringAsFixed(2);

    return 'Credits: \$$available'; // Show available credits
  }

  // Calculate total usage for the current conversation
  Map<String, dynamic> get conversationUsage {
    if (activeConversation == null) return {};

    num totalPromptTokens = 0;
    num totalCompletionTokens = 0;
    num totalTokens = 0;
    double totalCost = 0.0;

    for (final message in activeConversation!.messages) {
      if (message.role == MessageRole.assistant && message.usageData != null) {
        totalPromptTokens += message.usageData!['prompt_tokens'] ?? 0;
        totalCompletionTokens += message.usageData!['completion_tokens'] ?? 0;
        totalTokens += message.usageData!['total_tokens'] ?? 0;
        totalCost += (message.usageData!['cost'] ?? 0) / 1000; // Convert from millicredits to credits
      }
    }

    return {'prompt_tokens': totalPromptTokens, 'completion_tokens': totalCompletionTokens, 'total_tokens': totalTokens, 'cost': totalCost};
  }

  // Constructor
  ChatModel() {
    // Create a default conversation if none exists
    if (_conversations.isEmpty) {
      _createNewConversation();
    }

    // Load credits initially
    loadCredits();

    // Load reasoning settings
    loadReasoningSettings();

    // Load advanced view preference
    loadAdvancedViewPreference();
  }

  // Load credits from the API
  Future<void> loadCredits() async {
    if (_isLoadingCredits) return;

    _isLoadingCredits = true;
    notifyListeners();

    try {
      final creditsData = await _openRouterService.getCredits();
      _credits = creditsData;
    } catch (e) {
      _credits = {'error': e.toString()};
    } finally {
      _isLoadingCredits = false;
      notifyListeners();
    }
  }

  // Create a new conversation
  Future<Conversation> _createNewConversationAsync() async {
    final id = 'conv_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000)}';

    // Load settings from SharedPreferences synchronously
    final prefs = await SharedPreferences.getInstance();

    // Load all global settings
    final temperature = prefs.getDouble('temperature') ?? 0.7;
    final maxTokens = prefs.getInt('max_tokens') ?? 1000;
    final webSearchEnabled = prefs.getBool('webSearchEnabled') ?? false;
    final systemMessage = prefs.getString('system_message');

    // Load character settings
    final character = prefs.getString('character');
    final characterInfo = prefs.getString('character_info');
    final characterBreakdown = prefs.getBool('character_breakdown') ?? false;
    final customInstructions = prefs.getString('custom_instructions');

    // Create conversation with all global settings
    final conversation = Conversation.create(
      id: id,
      title: 'New Conversation',
      modelId: _selectedModel,
      reasoningEnabled: _reasoningEnabled,
      reasoningEffort: _reasoningEffort,
      temperature: temperature,
      maxTokens: maxTokens,
      webSearchEnabled: webSearchEnabled,
      systemMessage: systemMessage,
      character: character,
      characterInfo: characterInfo,
      characterBreakdown: characterBreakdown,
      customInstructions: customInstructions,
    );

    // Add to conversations list
    _conversations.add(conversation);
    _activeConversationId = id;

    notifyListeners();
    await _saveConversations(); // Await save
    return conversation;
  }

  // Create a new conversation
  Future<Conversation> _createNewConversation() async {
    // Add async and Future return type
    final id = 'conv_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000)}';

    // Create conversation with current global settings
    final conversation = Conversation.create(
      id: id,
      title: 'New Conversation',
      modelId: _selectedModel,
      reasoningEnabled: _reasoningEnabled,
      reasoningEffort: _reasoningEffort,
      temperature: 0.7, // Default temperature
      maxTokens: 1000, // Default max tokens
      webSearchEnabled: false, // Default web search setting
      systemMessage: null,
      character: null,
      characterInfo: null,
      characterBreakdown: false,
      customInstructions: null,
    );

    // Add to conversations list
    _conversations.add(conversation);
    _activeConversationId = id;

    // Load settings asynchronously and update the conversation
    _loadAndApplyGlobalSettings(conversation);

    notifyListeners();
    await _saveConversations(); // Await save
    return conversation;
  }

  // Load and apply global settings to a conversation
  Future<void> _loadAndApplyGlobalSettings(Conversation conversation) async {
    final prefs = await SharedPreferences.getInstance();

    // Check if this is a first run scenario
    final isFirstRun = !prefs.containsKey('last_settings_update');

    // Load all global settings
    final temperature = prefs.getDouble('temperature') ?? 0.7;
    final maxTokens = prefs.getInt('max_tokens') ?? 1000;
    final webSearchEnabled = prefs.getBool('webSearchEnabled') ?? false;
    final systemMessage = prefs.getString('system_message');
    final reasoningEnabled = prefs.getBool('reasoningEnabled') ?? false;
    final reasoningEffort = prefs.getString('reasoningEffort') ?? 'medium';

    // Load character settings
    final character = prefs.getString('character');
    final characterInfo = prefs.getString('character_info');
    final characterBreakdown = prefs.getBool('character_breakdown') ?? false;
    final customInstructions = prefs.getString('custom_instructions');

    // Debug log the settings being applied
    debugPrint('Applying global settings to conversation ${conversation.id}:');
    debugPrint('Is first run: $isFirstRun');
    debugPrint('Temperature: $temperature');
    debugPrint('Max Tokens: $maxTokens');
    debugPrint('Web Search Enabled: $webSearchEnabled');
    debugPrint('System Message: $systemMessage');
    debugPrint('Reasoning Enabled: $reasoningEnabled');
    debugPrint('Reasoning Effort: $reasoningEffort');
    debugPrint('Character: $character');
    debugPrint('Character Info: $characterInfo');
    debugPrint('Character Breakdown: $characterBreakdown');
    debugPrint('Custom Instructions: $customInstructions');

    // Apply all settings
    conversation.temperature = temperature;
    conversation.maxTokens = maxTokens;
    conversation.webSearchEnabled = webSearchEnabled;
    conversation.systemMessage = systemMessage;
    conversation.reasoningEnabled = reasoningEnabled;
    conversation.reasoningEffort = reasoningEffort;
    conversation.character = character;
    conversation.characterInfo = characterInfo;
    conversation.characterBreakdown = characterBreakdown;
    conversation.customInstructions = customInstructions;

    // Update the conversation's timestamp
    conversation.updatedAt = DateTime.now();

    // Save the updated conversation
    notifyListeners();

    // For first run, we'll save all conversations at once after applying settings to all of them
    // to avoid excessive writes
    if (!isFirstRun) {
      await _saveConversations();
    }
  }

  // Create a new conversation and make it active
  Future<void> createNewConversationAsync() async {
    await _createNewConversationAsync();
  }

  // Create a new conversation and make it active (synchronous version)
  void createNewConversation() {
    _createNewConversation();
  }

  // Set active conversation
  void setActiveConversation(String conversationId) {
    if (_conversations.any((c) => c.id == conversationId)) {
      _activeConversationId = conversationId;
      notifyListeners();
      _saveActiveConversationId();
    }
  }

  // Delete a conversation
  Future<void> deleteConversation(String conversationId) async {
    // Add async and Future return type
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index >= 0) {
      _conversations.removeAt(index);

      // If we deleted the active conversation, set a new active one
      if (_activeConversationId == conversationId) {
        _activeConversationId = _conversations.isNotEmpty ? _conversations.first.id : null;
      }

      notifyListeners();
      await _saveConversations(); // Await save
      await _saveActiveConversationId(); // Await save
    }
  }

  // Rename a conversation
  Future<void> renameConversation(String conversationId, String newTitle) async {
    // Add async and Future return type
    final conversation = _conversations.firstWhere((c) => c.id == conversationId, orElse: () => throw Exception('Conversation not found'));
    conversation.updateTitle(newTitle);
    notifyListeners();
    await _saveConversations(); // Await save
  }

  // Add a new message from the user
  Future<void> addUserMessage(String content) async {
    // Add async and Future return type
    if (activeConversation == null) {
      await _createNewConversation(); // Await the async creation
    }

    final message = Message(content: content, role: MessageRole.user);
    activeConversation!.addMessage(message);
    notifyListeners();
    await _saveConversations(); // Await save
  }

  // Add a response from the assistant
  Future<void> addAssistantMessage(dynamic response) async {
    // Add async and Future return type
    if (activeConversation == null) return;

    String content;
    String? reasoning;
    Map<String, dynamic>? usageData;

    if (response is String) {
      content = response;
    } else if (response is Map<String, dynamic>) {
      content = response['content'] as String;
      reasoning = response['reasoning'] as String?;
      usageData = response['usage'] != null ? Map<String, dynamic>.from(response['usage']) : null;
    } else {
      content = 'Error: Invalid response format';
    }

    final message = Message(content: content, role: MessageRole.assistant, reasoning: reasoning, usageData: usageData);
    activeConversation!.addMessage(message);
    notifyListeners();
    await _saveConversations(); // Await save
  }

  // Set system message (typically at the beginning of the conversation)
  Future<void> setSystemMessage(String content) async {
    // Add async and Future return type
    if (activeConversation == null) return;

    // Remove any existing system messages
    final messages = activeConversation!.messages;
    messages.removeWhere((msg) => msg.role == MessageRole.system);

    // Add the new system message at the beginning
    messages.insert(0, Message(content: content, role: MessageRole.system));

    // Update the system message in the conversation settings
    activeConversation!.systemMessage = content;

    notifyListeners();
    await _saveConversations(); // Await save
  }

  // Get a conversation by ID
  Conversation? getConversationById(String id) {
    try {
      return _conversations.firstWhere((c) => c.id == id);
    } catch (e) {
      return null;
    }
  }

  // Update character-related settings for a conversation
  Future<void> updateConversationCharacterSettings(
    // Already async
    String conversationId,
    String? character,
    String? characterInfo,
    bool characterBreakdown,
    String? customInstructions,
  ) async {
    // Add async keyword
    final conversation = getConversationById(conversationId);
    if (conversation == null) return; // Explicit return for void Future

    conversation.character = character;
    conversation.characterInfo = characterInfo;
    conversation.characterBreakdown = characterBreakdown;
    conversation.customInstructions = customInstructions;
    conversation.updatedAt = DateTime.now();

    notifyListeners();
    await _saveConversations(); // Await save
  }

  // Update general conversation settings by ID
  Future<void> updateConversationSettingsById({
    // Already async
    required String conversationId,
    double? temperature,
    int? maxTokens,
    bool? reasoningEnabled,
    String? reasoningEffort,
    bool? webSearchEnabled,
    String? systemMessage,
  }) async {
    // Add async keyword
    final conversation = getConversationById(conversationId);
    if (conversation == null) return; // Explicit return for void Future

    if (temperature != null) conversation.temperature = temperature;
    if (maxTokens != null) conversation.maxTokens = maxTokens;
    if (reasoningEnabled != null) conversation.reasoningEnabled = reasoningEnabled;
    if (reasoningEffort != null) conversation.reasoningEffort = reasoningEffort;
    if (webSearchEnabled != null) conversation.webSearchEnabled = webSearchEnabled;
    if (systemMessage != null) conversation.systemMessage = systemMessage;
    conversation.updatedAt = DateTime.now();

    notifyListeners();
    await _saveConversations(); // Await save
  }

  // Edit a message
  Future<void> editMessage(int index, String newContent) async {
    // Add async and Future return type
    if (activeConversation == null) return;

    activeConversation!.editMessage(index, newContent);
    notifyListeners();
    await _saveConversations(); // Await save
  }

  // Delete a message
  Future<void> deleteMessage(int index) async {
    // Add async and Future return type
    if (activeConversation == null) return;

    activeConversation!.deleteMessage(index);
    notifyListeners();
    await _saveConversations(); // Await save
  }

  // Clear all messages in the active conversation
  Future<void> clearMessages() async {
    // Add async and Future return type
    if (activeConversation == null) return;

    activeConversation!.messages.clear();
    notifyListeners();
    await _saveConversations(); // Await save
  }

  // Set loading state
  void setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  // Set selected model
  Future<void> setSelectedModel(String model) async {
    // Add async and Future return type
    _selectedModel = model;

    // Update the model for the active conversation
    if (activeConversation != null) {
      activeConversation!.modelId = model;
    }

    notifyListeners();
    await _saveSelectedModel(); // Await save
    await _saveConversations(); // Await save
  }

  // Set error message
  void setError(String error) {
    _error = error;
    notifyListeners();
  }

  // Toggle streaming
  void setStreamingEnabled(bool enabled) {
    _streamingEnabled = enabled;
    notifyListeners();
    _saveStreamingPreference();
  }

  // Toggle advanced view
  void setAdvancedViewEnabled(bool enabled) {
    _advancedViewEnabled = enabled;
    notifyListeners();
    _saveAdvancedViewPreference();
  }

  // Start a new streaming response
  void startStreamingResponse() {
    if (activeConversation == null) return;

    _currentStreamingContent = '';
    _isStreaming = true;

    // Add an empty assistant message that will be updated as streaming progresses
    final message = Message(content: '', role: MessageRole.assistant);
    activeConversation!.addMessage(message);
    notifyListeners();
  }

  // Cancel the current streaming response
  Future<void> cancelStreamingResponse() async {
    // Add async and Future return type
    if (!_isStreaming) return;

    // Cancel the API stream
    _openRouterService.cancelStream();

    // Update UI state
    _isStreaming = false;
    notifyListeners();

    // If we have an empty message (streaming just started), remove it
    if (activeConversation != null &&
        activeConversation!.messages.isNotEmpty &&
        activeConversation!.messages.last.role == MessageRole.assistant &&
        activeConversation!.messages.last.content.isEmpty) {
      activeConversation!.messages.removeLast();
      notifyListeners();
    }
    // If we have a partial message, keep it but mark it as cancelled
    else if (activeConversation != null &&
        activeConversation!.messages.isNotEmpty &&
        activeConversation!.messages.last.role == MessageRole.assistant &&
        _currentStreamingContent.isNotEmpty) {
      // Append a note that the response was cancelled
      final lastIndex = activeConversation!.messages.length - 1;
      final currentContent = activeConversation!.messages[lastIndex].content;
      activeConversation!.messages[lastIndex] = Message(
        content: '$currentContent\n\n_[Response cancelled by user]_',
        role: MessageRole.assistant,
        timestamp: activeConversation!.messages[lastIndex].timestamp,
        reasoning: activeConversation!.messages[lastIndex].reasoning,
        usageData: activeConversation!.messages[lastIndex].usageData,
      );
      notifyListeners();
      await _saveConversations(); // Await save
    }
  }

  // Update the streaming response with new content
  void updateStreamingResponse(dynamic chunk) {
    if (activeConversation == null || activeConversation!.messages.isEmpty) return;

    // Check if this is a usage data message
    if (chunk is Map<String, dynamic> && chunk.containsKey('usage')) {
      // Update the last message with usage data
      final messages = activeConversation!.messages;
      if (messages.isNotEmpty && messages.last.role == MessageRole.assistant) {
        final lastIndex = messages.length - 1;
        messages[lastIndex] = Message(
          content: messages[lastIndex].content,
          role: MessageRole.assistant,
          timestamp: messages[lastIndex].timestamp,
          reasoning: messages[lastIndex].reasoning,
          usageData: chunk['usage'] as Map<String, dynamic>,
        );
        notifyListeners();
      }
      return;
    }

    // Handle regular content chunks
    String newContent;
    if (chunk is String) {
      newContent = chunk;
    } else if (chunk is Map<String, dynamic> && chunk.containsKey('content')) {
      newContent = chunk['content'] as String;
    } else {
      return; // Invalid chunk format
    }

    try {
      // Sanitize content to handle potential markdown issues
      // This helps prevent issues with unterminated strings in URLs or code blocks
      newContent = _sanitizeMarkdownContent(newContent);

      _currentStreamingContent += newContent;

      // Update the last message (which should be the assistant's response)
      final messages = activeConversation!.messages;
      if (messages.isNotEmpty && messages.last.role == MessageRole.assistant) {
        final lastIndex = messages.length - 1;
        messages[lastIndex] = Message(
          content: _currentStreamingContent,
          role: MessageRole.assistant,
          timestamp: messages[lastIndex].timestamp,
          reasoning: messages[lastIndex].reasoning,
          usageData: messages[lastIndex].usageData,
        );
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error updating streaming response: $e');
    }
  }

  // Helper method to sanitize markdown content
  String _sanitizeMarkdownContent(String content) {
    try {
      // Check for unterminated markdown links
      if (content.contains('[') && !content.contains(']')) {
        // Add a temporary closing bracket to prevent parsing errors
        content = '$content]';
      }

      // Check for unterminated URLs in markdown links
      final linkPattern = RegExp(r'\[([^\]]*)\]\(([^\)]*)$');
      if (linkPattern.hasMatch(content)) {
        // Add a temporary closing parenthesis
        content = '$content)';
      }

      // Check for unterminated code blocks
      if (content.contains('```') && content.split('```').length % 2 == 0) {
        // Add a closing code block
        content = '$content\n```';
      }

      // Check for unterminated quotes
      if (content.contains('"') && content.split('"').length % 2 == 0) {
        // Add a closing quote
        content = '$content"';
      }

      // Handle URLs that might be cut off
      if (content.contains('http') && (content.endsWith('/') || content.endsWith('.'))) {
        // Add a temporary character to prevent parsing errors with cut-off URLs
        content = '${content}x';
      }

      // Handle specific case of Python version URLs that might be cut off
      if (content.contains('python.org/downloads/release/') && !content.contains('python.org/downloads/release/python-')) {
        // Add a temporary placeholder to complete the URL
        content = '$content-000/';
      }

      return content;
    } catch (e) {
      debugPrint('Error in sanitizeMarkdownContent: $e');
      // If any error occurs during sanitization, return the original content
      return content;
    }
  }

  // Finalize the streaming response
  Future<void> finalizeStreamingResponse() async {
    // Add async and Future return type
    // Clean up any temporary markdown fixes in the final content
    if (activeConversation != null && activeConversation!.messages.isNotEmpty && activeConversation!.messages.last.role == MessageRole.assistant) {
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
            reasoning: activeConversation!.messages[lastIndex].reasoning,
            usageData: activeConversation!.messages[lastIndex].usageData,
          );
        }
      } catch (e) {
        debugPrint('Error cleaning up markdown content: $e');
      }
    }

    // Save conversations to persistent storage
    await _saveConversations(); // Await save
    _currentStreamingContent = '';
    _isStreaming = false;
    notifyListeners();
  }

  // Helper method to clean up markdown content after streaming is complete
  String _cleanupMarkdownContent(String content) {
    try {
      String result = content;

      // Fix any malformed links by removing incomplete markdown links
      // This regex finds incomplete markdown links like [text]( without closing )
      final incompleteLinks = RegExp(r'\[([^\]]*)\]\(([^\)]*)$');
      if (incompleteLinks.hasMatch(result)) {
        // Remove the incomplete link or try to fix it
        result = result.replaceAllMapped(incompleteLinks, (match) {
          final linkText = match.group(1);
          final url = match.group(2);
          if (url != null && url.isNotEmpty) {
            // If we have some URL text, keep it as plain text
            return '[$linkText]($url)';
          } else {
            // Otherwise just keep the link text
            return linkText ?? '';
          }
        });
      }

      // Fix any unclosed code blocks
      final codeBlocks = result.split('```');
      if (codeBlocks.length % 2 == 0) {
        // If we have an odd number of ``` markers, add one more to close the last block
        result = '$result\n```';
      }

      // Fix any unterminated quotes
      final quoteCount = result.split('"').length - 1;
      if (quoteCount % 2 != 0) {
        // If we have an odd number of quotes, remove the last one or add one more
        if (result.endsWith('"')) {
          result = result.substring(0, result.length - 1);
        } else {
          result = '$result"';
        }
      }

      // Fix URLs that were cut off and had a placeholder added
      if (result.contains('http') && result.endsWith('x')) {
        // Remove the temporary 'x' character that was added to prevent parsing errors
        result = result.substring(0, result.length - 1);
      }

      // Fix Python version URLs that had a placeholder added
      result = result.replaceAll('python.org/downloads/release/-000/', 'python.org/downloads/release/');

      // Fix any malformed markdown links with proper URLs
      // This regex finds markdown links with URLs
      final markdownLinks = RegExp(r'\[([^\]]*)\]\(([^\)]*)\)');
      result = result.replaceAllMapped(markdownLinks, (match) {
        final linkText = match.group(1);
        final url = match.group(2);
        if (url != null && url.contains('http')) {
          // Check if the URL is malformed or cut off
          if (url.endsWith('x') || url.endsWith('-000/')) {
            // Clean up the URL
            final cleanUrl = url.endsWith('x') ? url.substring(0, url.length - 1) : url.replaceAll('-000/', '');
            return '[$linkText]($cleanUrl)';
          }
        }
        return match.group(0) ?? '';
      });

      return result;
    } catch (e) {
      debugPrint('Error in cleanupMarkdownContent: $e');
      // If any error occurs during cleanup, return the original content
      return content;
    }
  }

  // Regenerate an assistant response from a specific point
  Future<void> regenerateResponse(int messageIndex) async {
    if (activeConversation == null || messageIndex < 0 || messageIndex >= activeConversation!.messages.length) return;

    // Verify this is an assistant message
    final message = activeConversation!.messages[messageIndex];
    if (message.role != MessageRole.assistant) return;

    // Remove this message and all messages after it
    final messagesToKeep = activeConversation!.messages.sublist(0, messageIndex);

    // Find the last user message before this assistant message
    int lastUserMessageIndex = messageIndex - 1;
    while (lastUserMessageIndex >= 0 && activeConversation!.messages[lastUserMessageIndex].role != MessageRole.user) {
      lastUserMessageIndex--;
    }

    // If we couldn't find a user message, we can't regenerate
    if (lastUserMessageIndex < 0) return;

    // Update the conversation with just the messages to keep
    activeConversation!.messages.clear();
    activeConversation!.messages.addAll(messagesToKeep);
    notifyListeners();

    // Now trigger a new response as if the user had just sent their last message
    setLoading(true);
    setError('');

    try {
      if (streamingEnabled) {
        // Start streaming response
        startStreamingResponse();

        // Listen to the stream and update the UI
        await for (final chunk in sendStreamingChatRequest(messages: activeConversation!.messages, model: selectedModel)) {
          updateStreamingResponse(chunk);
        }

        // Finalize the streaming response
        finalizeStreamingResponse();
      } else {
        // Use non-streaming API
        final response = await sendChatRequest(messages: activeConversation!.messages, model: selectedModel);

        addAssistantMessage(response);
      }
    } catch (e) {
      setError(e.toString());
    } finally {
      setLoading(false);
    }
  }

  // Load conversations from SharedPreferences
  Future<void> loadConversations() async {
    debugPrint('Loading conversations from SharedPreferences');
    try {
      final prefs = await SharedPreferences.getInstance();
      final conversationsJson = prefs.getString('conversations');

      if (conversationsJson != null) {
        debugPrint('Found saved conversations JSON, size: ${conversationsJson.length} characters');
        try {
          final List<dynamic> decoded = jsonDecode(conversationsJson);
          debugPrint('Successfully decoded JSON, found ${decoded.length} conversations');

          _conversations.clear();

          // Convert each JSON object to a Conversation object
          final List<Conversation> loadedConversations = [];
          for (var item in decoded) {
            try {
              final conversation = Conversation.fromJson(item);
              loadedConversations.add(conversation);
            } catch (convError) {
              debugPrint('Error parsing conversation: $convError');
              debugPrint('Problematic conversation data: $item');
            }
          }

          _conversations.addAll(loadedConversations);
          debugPrint('Successfully loaded ${_conversations.length} conversations');

          // Load active conversation ID
          final activeId = prefs.getString('activeConversationId');
          if (activeId != null && _conversations.any((c) => c.id == activeId)) {
            _activeConversationId = activeId;
            debugPrint('Set active conversation ID to: $activeId');
          } else if (_conversations.isNotEmpty) {
            _activeConversationId = _conversations.first.id;
            debugPrint('Set active conversation ID to first conversation: ${_conversations.first.id}');
          }

          notifyListeners();
        } catch (jsonError) {
          debugPrint('Error decoding conversations JSON: $jsonError');
          debugPrint('Invalid JSON: ${conversationsJson.substring(0, min(100, conversationsJson.length))}...');
          // Create a default conversation if there was a JSON error
          if (_conversations.isEmpty) {
            debugPrint('Creating new conversation due to JSON error');
            _createNewConversation();
          }
        }
      } else {
        debugPrint('No saved conversations found in SharedPreferences');
        if (_conversations.isEmpty) {
          // Create a default conversation if none exists
          debugPrint('Creating new conversation as none exist');
          _createNewConversation();
        }
      }
    } catch (e) {
      debugPrint('Error loading conversations: $e');
      debugPrint(StackTrace.current.toString());
      // Create a default conversation if there was an error
      if (_conversations.isEmpty) {
        debugPrint('Creating new conversation due to error');
        _createNewConversation();
      }
    }
  }

  // Save conversations to SharedPreferences
  Future<void> _saveConversations() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Debug log the number of conversations being saved
      debugPrint('Saving ${_conversations.length} conversations to SharedPreferences');

      // Convert conversations to JSON
      final List<Map<String, dynamic>> conversationMaps = _conversations.map((c) => c.toJson()).toList();
      final conversationsJson = jsonEncode(conversationMaps);

      // Debug log the size of the JSON
      debugPrint('Conversations JSON size: ${conversationsJson.length} characters');

      // Save to SharedPreferences
      final result = await prefs.setString('conversations', conversationsJson);

      // Verify the save was successful
      if (result) {
        debugPrint('Conversations saved successfully');
      } else {
        debugPrint('Failed to save conversations to SharedPreferences');
      }

      // Verify the data was saved correctly by reading it back
      final savedJson = prefs.getString('conversations');
      if (savedJson != null) {
        final savedCount = jsonDecode(savedJson).length;
        debugPrint('Verified saved conversations: $savedCount');
      } else {
        debugPrint('WARNING: Could not verify saved conversations - data not found after save');
      }
    } catch (e) {
      debugPrint('Error saving conversations: $e');
      // Log the stack trace for debugging
      debugPrint(StackTrace.current.toString());
    }
  }

  // Public method to force saving conversations (used by AutoSyncService)
  Future<void> forceSaveConversations() async {
    debugPrint('Force saving conversations from external call');
    await _saveConversations();
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

  // Load selected model from SharedPreferences
  Future<void> loadSelectedModel() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final model = prefs.getString('selectedModel');

      if (model != null) {
        _selectedModel = model;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading selected model: $e');
    }
  }

  // Save selected model to SharedPreferences
  Future<void> _saveSelectedModel() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('selectedModel', _selectedModel);
    } catch (e) {
      debugPrint('Error saving selected model: $e');
    }
  }

  // Save streaming preference to SharedPreferences
  Future<void> _saveStreamingPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('streamingEnabled', _streamingEnabled);
    } catch (e) {
      debugPrint('Error saving streaming preference: $e');
    }
  }

  // Load streaming preference from SharedPreferences
  Future<void> loadStreamingPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('streamingEnabled');

      if (enabled != null) {
        _streamingEnabled = enabled;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading streaming preference: $e');
    }
  }

  // Save advanced view preference to SharedPreferences
  Future<void> _saveAdvancedViewPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('advancedViewEnabled', _advancedViewEnabled);
    } catch (e) {
      debugPrint('Error saving advanced view preference: $e');
    }
  }

  // Load advanced view preference from SharedPreferences
  Future<void> loadAdvancedViewPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('advancedViewEnabled');

      if (enabled != null) {
        _advancedViewEnabled = enabled;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading advanced view preference: $e');
    }
  }

  // Set reasoning enabled globally
  void setReasoningEnabled(bool enabled) {
    _reasoningEnabled = enabled;
    notifyListeners();
    _saveReasoningSettings();
  }

  // Set reasoning effort level globally
  void setReasoningEffort(String effort) {
    if (['low', 'medium', 'high'].contains(effort)) {
      _reasoningEffort = effort;
      notifyListeners();
      _saveReasoningSettings();
    }
  }

  // Set global character settings
  Future<void> setGlobalCharacterSettings(String? character, String? characterInfo, bool characterBreakdown, String? customInstructions) async {
    // Save to SharedPreferences
    final prefs = await SharedPreferences.getInstance();

    // Debug log the character settings being set
    debugPrint('Setting global character settings:');
    debugPrint('Character: $character');
    debugPrint('Character Info: $characterInfo');
    debugPrint('Character Breakdown: $characterBreakdown');
    debugPrint('Custom Instructions: $customInstructions');

    if (character != null) {
      await prefs.setString('character', character);
    } else {
      await prefs.remove('character');
    }

    if (characterInfo != null) {
      await prefs.setString('character_info', characterInfo);
      debugPrint('Saved character_info to SharedPreferences: $characterInfo');
    } else {
      await prefs.remove('character_info');
      debugPrint('Removed character_info from SharedPreferences');
    }

    await prefs.setBool('character_breakdown', characterBreakdown);

    if (customInstructions != null) {
      await prefs.setString('custom_instructions', customInstructions);
    } else {
      await prefs.remove('custom_instructions');
    }

    // Update the last settings update time
    await prefs.setInt('last_settings_update', DateTime.now().millisecondsSinceEpoch);
    debugPrint('Updated last_settings_update timestamp');

    // Verify the settings were saved correctly
    final savedCharacterInfo = prefs.getString('character_info');
    debugPrint('Verified character_info in SharedPreferences: $savedCharacterInfo');

    // Update the active conversation if it exists
    if (activeConversation != null) {
      activeConversation!.character = character;
      activeConversation!.characterInfo = characterInfo;
      activeConversation!.characterBreakdown = characterBreakdown;
      activeConversation!.customInstructions = customInstructions;
      activeConversation!.updatedAt = DateTime.now();

      notifyListeners();
      await _saveConversations(); // Await save
    } else {
      notifyListeners();
    }
  }

  // Update conversation-specific settings
  Future<void> updateConversationSettings({
    // Already async
    String? conversationId,
    bool? reasoningEnabled,
    String? reasoningEffort,
    double? temperature,
    int? maxTokens,
    bool? webSearchEnabled,
    String? systemMessage,
  }) async {
    // Add async keyword
    // Get the conversation to update
    final conversation =
        conversationId != null
            ? _conversations.firstWhere((c) => c.id == conversationId, orElse: () => throw Exception('Conversation not found'))
            : activeConversation;

    if (conversation == null) return; // Explicit return for void Future

    // Update the settings
    conversation.updateSettings(
      reasoningEnabled: reasoningEnabled,
      reasoningEffort: reasoningEffort,
      temperature: temperature,
      maxTokens: maxTokens,
      webSearchEnabled: webSearchEnabled,
      systemMessage: systemMessage,
    );

    // If system message is provided, update it in the conversation
    if (systemMessage != null) {
      // Remove any existing system messages
      conversation.messages.removeWhere((msg) => msg.role == MessageRole.system);

      // Add the new system message at the beginning if it's not empty
      if (systemMessage.isNotEmpty) {
        conversation.messages.insert(0, Message(content: systemMessage, role: MessageRole.system));
      }
    }

    notifyListeners();
    await _saveConversations(); // Await save
  }

  // Save reasoning settings to SharedPreferences
  Future<void> _saveReasoningSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('reasoningEnabled', _reasoningEnabled);
      await prefs.setString('reasoningEffort', _reasoningEffort);
    } catch (e) {
      debugPrint('Error saving reasoning settings: $e');
    }
  }

  // Load reasoning settings from SharedPreferences
  Future<void> loadReasoningSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('reasoningEnabled');
      final effort = prefs.getString('reasoningEffort');

      if (enabled != null) {
        _reasoningEnabled = enabled;
      }

      if (effort != null && ['low', 'medium', 'high'].contains(effort)) {
        _reasoningEffort = effort;
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Error loading reasoning settings: $e');
    }
  }

  // Import a conversation from Discord or other source
  Future<void> importConversation(Conversation conversation) async {
    // Add async and Future return type
    // Check if a conversation with this ID already exists
    final existingIndex = _conversations.indexWhere((c) => c.id == conversation.id);

    if (existingIndex >= 0) {
      // If the conversation exists, update it if the imported one is newer
      if (conversation.updatedAt.isAfter(_conversations[existingIndex].updatedAt)) {
        _conversations[existingIndex] = conversation;
      }
    } else {
      // If the conversation doesn't exist, add it
      _conversations.add(conversation);
    }

    notifyListeners();
    await _saveConversations(); // Await save (already added, just confirming)
  }

  // Import multiple conversations
  Future<void> importConversations(List<Conversation> conversations) async {
    // Add async and Future return type
    for (final conversation in conversations) {
      await importConversation(conversation); // Await the async import
    }
  }

  // Reload global settings and apply to all conversations
  Future<void> reloadAndApplyGlobalSettings() async {
    debugPrint('Reloading and applying global settings to all conversations');

    // Check if this is a first run scenario
    final prefs = await SharedPreferences.getInstance();
    final isFirstRun = !prefs.containsKey('last_settings_update');
    debugPrint('ChatModel.reloadAndApplyGlobalSettings: Is first run: $isFirstRun');

    // Reload all settings
    await loadSelectedModel();
    await loadStreamingPreference();
    await loadAdvancedViewPreference();
    await loadReasoningSettings();

    // Apply settings to all conversations
    for (final conversation in _conversations) {
      await _loadAndApplyGlobalSettings(conversation);
    }

    // For first run, make sure to save the conversations after applying settings
    if (isFirstRun) {
      debugPrint('First run detected - forcing save of conversations after applying settings');
      await _saveConversations();
    }

    debugPrint('Global settings applied to all conversations');
    notifyListeners();
  }

  // Import conversations from the Discord bot
  Future<void> importConversationsFromDiscord(SyncService syncService) async {
    if (!syncService.isLoggedIn) return;

    try {
      // First sync settings to ensure we have the latest settings
      debugPrint('Syncing settings before importing conversations...');
      await syncService.syncUserSettings();

      // Reload settings and apply to all conversations
      await reloadAndApplyGlobalSettings();
      debugPrint('Settings reloaded and applied to all conversations');

      // Get conversations from the Discord bot
      final conversations = _conversations.where((c) => c.messages.isNotEmpty).toList();
      final success = await syncService.syncConversations(conversations);

      if (success) {
        // Save the conversations
        _saveConversations();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error importing conversations from Discord: $e');
    }
  }
}
