% @hidden
-module(jorel_provider_dockerize).
-behaviour(jorel_provider).
-include("../include/jorel.hrl").

-export([init/1, do/1]).

-define(PROVIDER, dockerize).
-define(BUILD(OutputDir, Name), [
                                 {copy, [".", "/app/" ++ Name ++ "/"]},
                                 {workdir, "/app/" ++ Name}
                                ]).
-define(BUILD_ERLANG_CMD(Config), [
                     {cmd, "make distclean && make jorel.release c=" ++ Config}
                    ]).
-define(BUILD_ELIXIR_CMD(Extra), [
                     {cmd, "mix local.hex --force && mix local.rebar --force && mix deps.clean --all && mix clean && mix deps.get && mix compile && mix jorel.release" ++ Extra}
                    ]).
-define(RELEASE(BuildPath, Name), [
                    {copy, [BuildPath ++ "/.", "/app/"]},
                    {workdir, "/app/" ++ Name}
                   ]).
-define(RELEASECMD(Name), [
                       {cmd, ["./bin/" ++ Name, "foreground"]}
                   ]).


init(State) ->
  jorel_config:add_provider(
    State,
    {?PROVIDER,
     #{
        module => ?MODULE,
        depends => [],
        desc => "Create a Docker container with your App"
      }
    }
   ).

do(State) ->
  case jorel_config:get(State, dockerize) of
    {dockerize, []} ->
      ?HALT("!!! Missing dockerize configuration", []);
    {dockerize, Data} ->
      dockerize(State, Data)
  end.

dockerize(State, Data) ->
  ?INFO("== Start provider ~p", [?PROVIDER]),
  {BuildPath, State1} = build_in_docker(State, Data),
  State2 = release_in_docker(State1, Data, BuildPath),
  CleanBuild = buclists:keyfind(clean_build, 1, Data, true),
  _ = if
    CleanBuild ->
      ?DEBUG("* Remove ~s", [BuildPath]),
      case bucfile:remove_recursive(BuildPath) of
        ok ->
          ok;
        {error, Reason} ->
          ?ERROR("! Faild to delete ~s: ~p", [BuildPath, Reason])
      end;
    true ->
      ok
  end,
  ?INFO("== Provider ~p complete", [?PROVIDER]),
  State2.

