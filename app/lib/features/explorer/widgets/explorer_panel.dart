import 'dart:async';

import 'package:fireboxtransfer_app/features/explorer/controller/explorer_controller.dart';
import 'package:fireboxtransfer_app/features/explorer/controller/explorer_state.dart';
import 'package:fireboxtransfer_app/features/explorer/model/explorer_models.dart';
import 'package:fireboxtransfer_app/features/explorer/widgets/explorer_strings.dart';
import 'package:flutter/material.dart';

typedef ExplorerDropHandler = Future<void> Function(ExplorerDragPayload payload, ExplorerDirectoryRef destination);
typedef ExplorerFileOpenHandler = void Function(ExplorerFileEntry entry, ExplorerRoot root);

class ExplorerPanel extends StatefulWidget {
  const ExplorerPanel({
    required this.panelId,
    required this.controller,
    required this.device,
    this.strings = const ExplorerStrings(),
    this.compact = false,
    this.openDirectoriesOnSingleTap = false,
    this.autoInitialize = true,
    this.showDeviceHeader = true,
    this.enableDrag = false,
    this.allowMutations = true,
    this.onDrop,
    this.onOpenFile,
    super.key,
  });

  final String panelId;
  final ExplorerController controller;
  final ExplorerDevice device;
  final ExplorerStrings strings;
  final bool compact;
  final bool openDirectoriesOnSingleTap;
  final bool autoInitialize;
  final bool showDeviceHeader;
  final bool enableDrag;
  final bool allowMutations;
  final ExplorerDropHandler? onDrop;
  final ExplorerFileOpenHandler? onOpenFile;

  @override
  State<ExplorerPanel> createState() => _ExplorerPanelState();
}

class _ExplorerPanelState extends State<ExplorerPanel> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.controller.state.searchQuery);
    if (widget.autoInitialize) {
      _initializeAfterBuild();
    }
  }

  @override
  void didUpdateWidget(covariant ExplorerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _searchController.text = widget.controller.state.searchQuery;
      if (widget.autoInitialize) {
        _initializeAfterBuild();
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _initializeAfterBuild() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(widget.controller.initialize());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final state = widget.controller.state;
        if (_searchController.text != state.searchQuery) {
          _searchController.value = TextEditingValue(
            text: state.searchQuery,
            selection: TextSelection.collapsed(offset: state.searchQuery.length),
          );
        }

        return _PanelDropTarget(
          panelId: widget.panelId,
          destination: state.listing?.location,
          canWrite: state.capabilities.write,
          onDrop: widget.onDrop,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(10),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Column(
                children: [
                  if (widget.showDeviceHeader) _DeviceHeader(device: widget.device, strings: widget.strings, storage: state.listing?.storage),
                  _NavigationToolbar(
                    state: state,
                    controller: widget.controller,
                    strings: widget.strings,
                    allowMutations: widget.allowMutations,
                    onCreateDirectory: _createDirectory,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                    child: TextField(
                      key: ValueKey('explorer-search-${widget.panelId}'),
                      controller: _searchController,
                      onChanged: widget.controller.setSearchQuery,
                      decoration: InputDecoration(
                        hintText: widget.strings.searchHint,
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: state.searchQuery.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Limpiar',
                                onPressed: () {
                                  _searchController.clear();
                                  widget.controller.setSearchQuery('');
                                },
                                icon: const Icon(Icons.close, size: 18),
                              ),
                        isDense: true,
                      ),
                    ),
                  ),
                  _ColumnHeader(state: state, controller: widget.controller, strings: widget.strings, compact: widget.compact),
                  if (state.status == ExplorerLoadStatus.loading && state.listing != null) const LinearProgressIndicator(minHeight: 2),
                  if (state.loadError != null && state.listing != null)
                    _InlineError(message: state.loadError!, retryLabel: widget.strings.retry, onRetry: widget.controller.reload),
                  Expanded(
                    child: _ExplorerContent(
                      panelId: widget.panelId,
                      state: state,
                      controller: widget.controller,
                      strings: widget.strings,
                      compact: widget.compact,
                      openDirectoriesOnSingleTap: widget.openDirectoriesOnSingleTap,
                      enableDrag: widget.enableDrag,
                      onDrop: widget.onDrop,
                      onOpenFile: widget.onOpenFile,
                    ),
                  ),
                  if (state.selectedPaths.isNotEmpty)
                    _SelectionBar(
                      state: state,
                      strings: widget.strings,
                      allowMutations: widget.allowMutations,
                      onClear: widget.controller.clearSelection,
                      onRename: _renameSelected,
                      onDelete: _deleteSelected,
                    ),
                  _StorageFooter(storage: state.listing?.storage),
                  if (state.isMutating) const LinearProgressIndicator(minHeight: 2),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _createDirectory() async {
    final name = await _showNameDialog(title: widget.strings.newFolder, actionLabel: widget.strings.create);
    if (name == null || !mounted) {
      return;
    }
    await widget.controller.createDirectory(name);
    _showOperationError();
  }

  Future<void> _renameSelected() async {
    final entry = widget.controller.state.selectedEntries.singleOrNull;
    if (entry == null) {
      return;
    }
    final name = await _showNameDialog(title: widget.strings.rename, actionLabel: widget.strings.rename, initialValue: entry.name);
    if (name == null || !mounted) {
      return;
    }
    await widget.controller.renameEntry(entry, name);
    _showOperationError();
  }

  Future<void> _deleteSelected() async {
    final entries = widget.controller.state.selectedEntries;
    if (entries.isEmpty) {
      return;
    }
    final subject = entries.length == 1 ? '“${entries.first.name}”' : '${entries.length} elementos';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${widget.strings.delete} $subject'),
        content: Text('Esta acción eliminará $subject de ${widget.device.name}. No se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(widget.strings.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(widget.strings.delete)),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await widget.controller.deleteEntries(entries);
    _showOperationError();
  }

  Future<String?> _showNameDialog({required String title, required String actionLabel, String initialValue = ''}) async {
    final nameController = TextEditingController(text: initialValue);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: nameController,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              Navigator.pop(context, value);
            }
          },
          decoration: InputDecoration(labelText: widget.strings.name),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(widget.strings.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, nameController.text), child: Text(actionLabel)),
        ],
      ),
    );
    nameController.dispose();
    return result;
  }

  void _showOperationError() {
    if (!mounted) {
      return;
    }
    final error = widget.controller.state.operationError;
    if (error == null) {
      return;
    }
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(error)));
    widget.controller.clearOperationError();
  }
}

