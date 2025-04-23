import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/chat_model.dart';
import 'screens/home_screen.dart';
import 'utils/theme.dart';
import 'utils/constants.dart';
import 'services/sync_service.dart';
import 'services/discord_oauth_service.dart';
import 'services/auto_sync_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  await dotenv.load(fileName: '.env');

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Discord OAuth Service
        Provider<DiscordOAuthService>(create: (_) => DiscordOAuthService()),
        // Sync Service
        ChangeNotifierProxyProvider<DiscordOAuthService, SyncService>(
          create: (context) => SyncService(Provider.of<DiscordOAuthService>(context, listen: false)),
          update: (context, authService, previous) => previous ?? SyncService(authService),
        ),
        // Chat Model
        ChangeNotifierProvider<ChatModel>(
          create: (context) {
            final chatModel = ChatModel();
            // Load preferences
            Future.microtask(() async {
              debugPrint('App starting - loading preferences and conversations');

              // Load conversations first to ensure they're available
              debugPrint('Loading conversations...');
              await chatModel.loadConversations();
              debugPrint('Conversations loaded');

              // Load other preferences
              debugPrint('Loading other preferences...');
              await chatModel.loadSelectedModel();
              await chatModel.loadStreamingPreference();
              await chatModel.loadAdvancedViewPreference();
              await chatModel.loadReasoningSettings();
              debugPrint('All preferences loaded');

              // Initialize sync service
              if (context.mounted) {
                debugPrint('Initializing sync service...');
                final syncService = Provider.of<SyncService>(context, listen: false);
                await syncService.initialize();
                debugPrint('Sync service initialized');

                // Check if this is a first run scenario
                final prefs = await SharedPreferences.getInstance();
                final isFirstRun = !prefs.containsKey('last_settings_update');
                debugPrint('Main: Is first run or after shared prefs deletion: $isFirstRun');

                // Initialize auto sync service
                if (syncService.isLoggedIn) {
                  debugPrint('User is logged in, initializing auto sync service');

                  // First sync settings from Discord bot
                  // This is especially important for first run scenarios
                  debugPrint('Syncing settings from Discord bot...');

                  // For first run, we want to be extra careful to get settings from Discord
                  if (isFirstRun) {
                    debugPrint('First run detected - explicitly fetching settings from Discord bot');
                    // First try to explicitly fetch settings from Discord bot
                    await syncService.syncUserSettings();

                    // Wait a moment to ensure settings are properly applied
                    await Future.delayed(const Duration(milliseconds: 500));
                  } else {
                    // For regular runs, just sync settings normally
                    await syncService.syncUserSettings();
                  }

                  debugPrint('Settings sync completed');

                  // Reload and apply settings to all conversations
                  debugPrint('Reloading and applying settings to all conversations...');
                  await chatModel.reloadAndApplyGlobalSettings();
                  debugPrint('Settings applied to all conversations');

                  // Create the auto sync service
                  AutoSyncService(chatModel, syncService);
                  debugPrint('Auto sync service initialized');

                  // Force a save of conversations to ensure they're properly saved
                  await chatModel.forceSaveConversations();
                  debugPrint('Forced save of conversations on app start');

                  // Add listener for automatically synced conversations
                  syncService.addListener(() {
                    if (syncService.lastSyncedConversations != null) {
                      debugPrint('SyncService notified with new conversations, importing into ChatModel...');
                      chatModel.importConversations(syncService.lastSyncedConversations!);
                      // Optionally clear the list in SyncService after import?
                      // syncService.clearLastSyncedConversations(); // Need to add this method if desired
                    }
                  });
                  debugPrint('Added listener to SyncService for conversation updates.');
                } else {
                  debugPrint('User is not logged in, skipping auto sync service and listener setup');
                }
              }

              debugPrint('App initialization complete');
            });
            return chatModel;
          },
        ),
      ],
      child: MaterialApp(
        title: AppConstants.appName,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
        debugShowCheckedModeBanner: false,
        home: const HomeScreen(),
      ),
    );
  }
}
