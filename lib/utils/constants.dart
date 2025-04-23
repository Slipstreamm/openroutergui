class AppConstants {
  // App information
  static const String appName = 'OpenRouter GUI';
  static const String appVersion = '1.0.0';

  // API related
  static const String openRouterUrl = 'https://openrouter.ai';
  static const String openRouterDocsUrl = 'https://openrouter.ai/docs';

  // UI related
  static const double defaultPadding = 16.0;
  static const double smallPadding = 8.0;
  static const double largePadding = 24.0;

  // Default settings
  static const String defaultModel = 'openai/gpt-3.5-turbo';
  static const double defaultTemperature = 0.5;
  static const int defaultMaxTokens = 1000;

  // System messages
  static const String defaultSystemMessage = 'You are a helpful AI assistant. Answer questions concisely and accurately.';
}
