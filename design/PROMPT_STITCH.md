# Prompt para Google Stitch — #32 Línea de producción

Pega esto completo en Stitch (modo **Web**):

Diseña la interfaz web de un monitor de línea de producción de una maquiladora de Tijuana, para supervisores de planta. Tema oscuro tipo sala de control, todo en español, legible en celular y escritorio. Colores de estado: verde = procesando/ok, azul = esperando (inanición), ámbar = bloqueada o cuello de botella, rojo = falla/paro.

Pantallas:
1. Dashboard en vivo: barra superior "Línea de producción · Tijuana" con indicador "en vivo" y reloj de turno. Fila de indicadores: piezas terminadas / 900, piezas por hora contra meta de 120, capacidad real por hora, WIP, tiempo de ciclo (Ley de Little), estación cuello de botella, paro acumulado. Debajo, la línea de 8 estaciones en serie como tarjetas conectadas por buffers de 5 casillas (se llenan en ámbar); cada tarjeta muestra estado, tiempo de ciclo, barra de utilización y etiqueta "cuello", "bloqueo" o "inanición".
2. Detalle de estación: estado, ciclo base por factor, pieza actual, porcentajes de tiempo procesando, esperando, bloqueada y en falla, piezas hechas, reinicios del proceso y tiempo restante de falla.
3. Bitácora de eventos y alertas: lista cronológica con número, hora de turno, evento (paro iniciado, estación reanudada, cambio de ciclo, proceso reiniciado) y datos, con color por gravedad.
4. Panel de simulación y caos: selector de velocidad, botón "Turno 7.5 h", botones de paro (3 min estación 4, falta de material, cambio de modelo +20 % en estación 6) y botones rojos "Matar proceso de estación" y "Matar buffer".