class _DeviceHeader extends StatelessWidget {
  const _DeviceHeader({required this.device, required this.strings, required this.storage});

  final ExplorerDevice device;
  final ExplorerStrings strings;
  final ExplorerStorageInfo? storage;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = switch (device.connectionStatus) {
      ExplorerConnectionStatus.local || ExplorerConnectionStatus.connected => Colors.green,
      ExplorerConnectionStatus.connecting => Colors.orange,
      ExplorerConnectionStatus.offline => colorScheme.outline,
    };
    return Container(
      key: ValueKey('explorer-device-${device.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: colorScheme.surfaceContainerLow,
      child: Row(
        children: [
          Icon(_platformIcon(device.platform), size: 24, color: colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(device.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        strings.connection(device.connectionStatus),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (storage != null)
            Text(
              '${_formatBytes(storage!.freeBytes)} libres',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

class _NavigationToolbar extends StatelessWidget {
  const _NavigationToolbar({
    required this.state,
    required this.controller,
    required this.strings,
    required this.allowMutations,
    required this.onCreateDirectory,
  });

  final ExplorerState state;
  final ExplorerController controller;
  final ExplorerStrings strings;
  final bool allowMutations;
  final VoidCallback onCreateDirectory;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
      child: Row(
        children: [
          IconButton(tooltip: strings.goUp, onPressed: controller.canGoUp ? controller.goUp : null, icon: const Icon(Icons.arrow_upward, size: 20)),
          if (state.roots.length > 1)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  key: const ValueKey('explorer-root-selector'),
                  value: state.activeRoot?.id,
                  isExpanded: true,
                  items: state.roots
                      .map(
                        (root) => DropdownMenuItem(
                          value: root.id,
                          child: Text(root.label, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: state.status == ExplorerLoadStatus.loading ? null : (value) => value == null ? null : controller.selectRoot(value),
                ),
              ),
            )
          else if (state.activeRoot != null)
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(state.activeRoot!.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelLarge),
              ),
            ),
          const Icon(Icons.chevron_right, size: 18),
          Expanded(
            child: Tooltip(
              message: state.listing?.location.displayPath ?? '',
              child: Text(
                state.listing?.location.displayPath ?? '—',
                key: const ValueKey('explorer-current-path'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          if (allowMutations && state.capabilities.createDirectory)
            IconButton(
              tooltip: strings.newFolder,
              onPressed: state.isMutating ? null : onCreateDirectory,
              icon: const Icon(Icons.create_new_folder_outlined, size: 20),
            ),
          IconButton(
            tooltip: strings.refresh,
            onPressed: state.status == ExplorerLoadStatus.loading ? null : controller.reload,
            icon: const Icon(Icons.refresh, size: 20),
          ),
        ],
      ),
    );
  }
}

class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader({required this.state, required this.controller, required this.strings, required this.compact});

  final ExplorerState state;
  final ExplorerController controller;
  final ExplorerStrings strings;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Row(
        children: [
          const SizedBox(width: 34),
          Expanded(
            child: _SortButton(label: strings.name, field: ExplorerSortField.name, state: state, controller: controller, style: style),
          ),
          SizedBox(
            width: compact ? 76 : 92,
            child: _SortButton(
              label: strings.size,
              field: ExplorerSortField.size,
              state: state,
              controller: controller,
              style: style,
              alignment: Alignment.centerRight,
            ),
          ),
          if (!compact)
            SizedBox(
              width: 126,
              child: _SortButton(
                label: strings.modified,
                field: ExplorerSortField.modifiedAt,
                state: state,
                controller: controller,
                style: style,
                alignment: Alignment.centerRight,
              ),
            ),
        ],
      ),
    );
  }
}

class _SortButton extends StatelessWidget {
  const _SortButton({
    required this.label,
    required this.field,
    required this.state,
    required this.controller,
    required this.style,
    this.alignment = Alignment.centerLeft,
  });

  final String label;
  final ExplorerSortField field;
  final ExplorerState state;
  final ExplorerController controller;
  final TextStyle? style;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final active = state.sortField == field;
    return InkWell(
      onTap: () => controller.setSort(field),
      child: Align(
        alignment: alignment,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(label, overflow: TextOverflow.ellipsis, style: style),
            ),
            if (active) Icon(state.sortDirection == ExplorerSortDirection.ascending ? Icons.arrow_upward : Icons.arrow_downward, size: 12),
          ],
        ),
      ),
    );
  }
}

class _ExplorerContent extends StatelessWidget {
  const _ExplorerContent({
    required this.panelId,
    required this.state,
    required this.controller,
    required this.strings,
    required this.compact,
    required this.openDirectoriesOnSingleTap,
    required this.enableDrag,
    required this.onDrop,
    required this.onOpenFile,
  });

