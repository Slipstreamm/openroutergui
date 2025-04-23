import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/chat_model.dart';
import '../models/conversation.dart';
import 'conversation_settings_screen.dart';

class ConversationListScreen extends StatelessWidget {
  const ConversationListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Conversations'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () async {
              final chatModel = Provider.of<ChatModel>(context, listen: false);
              // Use the async version to ensure all settings are loaded
              await chatModel.createNewConversationAsync();
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
            tooltip: 'New Conversation',
          ),
        ],
      ),
      body: Consumer<ChatModel>(
        builder: (context, chatModel, child) {
          final conversations = chatModel.conversations;
          final activeId = chatModel.activeConversationId;

          if (conversations.isEmpty) {
            return const Center(child: Text('No conversations yet. Create one to get started.'));
          }

          return ListView.builder(
            itemCount: conversations.length,
            itemBuilder: (context, index) {
              final conversation = conversations[index];
              final isActive = conversation.id == activeId;

              return Dismissible(
                key: Key(conversation.id),
                background: Container(
                  color: Colors.red,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                direction: DismissDirection.endToStart,
                confirmDismiss: (direction) async {
                  return await showDialog(
                    context: context,
                    builder: (BuildContext context) {
                      return AlertDialog(
                        title: const Text('Confirm Delete'),
                        content: const Text('Are you sure you want to delete this conversation?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
                          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
                        ],
                      );
                    },
                  );
                },
                onDismissed: (direction) {
                  chatModel.deleteConversation(conversation.id);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Conversation deleted')));
                },
                child: ListTile(
                  title: Text(conversation.title, style: TextStyle(fontWeight: isActive ? FontWeight.bold : FontWeight.normal)),
                  subtitle: Text(conversation.preview, maxLines: 1, overflow: TextOverflow.ellipsis),
                  leading: Icon(Icons.chat_bubble_outline, color: isActive ? Theme.of(context).colorScheme.primary : null),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, size: 20),
                        onPressed: () => _showRenameDialog(context, chatModel, conversation),
                        tooltip: 'Rename',
                      ),
                      IconButton(
                        icon: const Icon(Icons.settings, size: 20),
                        onPressed: () {
                          Navigator.push(context, MaterialPageRoute(builder: (context) => ConversationSettingsScreen(conversationId: conversation.id)));
                        },
                        tooltip: 'Conversation Settings',
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  selected: isActive,
                  onTap: () {
                    chatModel.setActiveConversation(conversation.id);
                    Navigator.pop(context);
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showRenameDialog(BuildContext context, ChatModel chatModel, Conversation conversation) {
    final textController = TextEditingController(text: conversation.title);

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Rename Conversation'),
            content: TextField(
              controller: textController,
              decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
              autofocus: true,
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              TextButton(
                onPressed: () {
                  final newTitle = textController.text.trim();
                  if (newTitle.isNotEmpty) {
                    chatModel.renameConversation(conversation.id, newTitle);
                    Navigator.pop(context);
                  }
                },
                child: const Text('Save'),
              ),
            ],
          ),
    );
  }
}
