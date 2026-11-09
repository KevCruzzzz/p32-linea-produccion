%% Supervisor de la linea: est1, buf1, est2, buf2, ..., est8 (rest_for_one).
%% Si una estacion cae, se reinician ella y todo lo que esta aguas abajo; como la pieza
%% en proceso y las colas viven en ETS (p32_registro), nada se pierde ni se duplica.
-module(p32_linea_sup).
-behaviour(supervisor).
-export([start_link/0, init/1]).

start_link() -> supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
  N = p32_registro:cfg(n, 8),
  Est = fun(I) -> #{id => {est, I}, start => {p32_estacion, start_link, [I]}, restart => permanent, shutdown => 2000, type => worker} end,
  Buf = fun(I) -> #{id => {buf, I}, start => {p32_buffer, start_link, [I]}, restart => permanent, shutdown => 2000, type => worker} end,
  Hijos = lists:append([[Est(I)] ++ [Buf(I) || I < N] || I <- lists:seq(1, N)]),
  {ok, {#{strategy => rest_for_one, intensity => 50, period => 60}, Hijos}}.
