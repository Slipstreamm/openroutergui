import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import 'discord_oauth_service.dart';

class UserSettings {
  String modelId;
  double temperature;
  int maxTokens;
  bool reasoningEnabled;
  String reasoningEffort;
  bool webSearchEnabled;
  String? systemMessage;
  String? character;
  String? characterInfo;
  bool characterBreakdown;
  String? customInstructions;
  bool advancedViewEnabled;
  bool streamingEnabled;
  DateTime lastUpdated;
  String syncSource;

  UserSettings({
    this.modelId = 'openai/gpt-3.5-turbo',
    this.temperature = 0.7,
    this.maxTokens = 1000,
    this.reasoningEnabled = false,
    this.reasoningEffort = 'medium',
    this.webSearchEnabled = false,
    this.systemMessage,
    this.character,
    this.characterInfo,
    this.characterBreakdown = false,
    this.customInstructions,
    this.advancedViewEnabled = false,
    this.streamingEnabled = true,
    DateTime? lastUpdated,
    this.syncSource = 'flutter',
  }) : lastUpdated = lastUpdated ?? DateTime.now();

  // Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'model_id': modelId,
      'temperature': temperature,
      'max_tokens': maxTokens,
      'reasoning_enabled': reasoningEnabled,
      'reasoning_effort': reasoningEffort,
      'web_search_enabled': webSearchEnabled,
      // Include both system_message and system_prompt for compatibility
      if (systemMessage != null) 'system_message': systemMessage,
      if (systemMessage != null) 'system_prompt': systemMessage,
      if (character != null) 'character': character,
      if (characterInfo != null) 'character_info': characterInfo,
      'character_breakdown': characterBreakdown,
      if (customInstructions != null) 'custom_instructions': customInstructions,
      'advanced_view_enabled': advancedViewEnabled,
      'streaming_enabled': streamingEnabled,
      'last_updated': lastUpdated.toIso8601String(),
      'sync_source': syncSource,
    };
  }

  // Create from JSON
  factory UserSettings.fromJson(Map<String, dynamic> json) {
    // Handle system_message vs system_prompt field name mismatch
    String? systemMessage = json['system_message'] as String?;
    if (systemMessage == null && json.containsKey('system_prompt')) {
      systemMessage = json['system_prompt'] as String?;
    }

    return UserSettings(
      modelId: json['model_id'] as String? ?? 'openai/gpt-3.5-turbo',
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.7,
      maxTokens: json['max_tokens'] as int? ?? 1000,
      reasoningEnabled: json['reasoning_enabled'] as bool? ?? false,
      reasoningEffort: json['reasoning_effort'] as String? ?? 'medium',
      webSearchEnabled: json['web_search_enabled'] as bool? ?? false,
      systemMessage: systemMessage,
      character: json['character'] as String?,
      characterInfo: json['character_info'] as String?,
      characterBreakdown: json['character_breakdown'] as bool? ?? false,
      customInstructions: json['custom_instructions'] as String?,
      advancedViewEnabled: json['advanced_view_enabled'] as bool? ?? false,
      streamingEnabled: json['streaming_enabled'] as bool? ?? true,
      lastUpdated: json['last_updated'] != null ? DateTime.parse(json['last_updated']) : DateTime.now(),
      syncSource: json['sync_source'] as String? ?? 'flutter',
    );
  }
}

class SyncService extends ChangeNotifier {
  // The URL of your Discord bot's API
  // This should be the server where your Discord bot is running
  static const String botApiUrl = 'https://slipstreamm.dev/api';

  // For backward compatibility, we also define the old API URL
  static const String oldBotApiUrl = 'https://slipstreamm.dev/discordapi';

  // Discord OAuth service for authentication
  final DiscordOAuthService _authService;

  // Sync state
  bool _isSyncing = false;
  DateTime? _lastSyncTime;
  String? _syncError;
  Timer? _autoSyncTimer;
  bool _settingsUpdatedFromDiscord = false; // Flag to indicate settings were updated from Discord

