import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import '../models/message.dart';
import '../models/chat_model.dart';
import '../utils/constants.dart';
import 'package:intl/intl.dart';

class ChatMessageWidget extends StatefulWidget {
  final Message message;
  final int index;
  final Function(int index)? onDelete;
  final Function(int index, String content)? onEdit;
  final Function(int index)? onRegenerate;

  const ChatMessageWidget({super.key, required this.message, required this.index, this.onDelete, this.onEdit, this.onRegenerate});

  @override
  State<ChatMessageWidget> createState() => _ChatMessageWidgetState();
}

class _ChatMessageWidgetState extends State<ChatMessageWidget> {
  // Format a number to display with commas for thousands
  String _formatNumber(num value) {
    final formatter = NumberFormat.decimalPattern();
    return formatter.format(value);
  }

  @override
  Widget build(BuildContext context) {
    final isUser = widget.message.role == MessageRole.user;
    final isSystem = widget.message.role == MessageRole.system;

    // System messages are displayed differently
    if (isSystem) {
      return Card(
        margin: const EdgeInsets.symmetric(vertical: AppConstants.smallPadding, horizontal: AppConstants.defaultPadding),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.defaultPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('System', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
              const SizedBox(height: AppConstants.smallPadding),
              Text(widget.message.content),
            ],
          ),
        ),
      );
    }

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: IntrinsicWidth(
        child: Column(
          crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // Message bubble
            Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
              margin: EdgeInsets.only(
                top: AppConstants.smallPadding,
                bottom: AppConstants.smallPadding / 2,
                left: isUser ? AppConstants.largePadding : AppConstants.defaultPadding,
                right: isUser ? AppConstants.defaultPadding : AppConstants.largePadding,
              ),
              padding: const EdgeInsets.all(AppConstants.defaultPadding),
              decoration: BoxDecoration(
                color: isUser ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isUser ? 'You' : 'Assistant',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isUser ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: AppConstants.smallPadding),
                  isUser
                      ? Text(widget.message.content, style: TextStyle(color: Theme.of(context).colorScheme.onPrimary))
                      : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Builder(
                            builder: (context) {
                              try {
                                return MarkdownBody(
                                  data: widget.message.content,
                                  styleSheet: MarkdownStyleSheet(
                                    p: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                                    code: TextStyle(backgroundColor: Theme.of(context).colorScheme.surface, color: Theme.of(context).colorScheme.primary),
                                    codeblockDecoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(8)),
                                  ),
                                );
                              } catch (e) {
                                // If markdown parsing fails, display as plain text
                                debugPrint('Error rendering markdown: $e');
                                return Text(widget.message.content, style: TextStyle(color: Theme.of(context).colorScheme.onSurface));
                              }
                            },
                          ),
                          // Advanced view is now controlled globally

                          // Reasoning section (if available)
                          if (widget.message.reasoning != null)
                            Padding(
                              padding: const EdgeInsets.only(top: AppConstants.smallPadding),
                              child: ExpansionTile(
                                title: const Text('Reasoning', style: TextStyle(fontSize: 14)),
                                initiallyExpanded: false,
                                tilePadding: EdgeInsets.zero,
                                childrenPadding: const EdgeInsets.only(bottom: AppConstants.smallPadding),
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(AppConstants.smallPadding),
                                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(8)),
                                    child: Builder(
                                      builder: (context) {
                                        try {
                                          return MarkdownBody(
                                            data: widget.message.reasoning!,
                                            styleSheet: MarkdownStyleSheet(
                                              p: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 12),
                                              code: TextStyle(
                                                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                                                color: Theme.of(context).colorScheme.primary,
                                                fontSize: 12,
                                              ),
                                              codeblockDecoration: BoxDecoration(
                                                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                            ),
                                          );
                                        } catch (e) {
                                          // If markdown parsing fails, display as plain text
                                          debugPrint('Error rendering reasoning markdown: $e');
                                          return Text(
                                            widget.message.reasoning!,
                                            style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 12),
                                          );
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          // Usage data section (if available and advanced view is enabled)
                          if (Provider.of<ChatModel>(context).advancedViewEnabled && widget.message.usageData != null)
                            Padding(
                              padding: const EdgeInsets.only(top: AppConstants.smallPadding),
                              child: ExpansionTile(
                                title: const Text('Usage Data', style: TextStyle(fontSize: 14)),
                                initiallyExpanded: false,
                                tilePadding: EdgeInsets.zero,
                                childrenPadding: const EdgeInsets.only(bottom: AppConstants.smallPadding),
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(AppConstants.smallPadding),
                                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(8)),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (widget.message.usageData!.containsKey('prompt_tokens'))
                                          Text(
                                            'Prompt tokens: ${_formatNumber(widget.message.usageData!['prompt_tokens'])}',
                                            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface),
                                          ),
                                        if (widget.message.usageData!.containsKey('completion_tokens'))
                                          Text(
                                            'Completion tokens: ${_formatNumber(widget.message.usageData!['completion_tokens'])}',
                                            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface),
                                          ),
                                        if (widget.message.usageData!.containsKey('total_tokens'))
                                          Text(
                                            'Total tokens: ${_formatNumber(widget.message.usageData!['total_tokens'])}',
                                            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface),
                                          ),
                                        if (widget.message.usageData!.containsKey('cost'))
                                          Text(
                                            'Cost: ${widget.message.usageData!['cost']} credits',
                                            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface),
                                          ),

                                        // Prompt tokens details
                                        if (widget.message.usageData!.containsKey('prompt_tokens_details') &&
                                            widget.message.usageData!['prompt_tokens_details'] is Map)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 4.0),
                                            child: Text(
                                              'Cached tokens: ${_formatNumber(widget.message.usageData!['prompt_tokens_details']['cached_tokens'] ?? 0)}',
                                              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface),
                                            ),
                                          ),

                                        // Completion tokens details
                                        if (widget.message.usageData!.containsKey('completion_tokens_details') &&
                                            widget.message.usageData!['completion_tokens_details'] is Map)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 4.0),
                                            child: Text(
                                              'Reasoning tokens: ${_formatNumber(widget.message.usageData!['completion_tokens_details']['reasoning_tokens'] ?? 0)}',
                                              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                ],
              ),
            ),

            // Action buttons for both user and assistant messages
            if (widget.onEdit != null || widget.onDelete != null || (!isUser && widget.onRegenerate != null))
              Padding(
                padding: EdgeInsets.only(right: isUser ? AppConstants.defaultPadding : 0, left: isUser ? 0 : AppConstants.defaultPadding),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Regenerate button (only for assistant messages)
                    if (!isUser && widget.onRegenerate != null)
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 16),
                        onPressed: () => widget.onRegenerate!(widget.index),
                        tooltip: 'Regenerate response',
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(),
                        visualDensity: VisualDensity.compact,
                      ),
                    if (widget.onEdit != null)
                      IconButton(
                        icon: const Icon(Icons.edit, size: 16),
                        onPressed: () => _showEditDialog(context),
                        tooltip: 'Edit',
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(),
                        visualDensity: VisualDensity.compact,
                      ),
                    if (widget.onDelete != null)
                      IconButton(
                        icon: const Icon(Icons.delete, size: 16),
                        onPressed: () => _confirmDelete(context),
                        tooltip: 'Delete',
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Confirm deletion of a message
  void _confirmDelete(BuildContext context) {
    final isAssistant = widget.message.role == MessageRole.assistant;

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('Delete ${isAssistant ? "Assistant" : "User"} Message'),
            content: Text(isAssistant ? 'Are you sure you want to delete this assistant message?' : 'Are you sure you want to delete this message?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              TextButton(
                onPressed: () {
                  if (widget.onDelete != null) {
                    widget.onDelete!(widget.index);
                    Navigator.pop(context);
                  }
                },
                child: const Text('Delete'),
              ),
            ],
          ),
    );
  }

  // Show dialog to edit a message
  void _showEditDialog(BuildContext context) {
    final isAssistant = widget.message.role == MessageRole.assistant;

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('Edit ${isAssistant ? "Assistant" : "User"} Message'),
            content: _MessageEditContent(initialContent: widget.message.content, isAssistant: isAssistant),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              TextButton(
                onPressed: () {
                  // Get the current content from the edit content widget
                  final editContent = _MessageEditContent.of(context);
                  final newContent = editContent?.currentContent.trim() ?? '';

                  if (newContent.isNotEmpty && widget.onEdit != null) {
                    widget.onEdit!(widget.index, newContent);
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

// Stateful widget for editing message content with preview
class _MessageEditContent extends StatefulWidget {
  final String initialContent;
  final bool isAssistant;

  const _MessageEditContent({required this.initialContent, required this.isAssistant});

  // Allow parent to access the current state
  static _MessageEditContentState? of(BuildContext context) {
    return context.findAncestorStateOfType<_MessageEditContentState>();
  }

  @override
  State<_MessageEditContent> createState() => _MessageEditContentState();
}

class _MessageEditContentState extends State<_MessageEditContent> {
  late TextEditingController _textController;
  String get currentContent => _textController.text;
  bool _showPreview = false;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialContent);
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6, minHeight: 200, maxWidth: MediaQuery.of(context).size.width * 0.8),
      width: double.maxFinite,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.isAssistant)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                children: [
                  Expanded(
                    child: Text('This message contains markdown formatting.', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 12)),
                  ),
                  Switch(
                    value: _showPreview,
                    onChanged: (value) {
                      setState(() {
                        _showPreview = value;
                      });
                    },
                  ),
                  Text('Preview', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          Expanded(
            child:
                widget.isAssistant && _showPreview
                    ? Container(
                      decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(4)),
                      padding: const EdgeInsets.all(8.0),
                      child: SingleChildScrollView(
                        child: Builder(
                          builder: (context) {
                            try {
                              return MarkdownBody(
                                data: _textController.text,
                                styleSheet: MarkdownStyleSheet(
                                  p: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                                  code: TextStyle(backgroundColor: Theme.of(context).colorScheme.surface, color: Theme.of(context).colorScheme.primary),
                                  codeblockDecoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(8)),
                                ),
                              );
                            } catch (e) {
                              // If markdown parsing fails, display as plain text
                              debugPrint('Error rendering preview markdown: $e');
                              return Text(_textController.text, style: TextStyle(color: Theme.of(context).colorScheme.onSurface));
                            }
                          },
                        ),
                      ),
                    )
                    : TextField(
                      controller: _textController,
                      decoration: const InputDecoration(border: OutlineInputBorder()),
                      maxLines: null,
                      minLines: 5,
                      autofocus: true,
                      onChanged: (value) {
                        if (_showPreview) {
                          setState(() {});
                        }
                      },
                    ),
          ),
        ],
      ),
    );
  }
}
