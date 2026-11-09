%% Una estacion = un gen_statem con 4 estados:
%%   esperando  : sin pieza (inanicion: aguas arriba no entrega)
%%   procesando : trabajando una pieza (ciclo base x factor x variacion +-10 %)
%%   bloqueada  : termino pero el buffer de salida esta lleno (backpressure)
%%   falla      : paro; la pieza a medias se CONSERVA y se reanuda con el tiempo restante
%% La pieza en proceso y los tiempos acumulados se guardan en ETS, asi que si el proceso
%% muere (caos) el supervisor lo reinicia y retoma la misma pieza sin perderla ni duplicarla.
-module(p32_estacion).
-behaviour(gen_statem).
-export([start_link/1, nombre/1, paro/3, reparar/1]).
-export([callback_mode/0, init/1, esperando/3, procesando/3, bloqueada/3, falla/3]).
-define(POLL, 8).

nombre(N) -> list_to_atom("p32_estacion_" ++ integer_to_list(N)).
start_link(N) -> gen_statem:start_link({local, nombre(N)}, ?MODULE, N, []).
paro(N, SegSim, Causa) -> gen_statem:cast(nombre(N), {paro, SegSim, Causa}).
reparar(N) -> gen_statem:cast(nombre(N), reparar).

callback_mode() -> [state_functions, state_enter].