  // Getters
  bool get isSyncing => _isSyncing;
  DateTime? get lastSyncTime => _lastSyncTime;
  String? get syncError => _syncError;
  bool get isLoggedIn => _authService.isLoggedIn;
  String? get userId => _authService.userId;
  String? get username => _authService.username;
  bool get settingsUpdatedFromDiscord => _settingsUpdatedFromDiscord;

  // Constructor
  SyncService(this._authService) {
    // Load last sync time
    _loadLastSyncTime();
  }

  // Initialize the service
  Future<void> initialize() async {
    await _authService.initialize();
    await _loadLastSyncTime();

    // Start auto-sync timer if logged in
    if (_authService.isLoggedIn) {
      // First, explicitly fetch settings from the Discord bot
      debugPrint('Fetching settings from Discord bot during initialization...');

      // Check if this is a first run scenario
      final prefs = await SharedPreferences.getInstance();
      final isFirstRun = !prefs.containsKey('last_settings_update');
      debugPrint('Initialize: Is first run or after shared prefs deletion: $isFirstRun');

      // Always fetch settings from Discord bot, but pass the isFirstRun flag
      final success = await _fetchSettingsFromDiscordBot(isFirstRun: isFirstRun);
      debugPrint('Settings fetch result: ${success ? 'Success' : 'Failed'}');

      _startAutoSync();
    }
  }

  // Explicitly fetch settings from the Discord bot
  Future<bool> _fetchSettingsFromDiscordBot({bool isFirstRun = false}) async {
    if (!_authService.isLoggedIn) {
      debugPrint('Cannot fetch settings: Not logged in to Discord');
      return false;
    }

    try {
      // Get the authorization header
      final authHeader = _authService.getAuthHeader();
      if (authHeader == null) {
        debugPrint('Cannot fetch settings: Authentication error');
        return false;
      }

      debugPrint('Sending GET request to $botApiUrl/settings');

      // Try the new API endpoint first
      var response = await http.get(Uri.parse('$botApiUrl/settings'), headers: {'Authorization': authHeader});

      // If the new endpoint fails with a 404, try the old endpoint for backward compatibility
      if (response.statusCode == 404) {
        debugPrint('New API endpoint not found, trying old endpoint at $oldBotApiUrl/settings');
        response = await http.get(Uri.parse('$oldBotApiUrl/settings'), headers: {'Authorization': authHeader});
      }

      if (response.statusCode != 200) {
        debugPrint('Failed to get settings: ${response.statusCode} - ${response.body}');
        return false;
      }

      // Parse the response
      final responseData = jsonDecode(response.body);

      // Check if we got user settings back
      if (responseData['settings'] != null) {
        debugPrint('Received settings from Discord bot, applying...');

        // Get the settings as a map first so we can modify it
        final Map<String, dynamic> settingsJson = responseData['settings'];

        // Log the raw JSON for debugging
        debugPrint('Raw settings JSON from Discord bot:');
        debugPrint(jsonEncode(settingsJson));

        // Force the sync_source to be 'discord' to ensure the settings are applied
        settingsJson['sync_source'] = 'discord';
        debugPrint('Forcing sync_source to "discord" to ensure settings are applied');

        // Check for system_message and character settings
        if (settingsJson['system_message'] == null) {
          debugPrint('WARNING: system_message is null in Discord bot settings');
          // Try to get system_prompt instead (the bot might use a different field name)
          if (settingsJson.containsKey('system_prompt')) {
            debugPrint('Found system_prompt instead, using that value');
            settingsJson['system_message'] = settingsJson['system_prompt'];
          }
        }

        // Debug log the raw settings JSON
        debugPrint('Raw settings JSON after field name adjustments:');
        debugPrint(jsonEncode(settingsJson));

        // Create the settings object
        final syncedSettings = UserSettings.fromJson(settingsJson);

        // Log the settings we received
        debugPrint('Settings received from Discord bot:');
        debugPrint('Model: ${syncedSettings.modelId}');
        debugPrint('Temperature: ${syncedSettings.temperature}');
        debugPrint('Max Tokens: ${syncedSettings.maxTokens}');
        debugPrint('System Message: ${syncedSettings.systemMessage}');
        debugPrint('Character: ${syncedSettings.character}');
        debugPrint('Character Info: ${syncedSettings.characterInfo}');
        debugPrint('Character Breakdown: ${syncedSettings.characterBreakdown}');
        debugPrint('Custom Instructions: ${syncedSettings.customInstructions}');

        // Apply settings from Discord bot with the provided isFirstRun flag
        // This ensures first-run settings are properly handled
        await _applyUserSettings(syncedSettings, isFirstRun: isFirstRun);
        debugPrint('Applied settings from Discord bot with isFirstRun=$isFirstRun');
        return true;
      } else {
        debugPrint('No settings received from Discord bot');
        return false;
      }
    } catch (e) {
      debugPrint('Error fetching settings from Discord bot: $e');
      return false;
    }
  }

