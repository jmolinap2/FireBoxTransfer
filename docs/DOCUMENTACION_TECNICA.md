# FireBoxTransfer — Documentación técnica

**Estado:** Propuesta inicial  
**Base:** Fork de LocalSend  
**Objetivo:** aplicación multiplataforma para explorar, administrar y transferir archivos entre PC y móvil dentro de la misma red local, sin nube y sin cuentas.

---

## 1. Principios técnicos

1. **Local-first:** las operaciones de archivos y transferencias deben ocurrir dentro de la LAN.
2. **Sin dependencia de cuentas:** el emparejamiento será entre dispositivos, no entre identidades en la nube.
3. **Fork controlado:** conservar del fork únicamente las capacidades que aporten valor al producto.
4. **Separación de responsabilidades:** UI, aplicación, protocolo y motor de transferencia deben mantenerse desacoplados.
5. **Seguridad por defecto:** conexiones cifradas y autorización explícita por dispositivo.
6. **Rendimiento medible:** evitar cargar archivos completos en memoria; utilizar streaming para archivos grandes.
7. **Compatibilidad progresiva:** prioridad inicial Windows + Android; otras plataformas después.

---

## 2. Base tecnológica

LocalSend es una base adecuada porque ya resuelve transferencia local, descubrimiento de dispositivos y comunicación entre múltiples plataformas.

### Stack base

| Capa | Tecnología propuesta |
|---|---|
| UI multiplataforma | Flutter |
| Lenguaje principal | Dart |
| Gestión de estado heredada | Refena |
| Transferencia de alto rendimiento | Rust donde aporte una mejora real |
| Interoperabilidad Dart/Rust | FFI / bindings existentes en el fork |
| Comunicación | HTTP/HTTPS local |
| Descubrimiento | mecanismos compatibles con el protocolo LocalSend |
| Android | Flutter + APIs nativas cuando sean necesarias |
| Windows | Flutter Desktop + integración nativa puntual |
| Persistencia local | almacenamiento ligero; SQLite solo si el modelo lo justifica |

> No se debe reescribir el motor de LocalSend inicialmente. Primero se debe identificar qué componentes pueden conservarse sin modificar.

---

## 3. Arquitectura objetivo

```text
┌──────────────────────────────────────────┐
│                PRESENTACIÓN              │
│ Flutter UI                               │
│ Explorador dual / Transferencias / Setup │
└──────────────────────┬───────────────────┘
                       │
┌──────────────────────▼───────────────────┐
│               APLICACIÓN                 │
│ Casos de uso / Estado / Validaciones     │
│ Devices / Files / Transfers / Pairing    │
└──────────────────────┬───────────────────┘
                       │
┌──────────────────────▼───────────────────┐
│                 DOMINIO                  │
│ Device / RemotePath / Transfer / Session │
│ Reglas independientes de UI y transporte │
└──────────────┬────────────────┬──────────┘
               │                │
┌──────────────▼───────┐ ┌──────▼─────────────┐
│ INFRAESTRUCTURA LAN  │ │ FILE SYSTEM        │
│ Discovery / HTTPS    │ │ Local + Remote     │
│ Pairing / Sessions   │ │ Android / Windows  │
└──────────────┬───────┘ └──────┬─────────────┘
               │                │
               └────────┬───────┘
                        ▼
              ┌──────────────────┐
              │ TRANSFER ENGINE  │
              │ Dart/Rust        │
              │ streaming        │
              │ chunks*          │
              │ checksum*        │
              │ resume*          │
              └──────────────────┘
```

`*` Funcionalidad propia a implementar o ampliar; no asumir que LocalSend ya ofrece el comportamiento requerido.

---

## 4. Módulos

### 4.1 Device Discovery

Responsabilidades:

- detectar dispositivos compatibles en LAN;
- exponer nombre, plataforma y capacidades;
- mantener estado `online/offline`;
- permitir refresco manual;
- resolver escenarios donde el descubrimiento automático falle.

Modelo mínimo:

```text
Device
- id
- name
- platform
- ipAddress
- port
- protocol
- capabilities[]
- trustState
- lastSeen
```

---

### 4.2 Pairing & Trust

La primera conexión entre dispositivos debe requerir validación.

