%% Funciones PURAS: reciben la foto del sistema y un historial de fotos y devuelven
%% indicadores. Sin procesos ni efectos, por eso son faciles de probar con eunit.
-module(p32_metricas).
-export([ligera/1, calcular/3, ventana_s/0]).
-define(VENTANA, 600.0).   %% ventana movil en segundos simulados (10 min)
-define(TAKT, 30.0).       %% 27000 s / 900 unidades
-define(DEMANDA, 900).

ventana_s() -> ?VENTANA.

%% Resumen minimo de una foto para guardar en el historial.
ligera(#{t_sim := T, salidas := S, estaciones := Est}) ->
  {T, #{salidas => S, proc => [maps:get(procesando, E) || E <- Est],
        esp => [maps:get(esperando, E) || E <- Est],
        bloq => [maps:get(bloqueada, E) || E <- Est],
        falla => [maps:get(falla, E) || E <- Est]}}.

%% Hist: lista de {T, Ligera}, la mas reciente primero.
calcular(Foto = #{t_sim := T, estaciones := Est, buffers := Bufs, salidas := Sal}, Hist, Vent) ->
  {T0, L0} = hallar_inicio(T, Hist, Vent),
  Dt = max(T - T0, 1.0e-6),
  Frac = fun(Campo, I, Actual) ->
    Ant = case L0 of undefined -> 0.0; _ -> lists:nth(I, maps:get(Campo, L0)) end,
    min(1.0, max(0.0, (Actual - Ant) / Dt))
  end,
  Con = [begin
    I = maps:get(id, E),
    E#{util => Frac(proc, I, maps:get(procesando, E)),
       pct_esp => Frac(esp, I, maps:get(esperando, E)),
       pct_bloq => Frac(bloq, I, maps:get(bloqueada, E)),
       pct_falla => Frac(falla, I, maps:get(falla, E))}
  end || E <- Est],
  EnFalla = [maps:get(id, E) || E <- Con, maps:get(estado, E) =:= falla],
  {Cuello, Razon} = case EnFalla of
    [F | _] -> {F, paro};
    [] -> cuello_por_util(Con, Dt)
  end,
  SalAnt = case L0 of undefined -> 0; _ -> maps:get(salidas, L0) end,
  ThVentana = (Sal - SalAnt) / Dt * 3600,
  ThAcum = case T > 0 of true -> Sal / T * 3600; false -> 0.0 end,
  Wip = lists:sum([maps:get(nivel, B) || B <- Bufs]) +
        length([1 || E <- Est, maps:get(pieza, E) =/= null]),
  Ciclos = [maps:get(ciclo_s, E) || E <- Est],
  CapHora = 3600 / lists:max(Ciclos),
  Cierre = [E#{rol => rol(E, Cuello)} || E <- Con],
  #{t_sim => T, vel => maps:get(vel, Foto), produciendo => maps:get(produciendo, Foto),
    terminado => maps:get(terminado, Foto), salidas => Sal, creadas => maps:get(creadas, Foto),
    demanda => ?DEMANDA, takt_s => ?TAKT,
    th_hora_ventana => ThVentana, th_hora_acum => ThAcum, capacidad_hora => CapHora,
    th_objetivo_hora => 3600 / ?TAKT,
    wip => Wip,
    ciclo_little_s => case ThVentana > 0 of true -> Wip / (ThVentana / 3600); false -> 0.0 end,
    cuello => Cuello, razon_cuello => Razon,
    paro_total_s => lists:sum([maps:get(falla, E) || E <- Est]),
    estaciones => Cierre, buffers => Bufs}.

hallar_inicio(_T, [], _V) -> {0.0, undefined};
hallar_inicio(T, Hist, V) ->
  Dentro = [H || H = {Ti, _} <- Hist, Ti >= T - V],
  case Dentro of
    [] -> {0.0, undefined};
    _ -> lists:last(Dentro)
  end.

%% El cuello es la estacion mas ocupada procesando en la ventana (no la que espera).
cuello_por_util(Con, Dt) when Dt < 1.0 -> {maps:get(id, hd(Con)), ninguno};
cuello_por_util(Con, _Dt) ->
  [{U, Id} | _] = lists:reverse(lists:sort([{maps:get(util, E), maps:get(id, E)} || E <- Con])),
  case U > 0.05 of true -> {Id, utilizacion}; false -> {Id, ninguno} end.

rol(E, Cuello) ->
  case {maps:get(estado, E), maps:get(id, E) =:= Cuello} of
    {falla, _} -> paro;
    {_, true} -> cuello;
    _ ->
      case {maps:get(pct_esp, E) > 0.30, maps:get(pct_bloq, E) > 0.30} of
        {true, _} -> inanicion;
        {_, true} -> bloqueo;
        _ -> normal
      end
  end.
