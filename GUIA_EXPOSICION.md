# Guía para el video (Loom, solo pantalla) y para defenderlo si te preguntan

## Orden del video (≈5 min, sin voz: deja 3-5 s en cada cosa y selecciona con el mouse el texto del gist que explique)
1. **Gist** (40 s): título, tabla de enlaces y la sección "Arquitectura" (árbol y tabla de decisiones).
2. **Panel** (2.5 min): `▶ Turno 7.5 h` a ×1000 y deja correr; luego con ×200:
   - Espera a ver el cuello en ámbar (E6) y los buffers llenándose antes de él.
   - `Paro 15 min E4`: E3, E2 y E1 pasan a *bloqueada* y E5-E8 a *esperando*; abre el detalle de la E4.
   - `Cambio de modelo +20 % E6` y `E2 se vuelve lenta ×1.6`: el cuello se mueve (KPI "cuello").
3. **Caos** (1 min): `Matar proceso de estación` en la E4 y abre su detalle (Reinicios: 1, misma pieza). Mata también un buffer. Muestra la bitácora.
4. **asciinema** (30 s): hasta `8 tests, 0 failures` y `LISTO`.
5. **Stitch** (20 s) y **repositorio** (10 s).

## Cómo se explica en el pizarrón
Dibuja `E1 → [buf] → E2 → [buf] → … → E8` y debajo la caja `ETS (p32_registro)` con flechas punteadas: "aquí vive la pieza en proceso y la cola de cada buffer".

## Preguntas probables
- **¿Cómo sabes cuál estación limita ahora?** Si alguna está en falla, esa. Si no, la de mayor % de tiempo *procesando* en los últimos 10 min simulados: la que espera o está bloqueada no limita, solo sufre al que limita.
- **¿Qué pasa con la pieza a medias si la estación falla?** Se queda en la estación con el tiempo que le faltaba (`restante_ms`), guardada en ETS; al reparar o reiniciar el proceso continúa, no se pierde ni se duplica.
- **¿Por qué `rest_for_one`?** Porque la línea es una cadena: si cae una estación se reinicia con lo que va aguas abajo para resincronizar. No pierde datos porque el estado no vive en el proceso.
- **¿Por qué el estado está en ETS y no en el proceso?** Porque un proceso que muere pierde su estado; la tabla es de `p32_registro`, que es el primer hijo y casi nunca falla.
- **¿Qué hace el buffer?** Absorbe variaciones. Con buffer lleno la estación anterior queda *bloqueada* (backpressure); vacío, la siguiente *espera*. Sin buffer, un paro corta la línea entera.
- **¿Por qué no se cumple el takt?** Takt = 27,000 / 900 = 30 s, pero el cuello es de 36 s (43.2 s tras el cambio de modelo): la línea no puede pasar de 100 → 83 piezas/h contra las 120 que se piden.
- **¿Qué es la Ley de Little?** WIP = salida × tiempo de ciclo; el panel la usa para estimar el tiempo de ciclo con el WIP medido.