Flujo recomendado:

```text
PC detecta móvil
      ↓
Solicitar emparejamiento
      ↓
QR / código temporal / confirmación
      ↓
Intercambio de identidad de dispositivo
      ↓
Persistir confianza local
      ↓
Conexiones posteriores automáticas
```

Estados:

- `Unknown`
- `PairingPending`
- `Trusted`
- `Blocked`
- `Revoked`

No utilizar una contraseña global compartida entre todos los dispositivos.

---

### 4.3 Remote File System

Es la principal extensión respecto de un transferidor tradicional.

Debe abstraer el origen del archivo:

```text
IFileSystemProvider
- ListAsync(path)
- GetMetadataAsync(path)
- CreateDirectoryAsync(path)
- RenameAsync(path, newName)
- MoveAsync(source, destination)
- DeleteAsync(path)
- OpenReadAsync(path)
- OpenWriteAsync(path)
```

Implementaciones:

```text
LocalWindowsFileSystemProvider
AndroidFileSystemProvider
RemoteFileSystemProvider
```

La UI no debe conocer si está trabajando con una ruta local o remota.

La especificación de la implementación, endpoints, aislamiento de rutas y
límites entre las fases 2, 3 y 4 está en
[`REMOTE_FILESYSTEM.md`](REMOTE_FILESYSTEM.md).

---

## 5. API de administración remota

El fork requerirá endpoints adicionales al protocolo de transferencia de LocalSend.

Propuesta conceptual:

```http
GET    /api/v1/device
GET    /api/v1/storage
GET    /api/v1/files?path={path}
GET    /api/v1/files/metadata?path={path}

POST   /api/v1/files/directory
POST   /api/v1/files/rename
POST   /api/v1/files/move

DELETE /api/v1/files?path={path}
```

Transferencia:

```http
POST /api/v1/transfers
GET  /api/v1/transfers/{id}
POST /api/v1/transfers/{id}/pause
POST /api/v1/transfers/{id}/resume
DELETE /api/v1/transfers/{id}
```

### Reglas

- nunca aceptar una ruta sin validarla;
- impedir path traversal (`../`);
- validar que la ruta pertenezca a una raíz autorizada;
- autorizar cada operación según capacidades del dispositivo;
- no exponer rutas privadas de aplicaciones Android;
- las operaciones destructivas deben requerir permisos explícitos.

---

## 6. Transfer Engine

### MVP

- transferencia por streaming;
- múltiples archivos en cola;
- cancelación;
- progreso en bytes;
- velocidad;
- ETA;
- errores recuperables.

### Evolución

Para archivos grandes:

```text
Archivo
  ↓
Chunks
  ├── 0
  ├── 1
  ├── 2
  └── n
       ↓
verificación
       ↓
ensamblado / escritura
```

Objetivos posteriores:

- reanudación de transferencia;
- checksum por bloque o archivo;
- retry de bloques fallidos;
- concurrencia limitada;
- persistencia de sesiones incompletas.

No se debe agregar chunking únicamente por complejidad arquitectónica; debe implementarse cuando aporte reanudación o rendimiento medible.

---

## 7. Android

### Acceso a almacenamiento

Se deben soportar dos estrategias.

#### Modo estándar

Usar Storage Access Framework / permisos por carpetas autorizadas.

Ventajas:

- menor fricción con políticas de plataforma;
- principio de menor privilegio.

#### Modo administrador de archivos

Para un producto cuya función principal sea administrar archivos puede evaluarse el acceso amplio al almacenamiento cuando Android y la política de distribución lo permitan.

Restricciones:

- no asumir acceso ilimitado a directorios privados de otras aplicaciones;
- encapsular la implementación para que los permisos Android no contaminen el dominio.

---

## 8. Windows

Funciones prioritarias:

- drag & drop desde Explorer hacia la app;
- drag & drop desde el panel remoto hacia una carpeta local;
- acceso a unidades y carpetas;
- integración con bandeja del sistema solo si aporta al descubrimiento;
- comportamiento correcto con firewall;
- evitar servicios permanentes innecesarios.

No instalar un Windows Service en el MVP salvo que exista una necesidad demostrada.

---

## 9. Seguridad

### Requisitos mínimos

