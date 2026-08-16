import 'package:fireboxtransfer_app/features/explorer/model/explorer_models.dart';

class ExplorerStrings {
  const ExplorerStrings({
    this.searchHint = 'Buscar en esta carpeta',
    this.emptyFolder = 'Esta carpeta está vacía',
    this.noSearchResults = 'No hay resultados en esta carpeta',
    this.noAuthorizedRoots = 'No hay ubicaciones autorizadas',
    this.retry = 'Reintentar',
    this.goUp = 'Subir',
    this.refresh = 'Actualizar',
    this.newFolder = 'Nueva carpeta',
    this.rename = 'Renombrar',
    this.delete = 'Eliminar',
    this.cancel = 'Cancelar',
    this.create = 'Crear',
    this.name = 'Nombre',
    this.size = 'Tamaño',
    this.modified = 'Modificado',
    this.selectLocation = 'Ubicación',
    this.selected = 'seleccionado(s)',
    this.copyRight = 'Copiar al dispositivo de la derecha',
    this.copyLeft = 'Copiar al dispositivo de la izquierda',
    this.transferFailed = 'No se pudo completar la transferencia.',
  });

  final String searchHint;
  final String emptyFolder;
  final String noSearchResults;
  final String noAuthorizedRoots;
  final String retry;
  final String goUp;
  final String refresh;
  final String newFolder;
  final String rename;
  final String delete;
  final String cancel;
  final String create;
  final String name;
  final String size;
  final String modified;
  final String selectLocation;
  final String selected;
  final String copyRight;
  final String copyLeft;
  final String transferFailed;

  String connection(ExplorerConnectionStatus status) => switch (status) {
    ExplorerConnectionStatus.local => 'Este dispositivo',
    ExplorerConnectionStatus.connecting => 'Conectando',
    ExplorerConnectionStatus.connected => 'Conectado',
    ExplorerConnectionStatus.offline => 'Sin conexión',
  };
}
