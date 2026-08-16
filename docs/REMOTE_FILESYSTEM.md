# Remote File System de FireBoxTransfer

Este documento describe la implementación de las fases 2 y 3. La API amplía
el servidor compatible con LocalSend; no modifica los endpoints existentes.

## Estado de implementación — 2026-08-12

Implementado:

- contrato Remote FS y validación de protocolo en Rust;
- servidor HTTPS/mTLS y cliente con pinning de certificado;
- autorización dinámica por dispositivo confiable y raíz compartida;
- proveedores de escritorio y Android SAF;
- bindings FRB y streams binarios con backpressure;
- cliente remoto Flutter y adaptador común de filesystem;
- explorador dual de escritorio, explorador móvil con selector, operaciones
  por capacidades y transferencias directas por streaming;
- selección de dispositivo remoto, modo Copiar/Mover, drag & drop entre
  paneles y entrada desde el Explorador de Windows;
- persistencia y administración de raíces compartidas de solo lectura o
  lectura/escritura.

En verificación al redactar este estado:

- análisis y pruebas globales Dart/Flutter después de integrar todas las
  capas concurrentes;
- compilación Android/Kotlin y APK;
- compilación Windows;
- recorrido real Windows ↔ Android con una raíz SAF autorizada.

Este estado no declara cerradas las fases mientras las verificaciones
anteriores no tengan un resultado registrado. No se han creado commits.

## Modelo de seguridad

- La API solo se habilita cuando el servidor usa HTTPS.
- Cada petición requiere un certificado de cliente verificado por mTLS.
- La identidad efectiva es el SHA-256 del certificado, no la IP ni el
  `fingerprint` declarado en un JSON.
- El cliente presenta su certificado y fija el certificado del servidor antes
  de enviar una petición.
- Solo los fingerprints guardados como dispositivos confiables pueden acceder.
- Quitar un dispositivo de confianza o dejar de compartir una raíz actualiza
  la autorización del servidor sin reiniciarlo.

Las rutas nativas y los URI de SAF son datos privados del dispositivo. En la
red solo aparecen un identificador opaco de raíz y una ruta relativa validada.
Se rechazan rutas absolutas, `.`/`..`, separadores ambiguos, caracteres de
control y operaciones sobre la raíz compartida.

## API

Base: `/api/fireboxtransfer/v1`

| Método | Ruta | Operación |
| --- | --- | --- |
| `GET` | `/roots` | Raíces autorizadas y capacidades |
| `GET` | `/files` | Listado paginado |
| `GET` | `/files/metadata` | Metadatos |
| `POST` | `/files/directory` | Crear carpeta |
| `POST` | `/files/rename` | Renombrar |
| `POST` | `/files/move` | Mover |
| `DELETE` | `/files` | Eliminar |
| `GET` | `/files/content` | Lectura por streaming |
| `PUT` | `/files/content` | Escritura por streaming |

Copiar se construye con lectura y escritura por streaming. Esto mantiene la
misma semántica entre proveedores y permite copiar también entre dos
dispositivos sin exponer rutas del host.

Las respuestas de error usan códigos estables y mensajes seguros. Las
excepciones del proveedor, rutas nativas y URI nunca se devuelven al peer.

## Proveedores

### Windows y otros escritorios

Las carpetas se eligen explícitamente. La resolución comprueba confinamiento
léxico y real, rechaza symlinks/junctions que escapen de la raíz y aplica las
capacidades de solo lectura o lectura/escritura antes de cada operación.

### Android

Se usa Storage Access Framework con un permiso persistente por árbol. Los URI
se tratan como capacidades opacas y cada documento se valida contra un árbol
registrado. Las operaciones se ejecutan fuera del hilo de interfaz. Los file
descriptors de lectura y escritura pasan a Rust, que asume su propiedad y los
cierra al terminar.

## Streaming

El cuerpo de un archivo no se materializa completo en Dart ni en Rust. Los
canales binarios son acotados, aplican backpressure y validan el número exacto
de bytes. Las escrituras requieren `Content-Length` y respetan el límite de
tamaño configurado por el servidor.

## Explorer

La UI consume una única interfaz de filesystem para proveedores locales,
Android SAF y dispositivos remotos.

- Escritorio: dos paneles persistentes, origen/destino y ruta visibles,
  selección múltiple, flechas y drag & drop entre paneles.
- Móvil: un panel con selector `Este teléfono / dispositivo remoto`.
- Crear, renombrar y eliminar respetan las capacidades anunciadas; eliminar
  requiere una confirmación contextual con dispositivo y elemento.

La cola resiliente, pausa, reintento, resume, velocidad y ETA pertenecen a la
fase 4. El flujo de las fases 2 y 3 conserva streaming y backpressure, pero no
pretende reemplazar todavía al futuro Transfer Manager.

## Verificación mínima

Antes de considerar cerradas estas fases deben pasar:

- pruebas de integración del protocolo Rust;
- pruebas del bridge y sus streams;
- análisis y pruebas Flutter del paquete de isolates y de la app;
- compilación Kotlin del APK;
- compilación Windows;
- prueba real Windows ↔ Android con una raíz SAF autorizada en cada sentido.
