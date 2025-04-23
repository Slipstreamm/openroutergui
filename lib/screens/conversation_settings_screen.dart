import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_model.dart';
import '../services/sync_service.dart';
import '../utils/constants.dart';
import 'character_settings_screen.dart';

class ConversationSettingsScreen extends StatefulWidget {
  final String conversationId;

  const ConversationSettingsScreen({super.key, required this.conversationId});

  @override
  State<ConversationSettingsScreen> createState() => _ConversationSettingsScreenState();
}

class _ConversationSettingsScreenState extends State<ConversationSettingsScreen> {
  final _systemMessageController = TextEditingController();
  late double _temperature;
  late int _maxTokens;
  late bool _reasoningEnabled;
  late String _reasoningEffort;
  late bool _webSearchEnabled;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadConversationSettings();
  }

  @override
  void dispose() {
    _systemMessageController.dispose();
    super.dispose();
  }

  Future<void> _loadConversationSettings() async {
    setState(() {
      _isLoading = true;
    });

    final chatModel = Provider.of<ChatModel>(context, listen: false);
    final conversation = chatModel.conversations.firstWhere((c) => c.id == widget.conversationId, orElse: () => throw Exception('Conversation not found'));

    // Load system message
    final systemMessage = conversation.systemMessage ?? '';
    if (systemMessage.isEmpty) {
      // If no conversation-specific system message, try to load the global one
      final prefs = await SharedPreferences.getInstance();
      final globalSystemMessage = prefs.getString('system_message') ?? AppConstants.defaultSystemMessage;
      _systemMessageController.text = globalSystemMessage;
    } else {
      _systemMessageController.text = systemMessage;
    }

    // Load other settings
    setState(() {
      _temperature = conversation.temperature;
      _maxTokens = conversation.maxTokens;
      _reasoningEnabled = conversation.reasoningEnabled;
      _reasoningEffort = conversation.reasoningEffort;
      _webSearchEnabled = conversation.webSearchEnabled;
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    // Get providers before async operations
    final chatModel = Provider.of<ChatModel>(context, listen: false);
    final syncService = Provider.of<SyncService>(context, listen: false);
    final isLoggedIn = syncService.isLoggedIn;

    // Update conversation settings
    chatModel.updateConversationSettingsById(
      conversationId: widget.conversationId,
      temperature: _temperature,
      maxTokens: _maxTokens,
      reasoningEnabled: _reasoningEnabled,
      reasoningEffort: _reasoningEffort,
      webSearchEnabled: _webSearchEnabled,
      systemMessage: _systemMessageController.text.trim(),
    );

    // Save last settings update time
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_settings_update', DateTime.now().millisecondsSinceEpoch);

    // Sync settings with Discord bot if logged in
    if (isLoggedIn) {
      await syncService.syncUserSettings();

      // Also sync the conversation
      final conversations = chatModel.conversations.where((c) => c.messages.isNotEmpty).toList();
      await syncService.syncConversations(conversations);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Conversation settings saved')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(appBar: AppBar(title: const Text('Conversation Settings')), body: const Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Conversation Settings')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppConstants.defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // System Message Section
            const Text('System Message', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: AppConstants.smallPadding),
            const Text('This message will be sent to the model as a system instruction for this conversation.'),
            const SizedBox(height: AppConstants.defaultPadding),
            TextField(
              controller: _systemMessageController,
              decoration: const InputDecoration(
                labelText: 'System Message',
                border: OutlineInputBorder(),
                hintText: 'Leave empty to use the global system message',
              ),
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

            // Reasoning Tokens Section
            const Text('Reasoning Tokens', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: AppConstants.smallPadding),
            const Text(
              'Enable reasoning tokens to see the model\'s step-by-step reasoning process. This can help understand how the model arrived at its response.',
            ),
            SwitchListTile(
              title: const Text('Enable Reasoning Tokens'),
              subtitle: const Text('Show model\'s reasoning process'),
              value: _reasoningEnabled,
              onChanged: (value) {
                setState(() {
                  _reasoningEnabled = value;
                });
              },
            ),
            if (_reasoningEnabled)
              Padding(
                padding: const EdgeInsets.only(left: AppConstants.defaultPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Reasoning Effort', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: AppConstants.smallPadding),
                    DropdownButton<String>(
                      value: _reasoningEffort,
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _reasoningEffort = value;
                          });
                        }
                      },
                      items: const [
                        DropdownMenuItem(value: 'low', child: Text('Low')),
                        DropdownMenuItem(value: 'medium', child: Text('Medium')),
                        DropdownMenuItem(value: 'high', child: Text('High')),
                      ],
                    ),
                  ],
                ),
              ),
            const SizedBox(height: AppConstants.defaultPadding),

            // Web Search Section
            const Text('Web Search', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: AppConstants.smallPadding),
            const Text('Enable web search to allow the model to search the internet for information. This can help with recent events or specific facts.'),
            SwitchListTile(
              title: const Text('Enable Web Search'),
              subtitle: const Text('Allow model to search the internet'),
              value: _webSearchEnabled,
              onChanged: (value) {
                setState(() {
                  _webSearchEnabled = value;
                });
              },
            ),
            const SizedBox(height: AppConstants.largePadding),

            // Character Settings Button
            const Text('Character Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: AppConstants.smallPadding),
            const Text('Configure character roleplay settings, character information, and custom instructions.'),
            const SizedBox(height: AppConstants.smallPadding),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.of(context).push(MaterialPageRoute(builder: (context) => CharacterSettingsScreen(conversationId: widget.conversationId)));
                },
                child: const Text('Edit Character Settings'),
              ),
            ),
            const SizedBox(height: AppConstants.largePadding),

            // Save Button
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _saveSettings, child: const Text('Save Settings'))),
            const SizedBox(height: AppConstants.defaultPadding),
          ],
        ),
      ),
    );
  }
}
