import 'package:fireboxtransfer_app/model/persistence/shared_file_root.dart';
import 'package:fireboxtransfer_app/provider/shared_file_roots_provider.dart';
import 'package:fireboxtransfer_app/util/native/channel/android_channel.dart' as android;
import 'package:fireboxtransfer_app/util/native/pick_directory_path.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

class SharedRootsDialog extends StatelessWidget {
  const SharedRootsDialog({super.key});

  static Future<void> open(BuildContext context) => showDialog<void>(context: context, builder: (_) => const SharedRootsDialog());

  @override
  Widget build(BuildContext context) {
    final roots = context.watch(sharedFileRootsProvider);
    return AlertDialog(
      title: const Text('Carpetas compartidas'),
      content: SizedBox(
        width: 560,
        child: roots.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text('Añade las carpetas que podrán explorar tus dispositivos confiables.'),
              )
            : ListView.separated(
                shrinkWrap: true,
                itemCount: roots.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final root = roots[index];
                  return ListTile(
                    leading: Icon(root.type == SharedFileRootType.androidSaf ? Icons.phone_android : Icons.folder),
                    title: Text(root.name),
                    subtitle: Text(root.readOnly ? 'Solo lectura' : 'Lectura y escritura'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Tooltip(
                          message: 'Permitir modificaciones',
                          child: Switch(
                            value: !root.readOnly,
                            onChanged: (writable) async {
                              await context.ref
                                  .redux(sharedFileRootsProvider)
                                  .dispatchAsync(
                                    UpdateSharedFileRootAction(root.copyWith(readOnly: !writable)),
                                  );
                            },
                          ),
                        ),
                        IconButton(
                          tooltip: 'Dejar de compartir',
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () async {
                            if (root.type == SharedFileRootType.androidSaf) {
                              await android.releaseSharedRootAndroid(root.locator);
                            }
                            if (context.mounted) {
                              await context.ref.redux(sharedFileRootsProvider).dispatchAsync(RemoveSharedFileRootAction(root.id));
                            }
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
        FilledButton.icon(
          onPressed: () => _addRoot(context),
          icon: const Icon(Icons.add),
          label: const Text('Añadir carpeta'),
        ),
      ],
    );
  }

  Future<void> _addRoot(BuildContext context) async {
    final SharedFileRoot? root;
    if (defaultTargetPlatform == TargetPlatform.android) {
      final selected = await android.pickSharedRootAndroid();
      root = selected == null
          ? null
          : SharedFileRoot(
              id: const Uuid().v4(),
              name: selected.name,
              type: SharedFileRootType.androidSaf,
              locator: selected.uri,
              readOnly: !selected.canWrite,
            );
    } else {
      final selected = await pickDirectoryPath();
      root = selected == null
          ? null
          : SharedFileRoot(
              id: const Uuid().v4(),
              name: selected.replaceAll('\\', '/').split('/').where((part) => part.isNotEmpty).lastOrNull ?? selected,
              type: SharedFileRootType.localPath,
              locator: selected,
              readOnly: false,
            );
    }
    if (root != null && context.mounted) {
      await context.ref.redux(sharedFileRootsProvider).dispatchAsync(AddSharedFileRootAction(root));
    }
  }
}

extension<T> on Iterable<T> {
  T? get lastOrNull => isEmpty ? null : last;
}
