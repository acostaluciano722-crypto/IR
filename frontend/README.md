# IR · Frontend

Aplicación Flutter para pasajeros y conductores. Consulta el README de la raíz para arrancar Django y PostgreSQL.

```powershell
flutter pub get
flutter run -d chrome
```

En un teléfono físico configura la IP del equipo que ejecuta Django:

```powershell
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000/api
```

## Interfaz

- Tema oscuro y claro coherente en bienvenida, autenticación, pasajero, conductor, puntos, bonificaciones, historial, configuración y cartera.
- Formularios adaptables al teclado, validación por campo, autofill y protección contra envíos repetidos.
- Menús nativos con cierre de sesión y controles del mapa separados. La hoja de viaje y los controles flotantes interceptan los punteros para impedir que Google Maps reciba gestos iniciados sobre ellos.
- Entrada del logo de 650 ms, respuesta al toque de 120 ms y transiciones breves. Las animaciones añadidas respetan la preferencia del sistema de reducir movimiento.
- Cartera con saldos reales, selección y confirmación del monto, y actualización después de la recarga.
- Errores de conexión con tiempo límite de 20 segundos; las calificaciones fallidas conservan el formulario para reintentar.

## Comprobaciones

```powershell
flutter analyze
flutter test
flutter build web
```

Las pruebas cubren formularios, temas, teléfonos desde 280 px, texto ampliado, tablet, escritorio horizontal, teclado, aislamiento de controles sobre el mapa, calificaciones, cierre de sesión y recargas. Mapas, ubicación y API se sustituyen en las pruebas de widgets; su integración y rendimiento nativos requieren un dispositivo o emulador.

Para producir capturas locales con las fuentes de Windows:

```powershell
flutter test --update-goldens --dart-define=CAPTURE_UI=true
```

Las capturas se guardan en `artifacts/ui/after/`, excluido de Git.
