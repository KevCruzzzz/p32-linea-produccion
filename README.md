# #32 — Línea de producción (Erlang/OTP)

Simulación y monitoreo en vivo de una línea de **8 estaciones en serie** con **buffers finitos de 5 piezas**, paros inyectados, cuello de botella móvil y propagación de bloqueo e inanición. Cada estación es un proceso (`gen_statem`).

## Arranque

```bash
rebar3 compile && rebar3 eunit && rebar3 shell     # panel en http://localhost:8080
```
En servidor: `bash deploy/instalar.sh` (Ubuntu 24.04, deja un servicio systemd `linea32`).

## Diseño OTP

```
p32_linea_de_produccion_sup            (rest_for_one)
├── p32_registro        dueño de la tabla ETS: piezas, colas, contadores, bitácora
├── p32_linea_sup       (rest_for_one)  est1, buf1, est2, buf2, ... est8
│   ├── p32_estacion ×8   gen_statem: esperando | procesando | bloqueada | falla
│   └── p32_buffer   ×7   cola acotada (5) entre estación N y N+1
├── p32_linea           foto cada 200 ms + historial -> métricas (solo lee)
└── p32_simulador       escenario del turno + inyección de fallas y caos
cowboy -> p32_http      REST + SSE (/api/stream) + /metrics
```

| Decisión | Por qué (caso difícil que resuelve) |
|---|---|
| El estado duradero (pieza en proceso, colas, acumulados) vive en ETS dentro de `p32_registro`, el primer hijo | **Reanudar sin perder ni duplicar piezas**: una estación o buffer puede morir y el reinicio retoma la misma pieza con su tiempo restante. |
| Falla = estado propio; la pieza queda en la estación con `restante_ms` | **Pieza a medias**: al reparar sigue donde iba, no reinicia el ciclo. |
| Buffers con capacidad 5 y estación `bloqueada` si no hay lugar | **Propagación hacia atrás** (backpressure): el paro de E4 bloquea a E3, luego E2, etc., sin llenar nada de más. |
| Estación `esperando` distinta de `procesando`, con tiempos acumulados por estado | **Lenta vs. esperando**: la utilización (tiempo procesando / ventana) separa a la que limita de la que solo espera. |
| `rest_for_one` en orden de la línea | Si cae una estación, se reinician ella y lo que sigue aguas abajo para resincronizar; como el estado está en ETS, no se pierde nada. |
| `p32_linea` (métricas) y `p32_simulador` fuera de la línea | Si fallan, la producción sigue. |
| Operaciones de mover pieza (`tomar`/`poner`) pasan por `p32_registro` y son idempotentes (`vista`) | Un reintento tras un crash no duplica la pieza. |

**Cuello de botella:** si hay una estación en falla, esa limita ahora (`razon = paro`); si no, es la de mayor utilización en una ventana móvil de 10 min simulados (`razon = utilizacion`). Puede moverse (se prueba en eunit al volver lenta la E2).

## Escenario simulado (1 s simulado = 1000/velocidad ms)

- 8 estaciones, ciclos base 28, 30, 27, 34, 31, 36, 29, 32 s, con variación ±10 % por pieza.
- Buffers de 5. Falla de 3 min en E4 (hora 1). Cambio de modelo +20 % en E6 (hora 4). Turno de 27,000 s.

## Resultado medido (turno completo, velocidad ×1000)

| Indicador | Valor |
|---|---|
| Piezas terminadas al fin del turno (27,000 s) / tras vaciar la línea | 663 / **696** de 900 de demanda |
| Paro de E4 | 181 s (3 min) |
| Estación cuello | E6 (36 s → 43.2 s tras el cambio de modelo) |
| Capacidad teórica | 100 pzas/h antes y 83.3 pzas/h después del cambio (meta del takt: 120) |
| Estimación a mano | 4 h × 100 + 3.5 h × 83.3 ≈ 691 piezas (medido: 696) |
| Piezas perdidas o duplicadas | 0 (`creadas = salidas` tras vaciar) |

Conclusión: con un cuello de 36 s la línea **no puede cumplir el takt de 30 s**; el cambio de modelo agrava la brecha.

## Prueba de caos (eunit y panel)

| Qué se mató / inyectó | Qué esperaba | Qué ocurrió |
|---|---|---|
| `exit(Pid, kill)` a las estaciones 1, 3, 5 (dos veces), 2, 8, 6 y 4, y al buffer 3, en plena producción | El supervisor las reinicia y no se pierde ni duplica ninguna pieza | Los reinicios se contaron en cada estación; al vaciar la línea `creadas = salidas` y sin ids repetidos |
| Paro largo en E8 (última estación) | Backpressure: los buffers se llenan hasta 5 y nunca más; E7 queda bloqueada | Buffer 7 = 5/5, E7 `bloqueada`, ningún buffer excedió 5 |
| Paro en E4 con pieza a medias | La pieza se conserva y E8 queda en inanición | La misma pieza seguía en E4 durante el paro; al reparar, se terminó |

## Supuestos propios

- 1 s simulado equivale a 1000/velocidad ms reales (×50, ×200 o ×1000). La reparación de un proceso muerto se considera instantánea (milisegundos).
- Un buffer entre cada par de estaciones (7); la entrada tiene material infinito hasta el fin del turno; la salida de E8 no se bloquea.
- La bitácora vive en ETS: se pierde si se apaga toda la VM (no hay base de datos).
- OTP 25 (la que trae Ubuntu 24.04) y no OTP 27, por eso hay un codificador JSON mínimo propio (`p32_json`).

## Cifras del enunciado: qué verifiqué

- Takt = 27,000 s / 900 = **30 s** y 7.5 h × 3600 = 27,000 s: **verificado por cálculo**.
- Ley de Little (WIP = salida × tiempo de ciclo): se usa en el panel y se comprueba con las cifras medidas.
- Datos de contexto (peso de la manufactura en Tijuana, dispositivos médicos): **pendientes de verificar con fuente vigente**; citar solo si se confirman.

## Pruebas

`rebar3 eunit`: 8 pruebas (JSON, cuello por utilización, paro prioritario, conservación de piezas, límite de buffers, propagación de paro, caos y cuello móvil).
