# #32 — Línea de producción: el problema

## Contexto
Tijuana es uno de los grandes polos de manufactura de Mexico: electronica, dispositivos medicos (es de los principales centros de ese sector en Norteamerica), aeroespacial y automotriz, con cientos de miles de empleos en maquiladoras. Una linea de produccion es una cadena de estaciones donde la mas lenta marca el ritmo de toda la planta.

## Datos del mundo real
- **Takt time** = tiempo disponible / demanda. Con 7.5 h netas de turno (27,000 s) y 900 unidades por turno, el takt es de 30 s: cada 30 s debe salir una unidad.
- Una linea de 8 estaciones balanceada tiene tiempos de ciclo parecidos; si una estacion tarda 40 s, esa es la capacidad real de la linea (cuello de botella), no 30 s.
- **Ley de Little:** WIP = tasa de salida × tiempo de ciclo. Mas inventario en proceso significa mas tiempo atrapado y mas defectos que se descubren tarde.
- Los *buffers* entre estaciones absorben pequeñas variaciones, pero tambien ocultan problemas; sin buffer, un paro corta toda la linea (bloqueo aguas arriba, inanicion aguas abajo).
- Causas de paro: falta de material, falla de maquina, cambio de modelo, calidad. Un paro de 5 minutos en la estacion cuello de botella pierde 5 minutos de toda la linea.

## El problema
Simular y monitorear una linea de estaciones conectadas en serie con buffers finitos, calcular en vivo su salida real, identificar el cuello de botella actual (que puede moverse), contabilizar paros y propagar los efectos de bloqueo e inanicion entre estaciones.

## Escenario a simular
- 8 estaciones con tiempos de ciclo de 25 a 40 s con variacion de ±10 %.
- Buffers de 5 piezas; falla de 3 minutos en la estacion 4.
- Cambio de modelo que añade 20 % de tiempo a la estacion 6.

## Casos dificiles
- Distinguir una estacion lenta de una estacion esperando.
- Un paro que se propaga hacia atras y adelante.
- Reanudar sin perder ni duplicar piezas en proceso.

## Preguntas guia
1. ¿Como sabes cual estacion limita a la linea en este momento?
2. ¿Que pasa con una pieza que estaba a medias cuando la estacion fallo?

## Que debes entregar (sin que aqui se de la solucion)
- Un diseño OTP explicado brevemente: procesos, supervisores y quien reinicia a quien, justificando cada decision frente a los casos dificiles de arriba.
- La simulacion del escenario descrito, con datos generados y fallas inyectadas.
- Una lista de supuestos propios y de las cifras de este documento que verificaste.
- Una prueba de caos: que mataste, que esperabas y que ocurrio.
- `rebar3 compile` y `rebar3 eunit` en verde; capturas de Stitch y de la app real si hay interfaz.

---
*Las cifras son de referencia (ordenes de magnitud). Verifica la fuente vigente antes de citarlas en tu entrega y anota las que uses en tu README.*
