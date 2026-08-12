# FireBoxTransfer — Documento de alcance funcional

**Versión:** 0.1  
**Producto:** aplicación de administración y transferencia local de archivos PC ↔ móvil.

---

## 1. Visión

El producto debe conseguir que transferir archivos entre PC y móvil deje de sentirse como una operación de “compartir”.

La experiencia objetivo es:

> **Abrir la aplicación y trabajar con el almacenamiento del otro dispositivo casi como si estuviera conectado por USB.**

Sin:

- nube;
- cuentas;
- cables;
- subir archivos a terceros;
- configuración de IP en el flujo normal.

---

## 2. Plataformas del MVP

### Incluidas

- Windows 10/11
- Android

### Posteriores

- Linux
- macOS
- iOS

El soporte multiplataforma heredado de LocalSend no implica que todas las funciones nuevas deban publicarse simultáneamente en todas las plataformas.

---

## 3. Perfiles de usuario

### Usuario personal

Quiere pasar rápidamente:

- fotos;
- videos;
- música;
- APK;
- documentos;
- carpetas completas.

### Usuario técnico

Quiere:

- explorar rutas;
- mover grandes cantidades;
- controlar destino;
- verificar progreso;
- manejar varios dispositivos.

### Usuario avanzado / futuro Pro

Quiere:

- carpetas sincronizadas;
- reglas;
- tareas automáticas;
- historial avanzado;
- múltiples pares de dispositivos.

---

# 4. Alcance MVP

## RF-001 — Descubrimiento automático

El sistema debe detectar dispositivos compatibles en la misma red local.

### Criterios

- mostrar nombre;
- mostrar plataforma;
- mostrar estado;
- permitir refrescar;
- permitir conexión manual como fallback si el descubrimiento falla.

---

## RF-002 — Emparejamiento

La primera conexión debe ser autorizada.

Métodos admitidos:

- QR;
- código temporal;
- confirmación explícita.

Una vez confiado, el dispositivo puede reconectarse sin repetir todo el flujo, salvo revocación.

---

## RF-003 — Selector de dispositivo

Cuando exista un solo dispositivo confiable disponible, la UX debe minimizar pasos.

Cuando existan varios:

```text
Mis dispositivos

Galaxy S24 Ultra      Disponible
Tablet                Disponible
PC Oficina            Offline
```

---

## RF-004 — Explorador dual en escritorio

Pantalla principal Windows:

```text
┌──────────────────────┬──────────────────────┐
│ ESTE PC              │ GALAXY S24 ULTRA     │
│                      │                      │
│ Descargas            │ DCIM                 │
│ Documentos           │ Download             │
│ Música               │ Music                │
│ Videos               │ Movies               │
│                      │                      │
└──────────────────────┴──────────────────────┘
```

Debe permitir navegar ambos dispositivos sin cambiar de pantalla.

---

## RF-005 — Exploración remota

Desde Windows se debe poder navegar por las rutas Android autorizadas.

Mostrar:

- nombre;
- tipo;
- tamaño;
- fecha de modificación;
- ubicación;
- espacio disponible del dispositivo.

---

## RF-006 — Transferir PC → móvil

El usuario puede:

- arrastrar archivos;
- arrastrar carpetas;
- usar copiar/pegar;
- usar una acción “Enviar a”.

El destino debe ser visible antes de confirmar cuando exista riesgo de confusión.

---

## RF-007 — Transferir móvil → PC

Mismo principio:

```text
Seleccionar
    ↓
Arrastrar / Copiar
    ↓
Destino PC
```

En escritorio el comportamiento debe intentar parecerse al explorador de archivos convencional.

---

## RF-008 — Operaciones de archivos

Cuando el permiso remoto lo permita:

- crear carpeta;
- renombrar;
- mover;
- eliminar;
- copiar entre rutas.

Las acciones destructivas deben mostrar confirmación contextual cuando no puedan deshacerse.

---

## RF-009 — Cola de transferencias

Debe existir un panel no intrusivo.

Estados:

- preparando;
- en cola;
- transfiriendo;
- pausado;
- completado;
- cancelado;
- error.

---

## RF-010 — Progreso

Cada transferencia debe mostrar:

- porcentaje;
- bytes enviados / total;
- velocidad;
- ETA razonable;
- dispositivo origen/destino.

Evitar barras indeterminadas cuando el tamaño sea conocido.

---

## RF-011 — Cancelación

El usuario debe poder cancelar:

- una transferencia;
- un grupo;
- toda la cola.

Cancelar no debe eliminar el archivo de origen.

---

## RF-012 — Historial básico

Registrar localmente:

- archivo/carpeta;
- origen;
- destino;
- fecha;
- tamaño;
- resultado.

El historial no debe convertirse en telemetría externa.

---

## RF-013 — Información de almacenamiento

Mostrar en ambos paneles:

```text
Usado: 173 GB
Libre: 83 GB
Total: 256 GB
```

Debe ser información secundaria, no dominar la interfaz.

---

## RF-014 — Dispositivos confiables

Configuración:

- ver dispositivos;
- renombrar alias local;
- revocar confianza;
- bloquear.

