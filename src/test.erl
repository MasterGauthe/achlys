%%%-------------------------------------------------------------------
%%% @author Igor Kopestenski
%%% 2019, <UCLouvain>
%%% @doc
%%% Sample generic server demonstrating usage of the Achlys task
%%% model API.
%%% @end
%%%-------------------------------------------------------------------
-module(test).
-author("Igor Kopestenski").

-behaviour(gen_server).

%% API
-export([start_link/0]).

%% Adds the pmodnav_task to the working set
%% using the Achlys task model
-export([add_pmodnav_task/0,
show/0,
add_task_mintemp/0,
add_task_meantemp/0,
add_task_1/1,
add_task_temp/1]).

%% gen_server callbacks
-export([init/1 ,
handle_call/3 ,
handle_cast/2 ,
handle_info/2 ,
terminate/2 ,
code_change/3]).

-define(SERVER , ?MODULE).

-record(state , {}).

%%%===================================================================
%%% API
%%%===================================================================

println(What) -> io:format("~p~n", [What]).

average(List) ->
  lists:sum(List) / length(List).

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
-spec(start_link() ->
  {ok , Pid :: pid()} | ignore | {error , Reason :: term()}).
start_link() ->
  gen_server:start_link({local , ?SERVER} , ?MODULE , [] , []).

-spec(show() ->
  {ok , Pid :: pid()} | ignore | {error , Reason :: term()}).
