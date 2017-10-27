-module(jorel_release_app_elixir_tests).
-include_lib("eunit/include/eunit.hrl").

jorel_release_jorel_elixir_test_() ->
  {"Build release for Elixir app",
   {setup,
    fun() ->
        bucfile:make_dir(".tests-ex")
    end,
    fun(_) ->
        bucfile:remove_recursive(".tests-ex")
    end,
    [
     {timeout, 200,
      fun() ->
          ?assertEqual(ok, bucfile:make_dir(".tests-ex/0.0.1")),
          ?assertEqual(ok, bucfile:copy("test_apps/0.0.1/elixir_test", ".tests-ex/0.0.1", [recursive])),
          ?assertEqual(ok, bucfile:make_dir(".tests-ex/0.0.1/elixir_test/.jorel")),
          ?assertEqual(ok, bucfile:copy("_build/default/bin/jorel", ".tests-ex/0.0.1/elixir_test/.jorel/jorel"))
      end}
     , {timeout, 200,
        fun() ->
            ?assertMatch({ok, _},
                         bucos:run("mix compile",
                                   [{cd, ".tests-ex/0.0.1/elixir_test"}]))
        end}
     , {timeout, 200,
        fun() ->
            ?assertMatch({ok, _},
                         bucos:run(".jorel/jorel gen_config -v 0.0.1",
                                   [{cd, ".tests-ex/0.0.1/elixir_test"}]))
        end}
     , {timeout, 200,
        fun() ->
            ?assertMatch({ok, _},
                         bucos:run(".jorel/jorel release",
                                   [{cd, ".tests-ex/0.0.1/elixir_test"}]))
        end}
     , {timeout, 200,
        fun() ->
            ?assertMatch({error, 1, "Node 'elixir_test@127.0.0.1' not responding to pings.\n"},
                         bucos:run("_jorel/elixir_test/bin/elixir_test ping",
                                   [stdout_on_error, {cd, ".tests-ex/0.0.1/elixir_test"}]))
        end}
     , {timeout, 200,
        fun() ->
            ?assertMatch({ok, []},
                         bucos:run("_jorel/elixir_test/bin/elixir_test start",
                                   [{cd, ".tests-ex/0.0.1/elixir_test"}])),
            timer:sleep(1000)
        end}
     , {timeout, 200,
        fun() ->
            ?assertMatch({ok, "pong\n"},
                         bucos:run("_jorel/elixir_test/bin/elixir_test ping",
                                   [{cd, ".tests-ex/0.0.1/elixir_test"}]))
        end}
     , {timeout, 200,
        fun() ->
            ?assertMatch({ok, []},
                         bucos:run("_jorel/elixir_test/bin/elixir_test stop",
                                   [{cd, ".tests-ex/0.0.1/elixir_test"}]))
        end}
     , {timeout, 200,
        fun() ->
            ?assertMatch({error, 1, "Node 'elixir_test@127.0.0.1' not responding to pings.\n"},
                         bucos:run("_jorel/elixir_test/bin/elixir_test ping",
                                   [stdout_on_error, {cd, ".tests-ex/0.0.1/elixir_test"}]))
        end}
    ]}}.
