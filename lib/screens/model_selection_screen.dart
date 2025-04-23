import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/chat_model.dart';
import '../models/openrouter_models.dart';
import '../services/openrouter_service.dart';
import '../utils/constants.dart';
import 'model_detail_screen.dart';

class ModelSelectionScreen extends StatefulWidget {
  const ModelSelectionScreen({super.key});

  @override
  State<ModelSelectionScreen> createState() => _ModelSelectionScreenState();
}

class _ModelSelectionScreenState extends State<ModelSelectionScreen> {
  final OpenRouterService _openRouterService = OpenRouterService();
  List<OpenRouterModel> _models = [];
  List<OpenRouterModel> _filteredModels = [];
  bool _isLoading = true;
  String _error = '';

  // Search and filter state
  final TextEditingController _searchController = TextEditingController();
  String _sortBy = 'name'; // 'name', 'price', 'context'
  bool _sortAscending = true;
  String _filterProvider = 'all'; // 'all', 'openai', 'anthropic', etc.

  @override
  void initState() {
    super.initState();
    _loadModels();

    // Add listener for search field
    _searchController.addListener(_filterModels);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadModels() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final models = await _openRouterService.getModels();
      setState(() {
        _models = models;
        _isLoading = false;
        _filterModels(); // Apply initial filtering
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
        _models = defaultModels; // Use default models as fallback
        _filterModels(); // Apply initial filtering
      });
    }
  }

  // Filter and sort models based on current settings
  void _filterModels() {
    if (_models.isEmpty) {
      _filteredModels = [];
      return;
    }

    // Start with all models
    List<OpenRouterModel> filtered = List.from(_models);

    // Apply provider filter
    if (_filterProvider != 'all') {
      filtered = filtered.where((model) => model.id.toLowerCase().contains(_filterProvider.toLowerCase())).toList();
    }

    // Apply search filter
    final searchQuery = _searchController.text.toLowerCase().trim();
    if (searchQuery.isNotEmpty) {
      filtered =
          filtered.where((model) {
            return model.name.toLowerCase().contains(searchQuery) ||
                model.id.toLowerCase().contains(searchQuery) ||
                (model.description?.toLowerCase().contains(searchQuery) ?? false);
          }).toList();
    }

    // Apply sorting
    filtered.sort((a, b) {
      int result = 0;
      switch (_sortBy) {
        case 'name':
          result = a.name.compareTo(b.name);
          break;
        case 'price':
          // Sort by prompt price
          result = a.pricing['prompt']!.compareTo(b.pricing['prompt']!);
          break;
        case 'context':
          result = a.contextLength.compareTo(b.contextLength);
          break;
      }
      return _sortAscending ? result : -result;
    });

    setState(() {
      _filteredModels = filtered;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Model'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loadModels, tooltip: 'Refresh Models')],
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error.isNotEmpty
              ? _buildErrorView()
              : _buildModelList(),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.defaultPadding),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: AppConstants.defaultPadding),
            Text('Error loading models', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppConstants.smallPadding),
            Text(_error, textAlign: TextAlign.center),
            const SizedBox(height: AppConstants.defaultPadding),
            ElevatedButton(onPressed: _loadModels, child: const Text('Try Again')),
            const SizedBox(height: AppConstants.defaultPadding),
            const Text('Using default models list as fallback', style: TextStyle(fontStyle: FontStyle.italic)),
          ],
        ),
      ),
    );
  }

  Widget _buildModelList() {
    final chatModel = Provider.of<ChatModel>(context);
    final currentModel = chatModel.selectedModel;

    return Column(
      children: [
        // Info banner about API key
        Container(
          padding: const EdgeInsets.all(AppConstants.smallPadding),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          width: double.infinity,
          child: const Text(
            'Note: You can browse models without an API key, but you\'ll need one to send messages.',
            style: TextStyle(fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ),

        // Search bar
        Padding(
          padding: const EdgeInsets.all(AppConstants.smallPadding),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search models...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              suffixIcon:
                  _searchController.text.isNotEmpty
                      ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _filterModels();
                        },
                      )
                      : null,
            ),
          ),
        ),

        // Filter and sort options
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppConstants.smallPadding),
          child: Row(
            children: [
              // Provider filter
              Expanded(
                child: DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Provider', isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 8)),
                  value: _filterProvider,
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All Providers')),
                    DropdownMenuItem(value: 'openai', child: Text('OpenAI')),
                    DropdownMenuItem(value: 'anthropic', child: Text('Anthropic')),
                    DropdownMenuItem(value: 'google', child: Text('Google')),
                    DropdownMenuItem(value: 'meta', child: Text('Meta')),
                    DropdownMenuItem(value: 'mistral', child: Text('Mistral')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _filterProvider = value;
                      });
                      _filterModels();
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Sort options
              Expanded(
                child: DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Sort By', isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 8)),
                  value: _sortBy,
                  items: const [
                    DropdownMenuItem(value: 'name', child: Text('Name')),
                    DropdownMenuItem(value: 'price', child: Text('Price')),
                    DropdownMenuItem(value: 'context', child: Text('Context Length')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _sortBy = value;
                      });
                      _filterModels();
                    }
                  },
                ),
              ),
              // Sort direction
              IconButton(
                icon: Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward),
                onPressed: () {
                  setState(() {
                    _sortAscending = !_sortAscending;
                  });
                  _filterModels();
                },
                tooltip: _sortAscending ? 'Ascending' : 'Descending',
              ),
            ],
          ),
        ),

        // Results count
        Padding(
          padding: const EdgeInsets.all(AppConstants.smallPadding),
          child: Text('Showing ${_filteredModels.length} of ${_models.length} models', style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
        ),

        // Model list
        Expanded(
          child:
              _filteredModels.isEmpty
                  ? const Center(child: Text('No models match your search criteria'))
                  : ListView.builder(
                    itemCount: _filteredModels.length,
                    itemBuilder: (context, index) {
                      final model = _filteredModels[index];
                      final isSelected = model.id == currentModel;

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: AppConstants.defaultPadding, vertical: AppConstants.smallPadding),
                        child: Column(
                          children: [
                            ListTile(
                              title: Text(model.name),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (model.description != null) Text(model.description!, maxLines: 2, overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 4),
                                  Text('Context: ${model.contextLength} tokens', style: const TextStyle(fontSize: 12)),
                                  Text(
                                    'Pricing: \$${(model.pricing['prompt']! * 1000000).toStringAsFixed(2)}/M prompt, \$${(model.pricing['completion']! * 1000000).toStringAsFixed(2)}/M completion',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                              leading: isSelected ? const Icon(Icons.check_circle, color: Colors.green) : const Icon(Icons.smart_toy),
                              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                              selected: isSelected,
                              onTap: () {
                                chatModel.setSelectedModel(model.id);
                                Navigator.of(context).pop();
                              },
                            ),
                            Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: OverflowBar(
                                alignment: MainAxisAlignment.end,
                                children: [
                                  TextButton(
                                    onPressed: () {
                                      Navigator.push(context, MaterialPageRoute(builder: (context) => ModelDetailScreen(model: model)));
                                    },
                                    child: const Text('View Details'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
        ),
      ],
    );
  }
}
