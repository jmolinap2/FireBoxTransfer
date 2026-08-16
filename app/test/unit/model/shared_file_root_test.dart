import 'package:fireboxtransfer_app/model/persistence/shared_file_root.dart';
import 'package:test/test.dart';

void main() {
  test('shared root JSON round trip keeps the private locator and permissions', () {
    const root = SharedFileRoot(
      id: 'downloads',
      name: 'Descargas',
      type: SharedFileRootType.androidSaf,
      locator: 'content://provider/tree/primary%3ADownload',
      readOnly: true,
    );

    expect(SharedFileRoot.fromJson(root.toJson()).toJson(), root.toJson());
  });

  test('legacy shared root JSON defaults to writable', () {
    final root = SharedFileRoot.fromJson({
      'id': 'documents',
      'name': 'Documents',
      'type': 'localPath',
      'locator': r'C:\Users\User\Documents',
    });

    expect(root.readOnly, isFalse);
  });

  test('rejects malformed persisted roots', () {
    expect(
      () => SharedFileRoot.fromJson({
        'id': '',
        'name': 'Documents',
        'type': 'localPath',
        'locator': r'C:\Users\User\Documents',
      }),
      throwsFormatException,
    );
    expect(
      () => SharedFileRoot.fromJson({
        'id': 'documents',
        'name': 'Documents',
        'type': 'unknown',
        'locator': r'C:\Users\User\Documents',
      }),
      throwsFormatException,
    );
    expect(
      () => SharedFileRoot.fromJson({
        'id': 'documents',
        'name': 'Documents\nInjected',
        'type': 'localPath',
        'locator': r'C:\Users\User\Documents',
      }),
      throwsFormatException,
    );
  });
}
