import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/pending_model.dart';
import '../services/pending_model_scanner.dart';

class PendingModelsPage
    extends StatefulWidget {
  final String fabulariumPath;

  const PendingModelsPage({
    super.key,
    required this.fabulariumPath,
  });

  @override
  State<PendingModelsPage> createState() =>
      _PendingModelsPageState();
}

class _PendingModelsPageState
    extends State<PendingModelsPage> {
  final PendingModelScanner
      _scanner =
      PendingModelScanner();

  bool _isLoading = true;

  String? _error;

  List<PendingModel> _models =
      [];

  @override
  void initState() {
    super.initState();

    _loadModels();
  }

  Future<void> _loadModels() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final models =
          await _scanner.scan(
        widget.fabulariumPath,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _models = models;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _openForm(
    PendingModel model,
  ) async {
    final result =
        await Navigator.of(context)
            .push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            ModelConfigFormPage(
          folderPath:
              model.folderPath,
          pendingModel: model,
        ),
      ),
    );

    if (result == true) {
      await _loadModels();
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Pending Models',
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed:
                _isLoading
                    ? null
                    : _loadModels,
            icon: const Icon(
              Icons.refresh,
            ),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child:
            CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding:
              const EdgeInsets.all(
            24,
          ),
          child: Column(
            mainAxisSize:
                MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 64,
              ),
              const SizedBox(
                height: 16,
              ),
              const Text(
                'Error Loading Models',
              ),
              const SizedBox(
                height: 8,
              ),
              Text(
                _error!,
                textAlign:
                    TextAlign.center,
              ),
              const SizedBox(
                height: 20,
              ),
              FilledButton.icon(
                onPressed:
                    _loadModels,
                icon: const Icon(
                  Icons.refresh,
                ),
                label: const Text(
                  'Try Again',
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_models.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize:
              MainAxisSize.min,
          children: [
            Icon(
              Icons
                  .check_circle_outline,
              size: 64,
            ),
            SizedBox(
              height: 16,
            ),
            Text(
              'No Pending Models Found',
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding:
              const EdgeInsets.all(
            16,
          ),
          child: Align(
            alignment:
                Alignment.centerLeft,
            child: Text(
              '${_models.length} pending model(s)',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium,
            ),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding:
                const EdgeInsets.all(
              16,
            ),
            gridDelegate:
                const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 280,
              childAspectRatio: 0.75,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount:
                _models.length,
            itemBuilder:
                (context, index) {
              return _buildModelCard(
                _models[index],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildModelCard(
    PendingModel model,
  ) {
    final image =
        model.images.isNotEmpty
            ? model.images.first
            : null;

    return Card(
      clipBehavior:
          Clip.antiAlias,
      child: InkWell(
        onTap: () =>
            _openForm(model),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: image != null
                  ? Image.file(
                      image,
                      fit: BoxFit.cover,
                      cacheWidth: 600,
                    )
                  : const Center(
                      child: Icon(
                        Icons
                            .image_outlined,
                        size: 64,
                      ),
                    ),
            ),
            Padding(
              padding:
                  const EdgeInsets.all(
                16,
              ),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                children: [
                  Text(
                    model.folderName,
                    maxLines: 2,
                    overflow:
                        TextOverflow
                            .ellipsis,
                    style:
                        const TextStyle(
                      fontWeight:
                          FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(
                    height: 6,
                  ),
                  Text(
                    model.studioName,
                  ),
                  const SizedBox(
                    height: 12,
                  ),
                  SizedBox(
                    width:
                        double.infinity,
                    child:
                        OutlinedButton
                            .icon(
                      onPressed: () =>
                          _openForm(
                        model,
                      ),
                      icon: const Icon(
                        Icons
                            .edit_outlined,
                      ),
                      label:
                          const Text(
                        'Register',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ModelConfigFormPage
    extends StatefulWidget {
  final String folderPath;

  final PendingModel?
      pendingModel;

  final Map<String, dynamic>?
      existingConfig;

  const ModelConfigFormPage({
    super.key,
    required this.folderPath,
    this.pendingModel,
    this.existingConfig,
  });

  bool get isEditing =>
      existingConfig != null;

  @override
  State<ModelConfigFormPage> createState() =>
      _ModelConfigFormPageState();
}

class _ModelConfigFormPageState
    extends State<ModelConfigFormPage> {
  final _formKey =
      GlobalKey<FormState>();

  late final TextEditingController
      _nameController;

  late final TextEditingController
      _studioController;

  late final TextEditingController
      _categoryController;

  late final TextEditingController
      _scaleController;

  late final TextEditingController
      _heightController;

  late final TextEditingController
      _tagsController;

  late final TextEditingController
      _descriptionController;

  String _type = 'statue';

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();

    final config =
        widget.existingConfig ??
            <String, dynamic>{};

    _nameController =
        TextEditingController(
      text:
          config['name']
              ?.toString() ??
          widget.pendingModel
              ?.folderName ??
          '',
    );

    _studioController =
        TextEditingController(
      text:
          config['studio']
              ?.toString() ??
          widget.pendingModel
              ?.studioName ??
          '',
    );

    _categoryController =
        TextEditingController(
      text:
          config['category']
              ?.toString() ??
          '',
    );

    _scaleController =
        TextEditingController(
      text:
          config['scale']
              ?.toString() ??
          '',
    );

    _heightController =
        TextEditingController(
      text:
          config['height']
              ?.toString() ??
          '',
    );

    final tags =
        config['tags'];

    _tagsController =
        TextEditingController(
      text: tags is List
          ? tags
              .map(
                (tag) =>
                    tag.toString(),
              )
              .join(', ')
          : '',
    );

    _descriptionController =
        TextEditingController(
      text:
          config['description']
                  ?.toString() ??
              '',
    );

    final type =
        config['type']?.toString();

    if (type != null &&
        type.isNotEmpty) {
      _type = type;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _studioController.dispose();
    _categoryController.dispose();
    _scaleController.dispose();
    _heightController.dispose();
    _tagsController.dispose();
    _descriptionController.dispose();

    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!
        .validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final config =
          Map<String, dynamic>.from(
        widget.existingConfig ??
            <String, dynamic>{},
      );

      config['name'] =
          _nameController.text.trim();

      config['studio'] =
          _studioController.text.trim();

      config['category'] =
          _categoryController.text
              .trim();

      config['type'] = _type;

      final scale =
          _scaleController.text.trim();

      if (scale.isEmpty) {
        config.remove('scale');
      } else {
        config['scale'] = scale;
      }

      final height =
          _heightController.text.trim();

      if (height.isEmpty) {
        config.remove('height');
      } else {
        config['height'] = height;
      }

      final tags = _tagsController
          .text
          .split(',')
          .map(
            (tag) => tag.trim(),
          )
          .where(
            (tag) =>
                tag.isNotEmpty,
          )
          .toList();

      if (tags.isEmpty) {
        config.remove('tags');
      } else {
        config['tags'] = tags;
      }

      final description =
          _descriptionController
              .text
              .trim();

      if (description.isEmpty) {
        config.remove(
          'description',
        );
      } else {
        config['description'] =
            description;
      }

      final configFile = File(
        p.join(
          widget.folderPath,
          'config.json',
        ),
      );

      await configFile.writeAsString(
        const JsonEncoder.withIndent(
          '  ',
        ).convert(config),
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            widget.isEditing
                ? 'Model updated successfully.'
                : 'Model registered successfully.',
          ),
        ),
      );

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isSaving = false;
      });

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            'Error saving configuration: $e',
          ),
        ),
      );
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isEditing
              ? 'Edit Model'
              : 'Register Model',
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(
            maxWidth: 700,
          ),
          child:
              SingleChildScrollView(
            padding:
                const EdgeInsets.all(
              24,
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment
                        .stretch,
                children: [
                  if (widget.pendingModel !=
                          null &&
                      widget.pendingModel!
                          .images
                          .isNotEmpty)
                    ClipRRect(
                      borderRadius:
                          BorderRadius.circular(
                        12,
                      ),
                      child: Image.file(
                        widget
                            .pendingModel!
                            .images
                            .first,
                        height: 300,
                        fit: BoxFit.contain,
                      ),
                    ),

                  const SizedBox(
                    height: 24,
                  ),

                  TextFormField(
                    controller:
                        _nameController,
                    decoration:
                        const InputDecoration(
                      labelText: 'Name',
                      border:
                          OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value ==
                              null ||
                          value
                              .trim()
                              .isEmpty) {
                        return 'Enter the model name.';
                      }

                      return null;
                    },
                  ),

                  const SizedBox(
                    height: 16,
                  ),

                  TextFormField(
                    controller:
                        _studioController,
                    decoration:
                        const InputDecoration(
                      labelText: 'Studio',
                      border:
                          OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value ==
                              null ||
                          value
                              .trim()
                              .isEmpty) {
                        return 'Enter the studio name.';
                      }

                      return null;
                    },
                  ),

                  const SizedBox(
                    height: 16,
                  ),

                  TextFormField(
                    controller:
                        _categoryController,
                    decoration:
                        const InputDecoration(
                      labelText:
                          'Category',
                      hintText:
                          'Example: One Piece',
                      border:
                          OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(
                    height: 16,
                  ),

                  DropdownButtonFormField<
                      String>(
                    initialValue:
                        _type,
                    decoration:
                        const InputDecoration(
                      labelText: 'Type',
                      border:
                          OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'statue',
                        child:
                            Text('Statue'),
                      ),
                      DropdownMenuItem(
                        value: 'bust',
                        child:
                            Text('Bust'),
                      ),
                      DropdownMenuItem(
                        value: 'miniature',
                        child:
                            Text('Miniature'),
                      ),
                      DropdownMenuItem(
                        value: 'diorama',
                        child:
                            Text('Diorama'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value ==
                          null) {
                        return;
                      }

                      setState(() {
                        _type = value;
                      });
                    },
                  ),

                  const SizedBox(
                    height: 16,
                  ),

                  Row(
                    children: [
                      Expanded(
                        child:
                            TextFormField(
                          controller:
                              _scaleController,
                          decoration:
                              const InputDecoration(
                            labelText:
                                'Scale',
                            hintText:
                                'Example: 1/6',
                            border:
                                OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(
                        width: 16,
                      ),
                      Expanded(
                        child:
                            TextFormField(
                          controller:
                              _heightController,
                          decoration:
                              const InputDecoration(
                            labelText:
                                'Height',
                            hintText:
                                'Example: 300mm',
                            border:
                                OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(
                    height: 16,
                  ),

                  TextFormField(
                    controller:
                        _tagsController,
                    decoration:
                        const InputDecoration(
                      labelText: 'Tags',
                      hintText:
                          'anime, pirate, fantasy',
                      border:
                          OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(
                    height: 16,
                  ),

                  TextFormField(
                    controller:
                        _descriptionController,
                    minLines: 4,
                    maxLines: 8,
                    decoration:
                        const InputDecoration(
                      labelText:
                          'Description',
                      alignLabelWithHint:
                          true,
                      border:
                          OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(
                    height: 32,
                  ),

                  FilledButton.icon(
                    onPressed:
                        _isSaving
                            ? null
                            : _save,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child:
                                CircularProgressIndicator(
                              strokeWidth:
                                  2,
                            ),
                          )
                        : const Icon(
                            Icons
                                .save_outlined,
                          ),
                    label: Text(
                      _isSaving
                          ? 'Saving...'
                          : widget.isEditing
                              ? 'Save Changes'
                              : 'Save Configuration',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}