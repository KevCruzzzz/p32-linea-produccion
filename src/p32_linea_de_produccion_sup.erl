%% Supervisor raiz (rest_for_one). El ORDEN importa:
%%  1. p32_registro: dueno de la tabla ETS con TODO el estado que no puede perderse
%%     (piezas, colas de buffers, contadores, bitacora). Si muere, todo lo demas se reinicia.
%%  2. p32_linea_sup: estaciones + buffers (rest_for_one en orden de la linea).
%%  3. p32_linea: calcula metricas y cuello de botella (solo lee).
%%  4. p32_simulador: escenarios y fallas. Esta DESPUES de la linea, pero la linea no depende de el.
-module(p32_linea_de_produccion_sup).
-behaviour(supervisor).
-export([start_link/0, init/1]).

start_link() -> supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
  Hijo = fun(Id, Mod, Tipo) ->
    #{id => Id, start => {Mod, start_link, []}, restart => permanent, shutdown => 5000, type => Tipo, modules => [Mod]}
  end,
  Hijos = [Hijo(p32_registro, p32_registro, worker),
           Hijo(p32_linea_sup, p32_linea_sup, supervisor),
           Hijo(p32_linea, p32_linea, worker),
           Hijo(p32_simulador, p32_simulador, worker)],
  {ok, {#{strategy => rest_for_one, intensity => 10, period => 60}, Hijos}}.
