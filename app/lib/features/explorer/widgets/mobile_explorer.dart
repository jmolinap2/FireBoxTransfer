import 'package:fireboxtransfer_app/features/explorer/controller/explorer_controller.dart';
import 'package:fireboxtransfer_app/features/explorer/model/explorer_models.dart';
import 'package:fireboxtransfer_app/features/explorer/widgets/explorer_panel.dart';
import 'package:fireboxtransfer_app/features/explorer/widgets/explorer_strings.dart';
import 'package:flutter/material.dart';

class MobileExplorerSource {
  const MobileExplorerSource({required this.id, required this.label, required this.device, required this.controller});

  final String id;
  final String label;
  final ExplorerDevice device;
  final ExplorerController controller;
}

class MobileExplorer extends StatefulWidget {
  const MobileExplorer({
    required this.sources,
    this.initialSourceId,
    this.strings = const ExplorerStrings(),
    this.autoInitialize = true,
    this.onOpenFile,
    super.key,
  });

  final List<MobileExplorerSource> sources;
  final String? initialSourceId;
  final ExplorerStrings strings;
  final bool autoInitialize;
  final ExplorerFileOpenHandler? onOpenFile;

  @override
  State<MobileExplorer> createState() => _MobileExplorerState();
}

class _MobileExplorerState extends State<MobileExplorer> {
  String? _selectedSourceId;

  @override
  void initState() {
    super.initState();
    _selectedSourceId = _resolveInitialSourceId();
  }

  @override
  void didUpdateWidget(covariant MobileExplorer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.sources.any((source) => source.id == _selectedSourceId)) {
      _selectedSourceId = _resolveInitialSourceId();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sources.isEmpty) {
      return Center(child: Text(widget.strings.noAuthorizedRoots));
    }
    final selectedSource = widget.sources.firstWhere((source) => source.id == _selectedSourceId, orElse: () => widget.sources.first);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: DropdownButtonFormField<String>(
            key: const ValueKey('mobile-explorer-source-selector'),
            initialValue: selectedSource.id,
            decoration: InputDecoration(labelText: widget.strings.selectLocation, prefixIcon: const Icon(Icons.devices)),
            items: widget.sources.map((source) => DropdownMenuItem(value: source.id, child: Text(source.label))).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedSourceId = value);
              }
            },
          ),
        ),
        Expanded(
          child: ExplorerPanel(
            key: ValueKey('mobile-explorer-${selectedSource.id}'),
            panelId: 'mobile-${selectedSource.id}',
            controller: selectedSource.controller,
            device: selectedSource.device,
            strings: widget.strings,
            compact: true,
            openDirectoriesOnSingleTap: true,
            autoInitialize: widget.autoInitialize,
            onOpenFile: widget.onOpenFile,
          ),
        ),
      ],
    );
  }

  String? _resolveInitialSourceId() {
    if (widget.initialSourceId != null && widget.sources.any((source) => source.id == widget.initialSourceId)) {
      return widget.initialSourceId;
    }
    return widget.sources.firstOrNull?.id;
  }
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
