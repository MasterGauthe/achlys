%%%-------------------------------------------------------------------
%%% @author Igor Kopestenski
%%% 2019, <UCLouvain>
%%% @doc
%%% Sample generic server demonstrating usage of the Achlys task
%%% model API.
%%% @end
%%%-------------------------------------------------------------------
-module(earthquake).
-author("Igor Kopestenski").

-behaviour(gen_server).

%% API
-export([start_link/0]).

%% Adds the pmodnav_task to the working set
%% using the Achlys task model
-export([add_task_1/1]).

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

    %%--------------------------------------------------------------------
    %% @doc
    %% Propagates the pmodnav_task
    %% @end
    %%--------------------------------------------------------------------

    -spec(add_task_1(_Threshold) ->
      {ok , Pid :: pid()} | ignore | {error , Reason :: term()}).
    add_task_1(Threshold) ->
      gen_server:cast(?SERVER
      , {task, task_1(Threshold)}).

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

  task_1(Threshold) ->
    %% Declare an Achlys task that will be periodically
    %% executed as long as the node is up
    Task = achlys:declare(task_1
    , all
    , permanent
    , fun() ->
      logger:log(notice, "Reading PmodNAV pressure interval ~n"),
      %Press0 = pmod_nav:read(alt, [press_out]),
      Press0 = rand:uniform(10),
      %timer:sleep(2000),
      %Press1 = pmod_nav:read(alt, [press_out]),
      Press1 = rand:uniform(10),
      Node = erlang:node(),

      EWType = state_ewflag,
      EWVarName = <<"ewvar">>,
      ORSetType = state_orset,
      ORSetVarName = <<"orset">>,

      {ok, {EW, _, _, _}} = lasp:declare({EWVarName, EWType}, EWType),
      {ok, {ORSetA, _, _, _}} = lasp:declare({<<"orseta">>, ORSetType}, ORSetType),
      {ok, {ORSetB, _, _, _}} = lasp:declare({<<"orsetb">>, ORSetType}, ORSetType),
      if
          abs(Press0 - Press1) > Threshold -> lasp:update(ORSetA, {add, Node}, self()),
          lasp:update(ORSetB, {add, Node}, self());
          %grisp_led : color (1, green );
          true -> lasp:update(ORSetA, {rmv, Node}, self())
          %grisp_led : color (2, red )
      end,
      {ok, ORSet0} = lasp:query(ORSetA),
      {ok, ORSet1} = lasp:query(ORSetB),
      L1 = length(sets:to_list(ORSet0)),
      L2 = length(sets:to_list(ORSet1)),
      if
          (L2 == L1) and (L1 > 0) -> lasp:update(EW, enable, self());
          true -> lasp:update(EW, disable, self())
      end,
      %{ok, {SourceId, _, _, _}} = lasp:declare({<<"source">>, state_orset}, state_orset),
      %lasp:update(SourceId, {add, {abs(Press0 - Press1), Node}}, self()),
      {ok, EW0} = lasp:query(EW),
      println(sets:to_list(ORSet0)),
      println(sets:to_list(ORSet1)),
      println(EW0),
      println(" "),
      timer:sleep(3000)
    end).

%%%===================================================================

%%logger:log(notice, "Reading PmodNAV measurements ~n"),
%%Acc = pmod_nav:read(acc, [out_x_xl, out_y_xl, out_z_xl]),
%%Gyro = pmod_nav:read(acc, [out_x_g, out_y_g, out_z_g]),
%%Mag = pmod_nav:read(mag, [out_x_m, out_y_m, out_z_m]),
%%Press = pmod_nav:read(alt, [press_out]),
%%Temp = pmod_nav:read(alt, [temp_out]),
%%Node = erlang:node(),

%test:show().
%% {ok, Set} = lasp:query({<<"source">>, state_gset}), sets:to_list(Set).
%% {ok, FarenheitSet} = lasp:query({<<"destination">>, state_orset}), sets:to_list(FarenheitSet).
%% achlys_util:add_node('achlys1@130.104.213.164').
%% (achlys2@130.104.213.164)3> achlys:get_all_tasks().