  final String panelId;
  final ExplorerState state;
  final ExplorerController controller;
  final ExplorerStrings strings;
  final bool compact;
  final bool openDirectoriesOnSingleTap;
  final bool enableDrag;
  final ExplorerDropHandler? onDrop;
  final ExplorerFileOpenHandler? onOpenFile;

  @override
  Widget build(BuildContext context) {
    if (state.listing == null && state.status == ExplorerLoadStatus.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.listing == null && state.status == ExplorerLoadStatus.error) {
      return _FullError(message: state.loadError ?? strings.noAuthorizedRoots, retryLabel: strings.retry, onRetry: controller.initialize);
    }
    final entries = state.visibleEntries;
    if (entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(state.searchQuery.isEmpty ? Icons.folder_open : Icons.search_off, size: 44, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 10),
              Text(state.searchQuery.isEmpty ? strings.emptyFolder : strings.noSearchResults, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      key: PageStorageKey('explorer-list-$panelId-${state.listing!.location.path}'),
      itemCount: entries.length,
      itemExtent: compact ? 54 : 46,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final row = _ExplorerEntryRow(
          panelId: panelId,
          entry: entry,
          selected: state.selectedPaths.contains(entry.path),
          compact: compact,
          onTap: () {
            if (state.selectedPaths.isNotEmpty) {
              controller.selectEntry(entry, toggle: true);
            } else if (openDirectoriesOnSingleTap && entry.isDirectory) {
              unawaited(controller.openDirectory(entry));
            } else if (openDirectoriesOnSingleTap && !entry.isDirectory && state.activeRoot != null) {
              onOpenFile?.call(entry, state.activeRoot!);
            } else {
              controller.selectEntry(entry);
            }
          },
          onDoubleTap: () {
            if (entry.isDirectory) {
              unawaited(controller.openDirectory(entry));
            } else if (state.activeRoot != null) {
              onOpenFile?.call(entry, state.activeRoot!);
            }
          },
          onLongPress: () => controller.selectEntry(entry, toggle: true),
          canAcceptDrop: state.capabilities.write,
          onDrop: onDrop,
          destination: entry.isDirectory
              ? ExplorerDirectoryRef(
                  rootId: state.activeRoot!.id,
                  path: entry.path,
                  displayPath: entry.name,
                  parentPath: state.listing!.location.path,
                )
              : null,
        );

        if (!enableDrag || state.activeRoot == null) {
          return row;
        }
        final payload = ExplorerDragPayload(
          sourcePanelId: panelId,
          sourceRoot: state.activeRoot!,
          sourceDirectory: state.listing!.location,
          entries: controller.dragEntriesFor(entry),
        );
        return Draggable<ExplorerDragPayload>(
          data: payload,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          onDragStarted: () => controller.selectEntry(entry),
          feedback: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(_entryIcon(entry), size: 20), const SizedBox(width: 8), Text(entry.name)]),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.45, child: row),
          child: row,
        );
      },
    );
  }
}

