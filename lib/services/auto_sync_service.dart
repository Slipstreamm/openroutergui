import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/chat_model.dart';
import 'sync_service.dart';

/// A service that automatically syncs conversations when they change
class AutoSyncService {
  final ChatModel _chatModel;
  final SyncService _syncService;
  Timer? _syncTimer;
  bool _needsSync = true; // Start with true to force an initial sync

  AutoSyncService(this._chatModel, this._syncService) {
    // Listen for changes in the chat model
    _chatModel.addListener(_onChatModelChanged);

    // Set up a timer to sync every 30 seconds if needed
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) => _syncIfNeeded());

    // Force an immediate sync when the service is created
    debugPrint('Auto-sync service created, scheduling immediate sync');
    // Use a shorter delay to ensure it runs quickly after initialization
    Future.delayed(const Duration(milliseconds: 500), () {
      debugPrint('Forcing immediate sync on startup');
      _needsSync = true;
      _syncIfNeeded();
    });
  }

  void _onChatModelChanged() {
    // Mark that we need to sync
    _needsSync = true;

    // If we're logged in, schedule a sync in 5 seconds
    // This debounces rapid changes
    if (_syncService.isLoggedIn) {
      Timer(const Duration(seconds: 5), () => _syncIfNeeded());
    }
  }

  Future<void> _syncIfNeeded() async {
    // Only sync if needed and logged in
    if (!_needsSync) {
      debugPrint('Auto-sync not needed');
      return;
    }

    if (!_syncService.isLoggedIn) {
      debugPrint('Auto-sync skipped: not logged in to Discord');
      return;
    }

    debugPrint('Starting auto-sync process...');
    try {
      // First sync user settings to ensure character settings are synced
      debugPrint('Syncing user settings...');
      final settingsResult = await _syncService.syncUserSettings();
      debugPrint('User settings sync result: $settingsResult');

      // Reload settings and apply to all conversations
      await _chatModel.reloadAndApplyGlobalSettings();
      debugPrint('Settings reloaded and applied to all conversations');

      // Get conversations with messages
      final conversations = _chatModel.conversations.where((c) => c.messages.isNotEmpty).toList();
      debugPrint('Found ${conversations.length} conversations with messages to sync');

      // Sync conversations
      debugPrint('Syncing conversations...');
      final syncResult = await _syncService.syncConversations(conversations);
      debugPrint('Conversation sync result: $syncResult');

      // Reset the sync flag
      _needsSync = false;

      debugPrint('Auto-sync completed successfully');

      // Force save conversations to ensure they're persisted after sync
      await _chatModel.forceSaveConversations();
      debugPrint('Forced save of conversations after sync');
    } catch (e) {
      debugPrint('Error auto-syncing: $e');
      // Log the stack trace for debugging
      debugPrint(StackTrace.current.toString());
    }
  }

  void dispose() {
    // Clean up
    _chatModel.removeListener(_onChatModelChanged);
    _syncTimer?.cancel();
  }
}