---

# 5. Experiencia móvil MVP

La aplicación móvil no debe intentar copiar literalmente el explorador dual de escritorio.

Navegación primaria:

```text
Explorar
Transferencias
Dispositivos
Ajustes
```

### Explorar

Debe mostrar el dispositivo conectado y permitir alternar:

```text
Este teléfono
PC-YISUS
```

En pantallas pequeñas se utiliza **un explorador a la vez**, no dos columnas comprimidas.

---

# 6. Búsqueda

## MVP

Búsqueda dentro de la carpeta actual.

## Posterior

- búsqueda recursiva;
- filtros;
- tipos;
- fecha;
- tamaño.

---

# 7. Funciones posteriores al MVP

## F-101 — Reanudación real

Si la conexión se pierde:

```text
81 %
↓
Wi-Fi perdido
↓
Reconectado
↓
continúa desde estado recuperable
```

No reiniciar archivos grandes desde cero cuando técnicamente pueda evitarse.

---

## F-102 — Sincronización de carpetas

Tipos:

- PC → móvil;
- móvil → PC;
- bidireccional.

Ejemplo:

```text
PC/Music  ⇄  Android/Music
```

---

## F-103 — Carpetas favoritas

Accesos directos:

- Cámara;
- Descargas;
- Música;
- Documentos;
- carpeta personalizada.

---

## F-104 — Reglas de conflicto

Cuando ambos lados contienen el mismo nombre:

- reemplazar;
- conservar ambos;
- omitir;
- preguntar.

Para sincronización futura:

- más reciente;
- origen prioritario;
- política configurable.

---

## F-105 — Multi-dispositivo

Administrar más de un móvil o PC confiable.

---

## F-106 — Modo backup local

Ejemplo:

```text
DCIM Android
    ↓
D:\Backups\Galaxy\Fotos
```

El backup seguirá siendo LAN/local; no implica nube.

---

# 8. Funciones potencialmente monetizables

La transferencia básica debe ser suficientemente útil por sí sola.

Una posible separación futura:

| Free | Pro |
|---|---|
| Exploración | Sincronización automática |
| Transferencia manual | Carpetas espejo |
| Drag & drop | Reglas avanzadas |
| Cola básica | Backup programado |
| Historial básico | Historial avanzado |
| Dispositivos confiables | Multi-dispositivo avanzado |

La arquitectura no debe bloquear funciones Free artificialmente para forzar Pro.

---

# 9. Fuera de alcance

Para mantener el producto enfocado:

- chat;
- SMS;
- espejo de pantalla;
- control del mouse;
- notificaciones Android en PC;
- streaming de multimedia;
- llamadas;
- servidor cloud;
- acceso remoto a través de Internet;
- VPN propia;
- almacenamiento cloud;
- editor de archivos.

---

# 10. Requisitos no funcionales

## RNF-001 — Privacidad

Los archivos no deben salir de la red local debido al funcionamiento normal del producto.

## RNF-002 — Sin cuentas

No requerir registro.

## RNF-003 — Rendimiento

Archivos grandes no deben cargarse completos en RAM.

## RNF-004 — Respuesta visual

La UI debe permanecer fluida durante transferencias.

## RNF-005 — Recuperación

Errores de red deben mostrar acción útil:

```text
No se pudo conectar con Galaxy S24 Ultra.

[ Reintentar ]
[ Diagnosticar ]
```

No mostrar excepciones técnicas al usuario normal.

## RNF-006 — Seguridad

Un dispositivo no confiable no debe poder explorar ni modificar almacenamiento.

## RNF-007 — Claridad

El usuario siempre debe identificar:

- origen;
- destino;
- operación;
- estado.

---

# 11. Criterios de aceptación del MVP

El MVP se considera funcional cuando:

1. Windows y Android se detectan dentro de una LAN compatible.
2. Pueden emparejarse.
3. Windows puede listar almacenamiento Android autorizado.
4. Android puede listar ubicaciones PC autorizadas.
5. Se puede navegar por carpetas.
6. Un archivo puede transferirse PC → Android.
7. Un archivo puede transferirse Android → PC.
8. Se pueden transferir carpetas.
9. Se puede arrastrar y soltar desde Windows.
10. Existe cola y progreso.
11. Se pueden cancelar transferencias.
12. Se pueden crear/renombrar/mover/eliminar archivos donde los permisos lo permitan.
13. La pérdida de conexión produce un estado controlado.
14. Ninguna funcionalidad del MVP requiere una cuenta o servidor externo.

---

# 12. Fases sugeridas

### Fase 0 — Fork estable

Compilación y pruebas upstream.

### Fase 1 — Producto propio

Branding + limpieza de UX.

### Fase 2 — Explorer remoto

Filesystem API + permisos.

### Fase 3 — Explorer dual

Flujo definitivo Windows.

### Fase 4 — Transfer Manager

Cola + rendimiento + fallos.

### Fase 5 — Resiliencia

Resume / retry / checksum según diseño final.

### Fase 6 — Pro

Sync + backup + reglas avanzadas.
