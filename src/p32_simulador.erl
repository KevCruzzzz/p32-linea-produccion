%% Escenario del problema: turno de 7.5 h (27,000 s) con
%%  - 8 estaciones, ciclos 27-36 s (+-10 %), buffers de 5
%%  - falla de 3 min en la estacion 4 (a la hora 1)
%%  - cambio de modelo: +20 % de tiempo en la estacion 6 (a la hora 4)
%% 1 s simulado = 1000/vel ms reales.
-module(p32_simulador).
-behaviour(gen_server).
-export([start_link/0, iniciar_turno/1, sin_escenario/0, paro/3, factor/2, matar_estacion/1, matar_buffer/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).
-define(TURNO_S, 27000).

start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).
iniciar_turno(Vel) -> gen_server:call(?MODULE, {turno, Vel}, 10000).
%% Cancela los eventos programados (falla en est. 4, cambio de modelo, fin de turno): modo libre.
sin_escenario() -> gen_server:call(?MODULE, sin_escenario).
paro(N, Seg, Causa) -> p32_estacion:paro(N, Seg, Causa).
factor(N, F) ->
  ets:insert(p32_reg, {{factor, N}, F}),
  p32_registro:evento(cambio_de_ciclo, #{estacion => N, factor => F}), ok.
matar_estacion(N) ->
  case whereis(p32_estacion:nombre(N)) of
    undefined -> no_encontrada;
    Pid -> p32_registro:evento(caos_matar_estacion, #{estacion => N}), exit(Pid, kill), ok
  end.
matar_buffer(N) ->
  case whereis(p32_buffer:nombre(N)) of
    undefined -> no_encontrado;
    Pid -> p32_registro:evento(caos_matar_buffer, #{buffer => N}), exit(Pid, kill), ok
  end.

init([]) -> {ok, #{timers => []}}.

handle_call(sin_escenario, _From, S = #{timers := Ts}) ->
  [erlang:cancel_timer(T) || T <- Ts],
  {reply, ok, S#{timers := []}};
handle_call({turno, Vel}, _From, S = #{timers := Ts}) ->
  [erlang:cancel_timer(T) || T <- Ts],
  supervisor:terminate_child(p32_linea_de_produccion_sup, p32_linea_sup),
  p32_registro:reset(Vel, true),
  supervisor:restart_child(p32_linea_de_produccion_sup, p32_linea_sup),
  A = fun(SimS, Msg) -> erlang:send_after(p32_registro:sim_a_ms(SimS), self(), Msg) end,
  Nuevos = [A(3600, falla_est4), A(14400, cambio_modelo), A(?TURNO_S, fin_turno)],
  p32_registro:evento(turno_iniciado, #{velocidad => Vel, demanda => 900, takt_s => 30}),
  {reply, ok, S#{timers := Nuevos}}.

handle_cast(_, S) -> {noreply, S}.

handle_info(falla_est4, S) -> p32_estacion:paro(4, 180, falla_maquina), {noreply, S};
handle_info(cambio_modelo, S) -> factor(6, 1.2), {noreply, S};
handle_info(fin_turno, S) ->
  p32_registro:set_cfg(material, false), p32_registro:set_cfg(terminado, true),
  p32_registro:evento(turno_terminado, #{salidas => maps:get(salidas, p32_registro:foto())}),
  {noreply, S};
handle_info(_, S) -> {noreply, S}.
