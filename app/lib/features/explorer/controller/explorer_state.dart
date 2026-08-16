import 'package:fireboxtransfer_app/features/explorer/model/explorer_models.dart';

enum ExplorerLoadStatus { idle, loading, ready, error }

class ExplorerState {
  const ExplorerState({
    this.status = ExplorerLoadStatus.idle,
    this.roots = const [],
    this.activeRoot,
    this.listing,
    this.selectedPaths = const {},
    this.searchQuery = '',
    this.sortField = ExplorerSortField.name,
    this.sortDirection = ExplorerSortDirection.ascending,
    this.isMutating = false,
    this.loadError,
    this.operationError,
  });

  final ExplorerLoadStatus status;
  final List<ExplorerRoot> roots;
  final ExplorerRoot? activeRoot;
  final ExplorerDirectoryListing? listing;
  final Set<String> selectedPaths;
  final String searchQuery;
  final ExplorerSortField sortField;
  final ExplorerSortDirection sortDirection;
  final bool isMutating;
  final String? loadError;
  final String? operationError;

  ExplorerCapabilities get capabilities => listing?.capabilities ?? activeRoot?.capabilities ?? const ExplorerCapabilities.readOnly();

  List<ExplorerFileEntry> get visibleEntries {
    final normalizedQuery = searchQuery.trim().toLowerCase();
    final filtered = listing?.entries.where((entry) => normalizedQuery.isEmpty || entry.name.toLowerCase().contains(normalizedQuery)).toList() ?? [];

    filtered.sort((a, b) {
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }

      int result;
      switch (sortField) {
        case ExplorerSortField.name:
          result = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          break;
        case ExplorerSortField.size:
          result = (a.sizeBytes ?? 0).compareTo(b.sizeBytes ?? 0);
          break;
        case ExplorerSortField.modifiedAt:
          result = (a.modifiedAt ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(b.modifiedAt ?? DateTime.fromMillisecondsSinceEpoch(0));
          break;
      }

      if (result == 0) {
        result = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
      return sortDirection == ExplorerSortDirection.ascending ? result : -result;
    });

    return List.unmodifiable(filtered);
  }

  List<ExplorerFileEntry> get selectedEntries =>
      List.unmodifiable(listing?.entries.where((entry) => selectedPaths.contains(entry.path)) ?? const Iterable<ExplorerFileEntry>.empty());

  ExplorerState copyWith({
    ExplorerLoadStatus? status,
    List<ExplorerRoot>? roots,
    ExplorerRoot? activeRoot,
    bool clearActiveRoot = false,
    ExplorerDirectoryListing? listing,
    bool clearListing = false,
    Set<String>? selectedPaths,
    String? searchQuery,
    ExplorerSortField? sortField,
    ExplorerSortDirection? sortDirection,
    bool? isMutating,
    String? loadError,
    bool clearLoadError = false,
    String? operationError,
    bool clearOperationError = false,
  }) {
    return ExplorerState(
      status: status ?? this.status,
      roots: roots ?? this.roots,
      activeRoot: clearActiveRoot ? null : (activeRoot ?? this.activeRoot),
      listing: clearListing ? null : (listing ?? this.listing),
      selectedPaths: selectedPaths ?? this.selectedPaths,
      searchQuery: searchQuery ?? this.searchQuery,
      sortField: sortField ?? this.sortField,
      sortDirection: sortDirection ?? this.sortDirection,
      isMutating: isMutating ?? this.isMutating,
      loadError: clearLoadError ? null : (loadError ?? this.loadError),
      operationError: clearOperationError ? null : (operationError ?? this.operationError),
    );
  }
}