show() ->
  EWType = state_ewflag,
  EWVarName = <<"ewvar">>,
  GCountType = state_gcounter,
  GCountVarName = <<"gcountvar">>,

  {ok, {GCount, _, _, _}} = lasp:declare({GCountVarName, GCountType}, GCountType),
  {ok, GCountRes0} = lasp:query(GCount),
    {ok, {EW, _, _, _}} = lasp:declare({EWVarName, EWType}, EWType),
    {ok, EWRes0} = lasp:query(EW),

      println(GCountRes0),
      println(EWRes0).

    %%--------------------------------------------------------------------
    %% @doc
    %% Propagates the pmodnav_task
    %% @end
    %%--------------------------------------------------------------------
    -spec(add_pmodnav_task() ->
      {ok , Pid :: pid()} | ignore | {error , Reason :: term()}).
    add_pmodnav_task() ->
      gen_server:cast(?SERVER
      , {task, pmodnav_task()}).

    -spec(add_task_1(_Threshold) ->
      {ok , Pid :: pid()} | ignore | {error , Reason :: term()}).
    add_task_1(Threshold) ->
      gen_server:cast(?SERVER
      , {task, task_1(Threshold)}).

    -spec(add_task_temp(_Mode) ->
      {ok , Pid :: pid()} | ignore | {error , Reason :: term()}).
    add_task_temp(Mode) ->
      gen_server:cast(?SERVER
      , {task, temp(Mode)}).

    -spec(add_task_meantemp() ->
      {ok , Pid :: pid()} | ignore | {error , Reason :: term()}).
    add_task_meantemp() ->
      gen_server:cast(?SERVER
      , {task, meantemp_task()}).


    -spec(add_task_mintemp() ->
      {ok , Pid :: pid()} | ignore | {error , Reason :: term()}).
    add_task_mintemp() ->
      gen_server:cast(?SERVER
      , {task, mintemp_task()}).


    %%%===================================================================
    %%% gen_server callbacks
    %%%===================================================================

    %%--------------------------------------------------------------------
    %% @private
    %% @doc
    %% Initializes the server
    %%
    %% @spec init(Args) -> {ok, State} |
    %%                     {ok, State, Timeout} |
    %%                     ignore |
    %%                     {stop, Reason}
    %% @end
    %%--------------------------------------------------------------------
    -spec(init(Args :: term()) ->
      {ok , State :: #state{}} | {ok , State :: #state{} , timeout() | hibernate} |
      {stop , Reason :: term()} | ignore).
    init([]) ->
      ok = loop_schedule_task(1, 200),
      logger:log(critical, "Running provider ~n"),
      {ok , #state{}}.

    %%--------------------------------------------------------------------
    %% @private
    %% @doc
    %% Handling call messages
    %%
    %% @end
    %%--------------------------------------------------------------------
    -spec(handle_call(Request :: term() , From :: {pid() , Tag :: term()} ,
    State :: #state{}) ->
      {reply , Reply :: term() , NewState :: #state{}} |
      {reply , Reply :: term() , NewState :: #state{} , timeout() | hibernate} |
      {noreply , NewState :: #state{}} |
      {noreply , NewState :: #state{} , timeout() | hibernate} |
      {stop , Reason :: term() , Reply :: term() , NewState :: #state{}} |
      {stop , Reason :: term() , NewState :: #state{}}).
    handle_call(_Request , _From , State) ->
      {reply , ok , State}.

    %%--------------------------------------------------------------------
    %% @private
    %% @doc
    %% Handling cast messages
    %%
    %% @end
    %%--------------------------------------------------------------------
    -spec(handle_cast(Request :: term() , State :: #state{}) ->
      {noreply , NewState :: #state{}} |
      {noreply , NewState :: #state{} , timeout() | hibernate} |
      {stop , Reason :: term() , NewState :: #state{}}).
    handle_cast({task, Task} , State) ->
      logger:log(critical, "Received task cast signal ~n"),
      %% Task propagation to the cluster, including self
      achlys:bite(Task),
      {noreply , State};
    handle_cast(_Request , State) ->
      {noreply , State}.

    %%--------------------------------------------------------------------
    %% @private
    %% @doc
    %% Handling all non call/cast messages
    %%
    %% @spec handle_info(Info, State) -> {noreply, State} |
    %%                                   {noreply, State, Timeout} |
    %%                                   {stop, Reason, State}
    %% @end
    %%--------------------------------------------------------------------
    -spec(handle_info(Info :: timeout() | term() , State :: #state{}) ->
      {noreply , NewState :: #state{}} |
      {noreply , NewState :: #state{} , timeout() | hibernate} |
      {stop , Reason :: term() , NewState :: #state{}}).
    handle_info({task, Task} , State) ->
      logger:log(critical, "Received task signal ~n"),
      %% Task propagation to the cluster, including self
      achlys:bite(Task),
      {noreply , State};
    handle_info(_Info , State) ->
      {noreply , State}.

    %%--------------------------------------------------------------------
    %% @private
    %% @doc
    %% This function is called by a gen_server when it is about to
    %% terminate. It should be the opposite of Module:init/1 and do any
    %% necessary cleaning up. When it returns, the gen_server terminates
    %% with Reason. The return value is ignored.
    %%
    %% @spec terminate(Reason, State) -> void()
    %% @end
    %%--------------------------------------------------------------------
    -spec(terminate(Reason :: (normal | shutdown | {shutdown , term()} | term()) ,
    State :: #state{}) -> term()).
  terminate(_Reason , _State) ->
    ok.

  %%--------------------------------------------------------------------
  %% @private
  %% @doc
  %% Convert process state when code is changed
  %%
  %% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
  %% @end
  %%--------------------------------------------------------------------
  -spec(code_change(OldVsn :: term() | {down , term()} , State :: #state{} ,
  Extra :: term()) ->
    {ok , NewState :: #state{}} | {error , Reason :: term()}).
  code_change(_OldVsn , State , _Extra) ->
    {ok , State}.

  %%%===================================================================
  %%% Internal functions
  %%%===================================================================

  schedule_task() ->
    %% Declare an Achlys task that will be
    %% executed exactly once
    Task = achlys:declare(mytask
    , all
    , single
    , fun() ->
      io:format("Hello Joe ! ~n")
    end),
    %% Send the task to the current server module
    %% after a 5000ms delay
    erlang:send_after(5000, ?SERVER, {task, Task}),
    ok.

  %%%===================================================================

  loop_schedule_task(0, Time) ->
    io:format("Finish! ~n"),
    ok;
  loop_schedule_task(Count, Time) ->
    %% Declare an Achlys task that will be
    %% executed more than once
    Task = achlys:declare(mytask
    , all
    , single
    , fun() ->
      println(Count),
      loop_schedule_task(Count-1, Time)
    end),
    {task, Task},
    %% Send the task to the current server module
    %% after a 5000ms delay
    erlang:send_after(Time, ?SERVER, {task, Task}),
    ok.

  %%%===================================================================

  %% https://github.com/grisp/grisp/wiki/PmodNAV-Tutorial
  pmodnav_task() ->
    %% Declare an Achlys task that will be periodically
    %% executed as long as the node is up
    Task = achlys:declare(pmodnav_task
    , all
    , single
    , fun() ->
      logger:log(notice, "Reading PmodNAV measurements ~n"),
      Acc = pmod_nav:read(acc, [out_x_xl, out_y_xl, out_z_xl]),
      Gyro = pmod_nav:read(acc, [out_x_g, out_y_g, out_z_g]),
      Mag = pmod_nav:read(mag, [out_x_m, out_y_m, out_z_m]),
      Press = pmod_nav:read(alt, [press_out]),
      Temp = pmod_nav:read(alt, [temp_out]),
      Node = erlang:node(),

      F = fun({Acc, Gyro, Mag, Press, Temp, Node}) ->
        [T] = Temp,
        NewTemp = ((T * 1.8) + 32),
        {Acc, Gyro, Mag, Press, [NewTemp], Node}
      end,
      %% {ok, Set} = lasp:query({<<"source">>, state_orset}), sets:to_list(Set).
      %% {ok, FarenheitSet} = lasp:query({<<"destination">>, state_orset}), sets:to_list(FarenheitSet).
      {ok, {SourceId, _, _, _}} = lasp:declare({<<"source">>, state_orset}, state_orset),
      {ok, {DestinationId, _, _, _}} = lasp:declare({<<"destination">>, state_orset}, state_orset),
      lasp:map(SourceId, F, DestinationId),
      lasp:update(SourceId, {add, {Acc, Gyro, Mag, Press, Temp, Node}}, self())
    end).

  task_1(Threshold) ->
    %% Declare an Achlys task that will be periodically
    %% executed as long as the node is up
    Task = achlys:declare(task_1
    , all
    , single
    , fun() ->
      logger:log(notice, "Reading PmodNAV pressure interval ~n"),
      %Press0 = pmod_nav:read(alt, [press_out]),
      Press0 = rand:uniform(10),
      %% 50 ms interval
      %timer:sleep(2000),
      %Press1 = pmod_nav:read(alt, [press_out]),
      Press1 = rand:uniform(10),
      Node = erlang:node(),

      EWType = state_ewflag,
      EWVarName = <<"ewvar">>,
      GCountType = state_gcounter,
      GCountVarName = <<"gcountvar">>,

      {ok, {EW, _, _, _}} = lasp:declare({EWVarName, EWType}, EWType),
      {ok, {GCount, _, _, _}} = lasp:declare({GCountVarName, GCountType}, GCountType),

      {ok, GCountRes0} = lasp:query(GCount),
        {ok, EWRes0} = lasp:query(EW),
          println(GCountRes0),
          println(EWRes0),

          if
            abs(Press0 - Press1) > Threshold -> {ok, {EW1, _, _, _}} = lasp:update(EW, enable, self()),
            {ok, {GCount1, _, _, _}} = lasp:update(GCount, increment, self());
          %grisp_led : color (1, green );
          true -> {ok, {EW1, _, _, _}} = lasp:update(EW, disable, self())
          %grisp_led : color (2, red )
        end,

        F = fun({Press0, Press1, Node}) ->
          P0 = Press0,
          P1 = Press1,
          Delta = abs(P0 - P1),
          {Delta, Node}
        end,

        %% {ok, Set} = lasp:query({<<"source">>, state_orset}), sets:to_list(Set).
        %% {ok, FarenheitSet} = lasp:query({<<"destination">>, state_orset}), sets:to_list(FarenheitSet).

        {ok, GCountRes1} = lasp:query(GCount),
          {ok, EWRes1} = lasp:query(EW),
            println(GCountRes1),
            println(EWRes1),

            {ok, {SourceId, _, _, _}} = lasp:declare({<<"source">>, state_orset}, state_orset),
            {ok, {DestinationId, _, _, _}} = lasp:declare({<<"destination">>, state_orset}, state_orset),
            lasp:map(SourceId, F, DestinationId),
            lasp:update(SourceId, {add, {Press0, Press1, Node}}, self())
          end).


        temp(Mode) ->
        Task = achlys:declare(temp_task,
        all,
        single,
        fun() ->
          SourceId = {<<"temp">>, state_gset},
          {ok , {_SourceId , _Meta , _Type , _State }} = lasp : declare (SourceId , state_gset),

          Len = 5,
          Buffer = lists:foldl(fun
            (Elem,AccIn) ->
              timer : sleep(6000), %10 measurements per minute
              Temp = pmod_nav:read(acc,[out_temp]),
              Temp ++ AccIn
            end,[],lists:seq(1,5)),
            Name = node(),
            Pid = self(),

            case Mode of
              "min" ->
                  Min = lists:min(Buffer),
                  lasp : update (SourceId , {add , {Min , Name}}, Pid ),
                  println(Min);
              "mean" ->
                Mean = average(Buffer),
                lasp : update (SourceId , {add , {Mean , Name}}, Pid),
                println(Mean)
            end

          end).



        mintemp_task() ->
          Task = achlys:declare(mintemp_task,
          all,
          single,
          fun() ->
            SourceId = {<<"temp">>, state_gset},
            {ok , {_SourceId , _Meta , _Type , _State }} = lasp : declare (SourceId , state_gset),

            Len = 5,
            Buffer = lists:foldl(fun
              (Elem,AccIn) ->
                timer : sleep(6000), %10 measurements per minute
                Temp = pmod_nav:read(acc,[out_temp]),
                Temp ++ AccIn
              end,[],lists:seq(1,5)),

              Min = lists:min(Buffer),

              Name = node(),
              Pid = self(),
              lasp : update (SourceId , {add , {Min , Name}}, Pid ),
              println(Min)

            end).

          meantemp_task() ->
            Task = achlys:declare(meantemp_task,
            all,
            single,
            fun() ->
              SourceId = {<<"temp">>, state_gset},
              {ok , {_SourceId , _Meta , _Type , _State }} = lasp : declare (SourceId , state_gset),

              Len = 5,
              Buffer = lists:foldl(fun
                (Elem,AccIn) ->
                  timer : sleep(6000), %10 measurements per minute
                  %%Temp = pmod_nav:read(acc,[out_temp]),
                  Temp = [rand:uniform(10)],
                  Temp ++ AccIn
                end,[],lists:seq(1,Len)),
                Mean = average(Buffer),
                Name = node(),
                Pid = self(),
                lasp : update (SourceId , {add , {Mean , Name}}, Pid),
                println(Mean)
              end).



            %%=======================


            %% Execution scenario
            %% ==================
            %%
            %% Node 1 shell :
            %% --------------
            %%
            %% $ make shell n=1 PEER_PORT=27001
            %% ...
            %% booting up
            %% ...
            %%
            %% (achlys1@130.104.213.164)1> achlys_task_provider:start_link().
            %% {ok,<0.806.0>}
            %% (achlys1@130.104.213.164)2> Hello Joe !
            %% (achlys1@130.104.213.164)2> achlys_task_provider:add_pmodnav_task().
            %% ok
            %% (achlys1@130.104.213.164)3>
            %% (achlys1@130.104.213.164)3> {ok, Set} = lasp:query({<<"source">>, state_orset}), sets:to_list(Set).
            %% [{[-1.3732929999999999,-0.789584,-0.23198300000000002],
            %%   [0.0,0.0,0.0],
            %%   [0.0,0.0,0.0],
            %%   [0.0],
            %%   [42.5],
            %%   'achlys1@130.104.213.164'}]
            %% (achlys1@130.104.213.164)4>
            %% (achlys1@130.104.213.164)4> {ok, FarenheitSet} = lasp:query({<<"destination">>, state_orset}), sets:to_list(FarenheitSet).
            %% [{[-1.3732929999999999,-0.789584,-0.23198300000000002],
            %%   [0.0,0.0,0.0],
            %%   [0.0,0.0,0.0],
            %%   [0.0],
            %%   [108.5],
            %%   'achlys1@130.104.213.164'}]
            %% (achlys1@130.104.213.164)5>
            %%
            %% Now start a second Achlys shell :
            %%
            %% Node 2 shell :
            %% --------------
            %%
            %% $ make shell n=2 PEER_PORT=27002
            %% ...
            %% booting up
            %% ...
            %%
            %% (achlys2@130.104.213.164)1> achlys_util:add_node('achlys1@130.104.213.164').
            %% ok
            %% (achlys2@130.104.213.164)2> Hello Joe !
            %%
            %% (achlys2@130.104.213.164)2>
            %% (achlys2@130.104.213.164)2> {ok, FarenheitSet} = lasp:query({<<"destination">>, state_orset}), sets:to_list(FarenheitSet).
            %% [{[-1.733376,-1.7716230000000002,0.24387799999999998],
            %%   [0.0,0.0,0.0],
            %%   [0.0,0.0,0.0],
            %%   [0.0],
            %%   [108.5],
            %%   'achlys2@130.104.213.164'},
            %%  {[-1.3732929999999999,-0.789584,-0.23198300000000002],
            %%   [0.0,0.0,0.0],
            %%   [0.0,0.0,0.0],
            %%   [0.0],
            %%   [108.5],
            %%   'achlys1@130.104.213.164'}]
            %% (achlys2@130.104.213.164)3>
            %% (achlys2@130.104.213.164)3> achlys:get_all_tasks().
            %% [{#{execution_type => <<1>>,
            %%     function => #Fun<achlys_task_provider.0.44631258>,
            %%     name => mytask,
            %%     targets => <<0>>},
            %%   128479609},
            %%  {#{execution_type => <<1>>,
            %%     function => #Fun<achlys_task_provider.1.44631258>,
            %%     name => pmodnav_task,
            %%     targets => <<0>>},
            %%   30190207}]
            %% (achlys2@130.104.213.164)4>
