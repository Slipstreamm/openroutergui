import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_model.dart';
import '../services/discord_oauth_service.dart';
import '../services/sync_service.dart';
import '../services/auto_sync_service.dart';
import '../utils/constants.dart';

class DiscordSettingsScreen extends StatefulWidget {
  const DiscordSettingsScreen({super.key});

  @override
  State<DiscordSettingsScreen> createState() => _DiscordSettingsScreenState();
}

class _DiscordSettingsScreenState extends State<DiscordSettingsScreen> {
  bool _isLoading = false;
  String _statusMessage = '';
  bool _isError = false;

  late final DiscordOAuthService _authService;
  late final SyncService _syncService;

  @override
  void initState() {
    super.initState();
    _authService = DiscordOAuthService();
    _syncService = SyncService(_authService);
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Initializing...';
    });

    try {
      await _authService.initialize();
      await _syncService.initialize();

      setState(() {
        _isLoading = false;
        _statusMessage = _authService.isLoggedIn ? 'Logged in as ${_authService.username}' : 'Not logged in';
        _isError = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = 'Error initializing: $e';
        _isError = true;
      });
    }
  }

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Logging in...';
      _isError = false;
    });

    try {
      final success = await _authService.login(context);

      if (mounted) {
        if (success) {
          // Automatically sync settings and conversations after login
          setState(() {
            _statusMessage = 'Logged in as ${_authService.username}, syncing settings...';
          });

          try {
            // Get chat model before async operations
            final chatModel = Provider.of<ChatModel>(context, listen: false);

            // Check if this is a first run scenario
            final prefs = await SharedPreferences.getInstance();
            final isFirstRun = !prefs.containsKey('last_settings_update');
            debugPrint('DiscordSettingsScreen: Is first run: $isFirstRun');

            // Sync user settings - this is especially important for first run
            debugPrint('Syncing settings from Discord bot after login...');
            await _syncService.syncUserSettings();
            debugPrint('Settings sync completed');

            // Reload and apply settings to all conversations
            debugPrint('Reloading and applying settings to all conversations...');
            await chatModel.reloadAndApplyGlobalSettings();
            debugPrint('Settings applied to all conversations');

            // Sync conversations
            if (mounted) {
              debugPrint('Syncing conversations with Discord bot...');
              await _syncService.syncConversations(chatModel.conversations);
              debugPrint('Conversation sync completed');

              // Initialize auto sync service
              AutoSyncService(chatModel, _syncService);
              debugPrint('Auto sync service initialized');

              // Force a save of conversations to ensure they're properly saved
              await chatModel.forceSaveConversations();
              debugPrint('Forced save of conversations after login');

              setState(() {
                _isLoading = false;
                _statusMessage = 'Logged in and synced settings';
                _isError = false;
              });
            }
          } catch (syncError) {
            setState(() {
              _isLoading = false;
              _statusMessage = 'Logged in, but sync failed: $syncError';
              _isError = true;
            });
          }
        } else {
          setState(() {
            _isLoading = false;
            _statusMessage = 'Login failed';
            _isError = true;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Error logging in: $e';
          _isError = true;
        });
      }
    }
  }

  Future<void> _logout() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Logging out...';
      _isError = false;
    });

    try {
      await _authService.logout();

      setState(() {
        _isLoading = false;
        _statusMessage = 'Logged out';
        _isError = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = 'Error logging out: $e';
        _isError = true;
      });
    }
  }

  Future<void> _syncConversations() async {
    if (!_authService.isLoggedIn) {
      setState(() {
        _statusMessage = 'Please log in first';
        _isError = true;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Syncing conversations...';
      _isError = false;
    });

    try {
      final chatModel = Provider.of<ChatModel>(context, listen: false);
      final success = await _syncService.syncConversations(chatModel.conversations);

      setState(() {
        _isLoading = false;
        if (success) {
          _statusMessage = 'Conversations synced successfully';
          _isError = false;
        } else {
          _statusMessage = 'Sync failed: ${_syncService.syncError}';
          _isError = true;
        }
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = 'Error syncing: $e';
        _isError = true;
      });
    }
  }

  Future<void> _fetchConversations() async {
    if (!_authService.isLoggedIn) {
      setState(() {
        _statusMessage = 'Please log in first';
        _isError = true;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Fetching conversations from Discord...';
      _isError = false;
    });

    try {
      final conversations = await _syncService.getConversationsFromBot();

      if (conversations == null) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Failed to fetch conversations: ${_syncService.syncError}';
          _isError = true;
        });
        return;
      }

      // Ask user if they want to import these conversations
      if (mounted) {
        final shouldImport =
            await showDialog<bool>(
              context: context,
              builder:
                  (context) => AlertDialog(
                    title: const Text('Import Conversations'),
                    content: Text('Found ${conversations.length} conversations from Discord. Do you want to import them?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
                      TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Import')),
                    ],
                  ),
            ) ??
            false;

        if (mounted) {
          if (shouldImport) {
            final chatModel = Provider.of<ChatModel>(context, listen: false);
            for (final conversation in conversations) {
              chatModel.importConversation(conversation);
            }

            setState(() {
              _isLoading = false;
              _statusMessage = 'Imported ${conversations.length} conversations';
              _isError = false;
            });
          } else {
            setState(() {
              _isLoading = false;
              _statusMessage = 'Import cancelled';
              _isError = false;
            });
          }
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = 'Error fetching conversations: $e';
        _isError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Discord Integration')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppConstants.defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Discord OAuth section
            const Text('Discord Account', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: AppConstants.smallPadding),
            const Text('Connect your Discord account to sync conversations between this app and your Discord bot.'),
            const SizedBox(height: AppConstants.defaultPadding),

            // Status message
            if (_statusMessage.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(AppConstants.smallPadding),
                color: _isError ? Colors.red.shade100 : Colors.green.shade100,
                width: double.infinity,
                child: Text(_statusMessage, style: TextStyle(color: _isError ? Colors.red.shade900 : Colors.green.shade900)),
              ),
            const SizedBox(height: AppConstants.defaultPadding),

            // Login/logout button
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _authService.isLoggedIn
                ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Logged in as: ${_authService.username}'),
                    Text('User ID: ${_authService.userId}'),
                    const SizedBox(height: AppConstants.defaultPadding),
                    Row(
                      children: [
                        ElevatedButton(onPressed: _logout, child: const Text('Logout')),
                        const SizedBox(width: AppConstants.smallPadding),
                        ElevatedButton(onPressed: _syncConversations, child: const Text('Sync Conversations')),
                        const SizedBox(width: AppConstants.smallPadding),
                        ElevatedButton(onPressed: _fetchConversations, child: const Text('Import from Discord')),
                      ],
                    ),
                  ],
                )
                : ElevatedButton(onPressed: _login, child: const Text('Login with Discord')),

            const SizedBox(height: AppConstants.largePadding),

            // Sync information
            if (_authService.isLoggedIn) ...[
              const Text('Sync Information', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: AppConstants.smallPadding),
              Text('Last sync: ${_syncService.lastSyncTime != null ? _syncService.lastSyncTime.toString() : 'Never'}'),
              const SizedBox(height: AppConstants.defaultPadding),
              const Text(
                'Note: Syncing will merge conversations between this app and your Discord bot. '
                'If the same conversation exists in both places, the most recently updated version will be used.',
              ),
            ],

            const SizedBox(height: AppConstants.largePadding),

            // Setup instructions
            const Text('Setup Instructions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: AppConstants.smallPadding),
            const Text(
              '1. Make sure your Discord bot is running and has the sync API enabled.\n'
              '2. Log in with your Discord account using the button above.\n'
              '3. Use the Sync button to sync conversations between this app and your Discord bot.\n'
              '4. Use the Import button to fetch conversations from your Discord bot.',
            ),
          ],
        ),
      ),
    );
  }
}