build_in_docker(State, Data) ->
  case lists:keyfind(build, 1, Data) of
    {build, Conf} ->
      {relname, RelName} = jorel_config:get(State, relname),
      {relvsn, RelVsn} = jorel_config:get(State, relvsn),
      Dockerfile = "Dockerfile.build." ++ bucs:to_string(RelName) ++ "." ++ RelVsn,
      FromImageName = case buclists:keyfind(from, 1, Conf, buclists:keyfind(from, 1, Data, undefined)) of
                        undefined ->
                          ?HALT("!!! Missing from", []);
                        From1 ->
                          From1
                      end,
      Maintainer = case lists:keyfind(maintainer, 1, Data) of
                     false -> {maintainer, "Jorel"};
                     M -> M
                   end,
      {config, JorelConfig} = jorel_config:get(State, config),
      JorelBuildConfig = buclists:keyfind(jorel_config, 1, Data, JorelConfig),
      RemoveOrigin = buclists:keyfind(remove_origins, 1, Data, false),
      RemoveDockerfile = buclists:keyfind(remove_dockerfiles, 1, Data, false),
      BuildImageName = string:to_lower("jbi_" ++ bucrandom:randstr(8)),
      BuildContainerName = string:to_lower("jbc_" ++ bucrandom:randstr(8)),
      BuildPath = buclists:keyfind(output_dir, 1, Data, "_jorel_docker"),
      BuildCMDExtra = case lists:keyfind(use_master, 1, Data) of
        {use_master, true} -> " --master --upgrade";
        _ -> ""
      end,
      {output_dir, OutputDir} = jorel_config:get(State, output_dir),
      DockerAppPath = filename:join(["/app", RelName, OutputDir]),
      case file:open(Dockerfile, [write, binary]) of
        {ok, FD} ->
          ?INFO("* Create ~s", [Dockerfile]),
          DockerfileData = [{from, FromImageName}, Maintainer] ++
          buclists:keyfind(prebuild, 1, Conf, []) ++
          ?BUILD(OutputDir, bucs:to_string(RelName)) ++
          buclists:keyfind(postbuild, 1, Conf, []) ++
          case jorel_elixir:exist() of
            true ->
              ?BUILD_ELIXIR_CMD(BuildCMDExtra);
            false ->
              ?BUILD_ERLANG_CMD(JorelBuildConfig)
          end,
          _ = dockerfile(FD, DockerfileData),
          _ = file:close(FD);
        {error, Reason} ->
          ?HALT("!!! Can't create ~s: ~p", [Dockerfile, Reason])
      end,
      execute(
        "* Create build image (This can take a while... Go get yourself a cup of coffee.)",
        {"docker build --file=~s -q -t ~s .", [Dockerfile, BuildImageName]},
        "!!! Build image faild"
       ),
      execute(
        "* Release application",
        {"docker run --name ~s ~s", [BuildContainerName, BuildImageName]},
        "!!! Build release faild"
       ),
      execute(
        {"* Copy ~s:~s to ~s", [BuildContainerName, DockerAppPath, BuildPath]},
        {"docker cp ~s:~s ~s", [BuildContainerName, DockerAppPath, BuildPath]},
        "!!! Build release faild"
       ),
      execute(
        "* Remove build container and image",
        {"docker rm ~s", [BuildContainerName]},
        {"! Faild to remove container ~s", [BuildContainerName]}
       ),
      execute(
        "* Remove build image",
        {"docker rmi ~s", [BuildImageName]},
        {"! Faild to remove image ~s", [BuildImageName]}
       ),
      if
        RemoveOrigin ->
          execute(
            "* Remove origin image",
            {"docker rmi ~s", [FromImageName]},
            {"! Faild to remove image ~s", [FromImageName]}
           );
        true ->
          ok
      end,
      if
        RemoveDockerfile ->
          ?INFO("* Remove ~s", [Dockerfile]),
          case file:delete(Dockerfile) of
            ok ->
              ok;
            {error, Reason1} ->
              ?ERROR("! Can't delete file ~s: ~p", [Dockerfile, Reason1])
          end;
        true ->
          ok
      end,
      {BuildPath, State};
    false ->
      jorel_provider:run(State, release),
      {output_dir, OutputDir} = jorel_config:get(State, output_dir),
      {OutputDir, State}
  end.