  // Start auto-sync timer
  void _startAutoSync() {
    // Cancel existing timer if any
    _autoSyncTimer?.cancel();

    // Set up a timer to sync every 5 minutes
    _autoSyncTimer = Timer.periodic(const Duration(minutes: 5), (timer) async {
      if (_authService.isLoggedIn && !_isSyncing) {
        await syncUserSettings();
      }
    });
  }

  // Stop auto-sync timer

  // Sync conversations with the Discord bot
  Future<bool> syncConversations(List<Conversation> conversations) async {
    debugPrint('Starting conversation sync with Discord bot...');
    debugPrint('Number of conversations to sync: ${conversations.length}');

    if (!_authService.isLoggedIn) {
      _syncError = 'Not logged in to Discord';
      debugPrint('Sync failed: Not logged in to Discord');
      notifyListeners();
      return false;
    }

    if (_isSyncing) {
      debugPrint('Sync already in progress, skipping');
      return false;
    }

    _isSyncing = true;
    _syncError = null;
    notifyListeners();

    try {
      // Get the authorization header
      final authHeader = _authService.getAuthHeader();
      if (authHeader == null) {
        _syncError = 'Authentication error';
        debugPrint('Sync failed: Could not get authorization header');
        _isSyncing = false;
        notifyListeners();
        return false;
      }

      debugPrint('Authorization header obtained successfully');

      // Prepare conversations for sync
      debugPrint('Preparing conversations for sync...');
      final conversationsJson = conversations.map((c) => _prepareConversationForSync(c)).toList();
      debugPrint('Prepared ${conversationsJson.length} conversations for sync');

      // Prepare user settings for sync
      debugPrint('Preparing user settings for sync...');
      final userSettings = await _getUserSettingsForSync();
      debugPrint('User settings prepared for sync');

      // Prepare the request body
      final requestBody = {'conversations': conversationsJson, 'last_sync_time': _lastSyncTime?.toIso8601String(), 'user_settings': userSettings.toJson()};

      debugPrint('Sending sync request to $botApiUrl/sync');
      debugPrint('Request contains ${conversationsJson.length} conversations');

      // Try the new API endpoint first
      var response = await http.post(
        Uri.parse('$botApiUrl/sync'),
        headers: {'Content-Type': 'application/json', 'Authorization': authHeader},
        body: jsonEncode(requestBody),
      );

      debugPrint('Received response with status code: ${response.statusCode}');

      // If the new endpoint fails with a 404, try the old endpoint for backward compatibility
      if (response.statusCode == 404) {
        debugPrint('New API endpoint not found, trying old endpoint at $oldBotApiUrl/sync');
        response = await http.post(
          Uri.parse('$oldBotApiUrl/sync'),
          headers: {'Content-Type': 'application/json', 'Authorization': authHeader},
          body: jsonEncode(requestBody),
        );
        debugPrint('Received response from old endpoint with status code: ${response.statusCode}');
      }

      if (response.statusCode != 200) {
        _syncError = 'Sync failed: ${response.statusCode} - ${response.body}';
        debugPrint('Sync failed: ${response.statusCode} - ${response.body}');
        _isSyncing = false;
        notifyListeners();
        return false;
      }

      // Parse the response
      debugPrint('Parsing response...');
      final responseData = jsonDecode(response.body);
      debugPrint('Response parsed successfully');

      // Check if we got user settings back
      if (responseData['user_settings'] != null) {
        debugPrint('Received user settings from server, applying...');

        // Get the settings as a map first so we can modify it
        final Map<String, dynamic> settingsJson = responseData['user_settings'];

        // Force the sync_source to be 'discord' to ensure the settings are applied
        settingsJson['sync_source'] = 'discord';
        debugPrint('Forcing sync_source to "discord" to ensure settings are applied');

        final syncedSettings = UserSettings.fromJson(settingsJson);

        // Apply any settings from the server - force isFirstRun to true to ensure they're applied
        await _applyUserSettings(syncedSettings, isFirstRun: true);
        debugPrint('Applied synced user settings');
      } else {
        debugPrint('No user settings received from server');
      }

      // Update last sync time
      _lastSyncTime = DateTime.now();
      await _saveLastSyncTime();
      debugPrint('Updated last sync time to: ${_lastSyncTime?.toIso8601String()}');

      _isSyncing = false;
      notifyListeners();

      debugPrint('Conversation sync completed successfully');
      // Return the synced conversations
      return true;
    } catch (e) {
      _syncError = 'Sync error: $e';
      debugPrint('Sync error: $e');
      debugPrint(StackTrace.current.toString());
      _isSyncing = false;
      notifyListeners();
      return false;
    }
  }

