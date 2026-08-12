# FireBoxTransfer — Guía de interfaz y experiencia de usuario

Este documento define **cómo debe sentirse el producto**, no solamente cómo debe verse.

---

## 1. Promesa de UX

El usuario no debe pensar:

> “Voy a compartir un archivo.”

Debe pensar:

> “Voy a mover este archivo a mi teléfono.”

La diferencia es importante. La aplicación debe comportarse como un **administrador de archivos entre dispositivos**, no como una pantalla temporal de envío.

---

# 2. Escritorio — pantalla principal

## Composición

La pantalla principal debe ser el explorador dual.

```text
┌─────────────────────────────────────────────────────────────┐
│ FireBoxTransfer                 Galaxy S24 ● conectado       │
├─────────────────────────────┬───────────────────────────────┤
│ ESTE PC                     │ GALAXY S24 ULTRA              │
│ C:\Users\Yisus\Downloads    │ /storage/emulated/0/Download │
│                             │                               │
│ 📁 Proyecto                 │ 📁 DCIM                       │
│ 📄 reporte.pdf              │ 📁 Music                      │
│ 🎬 video.mp4                │ 📁 Download                   │
│                             │                               │
│ 421 GB libres               │ 83 GB libres                  │
├─────────────────────────────┴───────────────────────────────┤
│ 2 transferencias                                   ▴       │
└─────────────────────────────────────────────────────────────┘
```

---

## Regla UX-01 — ambos lados siempre identificables

Nunca depender solo del color.

Mostrar permanentemente:

- nombre del dispositivo;
- ruta;
- plataforma/icono;
- espacio disponible.

El usuario debe saber dónde caerá un archivo antes de soltarlo.

---

## Regla UX-02 — drag & drop natural

Cuando un archivo cruza al panel opuesto:

1. resaltar destino válido;
2. mostrar carpeta de destino;
3. indicar copia o movimiento;
4. iniciar inmediatamente si la acción es inequívoca.

Ejemplo visual:

```text
             reporte.pdf
                 ↓

┌─────────────────────────────┐
│ GALAXY S24 / Documents      │
│                             │
│      Suelta para copiar     │
│          12.4 MB            │
│                             │
└─────────────────────────────┘
```

No abrir un wizard de cuatro pasos para una copia simple.

---

# 3. Conexión inicial

## Primera ejecución

```text
Encuentra tus dispositivos

Tu PC
PC-YISUS

Misma red Wi-Fi
        ↓

Galaxy S24 Ultra
Encontrado

[ Conectar ]
```

Después:

```text
Emparejar Galaxy S24 Ultra

┌─────────────┐
│     QR      │
└─────────────┘

o confirma el código

       419 827
```

---

## Regla UX-03 — seguridad visible pero breve

La primera conexión puede requerir una acción extra.

Las siguientes no.

Estado esperado:

```text
Galaxy S24 Ultra
● Conectado y confiable
```

---

# 4. Transferencias

No cambiar automáticamente a una pantalla de progreso.

La persona debe poder seguir navegando.

Mostrar una bandeja inferior compacta:

```text
CyberpunkBackup.zip             81 %
47.8 GB → Galaxy S24
82 MB/s · 02:14

████████████████░░░░

[ Pausar ] [ × ]
```

Al expandir:

```text
Transferencias

EN CURSO
CyberpunkBackup.zip       81 %

EN COLA
Fotos vacaciones          3.5 GB
video.mp4                  2.7 GB

COMPLETADAS
Documentos                ✓
```

---

## Regla UX-04 — feedback real

Si el sistema conoce:

- velocidad;
- tamaño;
- porcentaje;
- ETA;

debe mostrarlos.

No usar:

```text
Procesando...
████████████████████
```

indefinidamente.

---

# 5. Errores

Un error debe responder tres preguntas:

1. ¿qué ocurrió?
2. ¿qué pasó con mis archivos?
3. ¿qué puedo hacer?

Correcto:

```text
Se perdió la conexión con Galaxy S24 Ultra.

El archivo original no fue modificado.
La transferencia quedó pausada en 81 %.

[ Reanudar ]
[ Cancelar ]
```

Incorrecto:

```text
SocketException:
Connection reset by peer
```

---

