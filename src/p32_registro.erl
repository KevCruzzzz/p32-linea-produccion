%% Dueno de la tabla ETS publica con el estado duradero de la linea.
%% Claves:  {est,N} estado/acumulados de la estacion   {pieza,N} pieza en manos de la estacion
%%          {buf,N} cola del buffer N (entre N y N+1)   {vista,N,Id} piezas ya aceptadas (dedup)
%%          {salida,Id} piezas terminadas                {ev,Seq} bitacora   {cfg,K} configuracion
-module(p32_registro).
-behaviour(gen_server).
-export([start_link/0, reset/2, cfg/1, cfg/2, set_cfg/2, ahora_ms/0, t_sim/0, ms_a_sim/1, sim_a_ms/1,
         nueva_pieza/1, tomar/2, poner/3, salir/2,
         leer_est/1, guardar_est/2, leer_pieza/1, guardar_pieza/2, factor/1,
         evento/2, eventos/1, foto/0, ciclo_base/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).
-define(T, p32_reg).
-define(CICLOS, [28, 30, 27, 34, 31, 36, 29, 32]).   %% s por estacion (rango 25-40 s)

start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% ---- tiempo ---- (OJO: el reloj monotonico puede ser NEGATIVO; nunca usar 0 como "ya paso")
ahora_ms() -> erlang:monotonic_time(millisecond).
cfg(K) -> cfg(K, undefined).
cfg(K, Def) -> case ets:lookup(?T, {cfg, K}) of [{_, V}] -> V; [] -> Def end.
set_cfg(K, V) -> ets:insert(?T, {{cfg, K}, V}).
ms_a_sim(Ms) -> Ms * cfg(vel, 50) / 1000.
sim_a_ms(S) -> round(S * 1000 / cfg(vel, 50)).
t_sim() -> ms_a_sim(ahora_ms() - cfg(t0, ahora_ms())).
ciclo_base(N) -> lists:nth(N, ?CICLOS).
factor(N) -> case ets:lookup(?T, {factor, N}) of [{_, F}] -> F; [] -> 1.0 end.

%% ---- API de estado (todas serializadas por el gen_server cuando mueven piezas) ----
reset(Vel, Produciendo) -> gen_server:call(?MODULE, {reset, Vel, Produciendo}).
nueva_pieza(Est) -> gen_server:call(?MODULE, {nueva, Est}).
tomar(Buf, Est) -> gen_server:call(?MODULE, {tomar, Buf, Est}).
poner(Buf, Est, Id) -> gen_server:call(?MODULE, {poner, Buf, Est, Id}).
salir(Est, Id) -> gen_server:call(?MODULE, {salir, Est, Id}).

leer_est(N) -> case ets:lookup(?T, {est, N}) of [{_, R}] -> R; [] -> undefined end.
guardar_est(N, R) -> ets:insert(?T, {{est, N}, R}).
leer_pieza(N) -> case ets:lookup(?T, {pieza, N}) of [{_, P}] -> P; [] -> none end.
guardar_pieza(N, P) -> ets:insert(?T, {{pieza, N}, P}).

evento(Tipo, Datos) ->
  Seq = ets:update_counter(?T, {cnt, ev}, 1, {{cnt, ev}, 0}),
  ets:insert(?T, {{ev, Seq}, #{n => Seq, t_sim => round(t_sim()), tipo => Tipo, datos => Datos}}),
  ok.
eventos(Max) ->
  Ult = cfg_cnt(ev),
  [E || S <- lists:seq(Ult, max(1, Ult - Max + 1), -1), [{_, E}] <- [ets:lookup(?T, {ev, S})]].
cfg_cnt(K) -> case ets:lookup(?T, {cnt, K}) of [{_, V}] -> V; [] -> 0 end.

%% ---- foto del sistema (acumulados incluyen el intervalo en curso) ----
foto() ->
  Now = ahora_ms(), Vel = cfg(vel, 50), N = cfg(n, 8),
  Est = [begin
    #{estado := E, desde := D, acc := Acc} = R = leer_est(I),
    Acc1 = Acc#{E := maps:get(E, Acc) + (Now - D)},
    P = leer_pieza(I),
    #{id => I, estado => E, hechas => maps:get(hechas, R), reinicios => maps:get(reinicios, R),
      causa => maps:get(causa, R),
      falla_restante => case E of falla -> max(0, (maps:get(falla_hasta, R) - Now) * Vel / 1000); _ -> 0 end,
      pieza => case P of #{id := Id} -> Id; _ -> null end,
      ciclo_s => ciclo_base(I) * factor(I),
      procesando => maps:get(procesando, Acc1) * Vel / 1000,
      esperando => maps:get(esperando, Acc1) * Vel / 1000,
      bloqueada => maps:get(bloqueada, Acc1) * Vel / 1000,
      falla => maps:get(falla, Acc1) * Vel / 1000}
  end || I <- lists:seq(1, N)],
  Buf = [#{id => I, nivel => case ets:lookup(?T, {buf, I}) of [{_, C}] -> length(C); [] -> 0 end,
           cap => cfg(buf_cap, 5)} || I <- lists:seq(1, N - 1)],
  #{run => cfg(t0), t_sim => t_sim(), vel => Vel, produciendo => cfg(produciendo, false),
    terminado => cfg(terminado, false), creadas => cfg_cnt(pieza), salidas => cfg_cnt(salidas),
    estaciones => Est, buffers => Buf}.

