%%%-------------------------------------------------------------------
%%% @author Igor Kopestenski
%%% 2019, <UCLouvain>
%%% @doc
%%% Sample generic server demonstrating usage of the Achlys task
%%% model API.
%%% @end
%%%-------------------------------------------------------------------
-module(gworker).
-author("Crochet Christophe, Van Vracem Gauthier").

-behaviour(gen_server).

%% API
-export([start_link/0]).

%% Adds the pmodnav_task to the working set
%% using the Achlys task model
-export([add_task_exp/0,
        add_task_press/6,
        add_task_temp/6]).

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
println(Text,What) -> io:format(Text ++ "~p~n", [What]).

average(List) ->
  lists:sum(List) / length(List).

variance(List) ->
  Mean = average(List),
  NewList = lists:flatmap(fun(Elem)->
                              [(abs(Elem-Mean))*(abs(Elem-Mean))]
                          end, List),
  average(NewList).

initGlobalVar(Set) ->
  {ok, {Best, _, _, _}} = lasp:declare({<<"best">>, Set}, Set),
  {ok, {Count, _, _, _}} = lasp:declare({<<"gcountvar">>, state_gcounter}, state_gcounter),
  {ok , S} = lasp:query(Best),
  {ok, Length} = lasp:query(Count),
  {Best,Count,S,Length}.

getElem(Mode, Length, Best, S) ->
  case Mode of
    min      -> if
                Length == 0 -> lasp:update(Best, {add, 100}, self()),
                               Elem = 100;
                true -> Elem = lists:min(sets:to_list(S))
              end;
    max      -> if
                Length == 0 -> lasp:update(Best, {add, 0}, self()),
                               Elem = 0;
                true -> Elem = lists:max(sets:to_list(S))
              end;
    mean     -> if
                Length == 0 -> lasp:update(Best, {add, 0}, self()),
                               Elem = 0;
                true -> Elem = average(sets:to_list(S))
              end;
    variance -> if
                Length == 0 -> lasp:update(Best, {add, 0}, self()),
                               Elem = 0;
                true -> Elem = variance(sets:to_list(S))
              end
  end,
  Elem.

updateElem(Mode,Value,Elem,Best) ->
  case Mode of
    min      -> if
                  Value < Elem -> lasp:update(Best, {add, Value}, self()),
                                  UpdateEle = Value;
                  true -> UpdateEle = Elem
                end;
    max      -> if
                  Value > Elem -> lasp:update(Best, {add, Value}, self()),
                                  UpdateEle = Value;
                  true -> UpdateEle = Elem
                end;
    mean     -> Value2 = (Value + Elem) / 2,
                lasp:update(Best, {add, Value2}, self()),
                UpdateEle = (Value + Elem) / 2;
    variance -> lasp:update(Best, {add, variance([Value,Elem])}, self()),
                UpdateEle = variance([Value,Elem])
