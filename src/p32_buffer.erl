%% Buffer finito entre la estacion N y la N+1. La cola vive en ETS (p32_registro) para
%% sobrevivir reinicios; este proceso solo serializa el acceso. Cuando esta lleno, la
%% estacion anterior queda "bloqueada" (backpressure); cuando esta vacio, la siguiente "espera".
-module(p32_buffer).
-behaviour(gen_server).
-export([start_link/1, tomar/2, poner/3, nombre/1]).
-export([init/1, handle_call/3, handle_cast/2]).

nombre(N) -> list_to_atom("p32_buffer_" ++ integer_to_list(N)).
start_link(N) -> gen_server:start_link({local, nombre(N)}, ?MODULE, N, []).

%% Buffer N -> estacion Est toma una pieza (o vacio).
tomar(N, Est) -> try p32_registro:tomar(N, Est) catch exit:_ -> vacio end.
%% La estacion Est deja su pieza en el buffer N (ok | lleno).
poner(N, Est, Id) -> try p32_registro:poner(N, Est, Id) catch exit:_ -> lleno end.

init(N) -> {ok, N}.
handle_call(_, _From, N) -> {reply, ok, N}.
handle_cast(_, N) -> {noreply, N}.
