import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/pending_model.dart';
import '../services/catalog_suggestions_service.dart';
import '../services/pending_model_scanner.dart';

class PendingModelsPage extends StatefulWidget {
  final String fabulariumPath;
  const PendingModelsPage({super.key, required this.fabulariumPath});

  @override
  State<PendingModelsPage> createState() => _PendingModelsPageState();
}

class _PendingModelsPageState extends State<PendingModelsPage> {
  final PendingModelScanner _scanner = PendingModelScanner();
  List<PendingModel> _models = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final models = await _scanner.scan(widget.fabulariumPath);
      if (!mounted) return;
      setState(() { _models = models; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _register(PendingModel pending) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ModelConfigFormPage(
          folderPath: pending.folderPath,
          existingConfig: <String, dynamic>{
            'name': pending.folderName,
            'studio': pending.studioName,
          },
        ),
      ),
    );
    if (saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pending Models'), actions: [IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh))]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _models.isEmpty
                  ? const Center(child: Text('No pending models.'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: _models.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final model = _models[i];
                        return Card(
                          child: ListTile(
                            leading: model.images.isNotEmpty
                                ? SizedBox(width: 64, height: 64, child: Image.file(model.images.first, fit: BoxFit.cover))
                                : const Icon(Icons.view_in_ar_outlined),
                            title: Text(model.folderName),
                            subtitle: Text('${model.studioName} • ${model.images.length} image(s) • ${model.archiveFiles.length} archive(s)'),
                            trailing: FilledButton.tonalIcon(onPressed: () => _register(model), icon: const Icon(Icons.add), label: const Text('Register')),
                          ),
                        );
                      },
                    ),
    );
  }
}

class ModelConfigFormPage extends StatefulWidget {
  final String folderPath;
  final Map<String, dynamic>? existingConfig;
  const ModelConfigFormPage({super.key, required this.folderPath, this.existingConfig});

  @override
  State<ModelConfigFormPage> createState() => _ModelConfigFormPageState();
}

class _ModelConfigFormPageState extends State<ModelConfigFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _studio;
  late final TextEditingController _category;
  late final TextEditingController _type;
  late final TextEditingController _scale;
  late final TextEditingController _height;
  late final TextEditingController _tags;
  late final TextEditingController _description;
  CatalogSuggestions _suggestions = const CatalogSuggestions.empty();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final c = widget.existingConfig ?? const <String, dynamic>{};
    _name = TextEditingController(text: c['name']?.toString() ?? p.basename(widget.folderPath));
    _studio = TextEditingController(text: c['studio']?.toString() ?? '');
    _category = TextEditingController(text: c['category']?.toString() ?? '');
    _type = TextEditingController(text: c['type']?.toString() ?? '');
    _scale = TextEditingController(text: c['scale']?.toString() ?? '');
    _height = TextEditingController(text: c['height']?.toString() ?? '');
    _tags = TextEditingController(text: (c['tags'] is List ? (c['tags'] as List).join(', ') : ''));
    _description = TextEditingController(text: c['description']?.toString() ?? '');
    _loadSuggestions();
  }

  Future<void> _loadSuggestions() async {
    final value = await CatalogSuggestionsService().load(widget.folderPath);
    if (mounted) setState(() => _suggestions = value);
  }

  @override
  void dispose() {
    for (final c in [_name, _studio, _category, _type, _scale, _height, _tags, _description]) { c.dispose(); }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _saving = true; _error = null; });
    try {
      final previous = Map<String, dynamic>.from(widget.existingConfig ?? const {});
      final data = <String, dynamic>{
        ...previous,
        'name': _name.text.trim(),
        'studio': _studio.text.trim(),
        'category': _category.text.trim(),
        'type': _type.text.trim(),
        'scale': _scale.text.trim(),
        'height': _height.text.trim(),
        'tags': _tags.text.split(',').map((e) => e.trim().toLowerCase()).where((e) => e.isNotEmpty).toSet().toList(),
        'description': _description.text.trim(),
      };
      final file = File(p.join(widget.folderPath, 'config.json'));
      final temp = File('${file.path}.tmp');
      const encoder = JsonEncoder.withIndent('  ');
      await temp.writeAsString(encoder.convert(data), flush: true);
      if (await file.exists()) await file.delete();
      await temp.rename(file.path);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.existingConfig == null ? 'Register Model' : 'Model Configuration')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _field('Name', _name, required: true),
            _field('Studio', _studio, required: true),
            _autoField('Category', _category, _suggestions.categories),
            _field('Type', _type),
            _autoField('Scale', _scale, _suggestions.scales),
            _field('Height', _height),
            _autoField('Tags (comma separated)', _tags, _suggestions.tags),
            TextFormField(controller: _description, maxLines: 6, decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder())),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            const SizedBox(height: 18),
            FilledButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Icons.save_outlined), label: Text(_saving ? 'Saving...' : 'Save Configuration')),
          ],
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController controller, {bool required = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        validator: required ? (v) => (v == null || v.trim().isEmpty) ? '$label is required.' : null : null,
      ),
    );
  }

  Widget _autoField(String label, TextEditingController controller, List<String> options) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: RawAutocomplete<String>(
        textEditingController: controller,
        focusNode: FocusNode(),
        optionsBuilder: (value) {
          final q = value.text.trim().toLowerCase();
          if (q.isEmpty) return const Iterable<String>.empty();
          return options.where((e) => e.toLowerCase().contains(q)).take(10);
        },
        onSelected: (value) {
          if (label.startsWith('Tags') && controller.text.contains(',')) {
            final parts = controller.text.split(',');
            parts[parts.length - 1] = ' $value';
            controller.text = parts.join(',').trimLeft();
            controller.selection = TextSelection.collapsed(offset: controller.text.length);
          } else {
            controller.text = value;
            controller.selection = TextSelection.collapsed(offset: value.length);
          }
        },
        fieldViewBuilder: (context, text, focus, submit) => TextField(
          controller: text,
          focusNode: focus,
          onSubmitted: (_) => submit(),
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        ),
        optionsViewBuilder: (context, onSelected, values) => Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240, maxWidth: 520),
              child: ListView(shrinkWrap: true, padding: EdgeInsets.zero, children: values.map((v) => ListTile(title: Text(v), onTap: () => onSelected(v))).toList()),
            ),
          ),
        ),
      ),
    );
  }
}