end,
{UpdateEle}.

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
  println(EWRes0),

  {ok, {Alpha, _, _, _}} = lasp:declare({<<"best_max">>, state_orset}, state_orset),
  {ok , Sa} = lasp:query(Alpha) ,
  println(sets:to_list(Sa)).

    %%--------------------------------------------------------------------
    %% @doc
    %% Propagates the pmodnav_task
    %% @end
    %%--------------------------------------------------------------------

    -spec(add_task_exp() ->
      {ok , Pid :: pid()} | ignore | {error , Reason :: term()}).
    add_task_exp() ->
      gen_server:cast(?SERVER
      , {task, task_exp()}).

    -spec(add_task_temp(_Mode1,_Mode2,_Len,_SampleRate,_LB,_UB) ->
      {ok , Pid :: pid()} | ignore | {error , Reason :: term()}).
    add_task_temp(Mode1,Mode2,Len,SampleRate,LB,UB) ->
      gen_server:cast(?SERVER
      , {task, temperature(Mode1,Mode2,Len,SampleRate,LB,UB)}).

    -spec(add_task_press(_Mode1,_Mode2,_Len,_SampleRate,_LB,_UB) ->
      {ok , Pid :: pid()} | ignore | {error , Reason :: term()}).
    add_task_press(Mode1,Mode2,Len,SampleRate,LB,UB) ->
      gen_server:cast(?SERVER
      , {task, pressure(Mode1,Mode2,Len,SampleRate,LB,UB)}).


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

  temperature(Mode1, Mode2, Len, SampleRate,LB,UB) ->
    Task = achlys:declare(temperature,
    all,
    permanent,
    fun() ->
      logger:log(notice, "Reading PmodNAV temperature interval ~n"),
      SourceId = {<<"temp_source">>, state_gset},
      {ok , {_SourceId , _Meta , _Type , _State }} = lasp : declare (SourceId , state_gset),

      Buffer = lists:foldl(fun
        (Elem,AccIn) ->
          timer : sleep(SampleRate), %10 measurements per minute
          %Temp = pmod_nav:read(acc,[out_temp]),
          Temp = rand:uniform(100),
          if
            Temp < UB ->
              if
                Temp > LB -> [Temp] ++ AccIn;
                true -> [LB]
              end;
            true->[UB]
          end
        end,[],lists:seq(1,Len)),

        Name = node(),
        Pid = self(),

        case Mode1 of
          current ->
              Current = pmod_nav:read(acc,[out_temp]),
              lasp:update(SourceId , {add , {Current , Name}}, Pid),
              println(Current);
          min ->
              {Best,Count,S,Length} = initGlobalVar(state_gset),
              MinElem = getElem(Mode2, Length, Best, S),
              Min = lists:min(Buffer),
              U = updateElem(Mode2,Min,MinElem,Best),
              lasp:update(SourceId , {add , {Min , Name}}, Pid),
              lasp:update(Count, increment, self()),
              println("Updated Elem = ",U),
              println("Local Min = ",Min);
          max ->
              {Best,Count,S,Length} = initGlobalVar(state_gset),
              MaxElem = getElem(Mode2, Length, Best, S),
              Max = lists:max(Buffer),
              U = updateElem(Mode2,Max,MaxElem,Best),
              lasp:update(SourceId , {add , {Max , Name}}, Pid),
              lasp:update(Count, increment, self()),
              println("Updated Elem = ",U),
              println("Local Max = ",Max);
          mean ->
              {Best,Count,S,Length} = initGlobalVar(state_gset),
              MeanElem = getElem(Mode2, Length, Best, S),
              Mean = average(Buffer),
              U = updateElem(Mode2,Mean,MeanElem,Best),
              lasp:update(SourceId , {add , {Mean , Name}}, Pid),
              lasp:update(Count, increment, self()),
              println("Updated Elem = ",U),
              println("Local Mean = ",Mean);
          variance ->
              {Best,Count,S,Length} = initGlobalVar(state_gset),
              VarElem = getElem(Mode2, Length, Best, S),
              Var = variance(Buffer),
              U = updateElem(Mode2,Var,VarElem,Best),
              lasp:update(SourceId , {add , {Var , Name}}, Pid),
              lasp:update(Count, increment, self()),
              println("Updated Elem = ",U),
              println("Local Var = ",Var)
          end,
          println(" ")
      end).

%%%===================================================================

