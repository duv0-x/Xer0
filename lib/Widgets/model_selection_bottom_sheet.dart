import 'package:flutter/material.dart';
import 'package:async/async.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:reins/Models/model_capabilities.dart';

import 'package:reins/Models/ollama_model.dart';
import 'package:reins/Models/ollama_request_state.dart';
import 'package:reins/Providers/chat_provider.dart';
import 'package:reins/Widgets/ollama_bottom_sheet_header.dart';

class ModelSelectionBottomSheet extends StatefulWidget {
  final String title;
  final String? currentModelName;

  const ModelSelectionBottomSheet({
    super.key,
    required this.title,
    this.currentModelName,
  });

  @override
  State<ModelSelectionBottomSheet> createState() => _ModelSelectionBottomSheetState();
}

class _ModelSelectionBottomSheetState extends State<ModelSelectionBottomSheet> {
  static final _modelsBucket = PageStorageBucket();

  late final ChatProvider _chatProvider;

  OllamaModel? _selectedModel;
  List<OllamaModel> _models = [];
  Set<String> _favoriteNames = {};

  final _searchController = TextEditingController();
  String _searchQuery = '';

  var _state = OllamaRequestState.uninitialized;
  late CancelableOperation _fetchOperation;

  /// Cache key derived from server address
  String get _cacheKey => Hive.box('settings').get('serverAddress') ?? 'default';

  /// Storage key for the favorite model names of the current server
  String get _favoritesKey => 'favoriteModels::$_cacheKey';

