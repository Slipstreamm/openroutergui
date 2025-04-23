import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/constants.dart';

// Custom text input formatter to handle Enter key press
class EnterKeyHandler extends TextInputFormatter {
  final VoidCallback onEnterPressed;

  EnterKeyHandler({required this.onEnterPressed});

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    // Check if Enter was pressed without Shift
    final isEnterPressed = newValue.text.length > oldValue.text.length && newValue.text.endsWith('\n') && !HardwareKeyboard.instance.isShiftPressed;

    if (isEnterPressed) {
      // Call the callback to send the message
      onEnterPressed();
      // Return empty text to clear the field
      return const TextEditingValue(text: '', selection: TextSelection.collapsed(offset: 0));
    }

    return newValue;
  }
}

class MessageInputWidget extends StatefulWidget {
  final Function(String) onSendMessage;
  final bool isLoading;
  final bool isStreaming;
  final VoidCallback? onCancelStreaming;

  const MessageInputWidget({super.key, required this.onSendMessage, required this.isLoading, this.isStreaming = false, this.onCancelStreaming});

  @override
  State<MessageInputWidget> createState() => _MessageInputWidgetState();
}

class _MessageInputWidgetState extends State<MessageInputWidget> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _canSend = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateCanSend);
  }

  @override
  void dispose() {
    _controller.removeListener(_updateCanSend);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _updateCanSend() {
    // Always allow sending, even with empty messages
    setState(() {
      _canSend = true;
    });
  }

  void _handleSend() {
    final text = _controller.text.trim();
    // Allow sending even if the message is empty
    widget.onSendMessage(text);
    // Clear the text field
    _controller.clear();
    // Reset focus to the text field
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.defaultPadding),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(26), blurRadius: 4, offset: const Offset(0, -2))],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              decoration: const InputDecoration(hintText: 'Type a message...', border: OutlineInputBorder()),
              maxLines: null,
              textInputAction: TextInputAction.newline,
              enabled: !widget.isLoading,
              keyboardType: TextInputType.multiline,
              // Use custom input formatter to handle Enter key
              inputFormatters: [EnterKeyHandler(onEnterPressed: _handleSend)],
            ),
          ),
          const SizedBox(width: AppConstants.defaultPadding),
          if (widget.isStreaming && widget.onCancelStreaming != null)
            IconButton(onPressed: widget.onCancelStreaming, icon: const Icon(Icons.stop), color: Colors.red, tooltip: 'Cancel response')
          else if (widget.isLoading)
            const CircularProgressIndicator()
          else
            IconButton(
              onPressed: _canSend ? _handleSend : null,
              icon: const Icon(Icons.send),
              color: Theme.of(context).colorScheme.primary,
              tooltip: 'Send message',
            ),
        ],
      ),
    );
  }
}