class _ExplorerEntryRow extends StatelessWidget {
  const _ExplorerEntryRow({
    required this.panelId,
    required this.entry,
    required this.selected,
    required this.compact,
    required this.onTap,
    required this.onDoubleTap,
    required this.onLongPress,
    required this.canAcceptDrop,
    required this.onDrop,
    required this.destination,
  });

  final String panelId;
  final ExplorerFileEntry entry;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final VoidCallback onLongPress;
  final bool canAcceptDrop;
  final ExplorerDropHandler? onDrop;
  final ExplorerDirectoryRef? destination;

  @override
  Widget build(BuildContext context) {
    Widget row = Material(
      color: selected ? Theme.of(context).colorScheme.primaryContainer : Colors.transparent,
      child: InkWell(
        key: ValueKey('explorer-entry-$panelId-${entry.id}'),
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              SizedBox(
                width: 34,
                child: Icon(_entryIcon(entry), size: 21, color: entry.isDirectory ? Colors.amber.shade700 : Theme.of(context).colorScheme.primary),
              ),
              Expanded(
                child: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5)),
              ),
              SizedBox(
                width: compact ? 76 : 92,
                child: Text(
                  entry.isDirectory || entry.sizeBytes == null ? '—' : _formatBytes(entry.sizeBytes!),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (!compact)
                SizedBox(
                  width: 126,
                  child: Text(
                    _formatDate(entry.modifiedAt),
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    if (destination != null) {
      row = _PanelDropTarget(panelId: panelId, destination: destination, canWrite: canAcceptDrop, onDrop: onDrop, child: row);
    }
    return row;
  }
}

class _PanelDropTarget extends StatelessWidget {
  const _PanelDropTarget({required this.panelId, required this.destination, required this.canWrite, required this.onDrop, required this.child});

  final String panelId;
  final ExplorerDirectoryRef? destination;
  final bool canWrite;
  final ExplorerDropHandler? onDrop;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DragTarget<ExplorerDragPayload>(
      onWillAcceptWithDetails: (details) => _accepts(details.data),
      onAcceptWithDetails: (details) {
        final target = destination;
        if (target != null && _accepts(details.data)) {
          unawaited(onDrop!(details.data, target));
        }
      },
      builder: (context, candidates, _) {
        final active = candidates.any(_accepts);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: active
              ? BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.55),
                  border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2),
                  borderRadius: BorderRadius.circular(8),
                )
              : null,
          child: child,
        );
      },
    );
  }

  bool _accepts(ExplorerDragPayload? payload) =>
      payload != null && destination != null && canWrite && onDrop != null && !payload.entries.any((entry) => entry.path == destination!.path);
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.state,
    required this.strings,
    required this.allowMutations,
    required this.onClear,
    required this.onRename,
    required this.onDelete,
  });

  final ExplorerState state;
  final ExplorerStrings strings;
  final bool allowMutations;
  final VoidCallback onClear;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.secondaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(tooltip: strings.cancel, onPressed: onClear, icon: const Icon(Icons.close, size: 19)),
          Expanded(child: Text('${state.selectedPaths.length} ${strings.selected}', style: Theme.of(context).textTheme.labelMedium)),
          if (allowMutations && state.selectedEntries.length == 1 && (state.selectedEntries.single.capabilities?.rename ?? state.capabilities.rename))
            IconButton(
              tooltip: strings.rename,
              onPressed: state.isMutating ? null : onRename,
              icon: const Icon(Icons.drive_file_rename_outline, size: 20),
            ),
          if (allowMutations && state.selectedEntries.every((entry) => entry.capabilities?.delete ?? state.capabilities.delete))
            IconButton(tooltip: strings.delete, onPressed: state.isMutating ? null : onDelete, icon: const Icon(Icons.delete_outline, size: 20)),
        ],
      ),
    );
  }
}

