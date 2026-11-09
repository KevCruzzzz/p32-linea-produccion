%% Toma una foto cada 200 ms, mantiene el historial para la ventana movil y
%% expone el ultimo resultado de p32_metricas. Solo LEE: si muere no afecta a la linea.
-module(p32_linea).
-behaviour(gen_server).
-export([start_link/0, estado/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).
-define(TICK, 200).

start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).
estado() -> gen_server:call(?MODULE, estado, 2000).

init([]) ->
  erlang:send_after(?TICK, self(), tick),
  {ok, #{hist => [], run => undefined, ultimo => #{}}}.

handle_call(estado, _From, S = #{ultimo := U}) -> {reply, U, S}.
handle_cast(_, S) -> {noreply, S}.

handle_info(tick, S = #{hist := H0, run := Run0}) ->
  erlang:send_after(?TICK, self(), tick),
  Foto = p32_registro:foto(),
  Run = maps:get(run, Foto),
  H1 = case Run =:= Run0 of true -> H0; false -> [] end,
  Vent = p32_metricas:ventana_s(),
  T = maps:get(t_sim, Foto),
  H2 = [p32_metricas:ligera(Foto) | [X || X = {Ti, _} <- H1, Ti >= T - 2 * Vent]],
  {noreply, S#{hist := H2, run := Run, ultimo := p32_metricas:calcular(Foto, H2, Vent)}};
handle_info(_, S) -> {noreply, S}.