init(N) ->
  rand:seed(exsss, {N, erlang:unique_integer([positive]), 7}),
  R0 = p32_registro:leer_est(N),
  %% si ya estaba arrancada, esto es un REINICIO por el supervisor: se cuenta
  R = case maps:get(arrancada, R0, false) of
        true -> R0#{reinicios := maps:get(reinicios, R0) + 1};
        false -> R0#{arrancada => true}
      end,
  p32_registro:guardar_est(N, R),
  Ahora = p32_registro:ahora_ms(),
  Inicial = case {maps:get(estado, R), p32_registro:leer_pieza(N)} of
    {falla, _} when map_get(falla_hasta, R) > Ahora -> falla;
    {_, #{fase := saliendo}} -> bloqueada;
    {_, #{fase := F}} when F =:= procesando; F =:= interrumpida -> procesando;
    _ -> esperando
  end,
  {ok, Inicial, #{n => N}}.

%% ---------- esperando ----------
esperando(enter, _Old, #{n := N}) ->
  set_estado(N, esperando),
  {keep_state_and_data, [{state_timeout, 0, poll}]};
esperando(state_timeout, poll, D = #{n := N}) ->
  case obtener(N) of
    {ok, Id} ->
      Ms = p32_registro:sim_a_ms(ciclo(N)),
      p32_registro:guardar_pieza(N, #{id => Id, fase => procesando, restante_ms => Ms,
                                      inicio => p32_registro:ahora_ms()}),
      {next_state, procesando, D};
    vacio -> {keep_state_and_data, [{state_timeout, ?POLL, poll}]}
  end;
esperando(cast, {paro, S, C}, D) -> iniciar_falla(S, C, esperando, D);
esperando(cast, _, _) -> keep_state_and_data.

%% ---------- procesando ----------
procesando(enter, _Old, #{n := N}) ->
  Rest = restante(p32_registro:leer_pieza(N)),
  P = p32_registro:leer_pieza(N),
  p32_registro:guardar_pieza(N, P#{fase := procesando, restante_ms := Rest, inicio => p32_registro:ahora_ms()}),
  set_estado(N, procesando),
  {keep_state_and_data, [{state_timeout, Rest, listo}]};
procesando(state_timeout, listo, D = #{n := N}) ->
  P = p32_registro:leer_pieza(N),
  p32_registro:guardar_pieza(N, P#{fase := saliendo}),
  {next_state, bloqueada, D};
procesando(cast, {paro, S, C}, D = #{n := N}) ->
  P = p32_registro:leer_pieza(N),
  p32_registro:guardar_pieza(N, P#{fase := interrumpida, restante_ms := restante(P)}),
  iniciar_falla(S, C, procesando, D);
procesando(cast, _, _) -> keep_state_and_data.

%% ---------- bloqueada ----------
bloqueada(enter, _Old, #{n := N}) ->
  set_estado(N, bloqueada),
  {keep_state_and_data, [{state_timeout, 0, poll}]};
bloqueada(state_timeout, poll, D = #{n := N}) ->
  #{id := Id} = p32_registro:leer_pieza(N),
  Res = case N =:= p32_registro:cfg(n, 8) of
    true -> p32_registro:salir(N, Id);
    false -> p32_buffer:poner(N, N, Id)
  end,
  case Res of
    ok ->
      R = p32_registro:leer_est(N),
      p32_registro:guardar_est(N, R#{hechas := maps:get(hechas, R) + 1}),
      {next_state, esperando, D};
    _ -> {keep_state_and_data, [{state_timeout, ?POLL, poll}]}
  end;
bloqueada(cast, {paro, S, C}, D) -> iniciar_falla(S, C, bloqueada, D);
bloqueada(cast, _, _) -> keep_state_and_data.

%% ---------- falla ----------
falla(enter, _Old, #{n := N}) ->
  set_estado(N, falla),
  Hasta = maps:get(falla_hasta, p32_registro:leer_est(N)),
  {keep_state_and_data, [{state_timeout, max(0, Hasta - p32_registro:ahora_ms()), reparada}]};
falla(state_timeout, reparada, D = #{n := N}) ->
  R = p32_registro:leer_est(N),
  p32_registro:evento(estacion_reanudada, #{estacion => N, causa => maps:get(causa, R)}),
  {next_state, maps:get(volver, R), D};
falla(cast, {paro, S, C}, D = #{n := N}) ->
  R = p32_registro:leer_est(N),
  Hasta = max(maps:get(falla_hasta, R), p32_registro:ahora_ms() + p32_registro:sim_a_ms(S)),
  p32_registro:guardar_est(N, R#{falla_hasta := Hasta, causa := C}),
  {repeat_state, D};
falla(cast, reparar, D = #{n := N}) ->
  R = p32_registro:leer_est(N),
  p32_registro:guardar_est(N, R#{falla_hasta := p32_registro:ahora_ms()}),
  {repeat_state, D};
falla(cast, _, _) -> keep_state_and_data.

%% ---------- auxiliares ----------
iniciar_falla(S, C, Volver, D = #{n := N}) ->
  R = p32_registro:leer_est(N),
  Hasta = p32_registro:ahora_ms() + p32_registro:sim_a_ms(S),
  p32_registro:guardar_est(N, R#{falla_hasta := Hasta, causa := C, volver := Volver}),
  p32_registro:evento(paro_iniciado, #{estacion => N, causa => C, segundos => S, estaba => Volver}),
  {next_state, falla, D}.

obtener(N) ->
  case p32_registro:leer_pieza(N) of
    #{id := Id, fase := nueva} -> {ok, Id};
    _ when N =:= 1 -> p32_registro:nueva_pieza(1);
    _ -> p32_buffer:tomar(N - 1, N)
  end.

ciclo(N) ->
  p32_registro:ciclo_base(N) * p32_registro:factor(N) * (0.9 + 0.2 * rand:uniform()).

restante(#{fase := procesando, restante_ms := R, inicio := I}) ->
  max(0, R - (p32_registro:ahora_ms() - I));
restante(#{restante_ms := R}) -> max(0, R).

set_estado(N, Nuevo) ->
  Now = p32_registro:ahora_ms(),
  #{estado := Prev, desde := D0, acc := Acc} = R = p32_registro:leer_est(N),
  Acc1 = Acc#{Prev := maps:get(Prev, Acc) + (Now - D0)},
  p32_registro:guardar_est(N, R#{estado := Nuevo, desde := Now, acc := Acc1}).