  // Get conversations from the Discord bot
  Future<List<Conversation>?> getConversationsFromBot() async {
    if (!_authService.isLoggedIn) {
      _syncError = 'Not logged in to Discord';
      notifyListeners();
      return null;
    }

    if (_isSyncing) {
      debugPrint('Sync already in progress');
      return null;
    }

    _isSyncing = true;
    _syncError = null;
    notifyListeners();

    try {
      // Get the authorization header
      final authHeader = _authService.getAuthHeader();
      if (authHeader == null) {
        _syncError = 'Authentication error';
        _isSyncing = false;
        notifyListeners();
        return null;
      }

      // Try the new API endpoint first
      var response = await http.get(Uri.parse('$botApiUrl/conversations'), headers: {'Authorization': authHeader});

      // If the new endpoint fails with a 404, try the old endpoint for backward compatibility
      if (response.statusCode == 404) {
        debugPrint('New API endpoint not found, trying old endpoint at $oldBotApiUrl/conversations');
        response = await http.get(Uri.parse('$oldBotApiUrl/conversations'), headers: {'Authorization': authHeader});
      }

      if (response.statusCode != 200) {
        _syncError = 'Failed to get conversations: ${response.statusCode} - ${response.body}';
        _isSyncing = false;
        notifyListeners();
        return null;
      }

      // Parse the response
      final responseData = jsonDecode(response.body);
      final conversationsJson = responseData['conversations'] as List<dynamic>;

      // Convert to Conversation objects
      final conversations =
          conversationsJson
              .map((json) => _convertBotConversationToLocal(json))
              .whereType<Conversation>() // Filter out nulls
              .toList();

      _isSyncing = false;
      notifyListeners();

      return conversations;
    } catch (e) {
      _syncError = 'Error getting conversations: $e';
      _isSyncing = false;
      notifyListeners();
      return null;
    }
  }

  // Prepare a conversation for syncing
  Map<String, dynamic> _prepareConversationForSync(Conversation conversation) {
    return {
      'id': conversation.id,
      'title': conversation.title,
      'messages':
          conversation.messages
              .map(
                (m) => {
                  'content': m.content,
                  'role': m.role.toString().split('.').last,
                  'timestamp': m.timestamp.toIso8601String(),
                  if (m.reasoning != null) 'reasoning': m.reasoning,
                  if (m.usageData != null) 'usage_data': m.usageData,
                },
              )
              .toList(),
      'created_at': conversation.createdAt.toIso8601String(),
      'updated_at': conversation.updatedAt.toIso8601String(),
      'model_id': conversation.modelId,
      'sync_source': 'flutter',
      // Include conversation settings
      'reasoning_enabled': conversation.reasoningEnabled,
      'reasoning_effort': conversation.reasoningEffort,
      'temperature': conversation.temperature,
      'max_tokens': conversation.maxTokens,
      'web_search_enabled': conversation.webSearchEnabled,
      // Include both system_message and system_prompt for compatibility
      if (conversation.systemMessage != null) 'system_message': conversation.systemMessage,
      if (conversation.systemMessage != null) 'system_prompt': conversation.systemMessage,
      // Include character-related settings
      if (conversation.character != null) 'character': conversation.character,
      if (conversation.characterInfo != null) 'character_info': conversation.characterInfo,
      'character_breakdown': conversation.characterBreakdown,
      if (conversation.customInstructions != null) 'custom_instructions': conversation.customInstructions,
    };
  }

