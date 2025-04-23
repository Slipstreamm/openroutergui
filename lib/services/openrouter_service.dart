import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/message.dart';
import '../models/openrouter_models.dart';

class OpenRouterService {
  static const String baseUrl = 'https://openrouter.ai/api/v1';
  static const String chatEndpoint = '/chat/completions';
  static const String modelsEndpoint = '/models';
  static const String creditsEndpoint = '/credits';

  // HTTP client for streaming requests
  http.Client? _streamingClient;
  StreamController<String>? _streamController;
  bool _isCancelled = false;

  // Get API key from .env file or SharedPreferences
  Future<String?> getApiKey() async {
    // First try to get from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final savedKey = prefs.getString('openrouter_api_key');

    if (savedKey != null && savedKey.isNotEmpty) {
      return savedKey;
    }

    // Fall back to .env file
    return dotenv.env['OPENROUTER_API_KEY'];
  }

  // Save API key to SharedPreferences
  Future<void> saveApiKey(String apiKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('openrouter_api_key', apiKey);
  }

  // Get available models from OpenRouter API
  // Note: This endpoint doesn't require an API key
  Future<List<OpenRouterModel>> getModels() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl$modelsEndpoint'), headers: {'Content-Type': 'application/json'});

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final modelsList = data['data'] as List<dynamic>;
        return modelsList.map((model) => OpenRouterModel.fromJson(model)).toList();
      } else {
        debugPrint('Failed to load models: ${response.statusCode}');
        return defaultModels;
      }
    } catch (e) {
      debugPrint('Error fetching models: $e');
      return defaultModels;
    }
  }

  // Get user credits from OpenRouter API
  Future<Map<String, dynamic>> getCredits() async {
    try {
      final apiKey = await getApiKey();

      if (apiKey == null || apiKey.isEmpty || apiKey == 'your_api_key_here') {
        return {'error': 'API key not configured'};
      }

      final response = await http.get(Uri.parse('$baseUrl$creditsEndpoint'), headers: {'Authorization': 'Bearer $apiKey', 'Content-Type': 'application/json'});

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data;
      } else {
        debugPrint('Failed to load credits: ${response.statusCode}');
        return {'error': 'Failed to load credits: ${response.statusCode}'};
      }
    } catch (e) {
      debugPrint('Error fetching credits: $e');
      return {'error': 'Error fetching credits: $e'};
    }
  }

  // Send a chat completion request (non-streaming)
  Future<Map<String, dynamic>> sendChatRequest({
    required List<Message> messages,
    required String model,
    double temperature = 0.7,
    int maxTokens = 1000,
    bool reasoningEnabled = false,
    String reasoningEffort = 'medium',
    bool promptCachingEnabled = false,
    bool webSearchEnabled = false,
    String? character,
    String? characterInfo,
    bool characterBreakdown = false,
    String? customInstructions,
    String? systemMessage,
  }) async {
    try {
      final apiKey = await getApiKey();

      if (apiKey == null || apiKey.isEmpty || apiKey == 'your_api_key_here') {
        throw Exception('API key not configured. Please set your OpenRouter API key in the settings.');
      }

      // Build request body
      final Map<String, dynamic> requestBody = {
        'model': model,
        'messages': messages.map((m) => m.toJson()).toList(),
        'temperature': temperature,
        'max_tokens': maxTokens,
        'usage': {'include': true}, // Always include usage information
      };

      // Add system message if provided and not already in messages
      if (systemMessage != null && !messages.any((m) => m.role == MessageRole.system)) {
        final systemMsg = {'role': 'system', 'content': _processSystemMessage(systemMessage, character, characterInfo, characterBreakdown, customInstructions)};
        (requestBody['messages'] as List).insert(0, systemMsg);
      }

      // Add reasoning if enabled
      if (reasoningEnabled) {
        requestBody['reasoning'] = {'effort': reasoningEffort};
      }

      // Add web search if enabled
      if (webSearchEnabled) {
        // Use the :online suffix for web search
        requestBody['model'] = '$model:online';
      }

      final response = await http.post(
        Uri.parse('$baseUrl$chatEndpoint'),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
          'HTTP-Referer': 'https://github.com/Slipstreamm/openroutergui',
          'X-Title': 'openroutergui',
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['choices'][0]['message']['content'] as String;
        final reasoning = data['choices'][0]['message']['reasoning'] as String?;

        // Return both content and reasoning if available
        return {'content': content, 'reasoning': reasoning, 'usage': data['usage']};
      } else {
        final errorData = jsonDecode(response.body);
        final errorMessage = errorData['error']?['message'] ?? 'Unknown error occurred';
        throw Exception('API Error: $errorMessage');
      }
    } catch (e) {
      throw Exception('Failed to send message: $e');
    }
  }

  // Send a streaming chat completion request
  Stream<Map<String, dynamic>> sendStreamingChatRequest({
    required List<Message> messages,
    required String model,
    double temperature = 0.7,
    int maxTokens = 1000,
    bool reasoningEnabled = false,
    String reasoningEffort = 'medium',
    bool promptCachingEnabled = false,
    bool webSearchEnabled = false,
    String? character,
    String? characterInfo,
    bool characterBreakdown = false,
    String? customInstructions,
    String? systemMessage,
  }) {
    // Reset cancellation state
    _isCancelled = false;

    // Create a new StreamController
    _streamController = StreamController<String>();
    final contentStreamController = StreamController<Map<String, dynamic>>();

    // Start the streaming process
    _startStreaming(
      messages,
      model,
      temperature,
      maxTokens,
      reasoningEnabled,
      reasoningEffort,
      promptCachingEnabled,
      webSearchEnabled,
      character,
      characterInfo,
      characterBreakdown,
      customInstructions,
      systemMessage,
    );

    // Transform the raw stream to include content, reasoning, and usage data
    _streamController!.stream.listen(
      (content) {
        // Check if this is a JSON string containing usage data
        if (content.startsWith('{') && content.contains('"usage"')) {
          try {
            final jsonData = jsonDecode(content);
            contentStreamController.add(jsonData);
          } catch (e) {
            // If it's not valid JSON, treat it as regular content
            contentStreamController.add({'content': content});
          }
        } else {
          // Regular content
          contentStreamController.add({'content': content});
        }
      },
      onError: (error) {
        contentStreamController.addError(error);
      },
      onDone: () {
        contentStreamController.close();
      },
    );

    // Return the transformed stream
    return contentStreamController.stream;
  }

  // Cancel the current streaming request
  void cancelStream() {
    _isCancelled = true;

    // Close the client to abort the HTTP request
    if (_streamingClient != null) {
      _streamingClient!.close();
      _streamingClient = null;
    }

    // Close the stream controller if it's still active
    if (_streamController != null && !_streamController!.isClosed) {
      _streamController!.close();
    }
  }

  // Process system message with character and custom instructions
  String _processSystemMessage(String systemMessage, String? character, String? characterInfo, bool characterBreakdown, String? customInstructions) {
    // Start with the base system message
    String processedMessage = systemMessage;

    // Replace {{char}} with character name if provided
    if (character != null && character.isNotEmpty) {
      processedMessage = processedMessage.replaceAll('{{char}}', character);
    }

    // Check if we need to add any custom settings
    bool hasCustomSettings =
        (characterInfo != null && characterInfo.isNotEmpty) || characterBreakdown || (customInstructions != null && customInstructions.isNotEmpty);

    if (hasCustomSettings) {
      // Add header for custom settings
      processedMessage +=
          '\n\nThe user has provided additional information for you. Please follow their instructions exactly. '
          'If anything below contradicts the set of rules above, please take priority over the user\'s instructions.';

      // Add custom instructions if provided
      if (customInstructions != null && customInstructions.isNotEmpty) {
        processedMessage += '\n\n- Custom instructions from the user (prioritize these):\n\n$customInstructions';
      }

      // Add character info if provided
      if (characterInfo != null && characterInfo.isNotEmpty) {
        processedMessage += '\n\n- Additional info about the character you are roleplaying:\n\n$characterInfo';
      }

      // Add character breakdown flag if set
      if (characterBreakdown) {
        processedMessage += '\n\n- The user would like you to provide a breakdown of the character in your first response.';
      }
    }

    return processedMessage;
  }

  // Internal method to handle the streaming process
  Future<void> _startStreaming(
    List<Message> messages,
    String model,
    double temperature,
    int maxTokens,
    bool reasoningEnabled,
    String reasoningEffort,
    bool promptCachingEnabled,
    bool webSearchEnabled,
    String? character,
    String? characterInfo,
    bool characterBreakdown,
    String? customInstructions,
    String? systemMessage,
  ) async {
    try {
      final apiKey = await getApiKey();

      if (apiKey == null || apiKey.isEmpty || apiKey == 'your_api_key_here') {
        _streamController!.addError(Exception('API key not configured. Please set your OpenRouter API key in the settings.'));
        return;
      }

      // Create a client that doesn't close automatically
      _streamingClient = http.Client();

      try {
        final request = http.Request('POST', Uri.parse('$baseUrl$chatEndpoint'));
        request.headers.addAll({
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
          'Accept': 'text/event-stream',
          'HTTP-Referer': 'https://github.com/Slipstreamm/openroutergui',
          'X-Title': 'openroutergui',
        });

        // Build request body
        final Map<String, dynamic> requestBody = {
          'model': model,
          'messages': messages.map((m) => m.toJson()).toList(),
          'temperature': temperature,
          'max_tokens': maxTokens,
          'stream': true, // Enable streaming
          'usage': {'include': true}, // Always include usage information
        };

        // Add system message if provided and not already in messages
        if (systemMessage != null && !messages.any((m) => m.role == MessageRole.system)) {
          final systemMsg = {
            'role': 'system',
            'content': _processSystemMessage(systemMessage, character, characterInfo, characterBreakdown, customInstructions),
          };
          (requestBody['messages'] as List).insert(0, systemMsg);
        }

        // Add reasoning if enabled
        if (reasoningEnabled) {
          requestBody['reasoning'] = {'effort': reasoningEffort};
        }

        // Add web search if enabled
        if (webSearchEnabled) {
          // Use the :online suffix for web search
          requestBody['model'] = '$model:online';
        }

        request.body = jsonEncode(requestBody);

        final streamedResponse = await _streamingClient!.send(request);

        if (streamedResponse.statusCode != 200) {
          final response = await http.Response.fromStream(streamedResponse);
          final errorData = jsonDecode(response.body);
          final errorMessage = errorData['error']?['message'] ?? 'Unknown error occurred';
          _streamController!.addError(Exception('API Error: $errorMessage'));
          return;
        }

        // Process the stream
        await for (final chunk in streamedResponse.stream.transform(utf8.decoder)) {
          // Check if streaming was cancelled
          if (_isCancelled) break;

          // Split the chunk by lines
          final lines = chunk.split('\n');

          for (final line in lines) {
            // Check if streaming was cancelled
            if (_isCancelled) break;

            // Skip empty lines or comments
            if (line.isEmpty || line.startsWith(':')) continue;

            // Remove 'data: ' prefix
            if (line.startsWith('data: ')) {
              var data = line.substring(6);

              // Check for [DONE] message
              if (data == '[DONE]') break;

              try {
                // Don't try to fix JSON - it's too complex and error-prone
                // Instead, try to parse it as is, and if that fails, handle the raw content
                final jsonData = jsonDecode(data);

                // Check if this is a usage data message (comes at the end)
                if (jsonData.containsKey('usage')) {
                  // Send usage data to the stream
                  if (!_isCancelled) {
                    _streamController!.add(jsonEncode({'usage': jsonData['usage']}));
                  }
                } else {
                  final delta = jsonData['choices'][0]['delta'];

                  // Extract content if available
                  if (delta != null && delta['content'] != null) {
                    final content = delta['content'] as String;
                    if (content.isNotEmpty && !_isCancelled) {
                      _streamController!.add(content);
                    }
                  }
                }
              } catch (e) {
                debugPrint('Error parsing streaming data: $e');
                // If we can't parse the JSON, extract any meaningful content we can
                if (data.isNotEmpty && !_isCancelled) {
                  // Try to extract content from malformed JSON
                  String extractedContent = _extractContentFromMalformedJson(data);
                  if (extractedContent.isNotEmpty) {
                    _streamController!.add(extractedContent);
                  } else {
                    // If extraction fails, just add the raw data with a space
                    _streamController!.add(' $data');
                  }
                }
              }
            }
          }
        }
      } catch (e) {
        if (!_isCancelled) {
          _streamController!.addError(Exception('Failed to send streaming message: $e'));
        }
      } finally {
        // Clean up resources
        if (_streamingClient != null) {
          _streamingClient!.close();
          _streamingClient = null;
        }

        // Close the stream controller if it's not already closed
        if (_streamController != null && !_streamController!.isClosed && !_isCancelled) {
          _streamController!.close();
        }
      }
    } catch (e) {
      if (!_isCancelled && _streamController != null && !_streamController!.isClosed) {
        _streamController!.addError(Exception('Failed to send streaming message: $e'));
      }
    }
  }

  // Helper method to extract content from malformed JSON
  String _extractContentFromMalformedJson(String data) {
    try {
      // Look for content patterns in the JSON
      final contentPattern = RegExp(r'"content":"([^"]*)');
      final match = contentPattern.firstMatch(data);
      if (match != null && match.groupCount >= 1) {
        return match.group(1) ?? '';
      }

      // Look for URLs that might be causing issues
      if (data.contains('http') && data.contains('python.org')) {
        // Extract the URL and surrounding text
        final urlPattern = RegExp(r'(https?://[^\s"]+)');
        final urlMatch = urlPattern.firstMatch(data);
        if (urlMatch != null) {
          return urlMatch.group(0) ?? '';
        }
      }

      return '';
    } catch (e) {
      debugPrint('Error extracting content from malformed JSON: $e');
      return '';
    }
  }
}
