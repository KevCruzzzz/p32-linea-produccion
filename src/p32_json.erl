%% Codificador JSON minimo (OTP 25 no trae modulo json). Solo mapas, listas, binarios, atomos y numeros.
-module(p32_json).
-export([encode/1]).

encode(true) -> <<"true">>;
encode(false) -> <<"false">>;
encode(null) -> <<"null">>;
encode(undefined) -> <<"null">>;
encode(A) when is_atom(A) -> str(atom_to_binary(A));
encode(B) when is_binary(B) -> str(B);
encode(I) when is_integer(I) -> integer_to_binary(I);
encode(F) when is_float(F) -> float_to_binary(F, [{decimals, 3}, compact]);
encode(L) when is_list(L) -> iolist_to_binary([$[, lists:join($,, [encode(X) || X <- L]), $]]);
encode(M) when is_map(M) ->
  Pares = [[str(clave(K)), $:, encode(V)] || {K, V} <- lists:sort(maps:to_list(M))],
  iolist_to_binary([${, lists:join($,, Pares), $}]).

clave(K) when is_atom(K) -> atom_to_binary(K);
clave(K) when is_binary(K) -> K;
clave(K) when is_integer(K) -> integer_to_binary(K).

str(B) -> iolist_to_binary([$", esc(B), $"]).
esc(<<>>) -> [];
esc(<<$", R/binary>>) -> [$\\, $" | esc(R)];
esc(<<$\\, R/binary>>) -> [$\\, $\\ | esc(R)];
esc(<<$\n, R/binary>>) -> [$\\, $n | esc(R)];
esc(<<C, R/binary>>) when C < 32 -> esc(R);
esc(<<C, R/binary>>) -> [C | esc(R)].