pressure(Mode1, Mode2, Len, SampleRate,LB,UB) ->
  Task = achlys:declare(temperature,
  all,
  permanent,
  fun() ->
    logger:log(notice, "Reading PmodNAV temperature interval ~n"),
    SourceId = {<<"temp_source">>, state_gset},
    {ok , {_SourceId , _Meta , _Type , _State }} = lasp : declare (SourceId , state_gset),

    Buffer = lists:foldl(fun
      (Elem,AccIn) ->
        timer : sleep(SampleRate), %10 measurements per minute
        %Temp = pmod_nav:read(acc,[press_out]),
        Press = rand:uniform(100),
        if
          Press < UB ->
            if
              Press > LB -> [Press] ++ AccIn;
              true -> [LB]
            end;
          true->[UB]
        end
      end,[],lists:seq(1,Len)),

      Name = node(),
      Pid = self(),

      case Mode1 of
        current ->
            Current = pmod_nav:read(acc,[press_out]),
            lasp:update(SourceId , {add , {Current , Name}}, Pid),
            println(Current);
        min ->
            {Best,Count,S,Length} = initGlobalVar(state_gset),
            MinElem = getElem(Mode2, Length, Best, S),
            Min = lists:min(Buffer),
            U = updateElem(Mode2,Min,MinElem,Best),
            lasp:update(SourceId , {add , {Min , Name}}, Pid),
            lasp:update(Count, increment, self()),
            println("Updated Elem = ",U),
            println("Local Min = ",Min);
        max ->
            {Best,Count,S,Length} = initGlobalVar(state_gset),
            MaxElem = getElem(Mode2, Length, Best, S),
            Max = lists:max(Buffer),
            U = updateElem(Mode2,Max,MaxElem,Best),
            lasp:update(SourceId , {add , {Max , Name}}, Pid),
            lasp:update(Count, increment, self()),
            println("Updated Elem = ",U),
            println("Local Max = ",Max);
        mean ->
            {Best,Count,S,Length} = initGlobalVar(state_gset),
            MeanElem = getElem(Mode2, Length, Best, S),
            Mean = average(Buffer),
            U = updateElem(Mode2,Mean,MeanElem,Best),
            lasp:update(SourceId , {add , {Mean , Name}}, Pid),
            lasp:update(Count, increment, self()),
            println("Updated Elem = ",U),
            println("Local Mean = ",Mean);
        variance ->
            {Best,Count,S,Length} = initGlobalVar(state_gset),
            VarElem = getElem(Mode2, Length, Best, S),
            Var = variance(Buffer),
            U = updateElem(Mode2,Var,VarElem,Best),
            lasp:update(SourceId , {add , {Var , Name}}, Pid),
            lasp:update(Count, increment, self()),
            println("Updated Elem = ",U),
            println("Local Var = ",Var)
        end,
        println(" ")
    end).


%%%===================================================================

    task_exp() ->
      Task = achlys:declare(task_exp
      , all
      , permanent
      , fun() ->
        logger:log(notice, "Reading PmodNAV pressure interval ~n"),
        Temp = rand:uniform(100),
        Node = erlang:node(),
        {ok, {SourceId, _, _, _}} = lasp:declare({<<"source">>, state_gset}, state_gset),
        {ok, {BestMax, _, _, _}} = lasp:declare({<<"best_max">>, state_gset}, state_gset),
        {ok, {Count, _, _, _}} = lasp:declare({<<"gcountvar">>, state_gcounter}, state_gcounter),
        {ok , Smax} = lasp:query(BestMax),
        {ok, Length} = lasp:query(Count),
        if
            Length == 0 -> lasp:update(BestMax, {add, 1}, self()),
            Max = 1;
            true -> Max = lists:max(sets:to_list(Smax))
        end,
        println(Max),
        if
            Temp > Max -> lasp:update(BestMax, {add, Temp}, self());
            true -> ok
        end,
        lasp:update(SourceId, {add, {Temp, Node}}, self()),
        lasp:update(Count, increment, self())
    end).


%%%===================================================================

%% {ok, Set} = lasp:query({<<"source">>, state_orset}), sets:to_list(Set).
%% {ok, FarenheitSet} = lasp:query({<<"destination">>, state_orset}), sets:to_list(FarenheitSet).
%% achlys_util:add_node('achlys1@130.104.213.164').
%% (achlys2@130.104.213.164)3> achlys:get_all_tasks().