  // Convert a bot conversation to a local Conversation object
  Conversation? _convertBotConversationToLocal(Map<String, dynamic> json) {
    try {
      return Conversation(
        id: json['id'],
        title: json['title'],
        messages:
            (json['messages'] as List<dynamic>)
                .map(
                  (m) => Message(
                    content: m['content'],
                    role: _roleFromString(m['role']),
                    reasoning: m['reasoning'],
                    usageData: m['usage_data'] != null ? Map<String, dynamic>.from(m['usage_data']) : null,
                    timestamp: DateTime.parse(m['timestamp']),
                  ),
                )
                .toList(),
        createdAt: DateTime.parse(json['created_at']),
        updatedAt: DateTime.parse(json['updated_at']),
        modelId: json['model_id'],
        // Include conversation settings if available
        reasoningEnabled: json['reasoning_enabled'] as bool? ?? false,
        reasoningEffort: json['reasoning_effort'] as String? ?? 'medium',
        temperature: (json['temperature'] as num?)?.toDouble() ?? 0.7,
        maxTokens: json['max_tokens'] as int? ?? 1000,
        webSearchEnabled: json['web_search_enabled'] as bool? ?? false,
        // Handle system_message vs system_prompt field name mismatch
        systemMessage: json['system_message'] as String? ?? json['system_prompt'] as String?,
        // Include character-related settings if available
        character: json['character'] as String?,
        characterInfo: json['character_info'] as String?,
        characterBreakdown: json['character_breakdown'] as bool? ?? false,
        customInstructions: json['custom_instructions'] as String?,
      );
    } catch (e) {
      debugPrint('Error converting bot conversation: $e');
      return null;
    }
  }

