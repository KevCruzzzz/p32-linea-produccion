%% Arranque: primero el arbol de supervision y despues cowboy (HTTP + SSE).
-module(p32_linea_de_produccion_app).
-behaviour(application).
-export([start/2, stop/1]).

start(_Type, _Args) ->
  {ok, Sup} = p32_linea_de_produccion_sup:start_link(),
  Rutas = cowboy_router:compile([{'_', [
    {"/", cowboy_static, {priv_file, p32_linea_de_produccion, "www/index.html"}},
    {"/api/linea", p32_http, linea},
    {"/api/stream", p32_http, stream},
    {"/api/bitacora", p32_http, bitacora},
    {"/api/simulacion/turno", p32_http, turno},
    {"/api/estaciones/:id/paro", p32_http, paro},
    {"/api/estaciones/:id/reparar", p32_http, reparar},
    {"/api/estaciones/:id/ciclo", p32_http, ciclo},
    {"/api/caos/matar_estacion/:id", p32_http, matar_estacion},
    {"/api/caos/matar_buffer/:id", p32_http, matar_buffer},
    {"/metrics", p32_http, metricas}
  ]}]),
  Puerto = application:get_env(p32_linea_de_produccion, puerto, 8080),
  {ok, _} = cowboy:start_clear(p32_http_listener, [{port, Puerto}], #{env => #{dispatch => Rutas}}),
  {ok, Sup}.

stop(_State) ->
  cowboy:stop_listener(p32_http_listener),
  ok.