release_in_docker(State, Data, BuildPath) ->
  {relname, RelName} = jorel_config:get(State, relname),
  {relvsn, RelVsn} = jorel_config:get(State, relvsn),
  Dockerfile = "Dockerfile.release." ++ bucs:to_string(RelName) ++ "." ++ RelVsn,
  Conf = buclists:keyfind(release, 1, Data, []),
  Maintainer = case lists:keyfind(maintainer, 1, Data) of
                 false -> {maintainer, "Jorel"};
                 M -> M
               end,
  RemoveOrigin = buclists:keyfind(remove_origins, 1, Data, false),
  RemoveDockerfile = buclists:keyfind(remove_dockerfiles, 1, Data, false),
  BuildImageName = string:to_lower(bucs:to_string(RelName) ++ ":" ++ RelVsn),
  FromImageName = case buclists:keyfind(from, 1, Conf, buclists:keyfind(from, 1, Data, undefined)) of
                    undefined ->
                      ?HALT("!!! Missing from", []);
                    From1 ->
                      From1
                  end,
  ?INFO("* Dockerize ~s", [BuildPath]),
  case file:open(Dockerfile, [write, binary]) of
    {ok, FD} ->
      ?INFO("* Create ~s", [Dockerfile]),
      DockerfileData = [{from, FromImageName}, Maintainer] ++
        buclists:keyfind(prerelease, 1, Conf, []) ++
        ?RELEASE(BuildPath, bucs:to_string(RelName)) ++
        buclists:keyfind(postrelease, 1, Conf, []) ++
        ?RELEASECMD(bucs:to_string(RelName)),
      _ = dockerfile(FD, DockerfileData),
      _ = file:close(FD);
    {error, Reason} ->
      ?HALT("!!! Can't create ~s: ~p", [Dockerfile, Reason])
  end,
  ?INFO("* Build release image ~s (This can take a while... Go get yourself a cup of coffee.)", [BuildImageName]),
  _ = case sh:sh("docker build --file=~s -q -t ~s .", [Dockerfile, BuildImageName], [return_on_error]) of
        {ok, _} ->
          ok;
        {error, _} ->
          ?HALT("!!! Build image faild", [])
      end,
  if
    RemoveOrigin ->
      ?INFO("* Remove origin image", []),
      _ = case sh:sh("docker rmi ~s", [FromImageName], [return_on_error]) of
            {ok, _} ->
              ok;
            {error, _} ->
              ?ERROR("! Faild to remove image ~s", [FromImageName])
          end;
    true ->
      ok
  end,
  if
    RemoveDockerfile ->
      ?INFO("* Remove ~s", [Dockerfile]),
      case file:delete(Dockerfile) of
        ok ->
          ok;
        {error, Reason1} ->
          ?ERROR("! Can't delete file ~s: ~p", [Dockerfile, Reason1])
      end;
    true ->
      ok
  end,
  State.

dockerfile(_, []) -> ok;
dockerfile(FD, [{label, Key, Value}|Data]) ->
  file:write(FD, io_lib:format("LABEL ~s=\"~s\"~n", [Key, Value])),
  dockerfile(FD, Data);
dockerfile(FD, [{env, Key, Value}|Data]) ->
  file:write(FD, io_lib:format("ENV ~s=\"~s\"~n", [Key, Value])),
  dockerfile(FD, Data);
dockerfile(FD, [{expose, Ports}|Data]) ->
  file:write(FD, io_lib:format("EXPOSE ~s~n", [string:join([bucs:to_string(E) || E <- Ports], " ")])),
  dockerfile(FD, Data);
dockerfile(FD, [{cmd, Cmd}|Data]) ->
  case is_list_of_list(Cmd) of
    true ->
      file:write(FD, io_lib:format("CMD [~s]~n",
                                   [string:join(["\"" ++ bucs:to_string(P) ++ "\"" || P <- Cmd], ", ")])),
      dockerfile(FD, Data);
    false ->
      file:write(FD, io_lib:format("CMD ~s~n", [Cmd])),
      dockerfile(FD, Data)
  end;
dockerfile(FD, [{Cmd, Paths}|Data]) when Cmd == add; Cmd == copy; Cmd == entrypoint, Cmd == volume ->
  file:write(FD, io_lib:format("~s [~s]~n",
                               [string:to_upper(bucs:to_string(Cmd)),
                                string:join(["\"" ++ bucs:to_string(P) ++ "\"" || P <- Paths], ", ")])),
  dockerfile(FD, Data);
dockerfile(FD, [{Cmd, Param}|Data]) ->
  file:write(FD, io_lib:format("~s ~s~n", [string:to_upper(bucs:to_string(Cmd)), Param])),
  dockerfile(FD, Data).

is_list_of_list(L) when is_list(L) ->
  lists:all(fun is_list/1, L);
is_list_of_list(_) ->
  false.

execute({Message, MessageArgs}, Command, {ErrorMessage, ErrorMessageArgs}) ->
  ?INFO(Message, MessageArgs),
  case bucos:run(Command, [display_stdout]) of
    {ok, _} -> ok;
    _ -> ?HALT(ErrorMessage, ErrorMessageArgs)
  end;
execute(Message, Command, ErrorMessage) when is_list(Message) ->
  execute({Message, []}, Command, ErrorMessage);
execute(Message, Command, ErrorMessage) when is_list(ErrorMessage) ->
  execute(Message, Command, {ErrorMessage, []}).

