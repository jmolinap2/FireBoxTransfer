import 'dart:async';

import 'package:fireboxtransfer_app/features/explorer/controller/explorer_controller.dart';
import 'package:fireboxtransfer_app/features/explorer/model/explorer_models.dart';
import 'package:fireboxtransfer_app/features/explorer/widgets/explorer_panel.dart';
import 'package:fireboxtransfer_app/features/explorer/widgets/explorer_strings.dart';
import 'package:flutter/material.dart';

typedef ExplorerTransferHandler = Future<void> Function(ExplorerTransferRequest request);

class DualExplorer extends StatefulWidget {
  const DualExplorer({
    required this.leftController,
    required this.leftDevice,
    required this.rightController,
    required this.rightDevice,
    this.onTransfer,
    this.operation = ExplorerTransferOperation.copy,
    this.strings = const ExplorerStrings(),
    this.autoInitialize = true,
    super.key,
  });

  final ExplorerController leftController;
  final ExplorerDevice leftDevice;
  final ExplorerController rightController;
  final ExplorerDevice rightDevice;
  final ExplorerTransferHandler? onTransfer;
  final ExplorerTransferOperation operation;
  final ExplorerStrings strings;
  final bool autoInitialize;

  @override
  State<DualExplorer> createState() => _DualExplorerState();
}

class _DualExplorerState extends State<DualExplorer> {
  bool _transferring = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.leftController.addListener(_controllerChanged);
    widget.rightController.addListener(_controllerChanged);
  }

  @override
  void didUpdateWidget(covariant DualExplorer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.leftController != widget.leftController) {
      oldWidget.leftController.removeListener(_controllerChanged);
      widget.leftController.addListener(_controllerChanged);
    }
    if (oldWidget.rightController != widget.rightController) {
      oldWidget.rightController.removeListener(_controllerChanged);
      widget.rightController.addListener(_controllerChanged);
    }
  }

  @override
  void dispose() {
    widget.leftController.removeListener(_controllerChanged);
    widget.rightController.removeListener(_controllerChanged);
    super.dispose();
  }

  void _controllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: ExplorerPanel(
                  panelId: 'left',
                  controller: widget.leftController,
                  device: widget.leftDevice,
                  strings: widget.strings,
                  autoInitialize: widget.autoInitialize,
                  enableDrag: widget.onTransfer != null && !_transferring,
                  onDrop: (payload, destination) => _handleDrop(payload: payload, destination: destination, targetPanelId: 'left'),
                ),
              ),
              _TransferRail(
                strings: widget.strings,
                leftController: widget.leftController,
                rightController: widget.rightController,
                enabled: widget.onTransfer != null && !_transferring,
                onLeftToRight: () => _transferSelection(sourcePanelId: 'left', targetPanelId: 'right'),
                onRightToLeft: () => _transferSelection(sourcePanelId: 'right', targetPanelId: 'left'),
              ),
              Expanded(
                child: ExplorerPanel(
                  panelId: 'right',
                  controller: widget.rightController,
                  device: widget.rightDevice,
                  strings: widget.strings,
                  autoInitialize: widget.autoInitialize,
                  enableDrag: widget.onTransfer != null && !_transferring,
                  onDrop: (payload, destination) => _handleDrop(payload: payload, destination: destination, targetPanelId: 'right'),
                ),
              ),
            ],
          ),
        ),
        if (_transferring) const LinearProgressIndicator(minHeight: 3),
        if (_error != null)
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.errorContainer,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              children: [
                Icon(Icons.error_outline, size: 18, color: Theme.of(context).colorScheme.onErrorContainer),
                const SizedBox(width: 8),
                Expanded(child: Text(_error!, maxLines: 2, overflow: TextOverflow.ellipsis)),
                IconButton(onPressed: () => setState(() => _error = null), icon: const Icon(Icons.close, size: 18)),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _transferSelection({required String sourcePanelId, required String targetPanelId}) async {
    final source = sourcePanelId == 'left' ? widget.leftController : widget.rightController;
    final target = targetPanelId == 'left' ? widget.leftController : widget.rightController;
    final sourceState = source.state;
    final targetState = target.state;
    final sourceRoot = sourceState.activeRoot;
    final sourceDirectory = sourceState.listing?.location;
    final targetRoot = targetState.activeRoot;
    final targetDirectory = targetState.listing?.location;
    if (sourceRoot == null || sourceDirectory == null || targetRoot == null || targetDirectory == null || sourceState.selectedEntries.isEmpty) {
      return;
    }
    await _performTransfer(
      ExplorerTransferRequest(
        sourcePanelId: sourcePanelId,
        targetPanelId: targetPanelId,
        sourceRoot: sourceRoot,
        sourceDirectory: sourceDirectory,
        entries: sourceState.selectedEntries,
        targetRoot: targetRoot,
        targetDirectory: targetDirectory,
        operation: widget.operation,
      ),
    );
  }

  Future<void> _handleDrop({required ExplorerDragPayload payload, required ExplorerDirectoryRef destination, required String targetPanelId}) async {
    final target = targetPanelId == 'left' ? widget.leftController : widget.rightController;
    final targetRoot = target.state.activeRoot;
    if (targetRoot == null) {
      return;
    }
    await _performTransfer(
      ExplorerTransferRequest(
        sourcePanelId: payload.sourcePanelId,
        targetPanelId: targetPanelId,
        sourceRoot: payload.sourceRoot,
        sourceDirectory: payload.sourceDirectory,
        entries: payload.entries,
        targetRoot: targetRoot,
        targetDirectory: destination,
        operation: widget.operation,
      ),
    );
  }

  Future<void> _performTransfer(ExplorerTransferRequest request) async {
    final handler = widget.onTransfer;
    if (handler == null || _transferring) {
      return;
    }
    setState(() {
      _transferring = true;
      _error = null;
    });
    try {
      await handler(request);
      final target = request.targetPanelId == 'left' ? widget.leftController : widget.rightController;
      await target.reload();
      if (request.operation == ExplorerTransferOperation.move) {
        final source = request.sourcePanelId == 'left' ? widget.leftController : widget.rightController;
        await source.reload();
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is Exception && error.toString().isNotEmpty ? error.toString() : widget.strings.transferFailed);
      }
    } finally {
      if (mounted) {
        setState(() => _transferring = false);
      }
    }
  }
}

