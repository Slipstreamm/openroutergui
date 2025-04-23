import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/chat_model.dart';
import '../models/openrouter_models.dart';
import '../utils/constants.dart';

class ModelDetailScreen extends StatelessWidget {
  final OpenRouterModel model;

  const ModelDetailScreen({super.key, required this.model});

  @override
  Widget build(BuildContext context) {
    final chatModel = Provider.of<ChatModel>(context);
    final isSelected = model.id == chatModel.selectedModel;

    return Scaffold(
      appBar: AppBar(
        title: Text(model.name),
        actions: [
          if (!isSelected)
            TextButton.icon(
              icon: const Icon(Icons.check),
              label: const Text('Select'),
              onPressed: () {
                chatModel.setSelectedModel(model.id);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${model.name} selected')));
              },
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppConstants.defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Model ID and selection status
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isSelected ? Colors.green : Theme.of(context).colorScheme.primary, width: 1.5),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading:
                      isSelected
                          ? const Icon(Icons.check_circle, color: Colors.green, size: 36)
                          : Icon(Icons.smart_toy, size: 36, color: Theme.of(context).colorScheme.primary),
                  title: Text('Model ID', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(model.id, style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ),
                  trailing:
                      isSelected ? Chip(label: const Text('Selected'), backgroundColor: Colors.green, labelStyle: const TextStyle(color: Colors.white)) : null,
                ),
              ),
            ),
            const SizedBox(height: AppConstants.defaultPadding),

            // Model description
            if (model.description != null) ...[
              Text('Description', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
              const SizedBox(height: AppConstants.smallPadding),
              Text(model.description!, style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
              const SizedBox(height: AppConstants.defaultPadding),
            ],

            // Context length
            Text('Context Length', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
            const SizedBox(height: AppConstants.smallPadding),
            Text('${model.contextLength} tokens', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
            const SizedBox(height: AppConstants.defaultPadding),

            // Pricing information
            Text('Pricing', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
            const SizedBox(height: AppConstants.smallPadding),
            _buildPricingTable(context),
            const SizedBox(height: AppConstants.defaultPadding),

            // Provider information
            Text('Provider', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
            const SizedBox(height: AppConstants.smallPadding),
            Text(_extractProvider(), style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
            const SizedBox(height: AppConstants.defaultPadding),

            // Select model button
            if (!isSelected)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    chatModel.setSelectedModel(model.id);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${model.name} selected')));
                  },
                  child: const Text('Select This Model', style: TextStyle(fontSize: 16)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPricingTable(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(2.0),
        child: Table(
          border: TableBorder.all(color: Theme.of(context).colorScheme.outlineVariant, borderRadius: BorderRadius.circular(8)),
          columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(3), 2: FlexColumnWidth(3)},
          children: [
            TableRow(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withAlpha(80),
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(8), topRight: Radius.circular(8)),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text('Unit', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
                ),
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text('Prompt', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
                ),
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text('Completion', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
                ),
              ],
            ),
            TableRow(
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerLow),
              children: [
                Padding(padding: const EdgeInsets.all(12.0), child: Text('Per Token', style: TextStyle(color: Theme.of(context).colorScheme.onSurface))),
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text(
                    '\$${model.pricing['prompt']!.toStringAsFixed(8)}',
                    style: TextStyle(fontFamily: 'monospace', color: Theme.of(context).colorScheme.onSurface),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text(
                    '\$${model.pricing['completion']!.toStringAsFixed(8)}',
                    style: TextStyle(fontFamily: 'monospace', color: Theme.of(context).colorScheme.onSurface),
                  ),
                ),
              ],
            ),
            TableRow(
              children: [
                Padding(padding: const EdgeInsets.all(12.0), child: Text('Per 1K Tokens', style: TextStyle(color: Theme.of(context).colorScheme.onSurface))),
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text(
                    '\$${(model.pricing['prompt']! * 1000).toStringAsFixed(5)}',
                    style: TextStyle(fontFamily: 'monospace', color: Theme.of(context).colorScheme.onSurface),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text(
                    '\$${(model.pricing['completion']! * 1000).toStringAsFixed(5)}',
                    style: TextStyle(fontFamily: 'monospace', color: Theme.of(context).colorScheme.onSurface),
                  ),
                ),
              ],
            ),
            TableRow(
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerLow),
              children: [
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text('Per Million Tokens', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
                ),
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text(
                    '\$${(model.pricing['prompt']! * 1000000).toStringAsFixed(2)}',
                    style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', color: Theme.of(context).colorScheme.primary),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text(
                    '\$${(model.pricing['completion']! * 1000000).toStringAsFixed(2)}',
                    style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', color: Theme.of(context).colorScheme.primary),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _extractProvider() {
    final parts = model.id.split('/');
    if (parts.length > 1) {
      // Capitalize the provider name
      final provider = parts[0];
      return provider.substring(0, 1).toUpperCase() + provider.substring(1);
    }
    return 'Unknown';
  }
}