# 6. Eliminación remota

Debe sentirse claramente diferente de una transferencia.

Ejemplo:

```text
¿Eliminar "video.mp4" del Galaxy S24 Ultra?

Esta acción eliminará el archivo del teléfono.

[ Cancelar ]    [ Eliminar ]
```

No utilizar una confirmación genérica como “¿Está seguro?”.

---

# 7. Experiencia Android

En móvil evitar el explorador dual permanente.

## Inicio conectado

```text
PC-YISUS
● Conectado

173 GB libres

Accesos rápidos
[ Descargas ]
[ Imágenes ]
[ Música ]
[ Documentos ]

Archivos
📁 DCIM
📁 Download
📁 Movies
📁 Music
```

Barra inferior:

```text
Explorar   Transferencias   Dispositivos   Ajustes
```

---

## Navegar el PC desde móvil

Selector superior:

```text
[ Este teléfono ▾ ]
```

Opciones:

```text
Este teléfono
PC-YISUS
```

Así se reutiliza el mismo explorador sin intentar meter dos árboles de directorios en una pantalla pequeña.

---

# 8. Gestos móvil

Recomendados:

- toque: abrir;
- mantener pulsado: selección;
- selección múltiple: barra contextual;
- menú `⋮`: operaciones menos frecuentes.

Acciones principales después de seleccionar:

```text
Copiar
Mover
Enviar a PC
Eliminar
Más
```

---

# 9. Jerarquía visual

Prioridad:

### Nivel 1

- archivos;
- carpetas;
- dispositivos;
- progreso.

### Nivel 2

- tamaño;
- fecha;
- ruta;
- almacenamiento.

### Nivel 3

- opciones avanzadas;
- logs;
- diagnóstico;
- configuración.

No inundar la pantalla principal con información técnica de red.

---

# 10. Apariencia

Dirección recomendada:

- moderna;
- limpia;
- cercana a un file manager nativo;
- sin estética excesivamente “gamer”;
- sin grandes tarjetas si una lista/tabla es más eficiente.

### Desktop

Densidad media/alta.

Un administrador de archivos necesita mostrar muchos elementos sin desperdiciar espacio.

### Mobile

Mayor separación y targets táctiles.

---

# 11. Tema

Soportar:

- sistema;
- claro;
- oscuro.

No utilizar colores fuertes para pintar paneles enteros.

Color de acento reservado para:

- selección;
- progreso;
- dispositivo conectado;
- acciones primarias.

---

# 12. Experiencia percibida de velocidad

Incluso si dos aplicaciones transfieren a la misma velocidad, esta puede sentirse más rápida si:

- descubre inmediatamente;
- lista carpetas progresivamente;
- responde al clic sin bloquear;
- muestra el archivo en cola instantáneamente;
- muestra velocidad y progreso estable;
- no presenta pantallas intermedias innecesarias.

Por esto la optimización debe considerar **latencia percibida**, no únicamente MB/s.

---

# 13. Principios resumidos

1. **Conectar y usar.**
2. **Origen y destino siempre claros.**
3. **La transferencia no interrumpe la navegación.**
4. **El escritorio se comporta como administrador de archivos.**
5. **El móvil se comporta como un explorador táctil.**
6. **Las acciones destructivas se diferencian claramente.**
7. **Errores recuperables tienen una acción de recuperación.**
8. **Sin cuenta, nube ni pantallas comerciales invasivas.**
9. **Las funciones Pro deben ampliar el producto, no degradar artificialmente la versión básica.**
10. **Menos pasos para las acciones frecuentes.**

---

# 14. Referencias visuales solicitadas

Las imágenes de referencia del proyecto deben representar escenarios concretos:

### Imagen A — Desktop Explorer

- PC y Android en dos paneles;
- arrastrar un archivo;
- ruta visible;
- almacenamiento;
- mini panel de transferencia.

### Imagen B — Android

- explorador del móvil;
- selector Este teléfono / PC;
- transferencia activa;
- interfaz táctil.

### Imagen C — Pairing + estados

- dispositivo detectado;
- QR/código;
- confirmación;
- estado confiable;
- error de red recuperable.

Estas imágenes son **referencias de experiencia**, no especificaciones pixel-perfect.
