%% Handler unico de cowboy: la accion llega en las opciones de la ruta.
%% GET /api/linea  /api/bitacora  /metrics  /api/stream (SSE)
%% POST /api/simulacion/turno?velocidad=50  /api/estaciones/:id/{paro,reparar,ciclo}
%% POST /api/caos/matar_estacion/:id  /api/caos/matar_buffer/:id
-module(p32_http).
-export([init/2, info/3, terminate/3]).

init(Req, stream) ->
  Req1 = cowboy_req:stream_reply(200, #{<<"content-type">> => <<"text/event-stream">>,
                                        <<"cache-control">> => <<"no-cache">>}, Req),
  self() ! enviar,
  {cowboy_loop, Req1, stream};
init(Req, Accion) ->
  {Code, Cuerpo, Tipo} = try responder(Accion, Req)
                         catch Clase:Razon -> {500, p32_json:encode(#{error => iolist_to_binary(io_lib:format("~p:~p", [Clase, Razon]))}), json}
                         end,
  CT = case Tipo of json -> <<"application/json">>; texto -> <<"text/plain; version=0.0.4">> end,
  {ok, cowboy_req:reply(Code, #{<<"content-type">> => CT, <<"access-control-allow-origin">> => <<"*">>}, Cuerpo, Req), Accion}.

info(enviar, Req, stream) ->
  erlang:send_after(500, self(), enviar),
  Datos = p32_json:encode(p32_linea:estado()),
  cowboy_req:stream_events(#{event => <<"linea">>, data => Datos}, nofin, Req),
  {ok, Req, stream};
info(_, Req, S) -> {ok, Req, S}.
terminate(_, _, _) -> ok.

responder(linea, _) -> {200, p32_json:encode(p32_linea:estado()), json};
responder(bitacora, _) -> {200, p32_json:encode(p32_registro:eventos(100)), json};
responder(turno, Req) ->
  Vel = num(qs(<<"velocidad">>, Req, <<"50">>)),
  ok = p32_simulador:iniciar_turno(Vel),
  {200, p32_json:encode(#{ok => true, velocidad => Vel}), json};
responder(paro, Req) ->
  N = id(Req), Seg = num(qs(<<"segundos">>, Req, <<"180">>)),
  Causa = binary_to_atom(qs(<<"causa">>, Req, <<"falla_maquina">>)),
  ok = ok_gen(p32_simulador:paro(N, Seg, Causa)),
  {200, p32_json:encode(#{ok => true, estacion => N, segundos => Seg}), json};
responder(reparar, Req) -> N = id(Req), p32_estacion:reparar(N), {200, p32_json:encode(#{ok => true}), json};
responder(ciclo, Req) ->
  N = id(Req), F = num(qs(<<"factor">>, Req, <<"1.2">>)) * 1.0,
  ok = p32_simulador:factor(N, F),
  {200, p32_json:encode(#{ok => true, estacion => N, factor => F}), json};
responder(matar_estacion, Req) ->
  N = id(Req), {200, p32_json:encode(#{resultado => p32_simulador:matar_estacion(N), estacion => N}), json};
responder(matar_buffer, Req) ->
  N = id(Req), {200, p32_json:encode(#{resultado => p32_simulador:matar_buffer(N), buffer => N}), json};
responder(metricas, _) ->
  E = p32_linea:estado(),
  Lineas = [
    {"p32_piezas_terminadas", maps:get(salidas, E, 0)},
    {"p32_piezas_por_hora", maps:get(th_hora_ventana, E, 0.0)},
    {"p32_wip", maps:get(wip, E, 0)},
    {"p32_estacion_cuello", maps:get(cuello, E, 0)},
    {"p32_tiempo_paro_segundos", maps:get(paro_total_s, E, 0.0)}],
  Txt = [io_lib:format("~s ~s~n", [K, num_txt(V)]) || {K, V} <- Lineas],
  {200, iolist_to_binary(Txt), texto}.

ok_gen(_) -> ok.
qs(K, Req, Def) -> proplists:get_value(K, cowboy_req:parse_qs(Req), Def).
id(Req) -> binary_to_integer(cowboy_req:binding(id, Req)).
num(B) -> try binary_to_integer(B) catch error:_ -> binary_to_float(B) end.
num_txt(V) when is_integer(V) -> integer_to_list(V);
num_txt(V) -> float_to_list(V * 1.0, [{decimals, 3}, compact]).