- cifrado de tráfico local mediante TLS cuando esté habilitado;
- emparejamiento explícito;
- identidad persistente por dispositivo;
- claves almacenadas en mecanismos seguros disponibles por plataforma;
- scopes/rutas autorizadas;
- revocación de dispositivos;
- sanitización estricta de nombres y rutas;
- límites de tamaño y concurrencia configurables;
- nunca ejecutar archivos recibidos automáticamente.

### Modelo de confianza

```text
Internet ─────────────── X
Cloud ────────────────── X

PC  ←──── LAN cifrada ────→  Android
       dispositivo confiable
```

---

## 10. Rendimiento

Metas de diseño:

- streaming constante;
- uso de memoria independiente del tamaño total del archivo;
- no calcular hashes globales de archivos gigantes antes de iniciar si no es necesario;
- backpressure;
- evitar reconstrucciones Flutter innecesarias durante progreso;
- throttling de eventos de progreso hacia UI;
- benchmark Android → Windows y Windows → Android por separado.

Métricas:

```text
Throughput MB/s
CPU %
RAM
latencia de descubrimiento
tiempo hasta primer byte
tasa de transferencias fallidas
tiempo de reanudación
```

---

## 11. Estructura sugerida del proyecto

No realizar una reestructuración total del fork durante la primera iteración.

Objetivo progresivo:

```text
lib/
├── app/
├── core/
│   ├── networking/
│   ├── security/
│   └── filesystem/
├── features/
│   ├── devices/
│   ├── pairing/
│   ├── explorer/
│   ├── transfers/
│   ├── history/
│   └── settings/
├── domain/
└── infrastructure/

rust/
└── transfer_engine/
```

---

## 12. Estrategia de evolución del fork

### Paso 1 — congelar baseline

- fork oficial;
- compilar Android y Windows;
- ejecutar pruebas de transferencia;
- registrar versión upstream utilizada.

### Paso 2 — branding aislado

- nombre;
- íconos;
- colores;
- identificadores de paquete;
- textos.

Sin tocar todavía el protocolo.

### Paso 3 — limpiar UI

Retirar o reemplazar pantallas que no encajen con el nuevo flujo.

### Paso 4 — Remote File System

Agregar navegación y operaciones remotas.

### Paso 5 — Explorer dual

Construir la UX PC ↔ móvil.

### Paso 6 — transferencias resilientes

Agregar cola, pausa, retry y posteriormente resume.

### Paso 7 — sincronización

Implementarla como módulo separado del explorador.

---

## 13. Estrategia para actualizaciones upstream

Evitar un fork imposible de actualizar.

Reglas:

1. minimizar cambios directos sobre componentes heredados;
2. crear adaptadores alrededor del código LocalSend;
3. mantener commits de branding separados de cambios funcionales;
4. documentar divergencias;
5. revisar periódicamente upstream;
6. no fusionar automáticamente cambios de protocolo sin pruebas de compatibilidad.

---

## 14. Testing

### Unit

- normalización de rutas;
- permisos;
- transfer state machine;
- resolución de conflictos;
- validación de nombres.

### Integration

- descubrimiento;
- pairing;
- browse remoto;
- upload/download;
- caída de Wi-Fi;
- reconexión;
- archivo grande;
- muchos archivos pequeños.

### E2E

Matrices iniciales:

```text
Windows 11 ↔ Android
Wi-Fi 5
Wi-Fi 6
Hotspot Android
LAN PC + Wi-Fi móvil
Firewall Windows activo
```

---

## 15. Fuera de la arquitectura inicial

No incorporar en MVP:

- cuentas;
- nube;
- servidor central;
- streaming multimedia;
- acceso remoto por Internet;
- chat;
- control remoto del PC;
- notificaciones del teléfono;
- ejecución remota;
- backup cloud.

---

## 16. Referencias base

- LocalSend: https://github.com/localsend/localsend
- Protocolo LocalSend: https://github.com/localsend/protocol
- Sitio oficial: https://localsend.org/

Estas referencias describen la base upstream. La navegación de archivos remotos, administración del filesystem, sincronización y reanudación avanzada descritas en este documento son objetivos del producto derivado y no deben presentarse como características existentes de LocalSend.