  // Convert a string role to MessageRole enum
  MessageRole _roleFromString(String roleStr) {
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

  // Sync user settings with the Discord bot
  Future<bool> syncUserSettings() async {
    if (!_authService.isLoggedIn) {
      _syncError = 'Not logged in to Discord';
      notifyListeners();
      return false;
    }

    if (_isSyncing) {
      debugPrint('Sync already in progress');
      return false;
    }

    _isSyncing = true;
    _syncError = null;
    notifyListeners();

    try {
      // Get the authorization header
      final authHeader = _authService.getAuthHeader();
      if (authHeader == null) {
        _syncError = 'Authentication error';
        _isSyncing = false;
        notifyListeners();
        return false;
      }

      // Check if this is a first run scenario by checking if we have any settings
      final prefs = await SharedPreferences.getInstance();
      final isFirstRun = !prefs.containsKey('last_settings_update');
      debugPrint('syncUserSettings: Is first run or after shared prefs deletion: $isFirstRun');

      // For first run, we want to prioritize getting settings from Discord
      if (isFirstRun) {
        debugPrint('First run detected - prioritizing Discord bot settings');

        // First try to get settings from Discord bot
        final fetchSuccess = await _fetchSettingsFromDiscordBot(isFirstRun: true);

        if (fetchSuccess) {
          debugPrint('Successfully fetched and applied settings from Discord bot during first run');

          // Update last sync time
          _lastSyncTime = DateTime.now();
          await _saveLastSyncTime();

          _isSyncing = false;
          notifyListeners();
          return true;
        } else {
          debugPrint('Failed to fetch settings from Discord bot during first run, will send local settings');
        }
      } else {
        // For non-first run, update the timestamp before sending settings
        await prefs.setInt('last_settings_update', DateTime.now().millisecondsSinceEpoch);
        debugPrint('Updated last_settings_update timestamp');
      }

      // Prepare user settings for sync
      final userSettings = await _getUserSettingsForSync();

      // Log the settings being sent for debugging
      debugPrint('Syncing settings to Discord bot:');
      debugPrint('Character: ${userSettings.character}');
      debugPrint('Character Info: ${userSettings.characterInfo}');
      debugPrint('Character Breakdown: ${userSettings.characterBreakdown}');
      debugPrint('Custom Instructions: ${userSettings.customInstructions}');

      // Prepare the request body with explicit character info
      final settingsJson = userSettings.toJson();

      // Log the full JSON being sent
      debugPrint('Full settings JSON being sent:');
      debugPrint(jsonEncode(settingsJson));

      // Send the settings to the bot API
      final response = await http.post(
        Uri.parse('$botApiUrl/settings'),
        headers: {'Content-Type': 'application/json', 'Authorization': authHeader},
        body: jsonEncode({'user_settings': settingsJson}),
      );

      if (response.statusCode != 200) {
        _syncError = 'Settings sync failed: ${response.statusCode} - ${response.body}';
        _isSyncing = false;
        notifyListeners();
        return false;
      }

      // Parse the response
      final responseData = jsonDecode(response.body);

      // Check if we got user settings back
      if (responseData['settings'] != null) {
        // Get the settings as a map first so we can modify it
        final Map<String, dynamic> settingsJson = responseData['settings'];

        // Force the sync_source to be 'discord' to ensure the settings are applied
        settingsJson['sync_source'] = 'discord';
        debugPrint('Forcing sync_source to "discord" to ensure settings are applied');

        final syncedSettings = UserSettings.fromJson(settingsJson);

        // Apply any settings from the server that are newer
        await _applyUserSettings(syncedSettings, isFirstRun: isFirstRun);
      }

      // Update last sync time
      _lastSyncTime = DateTime.now();
      await _saveLastSyncTime();

      _isSyncing = false;
      notifyListeners();

      return true;
    } catch (e) {
      _syncError = 'Settings sync error: $e';
      _isSyncing = false;
      notifyListeners();
      return false;
    }
  }

  // Get user settings from SharedPreferences for syncing
  Future<UserSettings> _getUserSettingsForSync() async {
    final prefs = await SharedPreferences.getInstance();

    // Get all the settings from SharedPreferences
    final modelId = prefs.getString('selected_model') ?? 'openai/gpt-3.5-turbo';
    final temperature = prefs.getDouble('temperature') ?? 0.7;
    final maxTokens = prefs.getInt('max_tokens') ?? 1000;
    final reasoningEnabled = prefs.getBool('reasoningEnabled') ?? false;
    final reasoningEffort = prefs.getString('reasoningEffort') ?? 'medium';
    final webSearchEnabled = prefs.getBool('webSearchEnabled') ?? false;
    final systemMessage = prefs.getString('system_message');
    final advancedViewEnabled = prefs.getBool('advancedViewEnabled') ?? false;
    final streamingEnabled = prefs.getBool('streamingEnabled') ?? true;

    // Get character settings
    final character = prefs.getString('character');
    final characterInfo = prefs.getString('character_info');
    final characterBreakdown = prefs.getBool('character_breakdown') ?? false;
    final customInstructions = prefs.getString('custom_instructions');

    // Debug log the character settings
    debugPrint('Character settings from SharedPreferences:');
    debugPrint('Character: $character');
    debugPrint('Character Info: $characterInfo');
    debugPrint('Character Breakdown: $characterBreakdown');
    debugPrint('Custom Instructions: $customInstructions');

    // Create and return the UserSettings object
    return UserSettings(
      modelId: modelId,
      temperature: temperature,
      maxTokens: maxTokens,
      reasoningEnabled: reasoningEnabled,
      reasoningEffort: reasoningEffort,
      webSearchEnabled: webSearchEnabled,
      systemMessage: systemMessage,
      character: character,
      characterInfo: characterInfo,
      characterBreakdown: characterBreakdown,
      customInstructions: customInstructions,
      advancedViewEnabled: advancedViewEnabled,
      streamingEnabled: streamingEnabled,
      lastUpdated: DateTime.now(),
      syncSource: 'flutter',
    );
  }

  // Apply synced user settings to SharedPreferences
  Future<void> _applyUserSettings(UserSettings settings, {bool isFirstRun = false}) async {
    if (settings.syncSource == 'flutter') {
      // Don't apply settings that originated from this app
      debugPrint('Skipping settings application as they originated from Flutter');
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    // Only update settings if they're from the Discord bot and newer than our local settings
    if (settings.syncSource == 'discord') {
      // Get the last settings update time
      final lastSettingsUpdate = prefs.getInt('last_settings_update');
      final lastUpdateTime = lastSettingsUpdate != null ? DateTime.fromMillisecondsSinceEpoch(lastSettingsUpdate) : null;

      // For first run, always apply Discord settings regardless of timestamps
      if (isFirstRun) {
        debugPrint('First run detected - applying Discord settings regardless of timestamps');
      } else if (lastUpdateTime != null && lastUpdateTime.isAfter(settings.lastUpdated)) {
        // For non-first run, check if local settings are newer
        debugPrint('Skipping Discord settings as Flutter settings are more recent');
        debugPrint('Local update time: ${lastUpdateTime.toIso8601String()}');
        debugPrint('Discord update time: ${settings.lastUpdated.toIso8601String()}');
        return;
      }

      debugPrint('Applying settings from Discord bot:');
      debugPrint('Model: ${settings.modelId}');
      debugPrint('Temperature: ${settings.temperature}');
      debugPrint('Max Tokens: ${settings.maxTokens}');
      debugPrint('Character: ${settings.character}');
      debugPrint('Character Info: ${settings.characterInfo}');
      debugPrint('Character Breakdown: ${settings.characterBreakdown}');
      debugPrint('Custom Instructions: ${settings.customInstructions}');

      // Save all the settings to SharedPreferences
      await prefs.setString('selected_model', settings.modelId);
      await prefs.setDouble('temperature', settings.temperature);
      await prefs.setInt('max_tokens', settings.maxTokens);
      await prefs.setBool('reasoningEnabled', settings.reasoningEnabled);
      await prefs.setString('reasoningEffort', settings.reasoningEffort);
      await prefs.setBool('webSearchEnabled', settings.webSearchEnabled);

      // Handle system message
      if (settings.systemMessage != null) {
        debugPrint('Saving system_message: ${settings.systemMessage}');
        await prefs.setString('system_message', settings.systemMessage!);
      } else {
        // Check if we should keep the existing system message
        final existingSystemMessage = prefs.getString('system_message');
        if (existingSystemMessage != null && existingSystemMessage.isNotEmpty) {
          debugPrint('Keeping existing system_message: $existingSystemMessage');
        } else {
          // Set a default system message if none exists
          const defaultSystemMessage = 'You are a helpful AI assistant. Answer questions concisely and accurately.';
          debugPrint('Setting default system_message: $defaultSystemMessage');
          await prefs.setString('system_message', defaultSystemMessage);
        }
      }

      // Apply character settings
      // For first run, always apply character settings from Discord
      // For non-first run, only apply if they're not null
      if (isFirstRun) {
        // Character
        if (settings.character != null) {
          debugPrint('Saving character: ${settings.character}');
          await prefs.setString('character', settings.character!);
        } else {
          // Check if we should keep the existing character
          final existingCharacter = prefs.getString('character');
          if (existingCharacter != null && existingCharacter.isNotEmpty) {
            debugPrint('Keeping existing character: $existingCharacter');
          } else {
            debugPrint('No character set in Discord or locally');
            await prefs.remove('character');
          }
        }

        // Character Info
        if (settings.characterInfo != null) {
          debugPrint('Saving character_info: ${settings.characterInfo}');
          await prefs.setString('character_info', settings.characterInfo!);
        } else {
          // Check if we should keep the existing character info
          final existingCharacterInfo = prefs.getString('character_info');
          if (existingCharacterInfo != null && existingCharacterInfo.isNotEmpty) {
            debugPrint('Keeping existing character_info: $existingCharacterInfo');
          } else {
            debugPrint('No character_info set in Discord or locally');
            await prefs.remove('character_info');
          }
        }

        // Character Breakdown
        await prefs.setBool('character_breakdown', settings.characterBreakdown);
        debugPrint('Saving character_breakdown: ${settings.characterBreakdown}');

        // Custom Instructions
        if (settings.customInstructions != null) {
          debugPrint('Saving custom_instructions: ${settings.customInstructions}');
          await prefs.setString('custom_instructions', settings.customInstructions!);
        } else {
          // Check if we should keep the existing custom instructions
          final existingCustomInstructions = prefs.getString('custom_instructions');
          if (existingCustomInstructions != null && existingCustomInstructions.isNotEmpty) {
            debugPrint('Keeping existing custom_instructions: $existingCustomInstructions');
          } else {
            debugPrint('No custom_instructions set in Discord or locally');
            await prefs.remove('custom_instructions');
          }
        }
      } else {
        // For non-first run, only apply if they're not null
        if (settings.character != null) {
          debugPrint('Saving character: ${settings.character}');
          await prefs.setString('character', settings.character!);
        } else {
          // Remove character if it's null in Discord settings
          debugPrint('Removing character as it is null in Discord settings');
          await prefs.remove('character');
        }

        if (settings.characterInfo != null) {
          debugPrint('Saving character_info: ${settings.characterInfo}');
          await prefs.setString('character_info', settings.characterInfo!);
        } else {
          // Remove character info if it's null in Discord settings
          debugPrint('Removing character_info as it is null in Discord settings');
          await prefs.remove('character_info');
        }

        await prefs.setBool('character_breakdown', settings.characterBreakdown);
        debugPrint('Saving character_breakdown: ${settings.characterBreakdown}');

        if (settings.customInstructions != null) {
          debugPrint('Saving custom_instructions: ${settings.customInstructions}');
          await prefs.setString('custom_instructions', settings.customInstructions!);
        } else {
          // Remove custom instructions if it's null in Discord settings
          debugPrint('Removing custom_instructions as it is null in Discord settings');
          await prefs.remove('custom_instructions');
        }
      }

      await prefs.setBool('advancedViewEnabled', settings.advancedViewEnabled);
      await prefs.setBool('streamingEnabled', settings.streamingEnabled);

      // Save the update time
      await prefs.setInt('last_settings_update', DateTime.now().millisecondsSinceEpoch);
      debugPrint('Settings from Discord bot applied successfully');

      // Notify listeners that settings have changed
      notifyListeners();

      // If this is a first run or we're explicitly applying Discord settings,
      // we should reload all conversation settings to ensure they reflect the synced settings
      if (isFirstRun) {
        debugPrint('First run detected - notifying to reload all conversation settings');
        // This will trigger any listeners to reload their settings
        notifyListeners();

        // Notify that settings have been updated from Discord
        // This is a special notification that will be caught by the ChatModel
        // to reload and apply settings to all conversations
        _settingsUpdatedFromDiscord = true;
        notifyListeners();
        _settingsUpdatedFromDiscord = false;
      }
    }
  }

  // Load last sync time from SharedPreferences
  Future<void> _loadLastSyncTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastSyncMillis = prefs.getInt('last_sync_time');
      if (lastSyncMillis != null) {
        _lastSyncTime = DateTime.fromMillisecondsSinceEpoch(lastSyncMillis);
      }
    } catch (e) {
      debugPrint('Error loading last sync time: $e');
    }
  }

  // Save last sync time to SharedPreferences
  Future<void> _saveLastSyncTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_lastSyncTime != null) {
        await prefs.setInt('last_sync_time', _lastSyncTime!.millisecondsSinceEpoch);
      }
    } catch (e) {
      debugPrint('Error saving last sync time: $e');
    }
  }
}
