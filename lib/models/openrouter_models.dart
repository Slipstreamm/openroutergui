class OpenRouterModel {
  final String id;
  final String name;
  final String? description;
  final Map<String, double> pricing;
  final int contextLength;

  OpenRouterModel({required this.id, required this.name, this.description, required this.pricing, required this.contextLength});

  factory OpenRouterModel.fromJson(Map<String, dynamic> json) {
    // Extract pricing information
    final pricingData = json['pricing'] as Map<String, dynamic>;
    final pricing = {'prompt': double.parse(pricingData['prompt'].toString()), 'completion': double.parse(pricingData['completion'].toString())};

    return OpenRouterModel(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      pricing: pricing,
      contextLength: json['context_length'] as int,
    );
  }
}

// A list of commonly used models as fallback if API fails
final List<OpenRouterModel> defaultModels = [
  OpenRouterModel(
    id: 'openai/gpt-3.5-turbo',
    name: 'GPT-3.5 Turbo',
    description: 'OpenAI\'s GPT-3.5 Turbo model',
    pricing: {'prompt': 0.0000015, 'completion': 0.0000020},
    contextLength: 16385,
  ),
  OpenRouterModel(
    id: 'openai/gpt-4o',
    name: 'GPT-4o',
    description: 'OpenAI\'s GPT-4o model',
    pricing: {'prompt': 0.000005, 'completion': 0.000015},
    contextLength: 128000,
  ),
  OpenRouterModel(
    id: 'anthropic/claude-3-opus',
    name: 'Claude 3 Opus',
    description: 'Anthropic\'s Claude 3 Opus model',
    pricing: {'prompt': 0.000015, 'completion': 0.000075},
    contextLength: 200000,
  ),
  OpenRouterModel(
    id: 'anthropic/claude-3-sonnet',
    name: 'Claude 3 Sonnet',
    description: 'Anthropic\'s Claude 3 Sonnet model',
    pricing: {'prompt': 0.000003, 'completion': 0.000015},
    contextLength: 200000,
  ),
  OpenRouterModel(
    id: 'anthropic/claude-3-haiku',
    name: 'Claude 3 Haiku',
    description: 'Anthropic\'s Claude 3 Haiku model',
    pricing: {'prompt': 0.00000025, 'completion': 0.00000125},
    contextLength: 200000,
  ),
];