%% ---- gen_server ----
init([]) ->
  ets:new(?T, [named_table, public, set, {read_concurrency, true}]),
  poblar(50, false),
  {ok, #{}}.

handle_call({reset, Vel, Prod}, _From, S) ->
  ets:delete_all_objects(?T), poblar(Vel, Prod), {reply, ok, S};
handle_call({nueva, Est}, _From, S) ->
  case cfg(produciendo, false) andalso cfg(material, true) of
    true ->
      Id = ets:update_counter(?T, {cnt, pieza}, 1, {{cnt, pieza}, 0}),
      guardar_pieza(Est, #{id => Id, fase => nueva}),
      {reply, {ok, Id}, S};
    false -> {reply, vacio, S}
  end;
handle_call({tomar, Buf, Est}, _From, S) ->
  case ets:lookup(?T, {buf, Buf}) of
    [{_, [H | T]}] ->
      ets:insert(?T, [{{buf, Buf}, T}, {{pieza, Est}, #{id => H, fase => nueva}}]),
      {reply, {ok, H}, S};
    _ -> {reply, vacio, S}
  end;
handle_call({poner, Buf, Est, Id}, _From, S) ->
  [{_, Cola}] = ets:lookup(?T, {buf, Buf}),
  Ya = lists:member(Id, Cola) orelse ets:member(?T, {vista, Buf, Id}),
  Cap = cfg(buf_cap, 5),
  if Ya -> ets:insert(?T, {{pieza, Est}, none}), {reply, ok, S};
     length(Cola) < Cap ->
       ets:insert(?T, [{{buf, Buf}, Cola ++ [Id]}, {{vista, Buf, Id}, true}, {{pieza, Est}, none}]),
       {reply, ok, S};
     true -> {reply, lleno, S}
  end;
handle_call({salir, Est, Id}, _From, S) ->
  case ets:insert_new(?T, {{salida, Id}, t_sim()}) of
    true -> ets:update_counter(?T, {cnt, salidas}, 1, {{cnt, salidas}, 0});
    false -> ok
  end,
  ets:insert(?T, {{pieza, Est}, none}),
  {reply, ok, S}.

handle_cast(_, S) -> {noreply, S}.
handle_info(_, S) -> {noreply, S}.

poblar(Vel, Prod) ->
  Now = ahora_ms(), N = 8,
  ets:insert(?T, [{{cfg, vel}, Vel}, {{cfg, t0}, Now}, {{cfg, n}, N}, {{cfg, buf_cap}, 5},
                  {{cfg, produciendo}, Prod}, {{cfg, material}, true}, {{cfg, terminado}, false}]),
  [ets:insert(?T, [{{est, I}, #{estado => esperando, desde => Now, hechas => 0, reinicios => 0,
                                falla_hasta => Now, causa => none, volver => esperando,
                                acc => #{esperando => 0, procesando => 0, bloqueada => 0, falla => 0}}},
                   {{pieza, I}, none}]) || I <- lists:seq(1, N)],
  [ets:insert(?T, {{buf, I}, []}) || I <- lists:seq(1, N - 1)],
  ok.