class _TransferRail extends StatelessWidget {
  const _TransferRail({
    required this.strings,
    required this.leftController,
    required this.rightController,
    required this.enabled,
    required this.onLeftToRight,
    required this.onRightToLeft,
  });

  final ExplorerStrings strings;
  final ExplorerController leftController;
  final ExplorerController rightController;
  final bool enabled;
  final VoidCallback onLeftToRight;
  final VoidCallback onRightToLeft;

  @override
  Widget build(BuildContext context) {
    final canCopyRight =
        enabled &&
        leftController.state.selectedEntries.isNotEmpty &&
        rightController.state.listing != null &&
        rightController.state.capabilities.write;
    final canCopyLeft =
        enabled &&
        rightController.state.selectedEntries.isNotEmpty &&
        leftController.state.listing != null &&
        leftController.state.capabilities.write;
    return SizedBox(
      width: 48,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            key: const ValueKey('explorer-copy-right'),
            tooltip: strings.copyRight,
            onPressed: canCopyRight ? onLeftToRight : null,
            icon: const Icon(Icons.arrow_forward),
          ),
          const SizedBox(height: 8),
          IconButton(
            key: const ValueKey('explorer-copy-left'),
            tooltip: strings.copyLeft,
            onPressed: canCopyLeft ? onRightToLeft : null,
            icon: const Icon(Icons.arrow_back),
          ),
        ],
      ),
    );
  }
}
