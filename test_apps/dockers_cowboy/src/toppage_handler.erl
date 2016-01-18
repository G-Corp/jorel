%% Feel free to use, reuse and abuse the code in this file.

%% @doc Hello world handler.
-module(toppage_handler).

-export([init/2]).

init(Req, Opts) ->
  Uuid = list_to_binary(uuid:to_string(uuid:uuid1())),
	Req2 = cowboy_req:reply(200, [
		{<<"content-type">>, <<"text/plain">>}
	], <<"Hello world! ", Uuid/binary>>, Req),
	{ok, Req2, Opts}.
