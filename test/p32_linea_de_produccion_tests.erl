-module(p32_linea_de_produccion_tests).
-include_lib("eunit/include/eunit.hrl").
-define(VEL, 2000).   %% 1 s simulado = 0.5 ms real (pruebas rapidas)

%% ---------- puras ----------
json_test() ->
  ?assertEqual(<<"{\"a\":[1,2.5,\"x\"],\"b\":true}">>, p32_json:encode(#{a => [1, 2.5, <<"x">>], b => true})).

foto(Util, Fallas) ->
  Est = [#{id => I, estado => case lists:member(I, Fallas) of true -> falla; false -> procesando end,
           pieza => 1, hechas => 0, reinicios => 0, causa => none, falla_restante => 0, ciclo_s => 30.0,
           procesando => U * 100.0, esperando => (1 - U) * 100.0, bloqueada => 0.0, falla => 0.0}
         || {I, U} <- lists:zip(lists:seq(1, length(Util)), Util)],
  #{run => 1, t_sim => 100.0, vel => 50, produciendo => true, terminado => false, creadas => 10,
    salidas => 5, estaciones => Est, buffers => [#{id => 1, nivel => 2, cap => 5}]}.

cuello_es_la_mas_ocupada_test() ->
  F = foto([0.7, 0.9, 1.0, 0.8], []),
  R = p32_metricas:calcular(F, [p32_metricas:ligera((foto([0,0,0,0], []))#{t_sim := 0.0, salidas := 0})], 600.0),
  ?assertEqual(3, maps:get(cuello, R)),
  ?assertEqual(utilizacion, maps:get(razon_cuello, R)).

paro_gana_sobre_utilizacion_test() ->
  F = foto([0.7, 0.9, 1.0, 0.8], [2]),
  R = p32_metricas:calcular(F, [], 600.0),
  ?assertEqual({2, paro}, {maps:get(cuello, R), maps:get(razon_cuello, R)}).

%% ---------- con la linea corriendo ----------
linea_test_() ->
  {setup,
   fun() ->
       application:set_env(p32_linea_de_produccion, puerto, 0),
       {ok, _} = application:ensure_all_started(p32_linea_de_produccion), ok
   end,
   fun(_) -> application:stop(p32_linea_de_produccion) end,
   {inorder, [
     {timeout, 30, fun conserva_piezas_/0},
     {timeout, 30, fun buffers_nunca_exceden_capacidad_/0},
     {timeout, 30, fun paro_propaga_y_conserva_pieza_/0},
     {timeout, 40, fun matar_estacion_no_pierde_ni_duplica_/0},
     {timeout, 40, fun cuello_se_mueve_/0}
   ]}}.

arrancar() -> ok = p32_simulador:iniciar_turno(?VEL), ok = p32_simulador:sin_escenario(), timer:sleep(300).

foto() -> p32_registro:foto().
en_linea(#{buffers := B, estaciones := E}) ->
  lists:sum([N || #{nivel := N} <- B]) + length([x || #{pieza := P} <- E, P =/= null]).

%% Detiene la entrada y deja que la linea se vacie; invariante: creadas = salidas.
vaciar() ->
  p32_registro:set_cfg(material, false),
  esperar(fun() -> en_linea(foto()) =:= 0 end, 15000).

esperar(F, Max) when Max =< 0 -> ?assert(F());
esperar(F, Max) -> case F() of true -> ok; false -> timer:sleep(50), esperar(F, Max - 50) end.

conserva_piezas_() ->
  arrancar(), timer:sleep(1500),
  F = foto(),
  ?assertEqual(maps:get(creadas, F), maps:get(salidas, F) + en_linea(F)),
  vaciar(),
  F2 = foto(),
  ?assertEqual(maps:get(creadas, F2), maps:get(salidas, F2)),
  ?assert(maps:get(salidas, F2) > 10).

buffers_nunca_exceden_capacidad_() ->
  arrancar(),
  p32_estacion:paro(8, 5000, falla_maquina),      %% la ultima estacion se detiene: todo se bloquea hacia atras
  Max = lists:max([muestrear(10) || _ <- lists:seq(1, 40)]),
  ?assert(Max =< 5),
  F = foto(),
  Estados = [maps:get(estado, E) || E <- maps:get(estaciones, F)],
  ?assertEqual(falla, lists:last(Estados)),
  ?assertEqual(bloqueada, lists:nth(7, Estados)),                  %% bloqueo aguas arriba
  ?assertEqual(5, maps:get(nivel, lists:last(maps:get(buffers, F)))).     %% el buffer pegado al paro esta lleno
muestrear(Ms) -> timer:sleep(Ms), lists:max([N || #{nivel := N} <- maps:get(buffers, foto())]).

paro_propaga_y_conserva_pieza_() ->
  arrancar(),
  esperar(fun() -> maps:get(pieza, lists:nth(4, maps:get(estaciones, foto()))) =/= null end, 3000),
  p32_estacion:paro(4, 3000, falla_maquina),
  timer:sleep(200),
  E4 = lists:nth(4, maps:get(estaciones, foto())),
  Pieza = maps:get(pieza, E4),
  ?assertEqual(falla, maps:get(estado, E4)),
  ?assertNotEqual(null, Pieza),                                    %% la pieza a medias NO se pierde
  timer:sleep(500),
  ?assertEqual(Pieza, maps:get(pieza, lists:nth(4, maps:get(estaciones, foto())))),
  Estados = [maps:get(estado, E) || E <- maps:get(estaciones, foto())],
  ?assertEqual(esperando, lists:last(Estados)),                    %% inanicion aguas abajo
  p32_estacion:reparar(4),
  esperar(fun() -> maps:get(estado, lists:nth(4, maps:get(estaciones, foto()))) =/= falla end, 2000),
  vaciar(),
  F = foto(), ?assertEqual(maps:get(creadas, F), maps:get(salidas, F)).

matar_estacion_no_pierde_ni_duplica_() ->
  arrancar(), timer:sleep(500),
  [begin ok = p32_simulador:matar_estacion(N), timer:sleep(120) end || N <- [1, 3, 5, 5, 2, 8, 6, 4]],
  ok = p32_simulador:matar_buffer(3),
  timer:sleep(1500),
  F = foto(),
  ?assert(lists:sum([maps:get(reinicios, E) || E <- maps:get(estaciones, F)]) >= 8),
  vaciar(),
  F2 = foto(),
  ?assertEqual(maps:get(creadas, F2), maps:get(salidas, F2)),      %% ni perdidas...
  Ids = [Id || {{salida, Id}, _} <- ets:tab2list(p32_reg)],
  ?assertEqual(length(Ids), length(lists:usort(Ids))).             %% ...ni duplicadas

cuello_se_mueve_() ->
  arrancar(),
  esperar(fun() -> maps:get(cuello, p32_linea:estado()) =:= 6 end, 8000),       %% base: estacion 6 (36 s)
  ok = p32_simulador:factor(2, 2.0),                                              %% estacion 2 pasa a 60 s
  esperar(fun() -> maps:get(cuello, p32_linea:estado()) =:= 2 end, 12000),
  E = p32_linea:estado(),
  ?assertEqual(utilizacion, maps:get(razon_cuello, E)),
  ?assert(maps:get(capacidad_hora, E) < maps:get(th_objetivo_hora, E)).   %% 60 piezas/h < 120 piezas/h del takt