class _StorageFooter extends StatelessWidget {
  const _StorageFooter({required this.storage});

  final ExplorerStorageInfo? storage;

  @override
  Widget build(BuildContext context) {
    if (storage == null) {
      return const SizedBox(height: 8);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: storage!.usedFraction,
                minHeight: 5,
                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text('${_formatBytes(storage!.usedBytes)} de ${_formatBytes(storage!.totalBytes)}', style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.retryLabel, required this.onRetry});

  final String message;
  final String retryLabel;
  final Future<bool> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialBanner(
      content: Text(message, maxLines: 2, overflow: TextOverflow.ellipsis),
      leading: const Icon(Icons.wifi_off),
      actions: [TextButton(onPressed: () => unawaited(onRetry()), child: Text(retryLabel))],
    );
  }
}

class _FullError extends StatelessWidget {
  const _FullError({required this.message, required this.retryLabel, required this.onRetry});

  final String message;
  final String retryLabel;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_off_outlined, size: 46, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: () => unawaited(onRetry()), icon: const Icon(Icons.refresh), label: Text(retryLabel)),
          ],
        ),
      ),
    );
  }
}

IconData _platformIcon(ExplorerPlatformKind platform) => switch (platform) {
  ExplorerPlatformKind.windows => Icons.computer,
  ExplorerPlatformKind.android => Icons.phone_android,
  ExplorerPlatformKind.linux => Icons.computer,
  ExplorerPlatformKind.macos => Icons.laptop_mac,
  ExplorerPlatformKind.ios => Icons.phone_iphone,
  ExplorerPlatformKind.unknown => Icons.devices_other,
};

IconData _entryIcon(ExplorerFileEntry entry) {
  if (entry.isDirectory) {
    return Icons.folder;
  }
  final mime = entry.mimeType ?? '';
  if (mime.startsWith('image/')) return Icons.image_outlined;
  if (mime.startsWith('video/')) return Icons.movie_outlined;
  if (mime.startsWith('audio/')) return Icons.audio_file_outlined;
  if (mime == 'application/pdf') return Icons.picture_as_pdf_outlined;
  if (mime.contains('zip') || mime.contains('archive') || mime.contains('compressed')) return Icons.archive_outlined;
  return Icons.insert_drive_file_outlined;
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final decimals = value >= 100 ? 0 : (value >= 10 ? 1 : 2);
  return '${value.toStringAsFixed(decimals)} ${units[unit]}';
}

String _formatDate(DateTime? value) {
  if (value == null) return '—';
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${twoDigits(value.month)}-${twoDigits(value.day)} ${twoDigits(value.hour)}:${twoDigits(value.minute)}';
}

extension<T> on Iterable<T> {
  T? get singleOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) return null;
    final result = iterator.current;
    return iterator.moveNext() ? null : result;
  }
}
