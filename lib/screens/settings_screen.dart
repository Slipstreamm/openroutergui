import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_model.dart';
import '../services/openrouter_service.dart';
import '../services/sync_service.dart';
import '../utils/constants.dart';
import 'discord_settings_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _apiKeyController = TextEditingController();
  final _systemMessageController = TextEditingController();
  final _characterController = TextEditingController();
  final _characterInfoController = TextEditingController();
  final _customInstructionsController = TextEditingController();
  final _openRouterService = OpenRouterService();
  bool _isApiKeyVisible = false;
  double _temperature = AppConstants.defaultTemperature;
  int _maxTokens = AppConstants.defaultMaxTokens;
  bool _characterBreakdown = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _systemMessageController.dispose();
    _characterController.dispose();
    _characterInfoController.dispose();
    _customInstructionsController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    // Load API key
    final apiKey = await _openRouterService.getApiKey();
    if (apiKey != null && apiKey != 'your_api_key_here') {
      _apiKeyController.text = apiKey;
    }

    // Load system message and other settings
    final prefs = await SharedPreferences.getInstance();
    final systemMessage = prefs.getString('system_message') ?? AppConstants.defaultSystemMessage;
    _systemMessageController.text = systemMessage;

    // Load character settings
    final character = prefs.getString('character') ?? '';
    final characterInfo = prefs.getString('character_info') ?? '';
    final customInstructions = prefs.getString('custom_instructions') ?? '';

    _characterController.text = character;
    _characterInfoController.text = characterInfo;
    _customInstructionsController.text = customInstructions;

    // Load temperature and max tokens and other boolean settings
    setState(() {
      _temperature = prefs.getDouble('temperature') ?? AppConstants.defaultTemperature;
      _maxTokens = prefs.getInt('max_tokens') ?? AppConstants.defaultMaxTokens;
      _characterBreakdown = prefs.getBool('character_breakdown') ?? false;
    });
  }

  Future<void> _saveSettings() async {
    // Get providers before async operations
    final chatModel = Provider.of<ChatModel>(context, listen: false);
    final syncService = Provider.of<SyncService>(context, listen: false);
    final isLoggedIn = syncService.isLoggedIn;

    final prefs = await SharedPreferences.getInstance();

    // Save API key
    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isNotEmpty) {
      await _openRouterService.saveApiKey(apiKey);
    }

    // Save system message
    final systemMessage = _systemMessageController.text.trim();
    await prefs.setString('system_message', systemMessage);

    // Update system message in chat model if it exists
    if (systemMessage.isNotEmpty) {
      chatModel.setSystemMessage(systemMessage);
    }

    // Save temperature and max tokens
    await prefs.setDouble('temperature', _temperature);
    await prefs.setInt('max_tokens', _maxTokens);

    // Save character settings
    final character = _characterController.text.trim();
    final characterInfo = _characterInfoController.text.trim();
    final customInstructions = _customInstructionsController.text.trim();

    await prefs.setString('character', character);
    await prefs.setString('character_info', characterInfo);
    await prefs.setString('custom_instructions', customInstructions);
    await prefs.setBool('character_breakdown', _characterBreakdown);

    // Update character settings in chat model
    await chatModel.setGlobalCharacterSettings(
      character.isNotEmpty ? character : null,
      characterInfo.isNotEmpty ? characterInfo : null,
      _characterBreakdown,
      customInstructions.isNotEmpty ? customInstructions : null,
    );

    // Save last settings update time
    await prefs.setInt('last_settings_update', DateTime.now().millisecondsSinceEpoch);

    // Sync settings with Discord bot if logged in
    if (isLoggedIn) {
      debugPrint('Syncing settings with Discord bot...');
      final success = await syncService.syncUserSettings();
      debugPrint('Sync result: ${success ? 'Success' : 'Failed'}');

      if (!success) {
        debugPrint('Sync error: ${syncService.syncError}');
      }
    }

    // Show snackbar if the widget is still mounted
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppConstants.defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // API Key Section
            const Text('API Key', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: AppConstants.smallPadding),
            const Text('Enter your OpenRouter API key. You can get one from openrouter.ai.'),
            const SizedBox(height: AppConstants.defaultPadding),
            TextField(
              controller: _apiKeyController,
              decoration: InputDecoration(
                labelText: 'API Key',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_isApiKeyVisible ? Icons.visibility_off : Icons.visibility),
                  onPressed: () {
                    setState(() {
                      _isApiKeyVisible = !_isApiKeyVisible;
                    });
                  },
                ),
              ),
              obscureText: !_isApiKeyVisible,
            ),
            const SizedBox(height: AppConstants.defaultPadding),

            // System Message Section
            const Text('System Message', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: AppConstants.smallPadding),
            const Text('This message will be sent to the model as a system instruction.'),
            const SizedBox(height: AppConstants.defaultPadding),
            TextField(
              controller: _systemMessageController,
              decoration: const InputDecoration(labelText: 'System Message', border: OutlineInputBorder()),
              maxLines: 3,
            ),
            const SizedBox(height: AppConstants.defaultPadding),

            // Temperature Section
            const Text('Temperature', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: AppConstants.smallPadding),
            const Text('Controls randomness: Lower values make responses more deterministic, higher values make responses more random.'),
            Slider(
              value: _temperature,
              min: 0.0,
              max: 2.0,
              divisions: 20,
              label: _temperature.toStringAsFixed(1),
              onChanged: (value) {
                setState(() {
                  _temperature = value;
                });
              },
            ),
            Text('Temperature: ${_temperature.toStringAsFixed(1)}'),
            const SizedBox(height: AppConstants.defaultPadding),

            // Max Tokens Section
            const Text('Max Tokens', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: AppConstants.smallPadding),
            const Text('Maximum number of tokens to generate in the response.'),
            Slider(
              value: _maxTokens.toDouble(),
              min: 100,
              max: 4000,
              divisions: 39,
              label: _maxTokens.toString(),
              onChanged: (value) {
                setState(() {
                  _maxTokens = value.toInt();
                });
              },
            ),
            Text('Max Tokens: $_maxTokens'),
            const SizedBox(height: AppConstants.defaultPadding),

            // Streaming Toggle Section
            const Text('Streaming', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: AppConstants.smallPadding),
            const Text('Enable streaming to see responses as they are generated. This provides a more interactive experience.'),
            Consumer<ChatModel>(
              builder: (context, chatModel, child) {
                return SwitchListTile(
                  title: const Text('Enable Streaming'),
                  subtitle: const Text('Show responses as they are generated'),
                  value: chatModel.streamingEnabled,
                  onChanged: (value) async {
                    chatModel.setStreamingEnabled(value);

                    // Sync settings with Discord bot if logged in
                    final syncService = Provider.of<SyncService>(context, listen: false);
                    if (syncService.isLoggedIn) {
                      await syncService.syncUserSettings();
                    }
                  },
                );
              },
            ),
            const SizedBox(height: AppConstants.defaultPadding),

            // Reasoning Tokens Section
            const Text('Reasoning Tokens', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: AppConstants.smallPadding),
            const Text(
              'Enable reasoning tokens to see the model\'s step-by-step reasoning process. This can help understand how the model arrived at its response.',
            ),
            Consumer<ChatModel>(
              builder: (context, chatModel, child) {
                return Column(
                  children: [
                    SwitchListTile(
                      title: const Text('Enable Reasoning Tokens'),
                      subtitle: const Text('Show model\'s reasoning process'),
                      value: chatModel.reasoningEnabled,
                      onChanged: (value) async {
                        chatModel.setReasoningEnabled(value);

                        // Sync settings with Discord bot if logged in
                        final syncService = Provider.of<SyncService>(context, listen: false);
                        if (syncService.isLoggedIn) {
                          await syncService.syncUserSettings();
                        }
                      },
                    ),
                    if (chatModel.reasoningEnabled)
                      Padding(
                        padding: const EdgeInsets.only(left: AppConstants.defaultPadding, right: AppConstants.defaultPadding),
                        child: DropdownButtonFormField<String>(
                          decoration: const InputDecoration(
                            labelText: 'Reasoning Effort',
                            helperText: 'Controls how much effort the model puts into reasoning',
                          ),
                          value: chatModel.reasoningEffort,
                          items: const [
                            DropdownMenuItem(value: 'low', child: Text('Low')),
                            DropdownMenuItem(value: 'medium', child: Text('Medium')),
                            DropdownMenuItem(value: 'high', child: Text('High')),
                          ],
                          onChanged: (value) async {
                            if (value != null) {
                              chatModel.setReasoningEffort(value);

                              // Sync settings with Discord bot if logged in
                              final syncService = Provider.of<SyncService>(context, listen: false);
                              if (syncService.isLoggedIn) {
                                await syncService.syncUserSettings();
                              }
                            }
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: AppConstants.defaultPadding),

            // Character Settings Section
            const Text('Global Character Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: AppConstants.smallPadding),
            const Text('These settings will be applied to all new conversations. You can override them for individual conversations.'),
            const SizedBox(height: AppConstants.defaultPadding),

            // Character Name Field
            TextField(
              controller: _characterController,
              decoration: const InputDecoration(labelText: 'Character Name', hintText: 'e.g., Hatsune Miku', border: OutlineInputBorder()),
            ),
            const SizedBox(height: AppConstants.defaultPadding),

            // Character Info Field
            TextField(
              controller: _characterInfoController,
              decoration: const InputDecoration(
                labelText: 'Character Information',
                hintText: 'Enter background, personality traits, appearance, etc.',
                border: OutlineInputBorder(),
              ),
              maxLines: 5,
            ),
            const SizedBox(height: AppConstants.defaultPadding),

            // Character Breakdown Toggle
            SwitchListTile(
              title: const Text('Enable Character Breakdown'),
              subtitle: const Text('AI will provide a breakdown of the character in its first response'),
              value: _characterBreakdown,
              onChanged: (value) {
                setState(() {
                  _characterBreakdown = value;
                });
              },
            ),

            // Custom Instructions Field
            TextField(
              controller: _customInstructionsController,
              decoration: const InputDecoration(
                labelText: 'Custom Instructions',
                hintText: 'Enter specific instructions for the AI',
                border: OutlineInputBorder(),
              ),
              maxLines: 5,
            ),
            const SizedBox(height: AppConstants.largePadding),

            // Save Button
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _saveSettings, child: const Text('Save Settings'))),
            const SizedBox(height: AppConstants.defaultPadding),

            // OpenRouter Links
            const Divider(),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('OpenRouter Website'),
              onTap: () {
                // Open OpenRouter website
              },
            ),
            ListTile(
              leading: const Icon(Icons.description),
              title: const Text('OpenRouter Documentation'),
              onTap: () {
                // Open OpenRouter documentation
              },
            ),

            // Discord Integration
            const Divider(),
            ListTile(
              leading: const Icon(Icons.discord),
              title: const Text('Discord Integration'),
              subtitle: const Text('Sync conversations with your Discord bot'),
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const DiscordSettingsScreen()));
              },
            ),
          ],
        ),
      ),
    );
  }
}
