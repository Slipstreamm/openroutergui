import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/chat_model.dart';
import '../models/message.dart';
import '../utils/constants.dart';
import '../widgets/chat_message.dart';
import '../widgets/message_input.dart';
import 'settings_screen.dart';
import 'model_selection_screen.dart';
import 'conversation_list_screen.dart';
import 'conversation_settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    debugPrint('HomeScreen: Loading data...');
    final chatModel = Provider.of<ChatModel>(context, listen: false);

    // Load conversations
    debugPrint('HomeScreen: Loading conversations...');
    await chatModel.loadConversations();
    debugPrint('HomeScreen: Conversations loaded, count: ${chatModel.conversations.length}');

    // Load model selection
    debugPrint('HomeScreen: Loading selected model...');
    await chatModel.loadSelectedModel();
    debugPrint('HomeScreen: Selected model loaded: ${chatModel.selectedModel}');

    // Check if API key is configured
    debugPrint('HomeScreen: Checking API key...');
    final apiKey = await chatModel.getApiKey();
    if (apiKey == null || apiKey.isEmpty || apiKey == 'your_api_key_here') {
      debugPrint('HomeScreen: API key not configured, showing dialog');
      // Show settings screen if API key is not configured
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showApiKeyDialog();
        });
      }
    } else {
      debugPrint('HomeScreen: API key is configured');
    }

    // Force save conversations to ensure they're properly saved
    if (chatModel.conversations.isNotEmpty) {
      debugPrint('HomeScreen: Force saving conversations...');
      await chatModel.forceSaveConversations();
      debugPrint('HomeScreen: Conversations saved');
    }

    debugPrint('HomeScreen: Data loading complete');
  }

  void _showApiKeyDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            title: const Text('API Key Required'),
            content: const Text(
              'An OpenRouter API key is required to use this app. '
              'Would you like to configure it now?',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(MaterialPageRoute(builder: (context) => const SettingsScreen()));
                },
                child: const Text('Yes'),
              ),
            ],
          ),
    );
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  Future<void> _sendMessage(String content) async {
    // Allow empty messages

    final chatModel = Provider.of<ChatModel>(context, listen: false);
    chatModel.addUserMessage(content);

    // Scroll to bottom after adding user message
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    chatModel.setLoading(true);
    chatModel.setError('');

    try {
      // Check if streaming is enabled
      if (chatModel.streamingEnabled) {
        // Start streaming response
        chatModel.startStreamingResponse();

        // Scroll to bottom to show the empty message that will be filled
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

        // Listen to the stream and update the UI
        final conversation = chatModel.activeConversation;
        await for (final chunk in chatModel.sendStreamingChatRequest(
          messages: chatModel.messages,
          model: chatModel.selectedModel,
          character: conversation?.character,
          characterInfo: conversation?.characterInfo,
          characterBreakdown: conversation?.characterBreakdown,
          customInstructions: conversation?.customInstructions,
          systemMessage: conversation?.systemMessage,
        )) {
          chatModel.updateStreamingResponse(chunk);
          // Scroll to bottom as content comes in
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
        }

        // Finalize the streaming response
        chatModel.finalizeStreamingResponse();
      } else {
        // Use non-streaming API
        final conversation = chatModel.activeConversation;
        final response = await chatModel.sendChatRequest(
          messages: chatModel.messages,
          model: chatModel.selectedModel,
          character: conversation?.character,
          characterInfo: conversation?.characterInfo,
          characterBreakdown: conversation?.characterBreakdown,
          customInstructions: conversation?.customInstructions,
          systemMessage: conversation?.systemMessage,
        );

        chatModel.addAssistantMessage(response);

        // Scroll to bottom after adding assistant message
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    } catch (e) {
      chatModel.setError(e.toString());
      // Check if widget is still mounted before using BuildContext
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.red));
      }
    } finally {
      chatModel.setLoading(false);
    }
  }

  // Edit a message
  void _editMessage(int index, String newContent) {
    final chatModel = Provider.of<ChatModel>(context, listen: false);
    chatModel.editMessage(index, newContent);
  }

  // Delete a message
  void _deleteMessage(int index) {
    final chatModel = Provider.of<ChatModel>(context, listen: false);
    chatModel.deleteMessage(index);
  }

  // Cancel streaming response
  void _cancelStreaming() {
    final chatModel = Provider.of<ChatModel>(context, listen: false);
    chatModel.cancelStreamingResponse();
  }

  // Regenerate an AI response
  void _regenerateResponse(int index) {
    final chatModel = Provider.of<ChatModel>(context, listen: false);
    chatModel.regenerateResponse(index);

    // Scroll to bottom after regenerating
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  // Clear all messages in the current conversation
  void _clearChat() {
    final chatModel = Provider.of<ChatModel>(context, listen: false);
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Clear Chat'),
            content: const Text('Are you sure you want to clear the chat history?'),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
              TextButton(
                onPressed: () {
                  chatModel.clearMessages();
                  Navigator.of(context).pop();
                },
                child: const Text('Clear'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Consumer<ChatModel>(
          builder: (context, chatModel, _) {
            final conversation = chatModel.activeConversation;
            return Text(conversation?.title ?? AppConstants.appName);
          },
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Consumer<ChatModel>(
            builder: (context, chatModel, _) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(chatModel.formattedCredits, style: const TextStyle(fontSize: 12)),
                    if (chatModel.isLoadingCredits)
                      const Padding(
                        padding: EdgeInsets.only(left: 8.0),
                        child: SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    else
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 14),
                        onPressed: () => chatModel.loadCredits(),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Refresh credits',
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () {
            Navigator.of(context).push(MaterialPageRoute(builder: (context) => const ConversationListScreen()));
          },
          tooltip: 'Conversations',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () async {
              final chatModel = Provider.of<ChatModel>(context, listen: false);
              // Use the async version to ensure all settings are loaded
              await chatModel.createNewConversationAsync();
            },
            tooltip: 'New Conversation',
          ),
          IconButton(
            icon: const Icon(Icons.model_training),
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (context) => const ModelSelectionScreen()));
            },
            tooltip: 'Select Model',
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            onPressed: () {
              final chatModel = Provider.of<ChatModel>(context, listen: false);
              if (chatModel.activeConversationId != null) {
                Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (context) => ConversationSettingsScreen(conversationId: chatModel.activeConversationId!)));
              }
            },
            tooltip: 'Conversation Settings',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (context) => const SettingsScreen()));
            },
            tooltip: 'Global Settings',
          ),
          IconButton(icon: const Icon(Icons.delete), onPressed: _clearChat, tooltip: 'Clear Chat'),
          Consumer<ChatModel>(
            builder: (context, chatModel, _) {
              return IconButton(
                icon: Icon(chatModel.advancedViewEnabled ? Icons.analytics : Icons.analytics_outlined),
                onPressed: () {
                  chatModel.setAdvancedViewEnabled(!chatModel.advancedViewEnabled);
                },
                tooltip: 'Toggle Advanced View',
              );
            },
          ),
        ],
      ),
      body: Consumer<ChatModel>(
        builder: (context, chatModel, child) {
          return Column(
            children: [
              // Model info banner
              Container(
                padding: const EdgeInsets.all(AppConstants.smallPadding),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Row(
                  children: [
                    const Icon(Icons.smart_toy, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Model: ${chatModel.selectedModel}', style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ),

              // Error message if any
              if (chatModel.error.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(AppConstants.smallPadding),
                  color: Colors.red.shade100,
                  width: double.infinity,
                  child: Text('Error: ${chatModel.error}', style: TextStyle(color: Colors.red.shade900)),
                ),

              // Conversation usage summary (only shown when advanced view is enabled)
              if (chatModel.advancedViewEnabled && chatModel.conversationUsage.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(AppConstants.smallPadding),
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  width: double.infinity,
                  child: Row(
                    children: [
                      const Icon(Icons.analytics, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Usage: ${NumberFormat.decimalPattern().format(chatModel.conversationUsage["total_tokens"])} tokens '
                          '(${NumberFormat.decimalPattern().format(chatModel.conversationUsage["prompt_tokens"])} prompt, '
                          '${NumberFormat.decimalPattern().format(chatModel.conversationUsage["completion_tokens"])} completion) | '
                          'Cost: \$${chatModel.conversationUsage["cost"].toStringAsFixed(4)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),

              // Chat messages
              Expanded(
                child:
                    chatModel.messages.isEmpty
                        ? const Center(child: Text('Send a message to start chatting'))
                        : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.only(bottom: AppConstants.defaultPadding),
                          itemCount: chatModel.messages.length,
                          itemBuilder: (context, index) {
                            final message = chatModel.messages[index];
                            return ChatMessageWidget(
                              message: message,
                              index: index,
                              onEdit: _editMessage,
                              onDelete: _deleteMessage,
                              onRegenerate: message.role == MessageRole.assistant ? _regenerateResponse : null,
                            );
                          },
                        ),
              ),

              // Message input
              MessageInputWidget(
                onSendMessage: _sendMessage,
                isLoading: chatModel.isLoading,
                isStreaming: chatModel.isStreaming,
                onCancelStreaming: chatModel.isStreaming ? _cancelStreaming : null,
              ),
            ],
          );
        },
      ),
    );
  }
}
