import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';
import '../models/chat_model.dart';
import '../services/sync_service.dart';

class CharacterSettingsScreen extends StatefulWidget {
  final String conversationId;

  const CharacterSettingsScreen({super.key, required this.conversationId});

  @override
  CharacterSettingsScreenState createState() => CharacterSettingsScreenState();
}

class CharacterSettingsScreenState extends State<CharacterSettingsScreen> {
  late TextEditingController _characterController;
  late TextEditingController _characterInfoController;
  late TextEditingController _customInstructionsController;
  late bool _characterBreakdown;

  @override
  void initState() {
    super.initState();
    final chatModel = Provider.of<ChatModel>(context, listen: false);
    final conversation = chatModel.getConversationById(widget.conversationId);

    _characterController = TextEditingController(text: conversation?.character ?? '');
    _characterInfoController = TextEditingController(text: conversation?.characterInfo ?? '');
    _customInstructionsController = TextEditingController(text: conversation?.customInstructions ?? '');
    _characterBreakdown = conversation?.characterBreakdown ?? false;
  }

  @override
  void dispose() {
    _characterController.dispose();
    _characterInfoController.dispose();
    _customInstructionsController.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    // Get providers before async operations
    final chatModel = Provider.of<ChatModel>(context, listen: false);
    final syncService = Provider.of<SyncService>(context, listen: false);
    final isLoggedIn = syncService.isLoggedIn;
    final conversation = chatModel.getConversationById(widget.conversationId);

    if (conversation != null) {
      chatModel.updateConversationCharacterSettings(
        widget.conversationId,
        _characterController.text,
        _characterInfoController.text,
        _characterBreakdown,
        _customInstructionsController.text,
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Character settings saved')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Character Settings'),
        actions: [IconButton(icon: const Icon(Icons.save), onPressed: _saveSettings, tooltip: 'Save Settings')],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppConstants.defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Character Name Section
            const Text('Character Name', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: AppConstants.smallPadding),
            const Text('Enter the name of the character you want the AI to roleplay as.'),
            const SizedBox(height: AppConstants.smallPadding),
            TextField(
              controller: _characterController,
              decoration: const InputDecoration(labelText: 'Character Name', hintText: 'e.g., Hatsune Miku', border: OutlineInputBorder()),
            ),
            const SizedBox(height: AppConstants.defaultPadding),

            // Character Breakdown Toggle
            const Text('Character Breakdown', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: AppConstants.smallPadding),
            const Text('When enabled, the AI will provide a breakdown of the character in its first response.'),
            SwitchListTile(
              title: const Text('Enable Character Breakdown'),
              value: _characterBreakdown,
              onChanged: (value) {
                setState(() {
                  _characterBreakdown = value;
                });
              },
            ),
            const SizedBox(height: AppConstants.defaultPadding),

            // Character Info Section
            const Text('Character Information', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: AppConstants.smallPadding),
            const Text('Provide detailed information about the character for the AI to reference.'),
            const SizedBox(height: AppConstants.smallPadding),
            TextField(
              controller: _characterInfoController,
              decoration: const InputDecoration(
                labelText: 'Character Information',
                hintText: 'Enter background, personality traits, appearance, etc.',
                border: OutlineInputBorder(),
              ),
              maxLines: 8,
            ),
            const SizedBox(height: AppConstants.defaultPadding),

            // Custom Instructions Section
            const Text('Custom Instructions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: AppConstants.smallPadding),
            const Text('Provide custom instructions for the AI to follow when responding.'),
            const SizedBox(height: AppConstants.smallPadding),
            TextField(
              controller: _customInstructionsController,
              decoration: const InputDecoration(
                labelText: 'Custom Instructions',
                hintText: 'Enter specific instructions for the AI',
                border: OutlineInputBorder(),
              ),
              maxLines: 8,
            ),
            const SizedBox(height: AppConstants.defaultPadding * 2),

            // Save Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saveSettings,
                child: const Padding(padding: EdgeInsets.symmetric(vertical: 12.0), child: Text('Save Character Settings')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