  @override
  void initState() {
    super.initState();

    _chatProvider = context.read<ChatProvider>();

    // Load the previous state of the models list
    _models = _modelsBucket.readState(context, identifier: _cacheKey) ?? [];
    _selectedModel = _findModelByName(widget.currentModelName);
    _favoriteNames = _loadFavoriteNames();

    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text);
    });

    _fetchOperation = CancelableOperation.fromFuture(_fetchModels());
  }

  @override
  void dispose() {
    _fetchOperation.cancel();
    _searchController.dispose();
    super.dispose();
  }

  OllamaModel? _findModelByName(String? name) {
    if (name == null) return null;
    try {
      return _models.firstWhere((m) => m.name == name);
    } catch (_) {
      return null;
    }
  }

  Set<String> _loadFavoriteNames() {
    final stored = Hive.box('settings').get(_favoritesKey) as List?;
    return stored?.cast<String>().toSet() ?? {};
  }

  void _toggleFavorite(String modelName) {
    setState(() {
      if (_favoriteNames.contains(modelName)) {
        _favoriteNames.remove(modelName);
      } else {
        _favoriteNames.add(modelName);
      }
    });
    Hive.box('settings').put(_favoritesKey, _favoriteNames.toList());
  }

  List<OllamaModel> get _searchFilteredModels {
    if (_searchQuery.isEmpty) return _models;

    final query = _searchQuery.toLowerCase();
    return _models.where((m) => m.name.toLowerCase().contains(query)).toList();
  }

  List<OllamaModel> get _favoriteModels {
    final favorites = _searchFilteredModels.where((m) => _favoriteNames.contains(m.name)).toList();
    favorites.sort((a, b) => a.name.compareTo(b.name));
    return favorites;
  }

  List<OllamaModel> get _otherModels {
    final others = _searchFilteredModels.where((m) => !_favoriteNames.contains(m.name)).toList();
    others.sort((a, b) => a.name.compareTo(b.name));
    return others;
  }

  Future<void> _fetchModels() async {
    setState(() {
      _state = OllamaRequestState.loading;
    });

    try {
      _models = await _chatProvider.fetchAvailableModels();
      _state = OllamaRequestState.success;

      // Update selection if we were searching by name (cache was empty)
      if (_selectedModel == null && widget.currentModelName != null) {
        _selectedModel = _findModelByName(widget.currentModelName);
      }

      if (mounted) {
        _modelsBucket.writeState(context, _models, identifier: _cacheKey);
      }
    } catch (e) {
      _state = OllamaRequestState.error;
    }

    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: OllamaBottomSheetHeader(title: widget.title)),
              if (_models.isNotEmpty && _state == OllamaRequestState.loading)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0),
                  child: CircularProgressIndicator(),
                ),
            ],
          ),
          const Divider(),
          if (_models.isNotEmpty) _buildSearchField(context),
          Expanded(child: _buildBody(context)),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: _selectedModel != null ? () => Navigator.of(context).pop(_selectedModel) : null,
                child: const Text('Select'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search models',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => _searchController.clear(),
                )
              : null,
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_state == OllamaRequestState.error) {
      return Center(
        child: Text(
          'An error occurred while fetching models.'
          '\nCheck your server connection and try again.',
          style: TextStyle(color: Theme.of(context).colorScheme.error),
          textAlign: TextAlign.center,
        ),
      );
    } else if (_state == OllamaRequestState.loading && _models.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    } else if (_state == OllamaRequestState.success || _models.isNotEmpty) {
      if (_models.isEmpty) {
        return const Center(child: Text('No models found.'));
      }

      return _buildModelsList(context);
    } else {
      return const SizedBox.shrink();
    }
  }

  Widget _buildModelsList(BuildContext context) {
    final favorites = _favoriteModels;
    final others = _otherModels;

    return RefreshIndicator(
      onRefresh: () async {
        _fetchOperation = CancelableOperation.fromFuture(_fetchModels());
      },
      child: favorites.isEmpty && others.isEmpty
          ? Center(child: Text('No models match "$_searchQuery".'))
          : RadioGroup<OllamaModel>(
              groupValue: _selectedModel,
              onChanged: (model) => setState(() => _selectedModel = model),
              child: ListView(
                children: [
                  if (favorites.isNotEmpty) ...[
                    const _SectionHeader(label: 'Favorites'),
                    for (final model in favorites)
                      _ModelListTile(
                        model: model,
                        isFavorite: true,
                        onToggleFavorite: () => _toggleFavorite(model.name),
                      ),
                    const Divider(),
                  ],
                  if (others.isNotEmpty) ...[
                    if (favorites.isNotEmpty) const _SectionHeader(label: 'All Models'),
                    for (final model in others)
                      _ModelListTile(
                        model: model,
                        isFavorite: false,
                        onToggleFavorite: () => _toggleFavorite(model.name),
                      ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;

  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _ModelListTile extends StatelessWidget {
  final OllamaModel model;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;

  const _ModelListTile({
    required this.model,
    required this.isFavorite,
    required this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final capabilities = model.capabilities;

    return RadioListTile<OllamaModel>(
      value: model,
      title: Text(model.name),
      subtitle: model.parameterSize.isNotEmpty
          ? Text(
              model.parameterSize,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            )
          : null,
      secondary: Row(
        spacing: 8,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (capabilities != null) ..._buildCapabilityChips(capabilities),
          IconButton(
            icon: Icon(
              isFavorite ? Icons.star : Icons.star_border,
              color: isFavorite ? Colors.amber : null,
            ),
            tooltip: isFavorite ? 'Remove from favorites' : 'Add to favorites',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(),
            onPressed: onToggleFavorite,
          ),
        ],
      ),
    );
  }

  List<Widget> _buildCapabilityChips(ModelCapabilities capabilities) {
    final chips = <Widget>[];

    if (capabilities.vision) {
      chips.add(_CapabilityChip(
        icon: Icons.visibility_outlined,
        label: 'Vision',
      ));
    }
    if (capabilities.tools) {
      chips.add(_CapabilityChip(
        icon: Icons.build_outlined,
        label: 'Tools',
      ));
    }
    if (capabilities.thinking) {
      chips.add(_CapabilityChip(
        icon: Icons.lightbulb_outline,
        label: 'Thinking',
      ));
    }

    return chips;
  }
}

class _CapabilityChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _CapabilityChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Icon(icon, size: 22),
    );
  }
}

/// Shows a model selection bottom sheet and returns the selected model.
///
/// Returns the selected [OllamaModel], or the current model if cancelled.
Future<OllamaModel?> showModelSelectionBottomSheet({
  required BuildContext context,
  required String title,
  String? currentModelName,
}) async {
  return await showModalBottomSheet<OllamaModel?>(
    context: context,
    builder: (context) {
      return ModelSelectionBottomSheet(title: title, currentModelName: currentModelName);
    },
    isDismissible: false,
    enableDrag: false,
  );
}
